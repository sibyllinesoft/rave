#!/usr/bin/env python3
from __future__ import annotations

"""
RAVE VM Integration Test

Tests the complete VM creation -> boot -> service verification pipeline.
This replaces manual testing with automated verification.

Usage: python test_vm_integration.py
"""

import argparse
import json
import os
import signal
import socket
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional


class RAVEVMIntegrationTest:
    """Integration test for RAVE VM creation and service verification."""

    def __init__(
        self,
        profile: str = "development",
        keep_vm: bool = False,
        mode: str = "single",
        skip_build_images: bool = True,
        apps_profile: str = "appsPlane",
        data_host: str = "10.0.2.2",
        data_pg_port: int = 25432,
        data_redis_port: int = 26379,
        data_http_port: int = 18081,
        data_https_port: int = 18443,
        data_ssh_port: int = 2226,
        data_test_port: int = 18890,
        data_vm_name: Optional[str] = None,
        apps_vm_name: Optional[str] = None,
    ):
        self.profile = profile
        self.mode = mode
        self.apps_profile = apps_profile
        self.skip_build_images = skip_build_images
        self.repo_root = Path(__file__).resolve().parent
        self.cli_path = self.repo_root / "cli" / "rave"
        self.test_vm_name = f"integration-{profile}"
        self.data_vm_name = data_vm_name or f"{self.test_vm_name}-data"
        self.apps_vm_name = apps_vm_name or f"{self.test_vm_name}-apps"
        self.cleanup_on_success = not keep_vm
        self.results: Dict[str, Any] = {}
        self.temp_home = Path(tempfile.mkdtemp(prefix="rave-e2e-home-"))
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.temp_home)
        self._bootstrap_test_home()
        self.test_keypair = self._ensure_test_keypair()
        self._purge_stale_vm_processes()

        # Split-plane settings
        self.split_guest_host_ip = data_host
        self.data_plane_pg_port = data_pg_port
        self.data_plane_redis_port = data_redis_port
        self.data_plane_http_port = data_http_port
        self.data_plane_https_port = data_https_port
        self.data_plane_ssh_port = data_ssh_port
        self.data_plane_test_port = data_test_port
        self.split_vm_names: List[str] = []
        self.apps_https_port: Optional[int] = None

    def log(self, message: str, level: str = "INFO") -> None:
        """Log test progress."""
        print(f"[{level}] {message}")

    def _bootstrap_test_home(self) -> None:
        """Prepare isolated HOME containing Age key + config dirs."""
        age_dir = self.temp_home / ".config" / "sops" / "age"
        age_dir.mkdir(parents=True, exist_ok=True)
        age_key_path = age_dir / "keys.txt"
        if not age_key_path.exists():
            age_key_path.write_text("AGE-SECRET-KEY-1TESTKEY0000000000000000000000000000000000000000000000000000\n")
        self.env["SOPS_AGE_KEY_FILE"] = str(age_key_path)
        self.env.setdefault("LIBGUESTFS_BACKEND", "direct")
        (self.temp_home / ".config" / "rave" / "vms").mkdir(parents=True, exist_ok=True)
        (self.temp_home / ".ssh").mkdir(parents=True, exist_ok=True)

    def _ensure_test_keypair(self) -> str:
        key_path = self.temp_home / ".ssh" / "integration_ed25519"
        if not key_path.exists():
            subprocess.run([
                "ssh-keygen",
                "-t",
                "ed25519",
                "-N",
                "",
                "-f",
                str(key_path),
            ], check=True)
        return str(key_path)

    def _run_cli(
        self,
        args: list[str],
        timeout: int = 60,
        extra_env: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        return self.run_command([str(self.cli_path), *args], timeout=timeout, env=env)
        
    def run_command(
        self,
        cmd: list[str],
        timeout: int = 30,
        capture_output: bool = True,
        env: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """Run command and return result."""
        try:
            result = subprocess.run(
                cmd, 
                capture_output=capture_output,
                text=True,
                timeout=timeout,
                cwd=str(self.repo_root),
                env=env or self.env,
            )
            return {
                "success": result.returncode == 0,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "cmd": " ".join(cmd)
            }
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": f"Command timed out after {timeout}s",
                "cmd": " ".join(cmd)
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "cmd": " ".join(cmd)
            }
    
    def cleanup(self, force: bool = False, vm_names: Optional[List[str]] = None) -> None:
        """Clean up one or more test VMs."""
        targets = vm_names or [self.test_vm_name]
        for name in targets:
            self._teardown_vm(name)

        should_prune_home = force or self.cleanup_on_success
        if self.temp_home.exists() and should_prune_home:
            shutil.rmtree(self.temp_home, ignore_errors=True)

    def _teardown_vm(self, name: str) -> None:
        config_dir = self.temp_home / ".config" / "rave" / "vms"
        config_file = config_dir / f"{name}.json"

        self._run_cli(["vm", "stop", name], timeout=30)

        image_path: Optional[Path] = None
        if config_file.exists():
            try:
                vm_data = json.loads(config_file.read_text())
                image_path = Path(vm_data.get("image_path", ""))
            except json.JSONDecodeError:
                image_path = None
            config_file.unlink()
            self.log(f"📁 Removed config: {config_file}")

        if image_path and image_path.exists():
            try:
                image_path.unlink()
                self.log(f"🧼 Removed image: {image_path}")
            except OSError as exc:
                self.log(f"⚠️  Unable to remove image {image_path}: {exc}", "WARN")

    def _purge_stale_vm_processes(self) -> None:
        """Kill leftover integration VM instances from previous runs."""
        for name in {self.test_vm_name, self.data_vm_name, self.apps_vm_name}:
            pidfile = Path("/tmp") / f"rave-{name}.pid"
            if pidfile.exists():
                try:
                    pid = int(pidfile.read_text().strip())
                    os.kill(pid, signal.SIGTERM)
                    self.log(f"💀 Terminated stale VM process {pid} ({name})")
                except Exception as exc:
                    self.log(f"⚠️  Unable to kill stale VM process for {name}: {exc}", "WARN")
                finally:
                    pidfile.unlink(missing_ok=True)

    # ------------------------------------------------------------------
    # Split plane helpers
    # ------------------------------------------------------------------

    def _wait_for_port(self, host: str, port: int, timeout: int, label: str) -> bool:
        key = label.lower().replace(" ", "_") + "_port"
        self.log(f"⏳ Waiting for {label} on {host}:{port} (timeout {timeout}s)...")
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with socket.create_connection((host, port), timeout=5):
                    self.log(f"✅ {label} is reachable on {host}:{port}")
                    self.results[key] = {"success": True, "port": port}
                    return True
            except OSError:
                time.sleep(2)

        self.log(f"❌ Timeout waiting for {label} on {host}:{port}", "ERROR")
        self.results[key] = {"success": False, "port": port}
        return False

    def _check_https_endpoint(self, port: int, path: str, label: str) -> bool:
        if port <= 0:
            self.log(f"❌ Invalid HTTPS port for {label}", "ERROR")
            return False
        url = f"https://localhost:{port}{path}"
        key = label.lower().replace(" ", "_")
        result = self.run_command(
            ["curl", "-k", "-s", "-o", "/dev/null", "-w", "%{http_code}", url],
            timeout=30,
        )
        self.results[key] = result
        if not result["success"]:
            self.log(f"❌ {label} check failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
        status = (result.get("stdout") or "").strip()
        if status and status[0] in {"2", "3"}:
            self.log(f"✅ {label} responded with HTTP {status}")
            return True
        self.log(f"❌ {label} returned unexpected status '{status}'", "ERROR")
        return False

    def _create_data_plane_vm(self) -> bool:
        self.log("🏗️  Creating data-plane VM...")
        args = [
            "vm",
            "create",
            self.data_vm_name,
            "--profile",
            "dataPlane",
            "--keypair",
            self.test_keypair,
            "--http-port",
            str(self.data_plane_http_port),
            "--https-port",
            str(self.data_plane_https_port),
            "--ssh-port",
            str(self.data_plane_ssh_port),
            "--test-port",
            str(self.data_plane_test_port),
            "--postgres-port",
            str(self.data_plane_pg_port),
            "--redis-port",
            str(self.data_plane_redis_port),
        ]
        if self.skip_build_images:
            args.append("--skip-build")
        result = self._run_cli(args, timeout=900)
        self.results["data_plane_create"] = result
        if not result["success"]:
            self.log(f"❌ Data-plane creation failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
        if self.data_vm_name not in self.split_vm_names:
            self.split_vm_names.append(self.data_vm_name)
        return True

    def _create_apps_plane_vm(self) -> bool:
        self.log("🏗️  Creating apps-plane VM...")
        args = [
            "vm",
            "create",
            self.apps_vm_name,
            "--profile",
            self.apps_profile,
            "--keypair",
            self.test_keypair,
        ]
        if self.skip_build_images:
            args.append("--skip-build")

        data_env = {
            "RAVE_DATA_HOST": self.split_guest_host_ip,
            "RAVE_DATA_PG_PORT": str(self.data_plane_pg_port),
            "RAVE_DATA_REDIS_PORT": str(self.data_plane_redis_port),
        }
        result = self._run_cli(args, timeout=1200, extra_env=data_env)
        self.results["apps_plane_create"] = result
        if not result["success"]:
            self.log(f"❌ Apps-plane creation failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
        if self.apps_vm_name not in self.split_vm_names:
            self.split_vm_names.append(self.apps_vm_name)
        return True

    def _start_split_vm(self, name: str, label: str, timeout: int = 420) -> bool:
        result = self._run_cli(["vm", "start", name], timeout=timeout)
        key = f"{label}_start"
        self.results[key] = result
        if not result["success"]:
            self.log(f"❌ Failed to start {label}: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
        self.log(f"✅ {label} started successfully")
        return True

    def _wait_for_apps_https(self) -> bool:
        ports = self.get_vm_ports(self.apps_vm_name)
        if not ports or "https" not in ports:
            self.log("❌ Could not determine apps-plane HTTPS port", "ERROR")
            return False
        self.apps_https_port = ports["https"]
        return self._wait_for_port("127.0.0.1", self.apps_https_port, 600, "apps-plane https")

    def _run_split_suite(self) -> bool:
        self.log("🧪 Starting split-plane integration tests (data + apps)")
        steps = [
            ("Prerequisites", self.test_prerequisites),
            ("Data plane creation", self._create_data_plane_vm),
            ("Data plane start", lambda: self._start_split_vm(self.data_vm_name, "data_plane")),
            (
                "Data postgres port",
                lambda: self._wait_for_port("127.0.0.1", self.data_plane_pg_port, 240, "data-plane postgres"),
            ),
            (
                "Data redis port",
                lambda: self._wait_for_port("127.0.0.1", self.data_plane_redis_port, 180, "data-plane redis"),
            ),
            ("Apps plane creation", self._create_apps_plane_vm),
            ("Apps plane start", lambda: self._start_split_vm(self.apps_vm_name, "apps_plane")),
            ("Apps https port", self._wait_for_apps_https),
            (
                "Apps root endpoint",
                lambda: self._check_https_endpoint(self.apps_https_port or 0, "/", "apps_root"),
            ),
            (
                "Mattermost proxy",
                lambda: self._check_https_endpoint(
                    self.apps_https_port or 0, "/mattermost/", "apps_mattermost"
                ),
            ),
        ]

        passed = 0
        failed = 0
        for name, func in steps:
            self.log(f"\n{'=' * 50}")
            self.log(f"🧪 Running: {name}")
            try:
                success = func()
            except Exception as exc:  # pragma: no cover - defensive logging
                success = False
                self.log(f"💥 {name}: ERROR - {exc}", "ERROR")

            if success:
                passed += 1
                self.log(f"✅ {name}: PASSED")
            else:
                failed += 1
                self.log(f"❌ {name}: FAILED")
                break

        self.log(f"\n{'=' * 50}")
        self.log("📊 SPLIT-PLANE TEST RESULTS:")
        self.log(f"   ✅ Passed: {passed}")
        self.log(f"   ❌ Failed: {failed}")
        self.log(
            f"   📈 Success Rate: {(passed / (passed + failed) * 100) if (passed + failed) else 0:.1f}%"
        )

        with open("integration_test_results.json", "w") as f:
            json.dump(self.results, f, indent=2)
        self.log("📁 Detailed results saved to integration_test_results.json")

        if failed == 0 and self.cleanup_on_success:
            self.cleanup(force=True, vm_names=self.split_vm_names)
        elif failed > 0:
            self.log("⚠️  Split-plane VMs left running for debugging")

        return failed == 0
    
    def test_prerequisites(self) -> bool:
        """Test that all prerequisites are met."""
        self.log("🔍 Testing prerequisites...")
        
        result = self._run_cli(["prerequisites"])
        self.results["prerequisites"] = result
        
        if not result["success"]:
            self.log(f"❌ Prerequisites failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        self.log("✅ Prerequisites satisfied")
        return True
    
    def test_vm_creation(self) -> bool:
        """Test VM creation."""
        self.log(f"🚀 Testing VM creation: {self.test_vm_name}")
        args = [
            "vm",
            "create",
            self.test_vm_name,
            "--profile",
            self.profile,
            "--keypair",
            self.test_keypair,
        ]
        if self.skip_build_images:
            args.append("--skip-build")

        result = self._run_cli(args, timeout=600)
        
        self.results["vm_creation"] = result
        
        if not result["success"]:
            self.log(f"❌ VM creation failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        self.log("✅ VM created successfully")
        return True
    
    def test_vm_start(self) -> bool:
        """Test VM startup."""
        self.log(f"▶️  Testing VM startup: {self.test_vm_name}")
        
        result = self._run_cli([
            "vm",
            "start",
            self.test_vm_name,
        ], timeout=420)
        
        self.results["vm_start"] = result
        
        if not result["success"]:
            self.log(f"❌ VM start failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        self.log("✅ VM started successfully")
        return True
    
    def test_vm_status(self) -> bool:
        """Test VM status check."""
        self.log(f"📊 Testing VM status: {self.test_vm_name}")
        
        result = self._run_cli([
            "vm",
            "status",
            self.test_vm_name,
        ])
        
        self.results["vm_status"] = result
        
        if not result["success"]:
            self.log(f"❌ VM status check failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        if "running" not in result["stdout"].lower():
            self.log(f"❌ VM is not running: {result['stdout']}", "ERROR")
            return False
            
        self.log("✅ VM is running")
        return True
    
    def get_vm_ports(self, vm_name: Optional[str] = None) -> Optional[Dict[str, int]]:
        """Extract VM port mappings."""
        target_name = vm_name or self.test_vm_name
        config_file = self.temp_home / ".config" / "rave" / "vms" / f"{target_name}.json"
        if config_file.exists():
            try:
                data = json.loads(config_file.read_text())
                return data.get("ports")
            except json.JSONDecodeError as exc:
                self.log(f"⚠️  Could not parse VM config: {exc}", "WARN")
        return None

    def _ssh_exec(self, command: str, timeout: int = 30) -> Dict[str, Any]:
        ports = self.get_vm_ports()
        if not ports or "ssh" not in ports:
            return {"success": False, "error": "SSH port unknown"}
        ssh_port = ports["ssh"]
        return self.run_command(
            [
                "ssh",
                "-i",
                self.test_keypair,
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
                "-o",
                "ConnectTimeout=20",
                "-p",
                str(ssh_port),
                "root@localhost",
                command,
            ],
            timeout=timeout,
        )
    
    def test_ssh_access(self) -> bool:
        """Test SSH access to VM."""
        self.log("🔑 Testing SSH access...")
        
        # Wait for VM to fully boot
        boot_wait = 150
        self.log(f"⏳ Waiting {boot_wait}s for VM boot...")
        time.sleep(boot_wait)
        
        # Test RAVE CLI SSH with retries
        max_attempts = 5
        retry_delay = 45
        for attempt in range(max_attempts):
            self.log(f"🔄 SSH attempt {attempt + 1}/{max_attempts}...")
            result = self.run_command([
                "bash",
                "-c",
                f"echo 'systemctl --version' | {self.cli_path} vm ssh {self.test_vm_name}"
            ], timeout=45)
            
            if result["success"] and "systemd" in result["stdout"]:
                self.log("✅ SSH access working via RAVE CLI")
                self.results["ssh_access"] = result
                return True
            
            if attempt < max_attempts - 1:  # Don't wait after last attempt
                self.log(f"⏳ Waiting {retry_delay}s before retry {attempt + 2}...")
                time.sleep(retry_delay)
        
        self.results["ssh_access"] = result
        
        self.log("🔐 Trying direct SSH with the injected key...")
        result = self._ssh_exec("systemctl --version", timeout=45)
        self.results["direct_ssh"] = result
        if result["success"] and "systemd" in result.get("stdout", ""):
            self.log("✅ SSH access working via keypair")
            return True
       
        self.log("❌ SSH access failed with all methods", "ERROR")
        return False
    
    def test_service_status(self) -> bool:
        """Test that key services are running."""
        if "ssh_access" not in self.results or not self.results["ssh_access"]["success"]:
            self.log("⚠️  Skipping service check - SSH not working", "WARN")
            return False
            
        self.log("🔍 Testing service status...")
        
        services = ["traefik", "postgresql", "nats"]
        all_services_ok = True
        
        for service in services:
            self.log(f"   Checking {service}...")
            result = self._ssh_exec(f"systemctl is-active {service}", timeout=30)
            
            if result["success"] and "active" in result["stdout"]:
                self.log(f"   ✅ {service} is active")
            else:
                self.log(f"   ❌ {service} is not active", "WARN")
                all_services_ok = False
                
        self.results["service_status"] = {"all_services_ok": all_services_ok}
        return all_services_ok
    
    def test_http_services(self) -> bool:
        """Test HTTP service accessibility."""
        self.log("🌐 Testing HTTP services...")
        
        ports = self.get_vm_ports()
        if not ports:
            self.log("❌ Could not determine VM ports", "ERROR")
            return False
            
        # Test HTTP port
        if "http" in ports:
            http_port = ports["http"]
            result = self.run_command([
                "curl", "-I", "-m", "10", 
                f"http://localhost:{http_port}/"
            ], timeout=15)
            
            self.results["http_test"] = result
            
            if result["success"] or "200" in result["stdout"] or "301" in result["stdout"]:
                self.log(f"✅ HTTP service responding on port {http_port}")
                return True
        
        # Test HTTPS port
        if "https" in ports:
            https_port = ports["https"]
            result = self.run_command([
                "curl", "-I", "-k", "-m", "10",
                f"https://localhost:{https_port}/"
            ], timeout=15)
            
            self.results["https_test"] = result
            
            if result["success"] or "200" in result["stdout"]:
                self.log(f"✅ HTTPS service responding on port {https_port}")
                return True
        
        self.log("❌ No HTTP services responding", "WARN")
        return False
    
    def run_tests(self) -> bool:
        """Run all integration tests."""
        if self.mode == "split":
            return self._run_split_suite()
        self.log("🧪 Starting RAVE VM Integration Tests")
        
        tests = [
            ("Prerequisites", self.test_prerequisites),
            ("VM Creation", self.test_vm_creation),
            ("VM Start", self.test_vm_start),
            ("VM Status", self.test_vm_status),
            ("SSH Access", self.test_ssh_access),
            ("Service Status", self.test_service_status),
            ("HTTP Services", self.test_http_services),
        ]
        
        passed = 0
        failed = 0
        
        for test_name, test_func in tests:
            try:
                self.log(f"\n{'='*50}")
                self.log(f"🧪 Running: {test_name}")
                
                success = test_func()
                if success:
                    passed += 1
                    self.log(f"✅ {test_name}: PASSED")
                else:
                    failed += 1
                    self.log(f"❌ {test_name}: FAILED")
                    
            except Exception as e:
                failed += 1
                self.log(f"💥 {test_name}: ERROR - {e}", "ERROR")
        
        self.log(f"\n{'='*50}")
        self.log(f"📊 INTEGRATION TEST RESULTS:")
        self.log(f"   ✅ Passed: {passed}")
        self.log(f"   ❌ Failed: {failed}")
        self.log(f"   📈 Success Rate: {(passed/(passed+failed)*100):.1f}%")
        
        # Save detailed results
        with open("integration_test_results.json", "w") as f:
            json.dump(self.results, f, indent=2)
        self.log("📁 Detailed results saved to integration_test_results.json")
        
        if failed == 0 and self.cleanup_on_success:
            self.cleanup(force=True)
        elif failed > 0:
            self.log("⚠️  Test VM left running for debugging")

        return failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run RAVE end-to-end VM tests")
    parser.add_argument("--profile", default="development", help="VM profile to test (default: development)")
    parser.add_argument("--keep-vm", action="store_true", help="Leave the VM/VHD around after tests for debugging")
    parser.add_argument(
        "--mode",
        choices=["single", "split"],
        default="single",
        help="Test mode: single VM or split data/apps",
    )
    parser.add_argument(
        "--build-images",
        action="store_true",
        help="Run nix builds during vm create instead of reusing cached images",
    )
    parser.add_argument(
        "--apps-profile",
        default="appsPlane",
        help="Flake profile to use for the apps plane when --mode split",
    )
    parser.add_argument(
        "--data-host",
        default="10.0.2.2",
        help="Host IP address as seen from the apps-plane VM (defaults to QEMU usernet gateway)",
    )
    parser.add_argument("--data-pg-port", type=int, default=25432, help="Host port forwarding to data-plane Postgres")
    parser.add_argument("--data-redis-port", type=int, default=26379, help="Host port forwarding to data-plane Redis")
    parser.add_argument("--data-http-port", type=int, default=18081, help="Host HTTP port for the data-plane VM")
    parser.add_argument("--data-https-port", type=int, default=18443, help="Host HTTPS port for the data-plane VM")
    parser.add_argument("--data-ssh-port", type=int, default=2226, help="Host SSH port for the data-plane VM")
    parser.add_argument("--data-test-port", type=int, default=18890, help="Host test/status port for the data-plane VM")
    parser.add_argument("--data-vm-name", default=None, help="Explicit name for the data-plane VM")
    parser.add_argument("--apps-vm-name", default=None, help="Explicit name for the apps-plane VM")
    args = parser.parse_args()

    test = RAVEVMIntegrationTest(
        profile=args.profile,
        keep_vm=args.keep_vm,
        mode=args.mode,
        skip_build_images=not args.build_images,
        apps_profile=args.apps_profile,
        data_host=args.data_host,
        data_pg_port=args.data_pg_port,
        data_redis_port=args.data_redis_port,
        data_http_port=args.data_http_port,
        data_https_port=args.data_https_port,
        data_ssh_port=args.data_ssh_port,
        data_test_port=args.data_test_port,
        data_vm_name=args.data_vm_name,
        apps_vm_name=args.apps_vm_name,
    )
    success = test.run_tests()
    sys.exit(0 if success else 1)
