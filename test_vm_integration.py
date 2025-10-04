#!/usr/bin/env python3
"""
RAVE VM Integration Test

Tests the complete VM creation -> boot -> service verification pipeline.
This replaces manual testing with automated verification.

Usage: python test_vm_integration.py
"""

import subprocess
import time
import json
import sys
import os
from pathlib import Path
from typing import Dict, Any, Optional


class RAVEVMIntegrationTest:
    """Integration test for RAVE VM creation and service verification."""
    
    def __init__(self):
        self.test_vm_name = "integration-test"
        self.test_keypair = "~/.ssh/rave-demo"
        self.cleanup_on_success = True
        self.results = {}
        
    def log(self, message: str, level: str = "INFO"):
        """Log test progress."""
        print(f"[{level}] {message}")
        
    def run_command(self, cmd: list, timeout: int = 30, capture_output: bool = True) -> Dict[str, Any]:
        """Run command and return result."""
        try:
            result = subprocess.run(
                cmd, 
                capture_output=capture_output,
                text=True,
                timeout=timeout,
                cwd="/home/nathan/Projects/rave"
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
    
    def cleanup(self):
        """Clean up test VM."""
        self.log("🧹 Cleaning up test VM...")
        
        # Stop VM if running
        self.run_command(["./cli/rave", "vm", "stop", self.test_vm_name])
        
        # Remove VM files
        vm_image = f"{self.test_vm_name}-dev.qcow2"
        if Path(vm_image).exists():
            os.remove(vm_image)
            
        # Remove config file (check both locations)
        config_locations = [
            Path.home() / ".rave" / "vms" / f"{self.test_vm_name}.json",
            Path.home() / ".config" / "rave" / "vms" / f"{self.test_vm_name}.json"
        ]
        for config_file in config_locations:
            if config_file.exists():
                os.remove(config_file)
                self.log(f"📁 Removed config: {config_file}")
                
        # Also copy a working base image for the test
        working_image = "rave-complete.qcow2"
        if Path(working_image).exists():
            import shutil
            shutil.copy2(working_image, vm_image)
            self.log(f"📋 Copied working base image: {working_image} -> {vm_image}")
    
    def test_prerequisites(self) -> bool:
        """Test that all prerequisites are met."""
        self.log("🔍 Testing prerequisites...")
        
        result = self.run_command(["./cli/rave", "prerequisites"])
        self.results["prerequisites"] = result
        
        if not result["success"]:
            self.log(f"❌ Prerequisites failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        self.log("✅ Prerequisites satisfied")
        return True
    
    def test_vm_creation(self) -> bool:
        """Test VM creation."""
        self.log(f"🚀 Testing VM creation: {self.test_vm_name}")
        
        result = self.run_command([
            "./cli/rave", "vm", "create", 
            self.test_vm_name, 
            "--keypair", self.test_keypair
        ], timeout=120)  # VM creation can take time
        
        self.results["vm_creation"] = result
        
        if not result["success"]:
            self.log(f"❌ VM creation failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        self.log("✅ VM created successfully")
        return True
    
    def test_vm_start(self) -> bool:
        """Test VM startup."""
        self.log(f"▶️  Testing VM startup: {self.test_vm_name}")
        
        result = self.run_command([
            "./cli/rave", "vm", "start", self.test_vm_name
        ], timeout=60)
        
        self.results["vm_start"] = result
        
        if not result["success"]:
            self.log(f"❌ VM start failed: {result.get('stderr', result.get('error'))}", "ERROR")
            return False
            
        self.log("✅ VM started successfully")
        return True
    
    def test_vm_status(self) -> bool:
        """Test VM status check."""
        self.log(f"📊 Testing VM status: {self.test_vm_name}")
        
        result = self.run_command([
            "./cli/rave", "vm", "status", self.test_vm_name
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
        try:
            # Find QEMU process for our VM
            result = subprocess.run([
                "ps", "aux"
            ], capture_output=True, text=True)
            
            for line in result.stdout.split('\n'):
                if self.test_vm_name in line and "qemu" in line:
                    # Parse hostfwd arguments
                    ports = {}
                    parts = line.split()
                    for i, part in enumerate(parts):
                        if part.startswith("hostfwd=tcp::"):
                            port_mapping = part.split(":")
                            if len(port_mapping) >= 4:
                                host_port = port_mapping[2]
                                vm_port = port_mapping[3].split("-")[0]
                                if vm_port == "80":
                                    ports["http"] = int(host_port)
                                elif vm_port == "443":
                                    ports["https"] = int(host_port)
                                elif vm_port == "22":
                                    ports["ssh"] = int(host_port)
                                elif vm_port == "8080":
                                    ports["status"] = int(host_port)
                    return ports
        except Exception as e:
            self.log(f"⚠️  Could not parse VM ports: {e}", "WARN")
            
        return None
    
    def test_ssh_access(self) -> bool:
        """Test SSH access to VM."""
        self.log("🔑 Testing SSH access...")
        
        # Wait for VM to fully boot
        self.log("⏳ Waiting 90s for VM boot...")
        time.sleep(90)
        
        # Test RAVE CLI SSH with retries
        for attempt in range(3):
            self.log(f"🔄 SSH attempt {attempt + 1}/3...")
            result = self.run_command([
                "bash", "-c", 
                f"echo 'systemctl --version' | ./cli/rave vm ssh {self.test_vm_name}"
            ], timeout=30)
            
            if result["success"] and "systemd" in result["stdout"]:
                self.log("✅ SSH access working via RAVE CLI")
                self.results["ssh_access"] = result
                return True
            
            if attempt < 2:  # Don't wait after last attempt
                self.log(f"⏳ Waiting 30s before retry {attempt + 2}...")
                time.sleep(30)
        
        self.results["ssh_access"] = result
        
        # Try direct SSH with password
        ports = self.get_vm_ports()
        if ports and "ssh" in ports:
            ssh_port = ports["ssh"]
            self.log(f"🔐 Trying direct SSH on port {ssh_port}...")
            
            result = self.run_command([
                "sshpass", "-p", "debug123",
                "ssh", "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=10",
                "-p", str(ssh_port),
                "root@localhost",
                "systemctl --version"
            ], timeout=20)
            
            self.results["direct_ssh"] = result
            
            if result["success"] and "systemd" in result["stdout"]:
                self.log("✅ SSH access working via password")
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
            result = self.run_command([
                "bash", "-c", 
                f"echo 'systemctl is-active {service}' | ./cli/rave vm ssh {self.test_vm_name}"
            ], timeout=15)
            
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
        
        # Clean up any existing test VM
        self.cleanup()
        
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
        
        if self.cleanup_on_success and failed == 0:
            self.cleanup()
        elif failed > 0:
            self.log("⚠️  Test VM left running for debugging")
        
        return failed == 0


if __name__ == "__main__":
    test = RAVEVMIntegrationTest()
    success = test.run_tests()
    sys.exit(0 if success else 1)