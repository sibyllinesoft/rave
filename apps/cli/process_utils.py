"""Subprocess helpers with consistent logging and timeout handling."""

from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Union


@dataclass
class ProcessResult:
    command: List[str]
    returncode: int
    stdout: str
    stderr: str
    duration: float


class ProcessError(RuntimeError):
    def __init__(self, result: ProcessResult, message: Optional[str] = None):
        super().__init__(message or result.stderr or "process failed")
        self.result = result


def run_command(
    command: Union[Sequence[str], str],
    *,
    check: bool = False,
    timeout: Optional[int] = None,
    text: bool = True,
    capture_output: bool = True,
    env: Optional[dict] = None,
    input_data: Optional[Union[bytes, str]] = None,
    cwd: Optional[Union[str, Path]] = None,
    shell: bool = False,
) -> ProcessResult:
    start = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            check=False,
            timeout=timeout,
            text=text,
            capture_output=capture_output,
            env=env,
            input=input_data,
            cwd=str(cwd) if isinstance(cwd, Path) else cwd,
            shell=shell,
        )
    except subprocess.TimeoutExpired as exc:
        raise ProcessError(
            ProcessResult(
                list(command) if not shell else ["/bin/sh", "-c", str(command)],
                exc.timeout or -1,
                (exc.output or "") if isinstance(exc.output, str) else "",
                (exc.stderr or "") if isinstance(exc.stderr, str) else "",
                time.monotonic() - start,
            ),
            message=f"Command timed out after {timeout}s: {command}",
        ) from exc

    duration = time.monotonic() - start
    stdout = completed.stdout if isinstance(completed.stdout, str) else (completed.stdout or b"").decode("utf-8", "replace")
    stderr = completed.stderr if isinstance(completed.stderr, str) else (completed.stderr or b"").decode("utf-8", "replace")
    result = ProcessResult(list(command), completed.returncode, stdout, stderr, duration)

    if check and completed.returncode != 0:
        raise ProcessError(result)

    return result
