import io
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parents[2] / "apps" / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from override_manager import OverrideManager, OverrideManagerError


class OverrideManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.repo_root = Path(self.tempdir.name)
        (self.repo_root / "config").mkdir(parents=True, exist_ok=True)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def test_init_creates_global_layer(self) -> None:
        manager = OverrideManager(self.repo_root)
        result = manager.ensure_initialized()
        self.assertTrue(result["created"])

        layer_dir = self.repo_root / "config" / "overrides" / "global"
        self.assertTrue((layer_dir / "layer.json").exists())
        self.assertTrue((layer_dir / "metadata.json").exists())
        self.assertTrue((layer_dir / "files").is_dir())
        self.assertTrue((layer_dir / "systemd").is_dir())

        manager_again = OverrideManager(self.repo_root)
        result_again = manager_again.ensure_initialized()
        self.assertFalse(result_again["created"])  # idempotent

    def test_build_layer_package_collects_metadata(self) -> None:
        manager = OverrideManager(self.repo_root)
        manager.ensure_initialized()

        overrides_root = self.repo_root / "config" / "overrides" / "global"
        files_dir = overrides_root / "files" / "etc" / "nginx"
        files_dir.mkdir(parents=True, exist_ok=True)
        nginx_conf = files_dir / "nginx.conf"
        nginx_conf.write_text("events {}")

        systemd_file = overrides_root / "systemd" / "custom.service"
        systemd_file.parent.mkdir(parents=True, exist_ok=True)
        systemd_file.write_text("[Unit]\nDescription=Custom\n")

        metadata_path = overrides_root / "metadata.json"
        metadata = {
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
                    "match": "etc/nginx/**",
                    "restart_units": ["nginx.service"],
                },
                {
                    "match": "etc/systemd/system/**",
                    "daemon_reload": True,
                },
            ],
        }
        metadata_path.write_text(json.dumps(metadata))

        package = manager.build_layer_package("global")
        entries = package.manifest["entries"]
        self.assertEqual(len(entries), 2)

        manifest_map = {entry["target_relpath"]: entry for entry in entries}
        nginx_entry = manifest_map["etc/nginx/nginx.conf"]
        self.assertIn("nginx.service", nginx_entry["restart_units"])
        self.assertFalse(nginx_entry["daemon_reload"])

        systemd_entry = manifest_map["etc/systemd/system/custom.service"]
        self.assertTrue(systemd_entry["daemon_reload"])

        with tarfile.open(fileobj=io.BytesIO(package.archive), mode="r:gz") as tar:
            names = tar.getnames()

        self.assertIn(".rave-manifest.json", names)
        self.assertIn("files/etc/nginx/nginx.conf", names)
        self.assertIn("systemd/custom.service", names)

    def test_create_layer_with_priority_and_copy(self) -> None:
        manager = OverrideManager(self.repo_root)
        manager.ensure_initialized()

        global_metadata = self.repo_root / "config" / "overrides" / "global" / "metadata.json"
        payload = json.loads(global_metadata.read_text())
        payload["patterns"].append({"match": "etc/example/**", "restart_units": ["example.service"]})
        global_metadata.write_text(json.dumps(payload))

        result = manager.create_layer("host-acme", priority=25, description="Host overrides", copy_from="global")
        self.assertEqual(result["name"], "host-acme")
        self.assertTrue((self.repo_root / "config" / "overrides" / "host-acme").exists())

        layers = manager.list_layers()
        names = [layer.name for layer in layers]
        self.assertEqual(names[0], "host-acme")  # highest priority
        new_metadata = json.loads((self.repo_root / "config" / "overrides" / "host-acme" / "metadata.json").read_text())
        self.assertTrue(any(pattern.get("match") == "etc/example/**" for pattern in new_metadata.get("patterns", [])))

    def test_create_layer_with_presets(self) -> None:
        manager = OverrideManager(self.repo_root)
        manager.ensure_initialized()

        result = manager.create_layer("preset-demo", presets=["nginx", "mattermost"])
        self.assertEqual(result["presets"], ["nginx", "mattermost"])

        metadata = json.loads((self.repo_root / "config" / "overrides" / "preset-demo" / "metadata.json").read_text())
        matches = {pattern.get("match") for pattern in metadata.get("patterns", [])}
        self.assertIn("etc/nginx/**", matches)
        self.assertIn("etc/mattermost/**", matches)

    def test_create_layer_unknown_preset_raises(self) -> None:
        manager = OverrideManager(self.repo_root)
        manager.ensure_initialized()

        with self.assertRaises(OverrideManagerError):
            manager.create_layer("bad-preset", presets=["does-not-exist"])
