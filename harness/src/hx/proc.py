"""Subprocess helper: never raises, always bounded by a timeout."""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Run:
    ok: bool
    out: str
    err: str = ""


def run(cmd: list[str], cwd: Path | None = None, timeout: float = 15) -> Run:
    exe = shutil.which(cmd[0])
    if exe is None:
        return Run(False, "", f"{cmd[0]} not found on PATH")
    try:
        p = subprocess.run(
            [exe, *cmd[1:]], cwd=cwd, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        return Run(p.returncode == 0, p.stdout.strip(), p.stderr.strip())
    except subprocess.TimeoutExpired:
        return Run(False, "", f"timed out after {timeout}s")
    except OSError as e:
        return Run(False, "", str(e))
