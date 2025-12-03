"""Lightweight tests for PlatformManager helpers."""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

CLI_DIR = Path(__file__).resolve().parents[2] / "apps" / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from platform_utils import PlatformManager  # noqa: E402


class PlatformManagerTests(unittest.TestCase):
    def test_get_nix_build_command_returns_plain_build(self) -> None:
        pm = PlatformManager()
        self.assertEqual(pm.get_nix_build_command(), ["nix", "build"])

    def test_get_config_dir_respects_xdg(self) -> None:
        pm = PlatformManager()
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "/tmp/rave-xdg"}):
            self.assertEqual(pm.get_config_dir(), Path("/tmp/rave-xdg") / "rave")

    def test_check_prerequisites_surfaces_missing(self) -> None:
        pm = PlatformManager()
        with mock.patch("shutil.which", return_value=None):
            result = pm.check_prerequisites()
        self.assertFalse(result["success"])
        self.assertIn("nix", result["missing"])


if __name__ == "__main__":
    unittest.main()
