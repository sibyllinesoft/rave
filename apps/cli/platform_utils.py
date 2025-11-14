"""
Platform-specific utilities for RAVE CLI
Handles differences between macOS, Linux, and potentially Windows
"""
import os
import platform
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

class PlatformManager:
    def __init__(self):
        self.system = platform.system()
        self.machine = platform.machine()
        
    def is_macos(self) -> bool:
        return self.system == "Darwin"
    
    def is_linux(self) -> bool:
        return self.system == "Linux"
        
    def is_apple_silicon(self) -> bool:
        return self.is_macos() and self.machine in ("arm64", "aarch64")
        
    def get_qemu_binary(self) -> Optional[str]:
        """Get the appropriate QEMU binary for this platform."""
        if self.is_apple_silicon():
            # Apple Silicon needs emulation for x86_64 VMs
            return shutil.which("qemu-system-x86_64")
        elif self.is_macos():
            # Intel Mac
            return shutil.which("qemu-system-x86_64")
        else:
            # Linux
            return shutil.which("qemu-system-x86_64")
    
    def get_acceleration_flags(self) -> List[str]:
        """Get hardware acceleration flags for QEMU."""
        if self.is_macos():
            return ["-accel", "hvf"]  # Hypervisor Framework on macOS
        elif self.is_linux():
            if Path("/dev/kvm").exists():
                return ["-accel", "kvm"]  # KVM on Linux
            else:
                return []  # No acceleration available
        else:
            return []  # Windows or other
    
    def get_nix_build_command(self) -> List[str]:
        """Get Nix build command with platform-specific flags."""
        base_cmd = ["nix", "build"]
        
        if self.is_apple_silicon():
            # Apple Silicon may need Rosetta 2 for x86_64 builds
            base_cmd.extend(["--system", "x86_64-darwin"])
        
        return base_cmd
    
    def check_prerequisites(self) -> Dict[str, any]:
        """Check if all required tools are available on this platform."""
        missing = []
        warnings = []
        
        # Check Nix
        if not shutil.which("nix"):
            missing.append("nix")
        else:
            # Check if flakes are enabled
            try:
                result = subprocess.run(
                    ["nix", "flake", "--help"], 
                    capture_output=True, 
                    text=True
                )
                if result.returncode != 0:
                    warnings.append("Nix flakes not enabled - run: echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf")
            except:
                warnings.append("Could not verify Nix flakes support")
        
        # Check QEMU
        qemu_binary = self.get_qemu_binary()
        if not qemu_binary:
            if self.is_macos():
                missing.append("qemu (install with: brew install qemu)")
            else:
                missing.append("qemu-system-x86_64")
        
        # Check secrets tooling
        if not shutil.which("sops"):
            missing.append("sops (https://github.com/getsops/sops/releases)")

        age_present = shutil.which("age") or shutil.which("age-keygen")
        if not age_present:
            missing.append("age / age-keygen (https://github.com/FiloSottile/age/releases)")

        # Check virtualization support
        if self.is_macos():
            # Check if HVF is available
            try:
                result = subprocess.run(
                    ["sysctl", "-n", "kern.hv_support"],
                    capture_output=True,
                    text=True
                )
                if result.stdout.strip() != "1":
                    warnings.append("Hypervisor Framework not available - VM performance will be poor")
            except:
                warnings.append("Could not check Hypervisor Framework support")
        elif self.is_linux():
            if not Path("/dev/kvm").exists():
                warnings.append("KVM not available - VM performance will be poor")
        
        # Apple Silicon specific checks
        if self.is_apple_silicon():
            warnings.append("Apple Silicon detected - x86_64 VM will run under emulation (slower)")
            
            # Check if Rosetta 2 is installed for Nix builds
            if not Path("/Library/Apple/usr/share/rosetta").exists():
                warnings.append("Rosetta 2 not detected - install with: softwareupdate --install-rosetta")
        
        return {
            "success": len(missing) == 0,
            "missing": missing,
            "warnings": warnings
        }

    # TLS / mkcert helpers -------------------------------------------------

    def ensure_mkcert_installed(self) -> Dict[str, any]:
        """Ensure mkcert is available on the host, installing it if possible."""

        if shutil.which("mkcert"):
            return {"success": True, "installed": False}

        install_steps: List[List[str]] = []

        if self.is_macos() and shutil.which("brew"):
            install_steps.append(["brew", "install", "mkcert", "nss"])
        elif self.is_linux():
            if shutil.which("apt-get"):
                install_steps.append(["sudo", "apt-get", "update"])
                install_steps.append(["sudo", "apt-get", "install", "-y", "mkcert", "libnss3-tools"])
            elif shutil.which("dnf"):
                install_steps.append(["sudo", "dnf", "install", "-y", "mkcert", "nss-tools"])
            elif shutil.which("pacman"):
                install_steps.append(["sudo", "pacman", "-Sy", "mkcert", "nss"])

        if not install_steps:
            return {
                "success": False,
                "error": "mkcert not found and automatic installation is unavailable",
                "hint": "Install mkcert manually (see https://github.com/FiloSottile/mkcert) and rerun."
            }

        for step in install_steps:
            try:
                result = subprocess.run(step, check=True, capture_output=True, text=True)
            except subprocess.CalledProcessError as exc:
                stderr = exc.stderr.strip() if exc.stderr else "unknown error"
                return {
                    "success": False,
                    "error": f"Failed to run '{' '.join(step)}': {stderr}"
                }

        if shutil.which("mkcert"):
            return {"success": True, "installed": True}

        return {
            "success": False,
            "error": "mkcert installation attempted but the binary is still missing."
        }

    def mkcert_caroot(self) -> Optional[Path]:
        """Return the mkcert CA root directory if available."""

        if not shutil.which("mkcert"):
            return None

        try:
            result = subprocess.run(
                ["mkcert", "-CAROOT"],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError:
            return None

        return Path(result.stdout.strip())
    
    def get_age_key_directory(self) -> Optional[Path]:
        """Get the directory containing AGE keys for SOPS, or None if not found."""
        # Standard SOPS/AGE key location
        age_key_file = Path.home() / ".config" / "sops" / "age" / "keys.txt"
        
        if age_key_file.exists():
            return age_key_file.parent
        
        # Alternative: look for AGE key in home directory
        home_age_key = Path.home() / ".age" / "key.txt"
        if home_age_key.exists():
            return home_age_key.parent
            
        # Check if age-keygen has generated keys
        try:
            result = subprocess.run(
                ["age-keygen", "-y", str(age_key_file)],
                capture_output=True,
                text=True,
                check=False
            )
            if result.returncode == 0:
                return age_key_file.parent
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
            
        return None
    
    def get_vm_start_command(self, image_path: str, memory_gb: int = 12,
                             port_forwards: List[Tuple[int, int]] = None,
                             age_key_dir: Optional[str] = None) -> Tuple[List[str], Optional[Dict[str, str]]]:
        """Generate command and environment for starting a VM."""
        repo_root = Path(__file__).resolve().parent.parent
        nix_vm_launcher = repo_root / "result" / "bin" / "run-rave-complete-vm"

        if self.is_linux() and nix_vm_launcher.exists():
            env = os.environ.copy()
            env["NIX_DISK_IMAGE"] = str(Path(image_path).resolve())

            if port_forwards:
                hostfwd_rules = [
                    f"hostfwd=tcp::{host_port}-:{guest_port}"
                    for host_port, guest_port in port_forwards
                ]
                env["QEMU_NET_OPTS"] = ",".join(hostfwd_rules)

            return [str(nix_vm_launcher)], env

        qemu_binary = self.get_qemu_binary()
        if not qemu_binary:
            raise RuntimeError("QEMU not available")

        cmd = [qemu_binary]

        # Basic VM settings
        cmd.extend([
            "-drive", f"file={image_path},format=qcow2",
            "-m", f"{memory_gb}G",
            "-smp", "2"
        ])

        # Hardware acceleration
        cmd.extend(self.get_acceleration_flags())

        # Network with port forwarding
        if port_forwards:
            hostfwd_rules = [
                f"hostfwd=tcp::{host_port}-:{guest_port}"
                for host_port, guest_port in port_forwards
            ]

            netdev = f"user,id=net0,{','.join(hostfwd_rules)}"
            cmd.extend([
                "-netdev", netdev,
                "-device", "virtio-net-pci,netdev=net0"
            ])
        else:
            cmd.extend([
                "-netdev", "user,id=net0",
                "-device", "virtio-net-pci,netdev=net0"
            ])

        # AGE key sharing via virtfs
        if age_key_dir:
            cmd.extend([
                "-virtfs", f"local,path={age_key_dir},mount_tag=sops-keys,security_model=none"
            ])

        # Platform-specific optimizations
        if self.is_macos():
            # macOS-specific QEMU optimizations
            cmd.extend([
                "-display", "none",  # No GUI on macOS
                "-serial", "mon:stdio"  # Serial console for debugging
            ])
        else:
            # Linux-specific optimizations
            cmd.extend([
                "-display", "none"
            ])

        return cmd, None
    
    def get_temp_dir(self) -> Path:
        """Get platform-appropriate temporary directory."""
        if self.is_macos():
            return Path("/tmp")
        else:
            return Path("/tmp")
    
    def get_config_dir(self) -> Path:
        """Get platform-appropriate configuration directory."""
        if self.is_macos():
            return Path.home() / "Library" / "Application Support" / "rave"
        else:
            return Path.home() / ".config" / "rave"
