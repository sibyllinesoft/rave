"""Small host helpers for the RAVE CLI."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from process_utils import ProcessError, run_command
from qemu_driver import build_vm_command


class PlatformManager:
    """Minimal host helpers (Linux-first) used by the CLI."""

    def check_prerequisites(self) -> Dict[str, any]:
        missing: List[str] = []
        warnings: List[str] = []

        for binary in ("nix", "qemu-system-x86_64", "sops", "age"):
            if not shutil.which(binary):
                missing.append(binary)

        if not shutil.which("sshpass"):
            warnings.append("sshpass missing - SSH password fallback will be unavailable")

        try:
            result = run_command(["nix", "flake", "--help"], check=False)
            if result.returncode != 0:
                warnings.append(
                    "Nix flakes not enabled - add 'experimental-features = nix-command flakes' to nix.conf"
                )
        except ProcessError:
            warnings.append("Could not verify Nix flakes support")
        except FileNotFoundError:
            pass

        return {"success": len(missing) == 0, "missing": missing, "warnings": warnings}

    def get_nix_build_command(self) -> List[str]:
        return ["nix", "build"]

    def get_vm_start_command(
        self,
        image_path: str,
        memory_gb: int = 12,
        port_forwards: Optional[List[Tuple[int, int]]] = None,
        age_key_dir: Optional[str] = None,
    ):
        return build_vm_command(
            image_path,
            memory_gb=memory_gb,
            port_forwards=port_forwards,
            age_key_dir=age_key_dir,
        )

    def get_temp_dir(self) -> Path:
        return Path(tempfile.gettempdir())

    def get_config_dir(self) -> Path:
        xdg_root = os.environ.get("XDG_CONFIG_HOME")
        base = Path(xdg_root).expanduser() if xdg_root else Path.home() / ".config"
        return base / "rave"

    def ensure_mkcert_installed(self) -> Dict[str, any]:
        """Check mkcert presence; surface actionable guidance."""
        if shutil.which("mkcert"):
            return {"success": True, "installed": False}
        return {
            "success": False,
            "error": "mkcert not found; install via your package manager (e.g. nix profile install nixpkgs#mkcert)",
        }

    def mkcert_caroot(self) -> Optional[Path]:
        if not shutil.which("mkcert"):
            return None
        try:
            result = run_command(["mkcert", "-CAROOT"], check=True)
        except ProcessError:
            return None
        return Path(result.stdout.strip())

    def get_age_key_directory(self) -> Optional[Path]:
        """Get the directory containing AGE keys for SOPS, or None if not found."""
        age_key_file = Path.home() / ".config" / "sops" / "age" / "keys.txt"

        if age_key_file.exists():
            return age_key_file.parent

        home_age_key = Path.home() / ".age" / "key.txt"
        if home_age_key.exists():
            return home_age_key.parent

        try:
            result = run_command(["age-keygen", "-y", str(age_key_file)], check=False)
            if result.returncode == 0:
                return age_key_file.parent
        except (ProcessError, FileNotFoundError):
            pass

        return None
