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
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Optional


class RAVEVMIntegrationTest:
    """Integration test for RAVE VM creation and service verification."""

    def __init__(self, profile: str = "development", keep_vm: bool = False):
        self.profile = profile
        self.repo_root = Path(__file__).resolve().parent
        self.cli_path = self.repo_root / "cli" / "rave"
        self.test_vm_name = f"integration-{profile}"
        self.cleanup_on_success = not keep_vm
        self.results: Dict[str, Any] = {}
        self.temp_home = Path(tempfile.mkdtemp(prefix="rave-e2e-home-"))
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.temp_home)
        self._bootstrap_test_home()
        self.test_keypair = self._ensure_test_keypair()
        self._purge_stale_vm_processes()

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

    def _run_cli(self, args: list[str], timeout: int = 60) -> Dict[str, Any]:
        return self.run_command([str(self.cli_path), *args], timeout=timeout)
        
    def run_command(self, cmd: list[str], timeout: int = 30, capture_output: bool = True) -> Dict[str, Any]:
        """Run command and return result."""
        try:
            result = subprocess.run(
                cmd, 
                capture_output=capture_output,
                text=True,
                timeout=timeout,
                cwd=str(self.repo_root),
                env=self.env,
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
    
    def cleanup(self, force: bool = False) -> None:
        """Clean up test VM."""
        self.log("🧹 Cleaning up test VM...")
        self._run_cli(["vm", "stop", self.test_vm_name], timeout=30)

        config_file = self.temp_home / ".config" / "rave" / "vms" / f"{self.test_vm_name}.json"
        image_path = None
        if config_file.exists():
            try:
                vm_data = json.loads(config_file.read_text())
                image_path = Path(vm_data.get("image_path", ""))
            except json.JSONDecodeError:
                pass
            config_file.unlink()
            self.log(f"📁 Removed config: {config_file}")

        if image_path and image_path.exists():
            image_path.unlink()
            self.log(f"🧼 Removed image: {image_path}")

        should_prune_home = force or self.cleanup_on_success
        if self.temp_home.exists() and should_prune_home:
            shutil.rmtree(self.temp_home, ignore_errors=True)

    def _purge_stale_vm_processes(self) -> None:
        """Kill leftover integration VM instances from previous runs."""
        pidfile = Path("/tmp") / f"rave-{self.test_vm_name}.pid"
        if pidfile.exists():
            try:
                pid = int(pidfile.read_text().strip())
                os.kill(pid, signal.SIGTERM)
                self.log(f"💀 Terminated stale VM process {pid}")
            except Exception as exc:
                self.log(f"⚠️  Unable to kill stale VM process: {exc}", "WARN")
            finally:
                pidfile.unlink(missing_ok=True)

        image_path = self.repo_root / f"{self.test_vm_name}-{self.profile}.qcow2"
        if image_path.exists():
            try:
                image_path.unlink()
                self.log(f"🧹 Removed stale VM image {image_path}")
            except OSError as exc:
                self.log(f"⚠️  Unable to remove stale image {image_path}: {exc}", "WARN")
    
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
        
        result = self._run_cli([
            "vm",
            "create",
            self.test_vm_name,
            "--profile",
            self.profile,
            "--keypair",
            self.test_keypair,
            "--skip-build",
        ], timeout=600)
        
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
    
    def get_vm_ports(self) -> Optional[Dict[str, int]]:
        """Extract VM port mappings."""
        config_file = self.temp_home / ".config" / "rave" / "vms" / f"{self.test_vm_name}.json"
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
        
        services = ["nginx", "postgresql", "nats"]
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
    args = parser.parse_args()

    test = RAVEVMIntegrationTest(profile=args.profile, keep_vm=args.keep_vm)
    success = test.run_tests()
    sys.exit(0 if success else 1)
