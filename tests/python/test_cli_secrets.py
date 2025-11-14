"""CLI tests for `rave secrets install`."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict
from unittest import mock

from click.testing import CliRunner

from importlib.machinery import SourceFileLoader
import importlib.util

CLI_DIR = Path(__file__).resolve().parents[2] / "apps" / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

_RAVE_LOADER = SourceFileLoader("rave_cli", str(CLI_DIR / "rave"))
_RAVE_SPEC = importlib.util.spec_from_loader("rave_cli", _RAVE_LOADER)
assert _RAVE_SPEC is not None
rave_cli = importlib.util.module_from_spec(_RAVE_SPEC)
_RAVE_LOADER.exec_module(rave_cli)


class SecretsInstallCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = CliRunner()
        self.isolated = self.runner.isolated_filesystem()
        self.isolated.__enter__()
        self.tmpdir = Path.cwd()
        self.key_file = self.tmpdir / "age.txt"
        self.key_file.write_text("AGE-KEY")
        self.secrets_file = self.tmpdir / "secrets.yaml"
        self.secrets_file.write_text("{}");

    def tearDown(self) -> None:
        self.isolated.__exit__(None, None, None)

    def _sample_secrets(self) -> Dict[str, Any]:
        return {
            "mattermost": {
                "admin-username": "mm-admin",
                "admin-email": "mm@example.com",
                "admin-password": "mm-pass",
            },
            "gitlab": {
                "api-token": "gitlab-token",
                "oauth-provider-client-secret": "gitlab-oauth",
                "root-password": "rootpass",
                "db-password": "gitpass",
                "secret-key-base": "git-secret",
            },
            "oidc": {
                "chat-control-client-secret": "oidc-secret",
            },
            "grafana": {
                "secret-key": "grafana-secret",
                "db-password": "grafana-db",
            },
            "database": {
                "mattermost-password": "mm-pass",
                "grafana-password": "grafana-admin",
                "penpot-password": "penpot-pass",
                "n8n-password": "n8n-pass",
                "prometheus-password": "prom-pass",
            },
        }

    def test_secrets_install_success(self) -> None:
        sync_result = {
            "success": True,
            "age_remote_path": "/var/lib/sops-nix/key.txt",
            "messages": ["Mattermost database credentials refreshed"],
            "warnings": [],
            "installed_secrets": ["gitlab/api-token"],
        }
        with mock.patch.object(rave_cli, "_sync_vm_secrets", return_value=sync_result) as sync_mock:
            result = self.runner.invoke(
                rave_cli.cli,
                [
                    "secrets",
                    "install",
                    "acme",
                    "--key-file",
                    str(self.key_file),
                    "--secrets-file",
                    str(self.secrets_file),
                ],
            )
        self.assertEqual(result.exit_code, 0, result.output)
        sync_mock.assert_called_once()
        self.assertIn("Installed secrets", result.output)
        self.assertIn("Mattermost database credentials refreshed", result.output)

    def test_secrets_install_failure_path(self) -> None:
        with mock.patch.object(
            rave_cli, "_sync_vm_secrets", return_value={"success": False, "error": "boom"}
        ) as sync_mock:
            result = self.runner.invoke(
                rave_cli.cli,
                [
                    "secrets",
                    "install",
                    "acme",
                    "--key-file",
                    str(self.key_file),
                    "--secrets-file",
                    str(self.secrets_file),
                ],
            )
        self.assertNotEqual(result.exit_code, 0)
        sync_mock.assert_called_once()
        self.assertIn("boom", result.output)

    def test_prepare_secret_entries_generates_expected_entries(self) -> None:
        plan = rave_cli._prepare_secret_entries(self._sample_secrets(), Path("config/secrets.yaml"))
        self.assertGreater(len(plan["entries"]), 0)
        self.assertNotIn("mattermost/env", [entry["name"] for entry in plan["entries"]])
        self.assertEqual(plan["datasource_password"], "mm-pass")

    def test_secrets_diff_outputs_plan(self) -> None:
        with mock.patch.object(rave_cli, "_load_decrypted_secrets", return_value=self._sample_secrets()):
            result = self.runner.invoke(
                rave_cli.cli,
                [
                    "secrets",
                    "diff",
                    "--key-file",
                    str(self.key_file),
                    "--secrets-file",
                    str(self.secrets_file),
                ],
            )

        self.assertEqual(result.exit_code, 0, result.output)
        self.assertIn("Planned secret file writes", result.output)
        self.assertIn("mattermost/admin-username", result.output)


if __name__ == "__main__":
    unittest.main()
