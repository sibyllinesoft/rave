"""CLI tests for user-related commands."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
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


class UserCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = CliRunner()
        self.user_manager = mock.MagicMock(name="UserManagerMock")
        self.vm_manager = mock.MagicMock(name="VMManagerMock")
        self.oauth_manager = mock.MagicMock(name="OAuthManagerMock")
        self.platform_manager = mock.MagicMock(name="PlatformManagerMock")

        self.patcher_user = mock.patch.object(rave_cli, "UserManager", return_value=self.user_manager)
        self.patcher_vm = mock.patch.object(rave_cli, "VMManager", return_value=self.vm_manager)
        self.patcher_oauth = mock.patch.object(rave_cli, "OAuthManager", return_value=self.oauth_manager)
        self.patcher_platform = mock.patch.object(rave_cli, "PlatformManager", return_value=self.platform_manager)

        self.patcher_user.start()
        self.patcher_vm.start()
        self.patcher_oauth.start()
        self.patcher_platform.start()

    def tearDown(self) -> None:
        self.patcher_user.stop()
        self.patcher_vm.stop()
        self.patcher_oauth.stop()
        self.patcher_platform.stop()

    def test_user_sync_success(self) -> None:
        self.user_manager.sync_users_with_gitlab.return_value = {
            "success": True,
            "synced": 3,
            "added": 1,
            "updated": 2,
        }

        result = self.runner.invoke(rave_cli.cli, ["user", "sync"])

        self.assertEqual(result.exit_code, 0, result.output)
        self.user_manager.sync_users_with_gitlab.assert_called_once_with()
        self.assertIn("Sync complete", result.output)
        self.assertIn("Synced: 3", result.output)
        self.assertIn("Added: 1", result.output)
        self.assertIn("Updated: 2", result.output)

    def test_user_sync_failure(self) -> None:
        self.user_manager.sync_users_with_gitlab.return_value = {
            "success": False,
            "error": "boom",
        }

        result = self.runner.invoke(rave_cli.cli, ["user", "sync"])

        self.assertNotEqual(result.exit_code, 0, result.output)
        self.user_manager.sync_users_with_gitlab.assert_called_once_with()
        self.assertIn("Failed to sync", result.output)


if __name__ == "__main__":
    unittest.main()
