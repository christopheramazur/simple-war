"""Start/stop the LiteLLM gateway as a detached background process."""

from __future__ import annotations

import os
import secrets as pysecrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from hx import keystore, providers
from hx.gateway import config
from hx.paths import HARNESS_ROOT


def pid_file() -> Path:
    return config.gateway_dir() / "gateway.pid"


def log_file() -> Path:
    return config.gateway_dir() / "gateway.log"


def base_url() -> str:
    return f"http://127.0.0.1:{config.PORT}"


def alive(timeout: float = 2) -> bool:
    try:
        with urllib.request.urlopen(base_url() + "/health/liveliness", timeout=timeout):
            return True
    except (urllib.error.URLError, OSError):
        return False


def master_key() -> str:
    """The local gateway key; generated and stored in the keystore on first use."""
    key = keystore.get(config.KEY_NAME)
    if not key:
        key = "hx-" + pysecrets.token_urlsafe(24)
        try:
            keystore.set(config.KEY_NAME, key)
        except RuntimeError:
            keystore.set(config.KEY_NAME, key, "file")
    return key


def child_env(roster) -> dict:
    env = dict(os.environ)
    env.update(keystore.env_for([k for p in roster.values() for k in p.keys]))
    env[config.KEY_NAME] = master_key()
    env["PYTHONPATH"] = str(HARNESS_ROOT / "src") + os.pathsep + env.get("PYTHONPATH", "")
    env["PYTHONUTF8"] = "1"
    return env


def start(wait: float = 180) -> tuple[bool, str]:
    if alive():
        return True, "already running"
    roster = providers.load()
    cfg_path, skipped, n = config.write(roster)
    uvx = shutil.which("uvx")
    if not uvx:
        return False, "uvx not on PATH"
    # prisma: LiteLLM's error handlers import it even with no database; without it every
    # 4xx (bad key, our 429 budget refusal) is masked as a 500.
    cmd = [uvx, "--python", config.PYTHON, "--with", "tzdata", "--with", "prisma", "--from", config.LITELLM, "litellm",
           "--config", str(cfg_path), "--host", "127.0.0.1", "--port", str(config.PORT)]
    log = log_file().open("ab")
    kw: dict = {"cwd": config.gateway_dir(), "env": child_env(roster), "stdout": log, "stderr": subprocess.STDOUT,
                "stdin": subprocess.DEVNULL}
    if sys.platform == "win32":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        try:  # survive the agent shell's job object
            proc = subprocess.Popen(cmd, creationflags=flags | subprocess.CREATE_BREAKAWAY_FROM_JOB, **kw)
        except OSError:
            proc = subprocess.Popen(cmd, creationflags=flags, **kw)
    else:
        proc = subprocess.Popen(cmd, start_new_session=True, **kw)
    pid_file().write_text(str(proc.pid))
    deadline = time.time() + wait
    while time.time() < deadline:
        if alive():
            return True, f"started pid {proc.pid}, {n} model(s)" + (f"; skipped {skipped}" if skipped else "")
        if proc.poll() is not None:
            return False, f"exited with {proc.returncode}; see {log_file()}"
        time.sleep(1)
    return False, f"not healthy after {wait:.0f}s; see {log_file()}"


def stop() -> str:
    pf = pid_file()
    if not pf.exists():
        return "not running (no pid file)"
    pid = pf.read_text().strip()
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/PID", pid, "/T", "/F"], capture_output=True)
    else:
        subprocess.run(["kill", "--", f"-{pid}"], capture_output=True)
    pf.unlink(missing_ok=True)
    return f"stopped pid {pid}"
