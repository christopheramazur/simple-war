"""Detached background processes (gateway, local model server) that outlive the agent's shell."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def spawn(cmd: list[str], cwd: Path, env: dict | None, log: Path) -> subprocess.Popen:
    log.parent.mkdir(parents=True, exist_ok=True)
    kw: dict = {"cwd": cwd, "env": env, "stdout": log.open("ab"), "stderr": subprocess.STDOUT,
                "stdin": subprocess.DEVNULL}
    if sys.platform == "win32":
        # CREATE_NO_WINDOW, not DETACHED_PROCESS: a detached process has no console at all, so every
        # console program it starts (the venv's python.exe launcher's real interpreter, uvx, litellm,
        # llama-server, Godot) gets a new visible Windows Terminal window. A hidden console is
        # inherited by those children instead.
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        try:  # break out of the agent shell's job object so the process survives it
            return subprocess.Popen(cmd, creationflags=flags | subprocess.CREATE_BREAKAWAY_FROM_JOB, **kw)
        except OSError:
            return subprocess.Popen(cmd, creationflags=flags, **kw)
    return subprocess.Popen(cmd, start_new_session=True, **kw)


def kill_tree(pid: str | int) -> None:
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    else:
        subprocess.run(["kill", "--", f"-{pid}"], capture_output=True)
