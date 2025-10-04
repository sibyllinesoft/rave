"""
VM Manager - Handles RAVE virtual machine lifecycle operations
"""

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional

from platform_utils import PlatformManager


class VMManager:
    """Manages RAVE virtual machine operations."""
    
    def __init__(self, vms_dir: Path):
        self.vms_dir = vms_dir
        self.vms_dir.mkdir(parents=True, exist_ok=True)
        self.platform = PlatformManager()
    
    def check_prerequisites(self) -> Dict[str, any]:
        """Check if all required tools are available for VM operations."""
        return self.platform.check_prerequisites()
        
    def _get_vm_config_path(self, company_name: str) -> Path:
        """Get path to VM configuration file."""
        return self.vms_dir / f"{company_name}.json"
    
    def _load_vm_config(self, company_name: str) -> Optional[Dict]:
        """Load VM configuration."""
        config_path = self._get_vm_config_path(company_name)
        if not config_path.exists():
            return None
        try:
            return json.loads(config_path.read_text())
        except (json.JSONDecodeError, FileNotFoundError):
            return None
    
    def _save_vm_config(self, company_name: str, config: Dict):
        """Save VM configuration."""
        config_path = self._get_vm_config_path(company_name)
        config_path.write_text(json.dumps(config, indent=2))
    
    def _get_next_port_range(self) -> tuple:
        """Get next available port range for VM."""
        # Start from 8100 and increment by 10 for each VM
        existing_vms = list(self.vms_dir.glob("*.json"))
        base_port = 8100 + (len(existing_vms) * 10)
        return (
            base_port,      # HTTP
            base_port + 1,  # HTTPS
            base_port + 2,  # SSH
            base_port + 3   # Test page
        )
    
    def _build_vm_image(self, company_name: str = None, ssh_public_key: str = None) -> Dict[str, any]:
        """Build VM image using Nix."""
        try:
            if company_name and ssh_public_key:
                # Build custom company VM with injected SSH key
                result = self._build_company_vm(company_name, ssh_public_key)
            else:
                # Get platform-specific build command
                nix_cmd = self.platform.get_nix_build_command()
                nix_cmd.extend(["--show-trace"])
                
                # Build the standard development VM image
                result = subprocess.run(
                    nix_cmd, 
                    cwd=Path.cwd(),  # Use current working directory instead of hardcoded path
                    capture_output=True, 
                    text=True
                )
            
            if result.returncode != 0:
                return {"success": False, "error": f"Failed to build VM image: {result.stderr}"}
            
            return {"success": True}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _build_company_vm(self, company_name: str, ssh_public_key: str) -> subprocess.CompletedProcess:
        """Build a custom VM for a specific company with SSH key injection."""
        # For now, let's use the standard development build and inject keys at runtime
        # This is simpler and more reliable than custom builds per company
        return subprocess.run([
            "nix", "build", "--show-trace"
        ], cwd="/home/nathan/Projects/rave", capture_output=True, text=True)
    
    def _inject_ssh_key(self, image_path: str, ssh_public_key: str) -> Dict[str, any]:
        """Inject SSH public key into VM image using guestfish."""
        try:
            # Use guestfish to modify the VM image
            # Escape the SSH key properly for guestfish
            escaped_key = ssh_public_key.replace('"', '\\"')
            guestfish_script = f'''launch
list-filesystems
mount /dev/sda1 /
mkdir-p /root/.ssh
write /root/.ssh/authorized_keys "{escaped_key}\\n"
chmod 0700 /root/.ssh
chmod 0600 /root/.ssh/authorized_keys
chown 0 0 /root/.ssh
chown 0 0 /root/.ssh/authorized_keys
sync
umount /
exit
'''
            
            # Run guestfish with proper error handling
            result = subprocess.run([
                "guestfish", "--add", image_path, "--rw"
            ], input=guestfish_script, text=True, capture_output=True)
            
            if result.returncode != 0:
                print(f"Guestfish failed: {result.stderr}")
                # Fallback: rely on runtime provisioning
                return self._inject_ssh_key_cloud_init(image_path, ssh_public_key)
            
            return {"success": True, "method": "guestfish"}
            
        except FileNotFoundError:
            # guestfish not available, use virt-customize approach
            return self._inject_ssh_key_cloud_init(image_path, ssh_public_key)
        except Exception as e:
            print(f"Guestfish exception: {e}")
            return self._inject_ssh_key_cloud_init(image_path, ssh_public_key)
    
    def _inject_ssh_key_simple(self, image_path: str, ssh_public_key: str) -> Dict[str, any]:
        """SSH key injection using loop mount approach."""
        try:
            import tempfile
            import os
            
            # Create a temporary mount point
            with tempfile.TemporaryDirectory() as temp_dir:
                mount_point = os.path.join(temp_dir, "mnt")
                os.makedirs(mount_point)
                
                # Get the partition offset using qemu-img
                result = subprocess.run([
                    "qemu-img", "info", image_path
                ], capture_output=True, text=True)
                
                if result.returncode != 0:
                    return {"success": False, "error": f"Failed to get image info: {result.stderr}"}
                
                # Try to mount the image directly
                # First convert to raw format temporarily if needed
                raw_image = os.path.join(temp_dir, "temp.raw")
                subprocess.run([
                    "qemu-img", "convert", "-f", "qcow2", "-O", "raw", image_path, raw_image
                ], capture_output=True, text=True)
                
                # Try to mount as ext4 filesystem
                # Get partition table info
                result = subprocess.run([
                    "parted", "-m", raw_image, "print"
                ], capture_output=True, text=True)
                
                if result.returncode == 0:
                    # Parse partition info to find the root partition
                    lines = result.stdout.strip().split('\n')
                    for line in lines[2:]:  # Skip header lines
                        parts = line.split(':')
                        if len(parts) >= 5 and ('ext' in parts[4] or 'linux' in parts[5].lower()):
                            # Found a Linux partition, try to mount it
                            start_sector = parts[1].rstrip('s')
                            try:
                                start_bytes = int(start_sector) * 512
                                
                                # Mount with offset
                                mount_result = subprocess.run([
                                    "sudo", "mount", "-o", f"loop,offset={start_bytes}", raw_image, mount_point
                                ], capture_output=True, text=True)
                                
                                if mount_result.returncode == 0:
                                    # Successfully mounted, inject SSH key
                                    ssh_dir = os.path.join(mount_point, "root", ".ssh")
                                    authorized_keys = os.path.join(ssh_dir, "authorized_keys")
                                    
                                    # Create .ssh directory and add key
                                    subprocess.run(["sudo", "mkdir", "-p", ssh_dir], check=True)
                                    subprocess.run(["sudo", "sh", "-c", f"echo '{ssh_public_key}' > {authorized_keys}"], check=True)
                                    subprocess.run(["sudo", "chmod", "700", ssh_dir], check=True)
                                    subprocess.run(["sudo", "chmod", "600", authorized_keys], check=True)
                                    subprocess.run(["sudo", "chown", "root:root", ssh_dir], check=True)
                                    subprocess.run(["sudo", "chown", "root:root", authorized_keys], check=True)
                                    
                                    # Unmount
                                    subprocess.run(["sudo", "umount", mount_point], check=True)
                                    
                                    # Convert back to qcow2
                                    subprocess.run([
                                        "qemu-img", "convert", "-f", "raw", "-O", "qcow2", raw_image, image_path
                                    ], check=True)
                                    
                                    return {"success": True, "method": "loop_mount"}
                                
                            except (ValueError, subprocess.CalledProcessError) as e:
                                # Clean up mount if it exists
                                subprocess.run(["sudo", "umount", mount_point], capture_output=True)
                                continue
                
                # If we get here, loop mount failed - fall back to a simpler approach
                return self._inject_ssh_key_cloud_init(image_path, ssh_public_key)
                
        except Exception as e:
            return {"success": False, "error": f"Loop mount injection failed: {e}"}
    
    def _inject_ssh_key_cloud_init(self, image_path: str, ssh_public_key: str) -> Dict[str, any]:
        """Fallback: Store SSH key info for runtime SSH use."""
        # Since image modification is complex, we'll rely on the SSH client
        # using the stored keypair information for authentication
        print(f"💡 SSH key injection skipped - will use keypair directly for SSH authentication")
        return {"success": True, "method": "runtime_auth", "note": "SSH will use stored keypair for authentication"}

    def _ensure_root_authorized_key(self, config: Dict[str, any]) -> bool:
        """Ensure the VM has the requested root SSH key configured via the agent account."""
        public_key = config.get("ssh_public_key")
        if not public_key:
            return False

        if not shutil.which("sshpass"):
            print("⚠️  sshpass not available - skipping automatic SSH key provisioning")
            return False

        ssh_port = config["ports"]["ssh"]
        escaped_key = public_key.replace("'", "'\"'\"'")
        remote_cmd = (
            "sudo mkdir -p /root/.ssh && "
            f"sudo sh -c \"grep -qxF '{escaped_key}' /root/.ssh/authorized_keys || echo '{escaped_key}' >> /root/.ssh/authorized_keys\" && "
            "sudo chmod 700 /root/.ssh && sudo chmod 600 /root/.ssh/authorized_keys"
        )

        ssh_cmd = [
            "sshpass", "-p", "agent",
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            "-p", str(ssh_port),
            "agent@localhost",
            remote_cmd
        ]

        for attempt in range(12):
            result = subprocess.run(ssh_cmd, capture_output=True, text=True)
            if result.returncode == 0:
                return True
            time.sleep(5)

        print("⚠️  Unable to inject SSH key automatically; password login may be required")
        return False

    def create_vm(self, company_name: str, keypair_path: str) -> Dict[str, any]:
        """Create a new company VM."""
        # Check if VM already exists
        if self._load_vm_config(company_name):
            return {"success": False, "error": f"VM '{company_name}' already exists"}
        
        # Validate and read keypair
        keypair_path = Path(keypair_path).expanduser()
        public_key_path = keypair_path.with_suffix('.pub')
        
        if not keypair_path.exists():
            return {"success": False, "error": f"Private key not found: {keypair_path}"}
        if not public_key_path.exists():
            return {"success": False, "error": f"Public key not found: {public_key_path}"}
        
        # Read the public key content
        try:
            ssh_public_key = public_key_path.read_text().strip()
        except Exception as e:
            return {"success": False, "error": f"Failed to read public key: {e}"}
        
        # Build VM image (or use existing if build fails)
        build_result = self._build_vm_image(company_name, ssh_public_key)
        if not build_result["success"]:
            print(f"⚠️  Build failed: {build_result['error']}")
            print("🔄 Will attempt to use existing working image...")
            # Continue anyway - we'll try to use existing image
        
        # Get port assignments
        http_port, https_port, ssh_port, test_port = self._get_next_port_range()
        
        # Create VM configuration
        config = {
            "name": company_name,
            "keypair": str(keypair_path),
            "ssh_public_key": ssh_public_key,
            "ports": {
                "http": http_port,
                "https": https_port,
                "ssh": ssh_port,
                "test": test_port
            },
            "status": "stopped",
            "created_at": time.time(),
            "image_path": f"/home/nathan/Projects/rave/{company_name}-dev.qcow2"
        }
        
        # Copy VM image (use existing working image if build failed)
        try:
            if Path("/home/nathan/Projects/rave/result/nixos.qcow2").exists():
                subprocess.run([
                    "cp", "result/nixos.qcow2", config["image_path"]
                ], cwd="/home/nathan/Projects/rave", check=True)
            elif Path("/home/nathan/Projects/rave/rave-complete-localhost.qcow2").exists():
                print(f"Using existing working image for {company_name}")
                subprocess.run([
                    "cp", "rave-complete-localhost.qcow2", config["image_path"]
                ], cwd="/home/nathan/Projects/rave", check=True)
            else:
                return {"success": False, "error": "No VM image available"}
            
            subprocess.run([
                "chmod", "644", config["image_path"]
            ], check=True)
            
            # Inject SSH key into the VM image
            injection_result = self._inject_ssh_key(config["image_path"], ssh_public_key)
            if not injection_result["success"]:
                print(f"⚠️  SSH key injection failed: {injection_result.get('error', 'Unknown error')}")
                print("🔄 VM will be created but may require password authentication")
                # Continue with VM creation - SSH will fall back to password auth
                
        except subprocess.CalledProcessError as e:
            return {"success": False, "error": f"Failed to copy VM image: {e}"}
        
        # Save configuration
        self._save_vm_config(company_name, config)
        
        return {"success": True, "config": config}
    
    def start_vm(self, company_name: str) -> Dict[str, any]:
        """Start a company VM."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}
        
        if self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is already running"}
        
        # Start VM with platform-specific launcher
        ports = config["ports"]
        port_forwards = [
            (ports['http'], 80),
            (ports['https'], 443),
            (ports['ssh'], 22),
            (ports['test'], 8080)
        ]
        memory_gb = 4
        cmd, env = self.platform.get_vm_start_command(
            config['image_path'], 
            memory_gb=memory_gb,
            port_forwards=port_forwards
        )

        pidfile = self.platform.get_temp_dir() / f"rave-{company_name}.pid"
        cmd.extend([
            "-daemonize",
            "-pidfile", str(pidfile)
        ])

        if env is not None and cmd:
            launcher = Path(cmd[0])
            if launcher.name.startswith("run-"):
                # Force headless mode and desired memory when using the Nix launcher script
                cmd.extend([
                    "-display", "none",
                    "-m", f"{memory_gb}G"
                ])
        
        try:
            subprocess.run(cmd, check=True, env=env)
            
            # Update status
            config["status"] = "running"
            config["started_at"] = time.time()
            
            # Wait a moment for VM to initialize
            time.sleep(5)
            if self._ensure_root_authorized_key(config):
                config["ssh_key_configured"] = True
            
            self._save_vm_config(company_name, config)
            
            return {"success": True}
        except subprocess.CalledProcessError as e:
            return {"success": False, "error": f"Failed to start VM: {e}"}
    
    def stop_vm(self, company_name: str) -> Dict[str, any]:
        """Stop a company VM."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}
        
        # Kill VM process
        pidfile = f"/tmp/rave-{company_name}.pid"
        try:
            if Path(pidfile).exists():
                with open(pidfile, 'r') as f:
                    pid = f.read().strip()
                subprocess.run(["kill", pid], check=True)
                Path(pidfile).unlink()
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Try alternative method
            subprocess.run(["pkill", "-f", f"rave-{company_name}"], check=False)
        
        # Update status
        config["status"] = "stopped"
        if "started_at" in config:
            del config["started_at"]
        self._save_vm_config(company_name, config)
        
        return {"success": True}
    
    def _is_vm_running(self, company_name: str) -> bool:
        """Check if VM is running."""
        pidfile = f"/tmp/rave-{company_name}.pid"
        if not Path(pidfile).exists():
            return False
        
        try:
            with open(pidfile, 'r') as f:
                pid = f.read().strip()
            # Check if process exists
            subprocess.run(["kill", "-0", pid], check=True, capture_output=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False
    
    def status_vm(self, company_name: str) -> Dict[str, any]:
        """Get VM status."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}
        
        running = self._is_vm_running(company_name)
        status = "running" if running else "stopped"
        
        return {
            "success": True,
            "running": running,
            "status": status,
            "config": config
        }
    
    def status_all_vms(self) -> Dict[str, Dict]:
        """Get status of all VMs."""
        results = {}
        for config_file in self.vms_dir.glob("*.json"):
            company_name = config_file.stem
            status_result = self.status_vm(company_name)
            if status_result["success"]:
                results[company_name] = {
                    "running": status_result["running"],
                    "status": status_result["status"]
                }
        return results
    
    def reset_vm(self, company_name: str) -> Dict[str, any]:
        """Reset VM to default state."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}
        
        # Stop VM if running
        if self._is_vm_running(company_name):
            stop_result = self.stop_vm(company_name)
            if not stop_result["success"]:
                return stop_result
        
        # Rebuild and copy fresh VM image
        build_result = self._build_vm_image()
        if not build_result["success"]:
            return build_result
        
        try:
            subprocess.run([
                "cp", "result/nixos.qcow2", config["image_path"]
            ], cwd="/home/nathan/Projects/rave", check=True)
            
            return {"success": True}
        except subprocess.CalledProcessError as e:
            return {"success": False, "error": f"Failed to reset VM: {e}"}
    
    def ssh_vm(self, company_name: str) -> Dict[str, any]:
        """SSH into company VM."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}
        
        if not self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is not running"}
        
        # SSH with keypair (if available) or password fallback
        ports = config["ports"]
        keypair_path = config.get("keypair")
        
        # Try SSH with multiple authentication methods
        if keypair_path and Path(keypair_path).exists():
            # First try key-based authentication
            ssh_cmd = [
                "ssh",
                "-i", keypair_path,
                "-o", "StrictHostKeyChecking=no",
                "-o", "PasswordAuthentication=no",
                "-o", "ConnectTimeout=10",
                "-p", str(ports["ssh"]),
                "root@localhost"
            ]
            
            # Test SSH connection first
            test_result = subprocess.run(ssh_cmd + ["echo", "SSH key test"], 
                                       capture_output=True, text=True, timeout=15)
            
            if test_result.returncode == 0:
                print("🔑 SSH key authentication successful!")
                # Use key-based auth
                import os
                os.execvp("ssh", ssh_cmd)
            else:
                print("🔑 SSH key failed, trying password authentication...")
                
        # Fallback to password authentication
        ssh_cmd = [
            "sshpass", "-p", "debug123",
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
            "-o", "PreferredAuthentications=password",
            "-p", str(ports["ssh"]),
            "root@localhost"
        ]
        
        # Test password authentication
        test_result = subprocess.run(ssh_cmd + ["echo", "SSH password test"], 
                                   capture_output=True, text=True, timeout=15)
        
        if test_result.returncode == 0:
            print("🔐 SSH password authentication successful!")
            # Use password auth
            import os
            os.execvp("sshpass", ssh_cmd)
        else:
            return {"success": False, "error": f"SSH connection failed with both key and password: {test_result.stderr}"}
    
    def get_logs(self, company_name: str, service: Optional[str] = None, 
                 follow: bool = False, tail: int = 50, since: Optional[str] = None,
                 all_services: bool = False) -> Dict[str, any]:
        """Get VM service logs."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}
        
        if not self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is not running"}
        
        # Build SSH command for journalctl
        ports = config["ports"]
        keypair_path = config.get("keypair")
        
        if keypair_path and Path(keypair_path).exists():
            ssh_base = [
                "ssh", "-i", keypair_path, "-o", "StrictHostKeyChecking=no",
                "-p", str(ports["ssh"]), "root@localhost"
            ]
            program = "ssh"
        else:
            ssh_base = [
                "sshpass", "-p", "debug123",
                "ssh", "-o", "StrictHostKeyChecking=no",
                "-p", str(ports["ssh"]), "root@localhost"
            ]
            program = "sshpass"
        
        # Build journalctl command
        journalctl_cmd = ["journalctl"]
        
        if service and not all_services:
            journalctl_cmd.extend(["-u", f"{service}.service"])
        elif all_services:
            # Show logs from all main services
            services = ["nginx", "postgresql", "nats", "redis-default", "redis-gitlab"]
            for svc in services:
                journalctl_cmd.extend(["-u", f"{svc}.service"])
        
        if follow:
            journalctl_cmd.append("-f")
        else:
            journalctl_cmd.extend(["-n", str(tail)])
        
        if since:
            journalctl_cmd.extend(["--since", since])
        
        journalctl_cmd.append("--no-pager")
        
        full_cmd = ssh_base + journalctl_cmd
        
        try:
            # Execute and stream output
            import os
            os.execvp(program, full_cmd)
        except Exception as e:
            return {"success": False, "error": f"Failed to get logs: {e}"}
