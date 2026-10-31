"""Model adapters: send (system, prompt), get back text + token usage. One call per task, no tools."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
import tomllib
import urllib.error
import urllib.request
from dataclasses import dataclass, field

from hx.paths import HARNESS_ROOT

TARGETS_FILE = HARNESS_ROOT / "config" / "bench_targets.toml"


@dataclass
class Reply:
    text: str = ""
    input_tokens: int | None = None
    output_tokens: int | None = None
    latency_s: float = 0.0
    error: str | None = None
    raw_model: str | None = None
    extra: dict = field(default_factory=dict)


def load_targets() -> dict[str, dict]:
    return tomllib.loads(TARGETS_FILE.read_text(encoding="utf-8")).get("target", {})


def call(target: dict, system: str, prompt: str, timeout: float) -> Reply:
    fn = {"openai": _openai, "claude-cli": _claude_cli}[target["adapter"]]
    t0 = time.perf_counter()
    try:
        r = fn(target, system, prompt, timeout)
    except Exception as e:  # one failed call must not kill a run
        r = Reply(error=f"{type(e).__name__}: {str(e)[:300]}")
    r.latency_s = round(time.perf_counter() - t0, 2)
    return r


def health(target: dict) -> str | None:
    """None if reachable, else a reason."""
    if target["adapter"] == "openai":
        try:
            req = urllib.request.Request(target["base_url"].rstrip("/") + "/models", headers=_auth(target))
            with urllib.request.urlopen(req, timeout=5):
                return None
        except (urllib.error.URLError, OSError) as e:
            return f"{target['base_url']} unreachable: {e}"
    if target["adapter"] == "claude-cli":
        exe = shutil.which("claude")
        if not exe:
            return "claude CLI not on PATH"
        try:
            p = subprocess.run([exe, "auth", "status"], capture_output=True, text=True, timeout=30)
            if not json.loads(p.stdout or "{}").get("loggedIn"):
                return "claude CLI is not logged in (run `claude auth login` in a terminal)"
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as e:
            return f"claude auth status failed: {e}"
        return None
    return f"unknown adapter {target['adapter']}"


def _auth(target: dict) -> dict:
    """Bearer header from a keystore name (e.g. HX_GATEWAY_KEY); keys never live in config."""
    if not target.get("api_key_secret"):
        return {}
    from hx import keystore
    return {"Authorization": f"Bearer {keystore.get(target['api_key_secret']) or ''}"}


def _openai(target, system, prompt, timeout) -> Reply:
    body = {"model": target["model"], "messages": [{"role": "system", "content": system},
                                                   {"role": "user", "content": prompt}],
            **target.get("params", {})}
    headers = {"Content-Type": "application/json", "x-hx-caller": "bench", **_auth(target)}
    req = urllib.request.Request(target["base_url"].rstrip("/") + "/chat/completions",
                                 data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        d = json.loads(resp.read())
    msg = d["choices"][0]["message"]
    u = d.get("usage") or {}
    return Reply(text=msg.get("content") or "", input_tokens=u.get("prompt_tokens"),
                 output_tokens=u.get("completion_tokens"), raw_model=d.get("model"),
                 extra={"finish_reason": d["choices"][0].get("finish_reason"),
                        "reasoning_chars": len(msg.get("reasoning_content") or "")})


def _claude_cli(target, system, prompt, timeout) -> Reply:
    # Run outside the repo so project hooks/settings never fire for benchmark calls.
    with tempfile.TemporaryDirectory(prefix="hx-bench-") as cwd:
        p = subprocess.run(
            ["claude", "-p", "--model", target["model"], "--output-format", "json", "--tools", "",
             "--no-session-persistence", "--system-prompt", system],
            input=prompt, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=timeout, cwd=cwd, executable=shutil.which("claude"))
    d = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else {}
    if d.get("is_error") or p.returncode != 0:
        return Reply(error=str(d.get("result") or p.stderr.strip()[:300] or f"exit {p.returncode}"))
    u = d.get("usage") or {}
    inp = sum(u.get(k, 0) or 0 for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    return Reply(text=d.get("result", ""), input_tokens=inp, output_tokens=u.get("output_tokens"),
                 raw_model=next(iter(d.get("modelUsage") or {}), None),
                 extra={"cost_usd": d.get("total_cost_usd")})
