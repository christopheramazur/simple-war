"""Local llama-server lifecycle and the context-fit probe (DESIGN.md §7, sw-lbm.12).

Launches the server directly from providers.toml [provider.<id>.server] (never with --agent),
and measures which context size fits the GPU at full speed.
"""

from __future__ import annotations

import json
import re
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

from hx import background, providers
from hx.paths import data_dir


def state_dir(pid: str = "bonsai") -> Path:
    return data_dir() / pid


def _server(pid: str) -> tuple[providers.Provider, dict]:
    p = providers.load()[pid]
    if p.kind != "local" or not p.server:
        raise ValueError(f"{pid} has no [provider.{pid}.server] launch settings")
    return p, p.server


def url(pid: str = "bonsai") -> str:
    _, s = _server(pid)
    return f"http://{s.get('host', '127.0.0.1')}:{s.get('port', 8080)}"


def alive(pid: str = "bonsai", timeout: float = 2) -> bool:
    try:
        with urllib.request.urlopen(url(pid) + "/health", timeout=timeout) as r:
            return json.loads(r.read() or b"{}").get("status") == "ok"
    except (urllib.error.URLError, OSError, ValueError):
        return False


def command(pid: str = "bonsai", ctx: int | None = None) -> list[str]:
    _, s = _server(pid)
    root = Path(s.get("root", "."))
    cmd = [str(root / s["exe"]), "-m", str(root / s["model"]), "--host", s.get("host", "127.0.0.1"),
           "--port", str(s.get("port", 8080)), "-c", str(ctx or s.get("ctx", 8192)), *s.get("args", [])]
    if "--agent" in cmd:
        raise ValueError("--agent must stay off for harness use (DESIGN.md Q23)")
    return cmd


def start(pid: str = "bonsai", ctx: int | None = None, wait: float = 300) -> tuple[bool, str]:
    if alive(pid):
        return True, "already running"
    cmd = command(pid, ctx)
    d = state_dir(pid)
    log = d / "server.log"
    proc = background.spawn(cmd, Path(cmd[0]).parent, None, log)
    (d / "server.pid").write_text(str(proc.pid))
    deadline = time.time() + wait
    while time.time() < deadline:
        if alive(pid):
            return True, f"pid {proc.pid}, ctx {ctx or _server(pid)[1].get('ctx')}"
        if proc.poll() is not None:
            return False, f"exited with {proc.returncode}: {_tail_error(log)}"
        time.sleep(1)
    return False, f"not healthy after {wait:.0f}s: {_tail_error(log)}"


def stop(pid: str = "bonsai") -> str:
    pf = state_dir(pid) / "server.pid"
    if not pf.exists():
        return "not running (no pid file)"
    p = pf.read_text().strip()
    background.kill_tree(p)
    pf.unlink(missing_ok=True)
    for _ in range(20):  # wait for VRAM to be released before anything measures it
        if not alive(pid, timeout=0.5):
            break
        time.sleep(0.5)
    return f"stopped pid {p}"


def _tail_error(log: Path) -> str:
    try:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()[-200:]
    except OSError:
        return "no log"
    hits = [ln for ln in lines if re.search(r"out of memory|failed|error|cudaMalloc", ln, re.I)]
    return (hits[-1] if hits else (lines[-1] if lines else "empty log")).strip()[:200]


def vram_used_mib() -> int | None:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=10).stdout
        return int(out.strip().splitlines()[0])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None


def vram_total_mib() -> int | None:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=10).stdout
        return int(out.strip().splitlines()[0])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None


# ---------------- probe ----------------

@dataclass
class ProbeResult:
    ctx: int
    loaded: bool
    vram_mib: int | None = None
    filled_tokens: int | None = None
    prefill_tps: float | None = None
    gen_tps: float | None = None
    fill_ok: bool = False
    seconds: float = 0.0
    error: str | None = None


def _complete(pid: str, prompt: str, max_tokens: int, timeout: float) -> dict:
    p, _ = _server(pid)
    model = p.models[0]["model"] if p.models else "local"
    body = {"model": model, "max_tokens": max_tokens, "temperature": 0,
            "messages": [{"role": "user", "content": prompt}],
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(url(pid) + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def probe_one(pid: str, ctx: int, fill: float = 0.9, timeout: float = 1800) -> ProbeResult:
    """Load at `ctx`, measure short-prompt generation speed, then fill to `fill` x ctx."""
    from hx.bench.runner import pad  # GDD filler: realistic text

    t0 = time.time()
    res = ProbeResult(ctx=ctx, loaded=False)
    ok, msg = start(pid, ctx, wait=600)
    if not ok:
        res.error = msg
        res.seconds = round(time.time() - t0, 1)
        stop(pid)
        return res
    res.loaded = True
    res.vram_mib = vram_used_mib()
    try:
        short = _complete(pid, "Write three sentences about tactical war games.", 128, 300)
        res.gen_tps = round((short.get("timings") or {}).get("predicted_per_second") or 0, 1) or None
        # Padding is sized at 4 chars/token; this tokenizer packs ~4.3, so the real prompt
        # lands near 0.93 x the target (8k -> 7.46k measured): safely inside ctx.
        prompt = pad("Reply with only the word: ok", int(ctx * fill))
        long = _complete(pid, prompt, 8, timeout)
        tm = long.get("timings") or {}
        res.filled_tokens = (long.get("usage") or {}).get("prompt_tokens")
        res.prefill_tps = round(tm.get("prompt_per_second") or 0, 1) or None
        res.fill_ok = True
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        res.error = f"{type(e).__name__}: {str(e)[:160]} | {_tail_error(state_dir(pid) / 'server.log')}"
    finally:
        stop(pid)
        res.seconds = round(time.time() - t0, 1)
    return res


def choose(results: list[ProbeResult], min_speed_ratio: float = 0.95) -> int | None:
    """Largest context that loaded, filled, and kept generation speed near the best seen.

    On Windows the NVIDIA driver can silently spill to shared system memory instead of
    failing; that shows up as a generation-speed drop on a *short* prompt (which shouldn't
    depend on context size at all), so speed is part of "fits". RTX 3060 12 GB, 2026-11-01:
    32k-96k 34.5 t/s, 128k 34.1, 160k 31.1 (-10%, spill starting), 200k 25.2 -> 128k.
    """
    good = [r for r in results if r.loaded and r.fill_ok and r.gen_tps]
    if not good:
        return None
    best = max(r.gen_tps for r in good)
    ok = [r for r in good if r.gen_tps >= best * min_speed_ratio]
    return max(r.ctx for r in ok) if ok else None


def save_probe(pid: str, results: list[ProbeResult], chosen: int | None) -> Path:
    out = state_dir(pid) / f"probe-{datetime.now():%Y%m%d-%H%M%S}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"chosen_ctx": chosen, "vram_total_mib": vram_total_mib(),
                               "results": [asdict(r) for r in results]}, indent=1), encoding="utf-8")
    return out


def apply_ctx(pid: str, ctx: int, path: Path | None = None) -> None:
    """Rewrite `ctx = N` inside [provider.<pid>.server] (keeps comments and layout)."""
    path = path or providers.PROVIDERS_FILE
    text = path.read_text(encoding="utf-8")
    m = re.search(rf"^\[provider\.{re.escape(pid)}\.server\]\s*$(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if not m or not re.search(r"^ctx\s*=", m.group(1), re.M):
        raise ValueError(f"no ctx line under [provider.{pid}.server]")
    section = re.sub(r"^ctx\s*=.*$", f"ctx = {ctx}", m.group(1), count=1, flags=re.M)
    path.write_text(text[:m.start(1)] + section + text[m.end(1):], encoding="utf-8", newline="\n")
