"""Tests for the secrets installation helpers."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from importlib.machinery import SourceFileLoader
import importlib.util

CLI_DIR = Path(__file__).resolve().parents[2] / "apps" / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from vm_manager import VMManager  # type: ignore

_RAVE_LOADER = SourceFileLoader("rave_cli", str(CLI_DIR / "rave"))
_RAVE_SPEC = importlib.util.spec_from_loader("rave_cli", _RAVE_LOADER)
assert _RAVE_SPEC is not None
rave_cli = importlib.util.module_from_spec(_RAVE_SPEC)
_RAVE_LOADER.exec_module(rave_cli)
_sync_vm_secrets = rave_cli._sync_vm_secrets  # type: ignore[attr-defined]


class SyncVmSecretsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.workdir = Path(self._tmpdir.name)
        self.vm_manager = mock.create_autospec(VMManager)
        self.company = "acme"
        self.age_key = self.workdir / "age.key"
        self.age_key.write_text("AGE-KEY")
        self.secrets_file = self.workdir / "secrets.yaml"
        self.secrets_file.write_text("{}");

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def test_sync_vm_secrets_requires_age_key(self) -> None:
        result = _sync_vm_secrets(
            self.vm_manager,
            self.company,
            self.workdir / "missing.key",
            self.secrets_file,
            restart_db=False,
        )
        self.assertFalse(result["success"])
        self.assertIn("Age key not found", result["error"])
        self.vm_manager.install_age_key.assert_not_called()

    def test_sync_vm_secrets_handles_install_failure(self) -> None:
        self.vm_manager.install_age_key.return_value = {"success": False, "error": "boom"}
        result = _sync_vm_secrets(
            self.vm_manager,
            self.company,
            self.age_key,
            self.secrets_file,
            restart_db=False,
        )
        self.assertFalse(result["success"])
        self.assertIn("boom", result["error"])

    def test_sync_vm_secrets_installs_entries(self) -> None:
        self.vm_manager.install_age_key.return_value = {"success": True, "path": "/var/lib/sops-nix/key.txt"}
        self.vm_manager.install_secret_files.return_value = {"success": True}

        secret_payload = {
            "mattermost": {
                "admin-username": "admin",
                "admin-email": "admin@example.com",
                "admin-password": "Password123",
                "env": "MM_SQLSETTINGS_DATASOURCE=postgres://mattermost:pass@localhost:5432/mattermost\n",
            },
            "gitlab": {
                "api-token": "token",
                "oauth-provider-client-secret": "oauth",
                "root-password": "rootpass",
                "db-password": "dbpass",
                "secret-key-base": "secret",
            },
            "oidc": {"chat-control-client-secret": "chat"},
            "grafana": {
                "secret-key": "g-secret",
                "db-password": "g-db",
            },
            "database": {
                "mattermost-password": "mmpass",
                "penpot-password": "ppass",
                "n8n-password": "n8npass",
                "prometheus-password": "prompass",
                "grafana-password": "g-admin",
            },
        }

        with mock.patch.object(rave_cli, "_load_decrypted_secrets", return_value=secret_payload):
            result = _sync_vm_secrets(
                self.vm_manager,
                self.company,
                self.age_key,
                self.secrets_file,
                restart_db=False,
            )

        self.assertTrue(result["success"])
        self.assertIn("mattermost/admin-username", result["installed_secrets"])
        self.vm_manager.install_secret_files.assert_called_once()

    def test_sync_vm_secrets_gracefully_handles_missing_secrets_file(self) -> None:
        self.vm_manager.install_age_key.return_value = {"success": True, "path": "/var/lib/sops-nix/key.txt"}
        missing = self.workdir / "missing.yaml"
        result = _sync_vm_secrets(
            self.vm_manager,
            self.company,
            self.age_key,
            missing,
            restart_db=False,
        )
        self.assertTrue(result["success"])
        self.assertTrue(result["warnings"])
        self.vm_manager.install_secret_files.assert_not_called()


if __name__ == "__main__":
    unittest.main()
