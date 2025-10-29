"""
VM Manager - Handles RAVE virtual machine lifecycle operations
"""

import base64
import json
import shlex
import socket
import shutil
import subprocess
import tempfile
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

    def _build_ssh_command(
        self,
        config: Dict,
        remote_script: str,
        *,
        connect_timeout: int = 10,
    ) -> Dict[str, any]:
        """Construct an SSH command for running a remote script."""

        ports = config["ports"]
        keypair_path = config.get("keypair")

        ssh_common = [
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-p",
            str(ports["ssh"]),
            "root@localhost",
            "bash",
            "-lc",
            remote_script,
        ]

        if keypair_path and Path(keypair_path).exists():
            command = ["ssh", "-i", keypair_path, *ssh_common]
            return {"success": True, "command": command}

        if not shutil.which("sshpass"):
            return {
                "success": False,
                "error": "sshpass not available; provide an SSH keypair for VM access",
            }

        command = [
            "sshpass",
            "-p",
            "debug123",
            "ssh",
            *ssh_common,
        ]
        return {"success": True, "command": command}

    def _run_remote_script(
        self,
        config: Dict,
        remote_script: str,
        *,
        timeout: int,
        description: str,
        connect_timeout: int = 10,
        max_attempts: int = 5,
        initial_delay: float = 1.0,
        max_delay: float = 16.0,
    ) -> Dict[str, any]:
        """Execute a remote script over SSH with exponential backoff."""

        delay = initial_delay
        last_error = ""

        for attempt in range(1, max_attempts + 1):
            build_result = self._build_ssh_command(
                config, remote_script, connect_timeout=connect_timeout
            )
            if not build_result.get("success"):
                return build_result

            ssh_cmd = build_result["command"]

            try:
                result = subprocess.run(
                    ssh_cmd,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                )
            except subprocess.TimeoutExpired:
                last_error = (
                    f"{description} attempt {attempt} timed out after {timeout} seconds"
                )
            else:
                if result.returncode == 0:
                    return {"success": True, "result": result}

                stderr = result.stderr.strip()
                stdout = result.stdout.strip()
                last_error = (
                    stderr
                    or stdout
                    or f"{description} failed with exit code {result.returncode}"
                )

            if attempt < max_attempts:
                time.sleep(delay)
                delay = min(delay * 2, max_delay)

        return {"success": False, "error": last_error or description}

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

    def _host_port_available(self, port: int) -> bool:
        """Check if a host TCP port is available for forwarding."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                return False
        return True
    
    def _build_vm_image(self, company_name: str = None, ssh_public_key: str = None) -> Dict[str, any]:
        """Build VM image using Nix."""
        try:
            # For now, custom company builds reuse the shared qcow2 artifact.
            nix_cmd = self.platform.get_nix_build_command()
            nix_cmd.extend(["--show-trace", ".#rave-qcow2"])

            result = subprocess.run(
                nix_cmd,
                cwd=Path.cwd(),
                capture_output=True,
                text=True,
            )

            warning: Optional[str] = None

            if result.returncode != 0:
                warning = (
                    "nix build .#rave-qcow2 failed; falling back to default build"
                )
                fallback_cmd = self.platform.get_nix_build_command()
                fallback_cmd.extend(["--show-trace"])
                result = subprocess.run(
                    fallback_cmd,
                    cwd=Path.cwd(),
                    capture_output=True,
                    text=True,
                )
                if result.returncode != 0:
                    return {
                        "success": False,
                        "error": result.stderr.strip() or "Failed to build VM image",
                    }

            result_dir = Path.cwd() / "result"
            if not result_dir.exists():
                return {
                    "success": True,
                    "image": None,
                    "warning": "nix build completed but no 'result' symlink was created",
                }

            candidates = list(result_dir.glob("*.qcow2"))
            if not candidates:
                return {
                    "success": True,
                    "image": None,
                    "warning": "nix build produced no qcow2 artifacts",
                }

            # Prefer a deterministic filename if present.
            image_path = None
            for preferred in ("nixos.qcow2", "disk.qcow2", "image.qcow2"):
                candidate = result_dir / preferred
                if candidate.exists():
                    image_path = candidate
                    break
            if image_path is None:
                image_path = candidates[0]

            response = {"success": True, "image": image_path}
            if warning:
                response["warning"] = warning
            return response
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _build_company_vm(self, company_name: str, ssh_public_key: str) -> subprocess.CompletedProcess:
        """Build a custom VM for a specific company with SSH key injection."""
        # For now, let's use the standard development build and inject keys at runtime
        # This is simpler and more reliable than custom builds per company
        return subprocess.run([
            "nix", "build", "--show-trace"
        ], cwd="/home/nathan/Projects/rave", capture_output=True, text=True)

    def _create_blank_disk(self, target: Path, size_gb: int = 20) -> Dict[str, any]:
        """Create a fresh QCOW2 disk image using qemu-img and mkfs."""

        qemu_img = shutil.which("qemu-img")
        mkfs_ext4 = shutil.which("mkfs.ext4")

        if not qemu_img or not mkfs_ext4:
            missing = []
            if not qemu_img:
                missing.append("qemu-img")
            if not mkfs_ext4:
                missing.append("mkfs.ext4")
            return {
                "success": False,
                "error": f"Required tooling missing: {', '.join(missing)}",
            }

        target.parent.mkdir(parents=True, exist_ok=True)

        raw_temp = None
        try:
            with tempfile.NamedTemporaryFile(prefix="rave-disk-", suffix=".raw", delete=False) as tmp:
                raw_temp = Path(tmp.name)

            subprocess.run(
                [qemu_img, "create", "-f", "raw", str(raw_temp), f"{size_gb}G"],
                check=True,
            )

            subprocess.run(
                [mkfs_ext4, "-F", "-L", "nixos", str(raw_temp)],
                check=True,
            )

            subprocess.run(
                [qemu_img, "convert", "-f", "raw", "-O", "qcow2", str(raw_temp), str(target)],
                check=True,
            )

            target.chmod(0o644)
            return {"success": True}
        except subprocess.CalledProcessError as exc:
            return {
                "success": False,
                "error": exc.stderr.strip() if exc.stderr else str(exc),
            }
        except Exception as exc:
            return {"success": False, "error": str(exc)}
        finally:
            if raw_temp and raw_temp.exists():
                try:
                    raw_temp.unlink()
                except OSError:
                    pass
    
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

    def _install_age_key_into_image(self, image_path: str, age_key_path: Path) -> Dict[str, any]:
        """Install the Age key into the VM image so secrets decrypt on first boot."""
        if not age_key_path.exists():
            return {"success": False, "error": f"Age key not found at {age_key_path}"}

        if shutil.which("guestfish") is None:
            return {
                "success": False,
                "error": (
                    "guestfish is not installed; install libguestfs-tools to embed the Age key during image build"
                ),
            }

        temp_key_path: Optional[Path] = None
        try:
            key_bytes = age_key_path.read_bytes()
        except OSError as exc:
            return {
                "success": False,
                "error": f"Failed to read Age key: {exc}",
            }

        try:
            with tempfile.NamedTemporaryFile(prefix="rave-age-key-", delete=False) as tmp:
                temp_key_path = Path(tmp.name)
                tmp.write(key_bytes)
                tmp.flush()

            remote_path = "/var/lib/sops-nix/key.txt"
            guestfish_script = f'''launch
list-filesystems
mount /dev/disk/by-label/nixos /
mkdir-p /var/lib/sops-nix
upload {temp_key_path} {remote_path}
chmod 0700 /var/lib/sops-nix
chmod 0400 {remote_path}
chown 0 0 /var/lib/sops-nix
chown 0 0 {remote_path}
sync
umount /
exit
'''

            result = subprocess.run(
                ["guestfish", "--add", image_path, "--rw"],
                input=guestfish_script,
                text=True,
                capture_output=True,
            )
            if result.returncode != 0:
                stderr = result.stderr.strip() if result.stderr else ""
                return {
                    "success": False,
                    "error": (
                        f"guestfish failed to install Age key"
                        + (f": {stderr}" if stderr else "")
                    ),
                }

            return {"success": True}
        except subprocess.CalledProcessError as exc:
            return {
                "success": False,
                "error": exc.stderr.strip() if exc.stderr else str(exc),
            }
        finally:
            if temp_key_path and temp_key_path.exists():
                try:
                    temp_key_path.unlink()
                except OSError:
                    pass

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

    def create_vm(
        self,
        company_name: str,
        keypair_path: str,
        age_key_path: Optional[Path] = None,
    ) -> Dict[str, any]:
        """Create a new company VM."""
        if self._load_vm_config(company_name):
            return {"success": False, "error": f"VM '{company_name}' already exists"}

        if age_key_path is not None:
            age_key_path = Path(age_key_path).expanduser()

        warnings: List[str] = []

        keypair_path = Path(keypair_path).expanduser()
        public_key_path = keypair_path.with_suffix(".pub")

        if not keypair_path.exists():
            return {"success": False, "error": f"Private key not found: {keypair_path}"}
        if not public_key_path.exists():
            return {"success": False, "error": f"Public key not found: {public_key_path}"}

        try:
            ssh_public_key = public_key_path.read_text().strip()
        except Exception as exc:
            return {"success": False, "error": f"Failed to read public key: {exc}"}

        build_result = self._build_vm_image(company_name, ssh_public_key)
        if not build_result["success"]:
            print(f"⚠️  Build failed: {build_result['error']}")
            print("🔄 Will attempt to use existing working image...")
            image_source: Optional[Path] = None
        else:
            built_image = build_result.get("image")
            image_source = Path(built_image) if built_image else None
            if image_source and not image_source.exists():
                print("⚠️  Built image path not found; falling back to cached image")
                image_source = None

        http_port, https_port, ssh_port, test_port = self._get_next_port_range()

        config: Dict[str, any] = {
            "name": company_name,
            "keypair": str(keypair_path),
            "ssh_public_key": ssh_public_key,
            "ports": {
                "http": http_port,
                "https": https_port,
                "ssh": ssh_port,
                "test": test_port,
            },
            "status": "stopped",
            "created_at": time.time(),
            "image_path": f"/home/nathan/Projects/rave/{company_name}-dev.qcow2",
        }

        try:
            repo_root = Path.cwd()
            if image_source and image_source.exists():
                shutil.copy2(image_source, config["image_path"])
            elif (repo_root / "rave-complete-localhost.qcow2").exists():
                print(f"Using existing working image for {company_name}")
                shutil.copy2(
                    repo_root / "rave-complete-localhost.qcow2", config["image_path"]
                )
            else:
                return {"success": False, "error": "No VM image available"}

            Path(config["image_path"]).chmod(0o644)

            injection_result = self._inject_ssh_key(
                config["image_path"], ssh_public_key
            )
            if not injection_result["success"]:
                print(
                    f"⚠️  SSH key injection failed: {injection_result.get('error', 'Unknown error')}"
                )
                print("🔄 VM will be created but may require password authentication")

            if age_key_path:
                age_result = self._install_age_key_into_image(
                    config["image_path"],
                    age_key_path,
                )
                if not age_result.get("success"):
                    error_msg = age_result.get(
                        "error",
                        "Failed to embed Age key into VM image",
                    )
                    return {"success": False, "error": error_msg}

                config["secrets"] = {
                    "age_key_path": str(age_key_path),
                    "age_key_installed": True,
                }

        except subprocess.CalledProcessError as exc:
            return {"success": False, "error": f"Failed to copy VM image: {exc}"}

        self._save_vm_config(company_name, config)

        response: Dict[str, any] = {"success": True, "config": config}
        if warnings:
            response["warnings"] = warnings
        return response
    
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

        # Ensure legacy external ports remain available for tooling that expects them.
        required_legacy_ports = {
            18221: 443,
        }
        optional_legacy_ports = {
            18220: 80,
            18231: 443,
            18230: 80,
        }
        existing_host_ports = {host for host, _ in port_forwards}

        for host_port, guest_port in required_legacy_ports.items():
            if host_port in existing_host_ports:
                continue

            if not self._host_port_available(host_port):
                return {
                    "success": False,
                    "error": (
                        f"Host port {host_port} is already in use; "
                        "stop the conflicting process to expose GitLab/Mattermost on the documented port."
                    ),
                }

            port_forwards.append((host_port, guest_port))
            existing_host_ports.add(host_port)

        for host_port, guest_port in optional_legacy_ports.items():
            if host_port in existing_host_ports:
                continue

            if not self._host_port_available(host_port):
                continue

            port_forwards.append((host_port, guest_port))
            existing_host_ports.add(host_port)
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
        """Check if VM is running (based on pidfile)."""
        pidfile = Path(f"/tmp/rave-{company_name}.pid")
        if not pidfile.exists():
            return False

        try:
            pid = pidfile.read_text().strip()
            subprocess.run(["kill", "-0", pid], check=True, capture_output=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError, OSError):
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

        create_result = self._create_blank_disk(Path(config["image_path"]))
        if not create_result.get("success"):
            return create_result

        ssh_public_key = config.get("ssh_public_key")
        if ssh_public_key:
            injection_result = self._inject_ssh_key(
                config["image_path"], ssh_public_key
            )
            if not injection_result.get("success"):
                return {
                    "success": True,
                    "warning": injection_result.get(
                        "error", "Unable to reinject SSH key"
                    ),
                }

        return {"success": True}
    
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

    def install_age_key(self, company_name: str, key_file: Path,
                         remote_path: str = "/var/lib/sops-nix/key.txt") -> Dict[str, any]:
        """Install an Age key into a running VM for sops-nix."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}

        if not self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is not running"}

        key_path = Path(key_file).expanduser()
        if not key_path.exists():
            return {"success": False, "error": f"Age key file not found: {key_path}"}

        key_text = key_path.read_text().strip()
        if not key_text:
            return {"success": False, "error": "Age key file is empty"}

        # Prepare remote script to install the key with correct permissions
        remote_file = Path(remote_path)
        remote_dir = remote_file.parent

        dir_q = shlex.quote(str(remote_dir))
        file_q = shlex.quote(str(remote_file))

        remote_script = (
            "set -euo pipefail\n"
            f"install -d -m 700 -o root -g root {dir_q}\n"
            f"cat <<'EOF' > {file_q}\n"
            f"{key_text}\n"
            "EOF\n"
            f"chmod 600 {file_q}\n"
            f"chown root:root {file_q}\n"
        )

        run_result = self._run_remote_script(
            config,
            remote_script,
            timeout=240,
            description="installing Age key",
            max_attempts=8,
            initial_delay=1.5,
        )

        if not run_result.get("success"):
            return {
                "success": False,
                "error": run_result.get("error", "Failed to install Age key"),
            }

        return {"success": True, "path": remote_path}

    def install_secret_files(
        self,
        company_name: str,
        entries: List[Dict[str, str]],
    ) -> Dict[str, any]:
        """Install one or more secrets on the VM using a single SSH session."""
        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}

        if not self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is not running"}

        secrets = [entry for entry in entries if entry.get("content")]
        if not secrets:
            return {"success": True}

        remote_lines = ["set -euo pipefail"]

        for secret in secrets:
            remote_path = secret["remote_path"]
            content = secret["content"]
            owner = secret.get("owner", "root")
            group = secret.get("group", owner)
            mode = secret.get("mode", "0600")
            dir_mode = secret.get("dir_mode", "0700")

            remote_file = Path(remote_path)
            remote_dir = remote_file.parent

            dir_q = shlex.quote(str(remote_dir))
            file_q = shlex.quote(str(remote_file))
            encoded = base64.b64encode(content.encode()).decode()

            remote_lines.extend(
                [
                    f"install -d -m {dir_mode} -o {owner} -g {group} {dir_q}",
                    f"base64 -d <<'EOF' > {file_q}",
                    encoded,
                    "EOF",
                    f"chmod {mode} {file_q}",
                    f"chown {owner}:{group} {file_q}",
                ]
            )

        remote_script = "\n".join(remote_lines) + "\n"

        run_result = self._run_remote_script(
            config,
            remote_script,
            timeout=600,
            description="installing secret files",
        )

        if not run_result.get("success"):
            return {
                "success": False,
                "error": run_result.get("error", "unknown error installing secret"),
            }

        return {"success": True}

    def install_secret_file(
        self,
        company_name: str,
        remote_path: str,
        content: str,
        owner: str,
        group: str,
        mode: str,
        dir_mode: str = "0700",
    ) -> Dict[str, any]:
        entry = {
            "remote_path": remote_path,
            "content": content,
            "owner": owner,
            "group": group,
            "mode": mode,
            "dir_mode": dir_mode,
        }
        return self.install_secret_files(company_name, [entry])

    def ensure_mattermost_database(self, company_name: str, password: str) -> Dict[str, any]:
        """Ensure the Mattermost database role and password are configured."""

        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}

        if not self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is not running"}

        password_sql = password.replace("'", "''")
        remote_script = "\n".join(
            [
                "set -euo pipefail",
                "sudo -u postgres psql postgres <<'SQL'",
                "DO $$",
                "BEGIN",
                "  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mattermost') THEN",
                f"    CREATE ROLE mattermost WITH LOGIN PASSWORD '{password_sql}';",
                "  ELSE",
                f"    ALTER ROLE mattermost WITH LOGIN PASSWORD '{password_sql}';",
                "  END IF;",
                "END",
                "$$;",
                "SQL",
                "sudo -u postgres psql postgres -tc \"SELECT 1 FROM pg_database WHERE datname = 'mattermost';\" | grep -q 1 || sudo -u postgres createdb -O mattermost mattermost",
                "sudo -u postgres psql mattermost -c \"GRANT ALL PRIVILEGES ON SCHEMA public TO mattermost;\"",
            ]
        ) + "\n"

        run_result = self._run_remote_script(
            config,
            remote_script,
            timeout=180,
            description="resetting Mattermost database",
        )

        if not run_result.get("success"):
            return {
                "success": False,
                "error": run_result.get("error", "database command failed"),
            }

        return {"success": True}

    def ensure_gitlab_database_password(self, company_name: str, password: str) -> Dict[str, any]:
        """Ensure the GitLab database user password matches the injected secret."""

        config = self._load_vm_config(company_name)
        if not config:
            return {"success": False, "error": f"VM '{company_name}' not found"}

        if not self._is_vm_running(company_name):
            return {"success": False, "error": f"VM '{company_name}' is not running"}

        password_sql = password.replace("'", "''")
        remote_script = "\n".join(
            [
                "set -euo pipefail",
                "sudo -u postgres psql postgres <<'SQL'",
                f"ALTER ROLE gitlab WITH LOGIN PASSWORD '{password_sql}';",
                "SQL",
            ]
        ) + "\n"

        run_result = self._run_remote_script(
            config,
            remote_script,
            timeout=60,
            description="refreshing GitLab database password",
        )

        if not run_result.get("success"):
            return {
                "success": False,
                "error": run_result.get("error", "database command failed"),
            }

        return {"success": True}

    # TLS helpers ---------------------------------------------------------

    def install_tls_certificate(
        self,
        company_name: str,
        *,
        cert_pem: str,
        fullchain_pem: str,
        key_pem: str,
        ca_pem: str,
    ) -> Dict[str, any]:
        """Copy TLS materials into the VM and restart nginx."""

        entries = [
            {
                "remote_path": "/var/lib/acme/localhost/cert.pem",
                "content": fullchain_pem,
                "owner": "root",
                "group": "root",
                "mode": "0644",
                "dir_mode": "0755",
            },
            {
                "remote_path": "/var/lib/acme/localhost/fullchain.pem",
                "content": fullchain_pem,
                "owner": "root",
                "group": "root",
                "mode": "0644",
                "dir_mode": "0755",
            },
            {
                "remote_path": "/var/lib/acme/localhost/chain.pem",
                "content": ca_pem,
                "owner": "root",
                "group": "root",
                "mode": "0644",
                "dir_mode": "0755",
            },
            {
                "remote_path": "/var/lib/acme/localhost/key.pem",
                "content": key_pem,
                "owner": "root",
                "group": "nginx",
                "mode": "0640",
                "dir_mode": "0750",
            },
        ]

        return self.install_secret_files(company_name, entries)

    def record_tls_metadata(self, company_name: str, metadata: Dict[str, any]) -> bool:
        config = self._load_vm_config(company_name)
        if not config:
            return False

        tls_meta = config.get("tls", {})
        tls_meta.update(metadata)
        tls_meta["updated_at"] = time.time()
        config["tls"] = tls_meta
        self._save_vm_config(company_name, config)
        return True
