"""Unit tests for VMManager helper utilities."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Dict, Optional
from unittest import mock

CLI_DIR = Path(__file__).resolve().parents[2] / "apps" / "cli"
if str(CLI_DIR) not in sys.path:
    sys.path.insert(0, str(CLI_DIR))

from vm_manager import VMManager  # type: ignore  # Imported via adjusted sys.path


class VMManagerPortRangeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.manager = VMManager(Path(self._tmpdir.name))

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    @mock.patch.object(VMManager, "_host_port_available", return_value=True)
    def test_get_port_range_defaults(self, mock_available: mock.MagicMock) -> None:
        """Defaults should return the configured port tuple when free."""
        http, https, ssh, test = self.manager._get_port_range()
        self.assertEqual(http, self.manager.port_config["http"])
        self.assertEqual(https, self.manager.port_config["https"])
        self.assertEqual(ssh, self.manager.port_config["ssh"])
        self.assertEqual(test, self.manager.port_config["test"])
        # Ensure we checked each preferred port once
        expected_calls = [
            mock.call(self.manager.port_config[key])
            for key in ("http", "https", "ssh", "test")
        ]
        mock_available.assert_has_calls(expected_calls, any_order=False)

    def test_get_port_range_skips_conflicts(self) -> None:
        """When a preferred port is busy the manager should choose the next free port."""
        responses = {
            self.manager.port_config["http"]: [False],  # force fallback
            self.manager.port_config["http"] + 1: [True],
            self.manager.port_config["https"]: [True],
            self.manager.port_config["ssh"]: [False],
            self.manager.port_config["ssh"] + 1: [False],
            self.manager.port_config["ssh"] + 2: [True],
            self.manager.port_config["test"]: [True],
        }

        def fake_available(self: VMManager, port: int) -> bool:  # type: ignore[override]
            values = responses.setdefault(port, [True])
            if len(values) > 1:
                return values.pop(0)
            return values[0]

        with mock.patch.object(VMManager, "_host_port_available", new=fake_available):
            http, https, ssh, test = self.manager._get_port_range()

        self.assertNotEqual(http, self.manager.port_config["http"])
        self.assertEqual(http, self.manager.port_config["http"] + 1)
        self.assertEqual(https, self.manager.port_config["https"])
        self.assertEqual(ssh, self.manager.port_config["ssh"] + 2)
        self.assertEqual(test, self.manager.port_config["test"])


class VMManagerAgeKeyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.workdir = Path(self._tmpdir.name)
        self.manager = VMManager(self.workdir / "vms")
        self.image = self.workdir / "image.qcow2"
        self.image.write_bytes(b"qcow")
        self.age_key = self.workdir / "age.key"
        self.age_key.write_text("AGE-KEY")

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def test_install_age_key_missing_file(self) -> None:
        missing = self.workdir / "nope.key"
        result = self.manager._install_age_key_into_image(str(self.image), missing)
        self.assertFalse(result["success"])
        self.assertIn("Age key not found", result["error"])

    def test_install_age_key_requires_guestfish(self) -> None:
        with mock.patch("vm_manager.shutil.which", return_value=None):
            result = self.manager._install_age_key_into_image(str(self.image), self.age_key)
        self.assertFalse(result["success"])
        self.assertIn("guestfish is not installed", result["error"])

    def test_install_age_key_invokes_guestfish(self) -> None:
        with mock.patch("vm_manager.shutil.which", return_value="/usr/bin/guestfish"), mock.patch(
            "vm_manager.subprocess.run", return_value=mock.Mock(returncode=0, stderr="", stdout="")
        ) as run_mock:
            result = self.manager._install_age_key_into_image(str(self.image), self.age_key)

        self.assertTrue(result["success"])
        run_mock.assert_called_once()
        args, kwargs = run_mock.call_args
        self.assertIn("guestfish", args[0][0])


class VMManagerCreateTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.workdir = Path(self._tmpdir.name)
        self.manager = VMManager(self.workdir / "vms")

        # Generate a fake keypair
        self.private_key = self.workdir / "id_ed25519"
        self.private_key.write_text("PRIVATE")
        self.public_key = self.private_key.with_suffix(".pub")
        self.public_key.write_text("ssh-ed25519 AAAATEST test@example")

        # Mocked images
        self.build_image = self.workdir / "result-image.qcow2"
        self.build_image.write_bytes(b"fake qcow build")
        self.default_image = self.workdir / "rave-development-localhost.qcow2"
        self.default_image.write_bytes(b"default profile image")

    def tearDown(self) -> None:
        self._tmpdir.cleanup()

    def _run_create(
        self,
        *,
        build_success: bool = True,
        age_key: bool = True,
        skip_build: bool = False,
        profile: str = "development",
        profile_attr: str = "development",
        custom_ports: Optional[Dict[str, int]] = None,
    ) -> tuple[dict, dict]:
        age_key_path = None
        if age_key:
            age_key_path = self.workdir / "age.txt"
            age_key_path.write_text("AGE-KEY")

        port_overrides = custom_ports or {"http": 9000}

        build_payload = {"success": build_success}
        if build_success:
            build_payload["image"] = self.build_image
        else:
            build_payload["error"] = "build failed"

        with mock.patch.object(
            VMManager, "_build_vm_image", return_value=build_payload
        ) as build_mock, mock.patch.object(
            VMManager, "_inject_ssh_key", return_value={"success": True}
        ) as inject_mock, mock.patch.object(
            VMManager,
            "_install_age_key_into_image",
            return_value={"success": True},
        ) as age_mock:
            result = self.manager.create_vm(
                company_name="acme",
                keypair_path=str(self.private_key),
                profile=profile,
                profile_attr=profile_attr,
                default_image_path=self.default_image,
                age_key_path=age_key_path,
                custom_ports=port_overrides,
                skip_build=skip_build,
            )

        if skip_build:
            build_mock.assert_not_called()
        else:
            self.assertTrue(build_mock.called)
        self.assertTrue(result["success"])
        config_path = self.manager._get_vm_config_path("acme")
        self.assertTrue(config_path.exists())
        data = json.loads(config_path.read_text())
        self.assertEqual(data["profile"], profile)
        self.assertEqual(data["ports"]["http"], 9000)
        # Verify injected path matches target copy
        target = Path(data["image_path"])
        self.assertTrue(target.exists())
        inject_mock.assert_called_once_with(str(target), mock.ANY)
        if age_key:
            age_mock.assert_called_once()
        else:
            age_mock.assert_not_called()
        return result, data

    def test_create_vm_uses_built_image(self) -> None:
        result, data = self._run_create(build_success=True, age_key=True)
        self.assertIn("age_key_path", data.get("secrets", {}))

    def test_create_vm_falls_back_to_default_image(self) -> None:
        result, data = self._run_create(build_success=False, age_key=False)
        # Target image should contain the default image contents
        target = Path(data["image_path"])
        self.assertEqual(target.read_bytes(), self.default_image.read_bytes())

    def test_create_vm_skip_build_reuses_existing_image(self) -> None:
        result, data = self._run_create(build_success=True, age_key=False, skip_build=True)
        target = Path(data["image_path"])
        self.assertEqual(target.read_bytes(), self.default_image.read_bytes())

    def test_dataplane_ports_forwarded_by_default(self) -> None:
        _, data = self._run_create(profile="dataPlane", profile_attr="dataPlane")
        self.assertEqual(
            data["ports"]["postgres"], self.manager.DATA_PLANE_PORT_DEFAULTS["postgres"]
        )
        self.assertEqual(
            data["ports"]["redis"], self.manager.DATA_PLANE_PORT_DEFAULTS["redis"]
        )

    def test_dataplane_ports_honor_custom_overrides(self) -> None:
        overrides = {"postgres": 40000, "redis": 40010}
        merged = {"http": 9000, **overrides}
        _, data = self._run_create(
            profile="dataPlane",
            profile_attr="dataPlane",
            custom_ports=merged,
        )
        self.assertEqual(data["ports"]["postgres"], overrides["postgres"])
        self.assertEqual(data["ports"]["redis"], overrides["redis"])

    def test_create_vm_errors_when_no_image_available(self) -> None:
        # Remove default image to force failure when build fails
        self.default_image.unlink()
        with mock.patch.object(
            VMManager, "_build_vm_image", return_value={"success": False, "error": "boom"}
        ):
            result = self.manager.create_vm(
                company_name="broken",
                keypair_path=str(self.private_key),
                profile="development",
                profile_attr="development",
                default_image_path=self.default_image,
                age_key_path=None,
            )
        self.assertFalse(result["success"])
        self.assertIn("No VM image available", result["error"])

    def test_create_vm_warns_when_age_embed_fails(self) -> None:
        expected_age_path = self.workdir / "age.txt"
        expected_age_path.write_text("AGE-KEY")

        failure = {"success": False, "error": "guestfish boom"}

        with mock.patch.object(
            VMManager, "_build_vm_image", return_value={"success": True, "image": self.build_image}
        ), mock.patch.object(
            VMManager, "_inject_ssh_key", return_value={"success": True}
        ), mock.patch.object(
            VMManager,
            "_install_age_key_into_image",
            return_value=failure,
        ):
            result = self.manager.create_vm(
                company_name="acme",
                keypair_path=str(self.private_key),
                profile="development",
                profile_attr="development",
                default_image_path=self.default_image,
                age_key_path=expected_age_path,
                custom_ports=None,
            )

        self.assertTrue(result["success"])
        warnings = result.get("warnings", [])
        self.assertTrue(warnings)
        self.assertIn("guestfish boom", warnings[0])

        config_path = self.manager._get_vm_config_path("acme")
        data = json.loads(config_path.read_text())
        secrets = data.get("secrets", {})
        self.assertEqual(secrets.get("age_key_path"), str(expected_age_path))
        self.assertFalse(secrets.get("age_key_installed"))
        self.assertEqual(secrets.get("age_key_embed_error"), "guestfish boom")


if __name__ == "__main__":
    unittest.main()
