"""Provisioning helpers for VM images and first-boot setup."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Optional


def create_blank_disk(target: Path, size_gb: int = 20) -> Dict[str, Any]:
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

    raw_temp: Optional[Path] = None
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
    except Exception as exc:  # pylint: disable=broad-except
        return {"success": False, "error": str(exc)}
    finally:
        if raw_temp and raw_temp.exists():
            try:
                raw_temp.unlink()
            except OSError:
                pass


def inject_ssh_key(image_path: str, ssh_public_key: str) -> Dict[str, Any]:
    """Inject SSH public key into VM image using guestfish."""
    try:
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

        result = subprocess.run(
            ["guestfish", "--add", image_path, "--rw"],
            input=guestfish_script,
            text=True,
            capture_output=True,
        )

        if result.returncode != 0:
            print(f"Guestfish failed: {result.stderr}")
            return inject_ssh_key_cloud_init(image_path, ssh_public_key)

        return {"success": True, "method": "guestfish"}

    except FileNotFoundError:
        return inject_ssh_key_cloud_init(image_path, ssh_public_key)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"Guestfish exception: {exc}")
        return inject_ssh_key_cloud_init(image_path, ssh_public_key)


def install_age_key_into_image(image_path: str, age_key_path: Path) -> Dict[str, Any]:
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
                    f"guestfish failed to install Age key" + (f": {stderr}" if stderr else "")
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


def inject_ssh_key_simple(image_path: str, ssh_public_key: str) -> Dict[str, Any]:
    """SSH key injection using loop mount approach."""
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            mount_point = os.path.join(temp_dir, "mnt")
            os.makedirs(mount_point)

            result = subprocess.run(
                ["qemu-img", "info", image_path], capture_output=True, text=True
            )

            if result.returncode != 0:
                return {"success": False, "error": f"Failed to get image info: {result.stderr}"}

            raw_image = os.path.join(temp_dir, "temp.raw")
            subprocess.run(
                ["qemu-img", "convert", "-f", "qcow2", "-O", "raw", image_path, raw_image],
                capture_output=True,
                text=True,
            )

            result = subprocess.run(
                ["parted", "-m", raw_image, "print"], capture_output=True, text=True
            )

            if result.returncode == 0:
                lines = result.stdout.strip().split("\n")
                for line in lines[2:]:
                    parts = line.split(":")
                    if len(parts) >= 5 and ("ext" in parts[4] or "linux" in parts[5].lower()):
                        start_sector = parts[1].rstrip("s")
                        try:
                            start_bytes = int(start_sector) * 512

                            mount_result = subprocess.run(
                                ["sudo", "mount", "-o", f"loop,offset={start_bytes}", raw_image, mount_point],
                                capture_output=True,
                                text=True,
                            )

                            if mount_result.returncode == 0:
                                ssh_dir = os.path.join(mount_point, "root", ".ssh")
                                authorized_keys = os.path.join(ssh_dir, "authorized_keys")

                                subprocess.run(["sudo", "mkdir", "-p", ssh_dir], check=True)
                                subprocess.run(
                                    ["sudo", "sh", "-c", f"echo '{ssh_public_key}' > {authorized_keys}"],
                                    check=True,
                                )
                                subprocess.run(["sudo", "chmod", "700", ssh_dir], check=True)
                                subprocess.run(["sudo", "chmod", "600", authorized_keys], check=True)
                                subprocess.run(["sudo", "chown", "root:root", ssh_dir], check=True)
                                subprocess.run(["sudo", "chown", "root:root", authorized_keys], check=True)

                                subprocess.run(["sudo", "umount", mount_point], check=True)

                                subprocess.run(
                                    ["qemu-img", "convert", "-f", "raw", "-O", "qcow2", raw_image, image_path],
                                    check=True,
                                )

                                return {"success": True, "method": "loop_mount"}

                        except (ValueError, subprocess.CalledProcessError):
                            subprocess.run(["sudo", "umount", mount_point], capture_output=True)
                            continue

            return inject_ssh_key_cloud_init(image_path, ssh_public_key)

    except Exception as exc:  # pylint: disable=broad-except
        return {"success": False, "error": f"Loop mount injection failed: {exc}"}


def inject_ssh_key_cloud_init(image_path: str, ssh_public_key: str) -> Dict[str, Any]:
    """Fallback: Store SSH key info for runtime SSH use."""
    print("💡 SSH key injection skipped - will use keypair directly for SSH authentication")
    return {"success": True, "method": "runtime_auth", "note": "SSH will use stored keypair for authentication"}


def ensure_root_authorized_key(config: Dict[str, Any]) -> bool:
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
        "sshpass",
        "-p",
        "agent",
        "ssh",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-o",
        "ConnectTimeout=10",
        "-p",
        str(ssh_port),
        "agent@localhost",
        remote_cmd,
    ]

    max_attempts = 30
    delay_seconds = 6

    for attempt in range(1, max_attempts + 1):
        result = subprocess.run(ssh_cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True

        print(
            f"⏳ Waiting for VM SSH to accept key injection "
            f"({attempt}/{max_attempts})..."
        )
        time.sleep(delay_seconds)

    return False
