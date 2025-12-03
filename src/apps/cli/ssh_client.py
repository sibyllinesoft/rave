"""Lightweight SSH helper used by the VM manager."""

from __future__ import annotations

import shutil
import time
from pathlib import Path
from typing import Any, Dict, Optional

from process_utils import ProcessError, run_command


def build_ssh_command(
    config: Dict[str, Any],
    remote_script: str,
    *,
    connect_timeout: int = 10,
) -> Dict[str, Any]:
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
        "-o",
        f"ConnectTimeout={connect_timeout}",
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


def run_remote_script(
    config: Dict[str, Any],
    remote_script: str,
    *,
    timeout: int,
    description: str,
    connect_timeout: int = 10,
    max_attempts: int = 5,
    initial_delay: float = 1.0,
    max_delay: float = 16.0,
) -> Dict[str, Any]:
    """Execute a remote script over SSH with exponential backoff."""

    delay = initial_delay
    last_error = ""

    for attempt in range(1, max_attempts + 1):
        build_result = build_ssh_command(
            config, remote_script, connect_timeout=connect_timeout
        )
        if not build_result.get("success"):
            return build_result

        ssh_cmd = build_result["command"]

        try:
            result_obj = run_command(
                ssh_cmd,
                timeout=timeout,
            )
        except ProcessError as exc:
            last_error = (
                exc.result.stderr.strip()
                or exc.result.stdout.strip()
                or f"{description} attempt {attempt} failed"
            )
        else:
            if result_obj.returncode == 0:
                return {"success": True, "result": result_obj}

            stderr = result_obj.stderr.strip()
            stdout = result_obj.stdout.strip()
            last_error = (
                stderr
                or stdout
                or f"{description} failed with exit code {result_obj.returncode}"
            )

        if attempt < max_attempts:
            time.sleep(delay)
            delay = min(delay * 2, max_delay)

    return {"success": False, "error": last_error or description}


def run_remote_stream(
    config: Dict[str, Any],
    remote_script: str,
    *,
    data: bytes,
    timeout: int,
    description: str,
    connect_timeout: int = 10,
    max_attempts: int = 5,
    initial_delay: float = 1.0,
    max_delay: float = 16.0,
) -> Dict[str, Any]:
    """Stream data to a remote script over SSH with retries."""

    delay = initial_delay
    last_error: Optional[str] = None

    for attempt in range(1, max_attempts + 1):
        build_result = build_ssh_command(
            config, remote_script, connect_timeout=connect_timeout
        )
        if not build_result.get("success"):
            return build_result

        ssh_cmd = build_result["command"]

        try:
            result_obj = run_command(
                ssh_cmd,
                input_data=data,
                timeout=timeout,
            )
        except ProcessError as exc:
            last_error = (
                exc.result.stderr.strip()
                or exc.result.stdout.strip()
                or f"{description} attempt {attempt} failed"
            )
        else:
            if result_obj.returncode == 0:
                return {"success": True, "result": result_obj}

            stderr = result_obj.stderr.strip()
            stdout = result_obj.stdout.strip()
            last_error = (
                stderr
                or stdout
                or f"{description} failed with exit code {result_obj.returncode}"
            )

        if attempt < max_attempts:
            time.sleep(delay)
            delay = min(delay * 2, max_delay)

    return {"success": False, "error": last_error or description}
