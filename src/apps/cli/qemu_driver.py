"""QEMU command generation for launching RAVE VMs."""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def build_vm_command(
    image_path: str,
    *,
    memory_gb: int = 12,
    port_forwards: Optional[List[Tuple[int, int]]] = None,
    age_key_dir: Optional[str] = None,
) -> Tuple[List[str], Optional[Dict[str, str]]]:
    """Generate a QEMU/launcher command and environment."""

    repo_root = Path(__file__).resolve().parent.parent
    nix_vm_launcher = repo_root / "result" / "bin" / "run-rave-complete-vm"

    if nix_vm_launcher.exists():
        env = os.environ.copy()
        env["NIX_DISK_IMAGE"] = str(Path(image_path).resolve())

        if port_forwards:
            hostfwd_rules = [
                f"hostfwd=tcp::{host_port}-:{guest_port}"
                for host_port, guest_port in port_forwards
            ]
            env["QEMU_NET_OPTS"] = ",".join(hostfwd_rules)

        return [str(nix_vm_launcher)], env

    qemu_binary = shutil.which("qemu-system-x86_64")
    if not qemu_binary:
        raise RuntimeError("qemu-system-x86_64 is required to launch the VM")

    cmd: List[str] = [qemu_binary]

    cmd.extend(
        [
            "-drive",
            f"file={image_path},format=qcow2",
            "-m",
            f"{memory_gb}G",
            "-smp",
            "2",
        ]
    )

    if Path("/dev/kvm").exists():
        cmd.extend(["-accel", "kvm"])

    if port_forwards:
        hostfwd_rules = [
            f"hostfwd=tcp::{host_port}-:{guest_port}"
            for host_port, guest_port in port_forwards
        ]

        netdev = f"user,id=net0,{','.join(hostfwd_rules)}"
        cmd.extend(
            [
                "-netdev",
                netdev,
                "-device",
                "virtio-net-pci,netdev=net0",
            ]
        )
    else:
        cmd.extend(
            [
                "-netdev",
                "user,id=net0",
                "-device",
                "virtio-net-pci,netdev=net0",
            ]
        )

    if age_key_dir:
        cmd.extend(
            [
                "-virtfs",
                f"local,path={age_key_dir},mount_tag=sops-keys,security_model=none",
            ]
        )

    cmd.extend(["-display", "none"])

    return cmd, None
