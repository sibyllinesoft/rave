"""Override layer management for the RAVE CLI."""
from __future__ import annotations

from datetime import datetime, timezone
import fnmatch
import hashlib
import io
import json
import re
import tarfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

DEFAULT_LAYER_PRIORITY = 100
MANIFEST_VERSION = 1
MANIFEST_FILE_NAME = ".rave-manifest.json"
LAYER_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def _default_metadata() -> Dict[str, Any]:
    return {
        "version": 1,
        "defaults": {
            "owner": "root",
            "group": "root",
            "file_mode": "0644",
            "dir_mode": "0755",
            "restart_units": [],
            "reload_units": [],
            "commands": [],
            "daemon_reload": False,
        },
        "patterns": [
            {
                "match": "etc/systemd/system/**/*.service",
                "daemon_reload": True,
                "scope": ["systemd"],
            },
            {
                "match": "etc/systemd/system/**/*.timer",
                "daemon_reload": True,
                "scope": ["systemd"],
            },
            {
                "match": "etc/systemd/system/**/*.path",
                "daemon_reload": True,
                "scope": ["systemd"],
            },
            {
                "match": "etc/traefik/**",
                "reload_units": ["traefik.service"],
                "scope": ["file"],
            },
            {
                "match": "etc/rave/overrides/traefik/**/*.yaml",
                "reload_units": ["traefik.service"],
                "scope": ["file"],
            },
            {
                "match": "etc/nginx/**",
                "reload_units": ["traefik.service"],
                "scope": ["file"],
            },
            {
                "match": "etc/rave/overrides/nginx/**/*.conf",
                "reload_units": ["traefik.service"],
                "scope": ["file"],
            },
        ],
    }


TRAEFIK_PRESET = [
    {
        "match": "etc/traefik/**",
        "reload_units": ["traefik.service"],
        "scope": ["file"],
    },
    {
        "match": "etc/rave/overrides/traefik/**/*.yaml",
        "reload_units": ["traefik.service"],
        "scope": ["file"],
    },
    {
        "match": "etc/nginx/**",
        "reload_units": ["traefik.service"],
        "scope": ["file"],
    },
    {
        "match": "etc/rave/overrides/nginx/**/*.conf",
        "reload_units": ["traefik.service"],
        "scope": ["file"],
    },
]


METADATA_PRESETS: Dict[str, List[Dict[str, Any]]] = {
    "traefik": TRAEFIK_PRESET,
    "nginx": TRAEFIK_PRESET,
    "gitlab": [
        {
            "match": "etc/gitlab/**",
            "restart_units": ["gitlab.target"],
            "scope": ["file"],
        },
        {
            "match": "var/opt/gitlab/**",
            "restart_units": ["gitlab.target"],
            "scope": ["file"],
        },
    ],
    "mattermost": [
        {
            "match": "etc/mattermost/**",
            "restart_units": ["mattermost.service"],
            "scope": ["file"],
        },
        {
            "match": "var/lib/mattermost/**",
            "restart_units": ["mattermost.service"],
            "scope": ["file"],
        },
    ],
    "pomerium": [
        {
            "match": "etc/pomerium/**",
            "restart_units": ["pomerium.service"],
            "scope": ["file"],
        }
    ],
    "authentik": [
        {
            "match": "etc/authentik/**",
            "restart_units": ["authentik-server.service", "authentik-worker.service"],
            "scope": ["file"],
        },
        {
            "match": "etc/systemd/system/authentik-*.service",
            "daemon_reload": True,
            "restart_units": ["authentik-server.service", "authentik-worker.service"],
            "scope": ["systemd"],
        },
    ],
}


class OverrideManagerError(Exception):
    """Raised when override layer operations fail."""


@dataclass
class OverrideSource:
    source_path: Path
    source_relpath: str
    target_relpath: str
    kind: str  # "file" | "systemd"


@dataclass
class OverrideLayer:
    name: str
    root: Path
    priority: int
    description: str
    files_dir: Path
    systemd_dir: Path
    metadata: "OverrideMetadata"

    def ensure_dirs(self) -> None:
        self.files_dir.mkdir(parents=True, exist_ok=True)
        self.systemd_dir.mkdir(parents=True, exist_ok=True)


class OverrideMetadata:
    """Pattern-driven metadata (ownership, restart hints, etc.)."""

    _LIST_FIELDS = {"restart_units", "reload_units", "commands"}

    def __init__(self, metadata_path: Path):
        self.path = metadata_path
        self.version = 1
        self.defaults: Dict[str, Any] = {
            "owner": "root",
            "group": "root",
            "file_mode": "0644",
            "dir_mode": "0755",
            "restart_units": [],
            "reload_units": [],
            "commands": [],
            "daemon_reload": False,
        }
        self.patterns: List[Dict[str, Any]] = []
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            return

        try:
            data = json.loads(self.path.read_text())
        except json.JSONDecodeError as exc:
            raise OverrideManagerError(
                f"Invalid metadata JSON at {self.path}: {exc}"
            ) from exc

        version = data.get("version", 1)
        self.version = version

        defaults = data.get("defaults") or {}
        self.defaults = {
            **self.defaults,
            **{k: defaults.get(k, self.defaults[k]) for k in self.defaults.keys()},
        }
        # Normalize list fields in defaults
        for field in self._LIST_FIELDS:
            self.defaults[field] = list(self.defaults.get(field, []))
        self.defaults["daemon_reload"] = bool(self.defaults.get("daemon_reload", False))

        patterns = data.get("patterns") or []
        normalized: List[Dict[str, Any]] = []
        for pattern in patterns:
            entry = dict(pattern)
            for field in self._LIST_FIELDS:
                if field in entry:
                    entry[field] = [str(value) for value in entry[field]]
            if "daemon_reload" in entry:
                entry["daemon_reload"] = bool(entry["daemon_reload"])
            scopes = entry.get("scope")
            if scopes is None:
                entry["scope"] = []
            elif isinstance(scopes, str):
                entry["scope"] = [scopes]
            else:
                entry["scope"] = [str(scope) for scope in scopes]
            normalized.append(entry)
        self.patterns = normalized

    def resolve(self, target_relpath: str, kind: str) -> Dict[str, Any]:
        result = {
            "owner": self.defaults["owner"],
            "group": self.defaults["group"],
            "file_mode": self.defaults["file_mode"],
            "dir_mode": self.defaults["dir_mode"],
            "restart_units": list(self.defaults.get("restart_units", [])),
            "reload_units": list(self.defaults.get("reload_units", [])),
            "commands": list(self.defaults.get("commands", [])),
            "daemon_reload": bool(self.defaults.get("daemon_reload", False)),
        }

        for pattern in self.patterns:
            scope = pattern.get("scope")
            if scope:
                allowed = set(scope)
                if kind not in allowed:
                    continue

            matches = False
            if pattern.get("path") == target_relpath:
                matches = True
            else:
                glob = pattern.get("match")
                if glob and fnmatch.fnmatch(target_relpath, glob):
                    matches = True
            if not matches:
                continue

            if "owner" in pattern:
                result["owner"] = str(pattern["owner"])
            if "group" in pattern:
                result["group"] = str(pattern["group"])
            if "file_mode" in pattern:
                result["file_mode"] = str(pattern["file_mode"])
            if "dir_mode" in pattern:
                result["dir_mode"] = str(pattern["dir_mode"])
            if "daemon_reload" in pattern:
                result["daemon_reload"] = bool(pattern["daemon_reload"])

            for field in self._LIST_FIELDS:
                values = pattern.get(field)
                if not values:
                    continue
                merged = result.get(field, []) + list(values)
                # Preserve order but drop duplicates
                seen = set()
                deduped = []
                for item in merged:
                    if item in seen:
                        continue
                    seen.add(item)
                    deduped.append(item)
                result[field] = deduped

        return result


@dataclass
class OverridePackage:
    layer: OverrideLayer
    manifest: Dict[str, Any]
    archive: bytes


class OverrideManager:
    """Manages Git-backed override layers under config/overrides."""

    def __init__(self, repo_root: Path):
        self.repo_root = Path(repo_root)
        self.overrides_root = self.repo_root / "config" / "overrides"

    def _normalize_layer_name(self, name: str) -> str:
        slug = name.strip().replace(" ", "-")
        if not slug:
            raise OverrideManagerError("Layer name cannot be empty")
        if not LAYER_NAME_PATTERN.match(slug):
            raise OverrideManagerError(
                "Layer names must be alphanumeric and may include . _ - characters"
            )
        return slug

    def _write_layer_config(
        self,
        layer_dir: Path,
        *,
        name: str,
        priority: int,
        description: str,
        files_dir_name: str = "files",
        systemd_dir_name: str = "systemd",
    ) -> None:
        data = {
            "name": name,
            "description": description,
            "priority": priority,
            "files_dir": files_dir_name,
            "systemd_dir": systemd_dir_name,
            "metadata": "metadata.json",
        }
        (layer_dir / "layer.json").write_text(json.dumps(data, indent=2))

    def _write_metadata(self, target: Path, metadata: Dict[str, Any]) -> None:
        target.write_text(json.dumps(metadata, indent=2))

    def _scaffold_layer(
        self,
        name: str,
        *,
        priority: int,
        description: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Path:
        layer_dir = self.overrides_root / name
        files_dir = layer_dir / "files"
        systemd_dir = layer_dir / "systemd"
        layer_dir.mkdir(parents=True, exist_ok=True)
        files_dir.mkdir(parents=True, exist_ok=True)
        systemd_dir.mkdir(parents=True, exist_ok=True)
        (files_dir / ".gitkeep").write_text("", encoding="utf-8")
        (systemd_dir / ".gitkeep").write_text("", encoding="utf-8")

        self._write_layer_config(
            layer_dir,
            name=name,
            priority=priority,
            description=description,
        )

        metadata_blob = json.loads(json.dumps(metadata or _default_metadata()))
        self._write_metadata(layer_dir / "metadata.json", metadata_blob)
        return layer_dir

    # ------------------------------------------------------------------
    # Layer discovery / initialization

    def ensure_initialized(self) -> Dict[str, Any]:
        """Ensure the base overrides directory and the global layer exist."""
        created = False
        global_layer = self.overrides_root / "global"

        if not self.overrides_root.exists():
            self.overrides_root.mkdir(parents=True, exist_ok=True)

        if not global_layer.exists():
            self._scaffold_layer(
                "global",
                priority=DEFAULT_LAYER_PRIORITY,
                description="Global overrides applied to every RAVE-managed host.",
            )
            created = True
        else:
            # Ensure expected directories exist without clobbering user content
            (global_layer / "files").mkdir(parents=True, exist_ok=True)
            (global_layer / "systemd").mkdir(parents=True, exist_ok=True)

            layer_config = global_layer / "layer.json"
            if not layer_config.exists():
                self._write_layer_config(
                    global_layer,
                    name="global",
                    priority=DEFAULT_LAYER_PRIORITY,
                    description="Global overrides applied to every RAVE-managed host.",
                )
                created = True

            metadata_path = global_layer / "metadata.json"
            if not metadata_path.exists():
                self._write_metadata(metadata_path, _default_metadata())
                created = True

        return {
            "created": created,
            "path": str(global_layer),
        }

    def create_layer(
        self,
        name: str,
        *,
        priority: int = DEFAULT_LAYER_PRIORITY,
        description: str = "",
        copy_from: Optional[str] = None,
        presets: Optional[Sequence[str]] = None,
    ) -> Dict[str, Any]:
        self.ensure_initialized()
        normalized = self._normalize_layer_name(name)
        layer_dir = self.overrides_root / normalized
        if layer_dir.exists():
            raise OverrideManagerError(f"Override layer '{normalized}' already exists")

        metadata_blob = None
        if copy_from:
            source_layer = self.get_layer(copy_from)
            metadata_blob = json.loads(source_layer.metadata.path.read_text())

        if metadata_blob is not None:
            metadata_blob = json.loads(json.dumps(metadata_blob))

        if presets:
            metadata_blob = metadata_blob or _default_metadata()
            metadata_blob = json.loads(json.dumps(metadata_blob))
            patterns = metadata_blob.setdefault("patterns", [])
            for preset in presets:
                if preset not in METADATA_PRESETS:
                    raise OverrideManagerError(
                        f"Unknown metadata preset '{preset}'. Available presets: {', '.join(sorted(METADATA_PRESETS))}"
                    )
                preset_patterns = json.loads(json.dumps(METADATA_PRESETS[preset]))
                patterns.extend(preset_patterns)

        self._scaffold_layer(
            normalized,
            priority=priority,
            description=description or f"Custom override layer '{normalized}'",
            metadata=metadata_blob,
        )

        return {
            "name": normalized,
            "priority": priority,
            "path": str(layer_dir),
            "presets": list(presets or []),
        }

    def list_layers(self) -> List[OverrideLayer]:
        """Discover configured layers sorted by priority (low→high)."""
        layers: List[OverrideLayer] = []
        if not self.overrides_root.exists():
            return layers

        for child in sorted(self.overrides_root.iterdir()):
            if not child.is_dir():
                continue
            layer_config = child / "layer.json"
            if not layer_config.exists():
                continue
            try:
                data = json.loads(layer_config.read_text())
            except json.JSONDecodeError as exc:
                raise OverrideManagerError(
                    f"Invalid layer.json at {layer_config}: {exc}"
                ) from exc

            name = data.get("name") or child.name
            priority = int(data.get("priority", DEFAULT_LAYER_PRIORITY))
            description = data.get("description", "")
            files_dir = child / data.get("files_dir", "files")
            systemd_dir = child / data.get("systemd_dir", "systemd")
            metadata_path = child / data.get("metadata", "metadata.json")

            metadata = OverrideMetadata(metadata_path)
            layer = OverrideLayer(
                name=name,
                root=child,
                priority=priority,
                description=description,
                files_dir=files_dir,
                systemd_dir=systemd_dir,
                metadata=metadata,
            )
            layer.ensure_dirs()
            layers.append(layer)

        return sorted(layers, key=lambda layer: layer.priority)

    def get_layer(self, name: str) -> OverrideLayer:
        for layer in self.list_layers():
            if layer.name == name:
                return layer
        raise OverrideManagerError(f"Override layer '{name}' not found")

    # ------------------------------------------------------------------
    # Packaging helpers

    def _gather_sources(self, layer: OverrideLayer) -> List[OverrideSource]:
        sources: List[OverrideSource] = []

        def collect(root: Path, prefix: str, target_prefix: str, kind: str) -> None:
            if not root.exists():
                return
            for path in sorted(root.rglob("*")):
                if path.is_dir():
                    continue
                if not path.is_file() and not path.is_symlink():
                    continue
                if path.name == ".gitkeep":
                    continue
                rel = path.relative_to(root).as_posix()
                source_relpath = f"{prefix}/{rel}" if prefix else rel
                target_relpath = f"{target_prefix}{rel}" if target_prefix else rel
                sources.append(
                    OverrideSource(
                        source_path=path,
                        source_relpath=source_relpath,
                        target_relpath=target_relpath,
                        kind=kind,
                    )
                )

        collect(layer.files_dir, "files", "", "file")
        collect(layer.systemd_dir, "systemd", "etc/systemd/system/", "systemd")
        return sources

    def build_layer_package(self, layer_name: str) -> OverridePackage:
        layer = self.get_layer(layer_name)
        sources = self._gather_sources(layer)
        entries: List[Dict[str, Any]] = []
        seen_targets = set()

        for source in sources:
            if source.target_relpath in seen_targets:
                raise OverrideManagerError(
                    f"Duplicate target path '{source.target_relpath}' in layer '{layer.name}'"
                )
            seen_targets.add(source.target_relpath)
            entry = self._build_entry(layer, source)
            entries.append(entry)

        entries.sort(key=lambda item: item["target_relpath"])

        manifest = {
            "version": MANIFEST_VERSION,
            "layer": layer.name,
            "priority": layer.priority,
            "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "metadata_version": layer.metadata.version,
            "entries": entries,
        }

        archive = self._build_archive(entries, manifest, layer)
        return OverridePackage(layer=layer, manifest=manifest, archive=archive)

    def _build_entry(self, layer: OverrideLayer, source: OverrideSource) -> Dict[str, Any]:
        rel_target = source.target_relpath
        metadata = layer.metadata.resolve(rel_target, source.kind)
        file_bytes = source.source_path.read_bytes()
        digest = hashlib.sha256(file_bytes).hexdigest()

        return {
            "target_relpath": rel_target,
            "path": f"/{rel_target}",
            "source_relpath": source.source_relpath,
            "kind": source.kind,
            "owner": metadata["owner"],
            "group": metadata["group"],
            "file_mode": metadata["file_mode"],
            "dir_mode": metadata["dir_mode"],
            "restart_units": metadata.get("restart_units", []),
            "reload_units": metadata.get("reload_units", []),
            "commands": metadata.get("commands", []),
            "daemon_reload": bool(metadata.get("daemon_reload", False)),
            "hash": f"sha256:{digest}",
        }

    def _build_archive(
        self,
        entries: Sequence[Dict[str, Any]],
        manifest: Dict[str, Any],
        layer: OverrideLayer,
    ) -> bytes:
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz", dereference=True) as tar:
            for entry in entries:
                source_relpath = entry["source_relpath"]
                source_path = self._resolve_source_path(layer, source_relpath)
                tar.add(source_path, arcname=source_relpath)

            manifest_bytes = json.dumps(manifest, indent=2).encode()
            info = tarfile.TarInfo(name=MANIFEST_FILE_NAME)
            info.size = len(manifest_bytes)
            tar.addfile(info, io.BytesIO(manifest_bytes))

        return buffer.getvalue()

    def _resolve_source_path(self, layer: OverrideLayer, source_relpath: str) -> Path:
        if source_relpath.startswith("files/"):
            relative = source_relpath[len("files/"):]
            return layer.files_dir / relative
        if source_relpath.startswith("systemd/"):
            relative = source_relpath[len("systemd/"):]
            return layer.systemd_dir / relative
        # Fallback: treat as direct relative path to layer root
        return layer.root / source_relpath

    # ------------------------------------------------------------------
    # Utility helpers

    def layer_stats(self) -> List[Dict[str, Any]]:
        stats: List[Dict[str, Any]] = []
        for layer in self.list_layers():
            sources = self._gather_sources(layer)
            stats.append(
                {
                    "name": layer.name,
                    "priority": layer.priority,
                    "description": layer.description,
                    "path": str(layer.root.relative_to(self.repo_root)),
                    "file_count": len(sources),
                }
            )
        return stats
