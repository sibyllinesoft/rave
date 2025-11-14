"""Unit tests for PlatformManager helpers."""
from __future__ import annotations

import platform
import sys
import unittest
from pathlib import Path
from unittest import mock

CLI_DIR = Path(__file__).resolve().parents[2] / "apps" / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from platform_utils import PlatformManager


class PlatformManagerTests(unittest.TestCase):
    def test_is_macos_true_when_system_darwin(self) -> None:
        with mock.patch.object(platform, "system", return_value="Darwin"), mock.patch.object(
            platform, "machine", return_value="x86_64"
        ):
            pm = PlatformManager()
        self.assertTrue(pm.is_macos())
        self.assertFalse(pm.is_linux())

    def test_get_nix_build_command_apple_silicon(self) -> None:
        with mock.patch.object(platform, "system", return_value="Darwin"), mock.patch.object(
            platform, "machine", return_value="arm64"
        ):
            pm = PlatformManager()
        cmd = pm.get_nix_build_command()
        self.assertIn("--system", cmd)
        self.assertIn("x86_64-darwin", cmd)

    def test_get_nix_build_command_linux_default(self) -> None:
        with mock.patch.object(platform, "system", return_value="Linux"), mock.patch.object(
            platform, "machine", return_value="x86_64"
        ):
            pm = PlatformManager()
        cmd = pm.get_nix_build_command()
        self.assertEqual(cmd, ["nix", "build"])


if __name__ == "__main__":
    unittest.main()
