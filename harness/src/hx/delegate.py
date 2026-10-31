"""Hand a task to the cheapest model the routing table trusts with it (DESIGN.md §7, sw-lbm.15).

Lookup in config/routing.toml (written by `hx bench route --write`):
  1. the exact route "<level>/<task_class>/<size>";
  2. the same class at the next larger size (a model trusted with more output is trusted with less);
  3. otherwise level-wide: targets that are `auto` on every route of that level.
Candidates are tried in table order (auto before review, cheapest tier first). A candidate is
skipped when it can't serve right now (local server down and no VRAM, gateway 429 budget/quota,
connection error) and the next one is tried: fallback lives here, not in LiteLLM (DESIGN.md §4).
No candidate left = escalate: the caller does the task itself.
"""

from __future__ import annotations

import json
import time
import tomllib
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from hx import paths, providers
from hx.bench import adapters
from hx.bench.routing import ROUTING_FILE

SIZES = ["s", "m", "l"]
MAX_TOKENS = 16384
LOCAL_FREE_MIB = 11000  # Q33: start the local model only when ~11 GB of VRAM is free
SYSTEM = "You are a precise assistant. Do exactly what the task asks and output only the result."


@dataclass
class Outcome:
    route: str | None = None
    match: str = "none"  # exact | larger-size | level | none
    verdict: str = "no"
    target: str | None = None
    model: str | None = None
    text: str = ""
    needs_review: bool = False
    tried: list[dict] = field(default_factory=list)
    input_tokens: int | None = None
    output_tokens: int | None = None
    latency_s: float = 0.0

    @property
    def escalate(self) -> bool:
        return self.target is None


def guess_size(text: str) -> str:
    """Suite sizes by prompt tokens (~4 chars each): s < 400, m < 1500, else l."""
    tokens = len(text) // 4
    return "s" if tokens < 400 else "m" if tokens < 1500 else "l"


def load_table(path: Path | None = None) -> dict:
    p = path or ROUTING_FILE
    return tomllib.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def lookup(table: dict, level: str, task_class: str | None, size: str) -> tuple[str | None, str, list[dict]]:
    """(route key, match kind, candidates usable for handoff in try order)."""
    routes = table.get("route", {})
    usable = lambda r: [c for c in r.get("candidates", []) if c.get("verdict") in ("auto", "review")]  # noqa: E731
    if task_class:
        for s in SIZES[SIZES.index(size):]:
            key = f"{level}/{task_class}/{s}"
            if key in routes and usable(routes[key]):
                return key, "exact" if s == size else "larger-size", usable(routes[key])
    level_routes = [r for r in routes.values() if r.get("level") == level]
    if not level_routes:
        return None, "none", []
    # Targets trusted (auto) on every route of the level; order by tier, then slowest p50 seen.
    stats: dict[str, list[dict]] = {}
    for r in level_routes:
        for c in r.get("candidates", []):
            stats.setdefault(c["target"], []).append(c)
    everywhere = [cs for cs in stats.values()
                  if len(cs) == len(level_routes) and all(c["verdict"] == "auto" for c in cs)]
    cands = [{**cs[0], "pass_rate": min(c["pass_rate"] for c in cs),
              "p50_s": max((c.get("p50_s") or 0) for c in cs)} for cs in everywhere]
    cands.sort(key=lambda c: (c.get("tier", 9), c["p50_s"]))
    return (f"{level}/*", "level", cands) if cands else (None, "none", [])


def _call_target(cand: dict, roster: dict[str, providers.Provider]) -> dict:
    """An adapters target for a routing candidate: gateway for api/local, claude CLI for the subscription."""
    p = roster.get(cand.get("provider", ""))
    if p and p.kind == "subscription":
        return {"adapter": "claude-cli", "model": cand["model"]}
    from hx.gateway import process
    return {"adapter": "openai", "base_url": process.base_url() + "/v1", "model": cand["model"],
            "api_key_secret": "HX_GATEWAY_KEY", "params": {"temperature": 0.0, "max_tokens": MAX_TOKENS}}


def _ready(cand: dict, roster: dict[str, providers.Provider], start_local: bool) -> str | None:
    """None if the candidate can take a call now (starting servers if allowed), else why not."""
    p = roster.get(cand.get("provider", ""))
    if p is None:
        return "provider not in roster"
    if not p.enabled:
        return "provider disabled"
    if p.kind == "subscription":
        return None
    from hx.gateway import process
    if not process.alive():
        ok, msg = process.start()
        if not ok:
            return f"gateway down: {msg}"
    if p.kind == "local" and p.server:
        from hx import localmodel
        if localmodel.alive(p.id):
            return None
        if not start_local:
            return "local server not running"
        used, total = localmodel.vram_used_mib(), localmodel.vram_total_mib()
        if used is None or total is None or total - used < LOCAL_FREE_MIB:
            return f"not enough free VRAM to start {p.id}"
        ok, msg = localmodel.start(p.id)
        if not ok:
            return f"{p.id} failed to start: {msg}"
    return None


def run(prompt: str, level: str, task_class: str | None = None, size: str | None = None,
        system: str = SYSTEM, start_local: bool = True, timeout: float = 900,
        table: dict | None = None, roster: dict | None = None, call=adapters.call) -> Outcome:
    table = load_table() if table is None else table
    roster = providers.load() if roster is None else roster
    size = size or guess_size(prompt)
    out = Outcome()
    out.route, out.match, cands = lookup(table, level, task_class, size)
    t0 = time.perf_counter()
    for c in cands:
        why = _ready(c, roster, start_local)
        if why:
            out.tried.append({"target": c["target"], "skipped": why})
            continue
        reply = call(_call_target(c, roster), system, prompt, timeout)
        if reply.error:
            out.tried.append({"target": c["target"], "error": reply.error[:200]})
            continue
        out.tried.append({"target": c["target"], "ok": True})
        out.target, out.model, out.verdict = c["target"], c["model"], c["verdict"]
        out.needs_review = c["verdict"] == "review"
        out.text, out.input_tokens, out.output_tokens = reply.text, reply.input_tokens, reply.output_tokens
        break
    out.latency_s = round(time.perf_counter() - t0, 2)
    _log(out, level, task_class, size)
    return out


def opencode_models(path: Path | None = None) -> set[str]:
    """Gateway models OpenCode can drive (provider "hx" in the repo's opencode.json)."""
    f = path or paths.repo_root() / "opencode.json"
    try:
        return set(json.loads(f.read_text(encoding="utf-8"))["provider"]["hx"]["models"])
    except (OSError, ValueError, KeyError):
        return set()


def run_agent(prompt: str, level: str, task_class: str | None = None, size: str | None = None,
              start_local: bool = True, timeout: float = 1800, table: dict | None = None,
              roster: dict | None = None) -> Outcome:
    """Tool-using handoff: headless `opencode run` on the first routed model OpenCode can drive.
    It edits the working tree; the caller reviews the diff."""
    import subprocess
    table = load_table() if table is None else table
    roster = providers.load() if roster is None else roster
    size = size or guess_size(prompt)
    out = Outcome()
    out.route, out.match, cands = lookup(table, level, task_class, size)
    allowed = opencode_models()
    oc = roster.get("opencode-zen")
    exe = providers.find_cli(oc) if oc else None
    t0 = time.perf_counter()
    for c in cands:
        if c["model"] not in allowed:
            out.tried.append({"target": c["target"], "skipped": "not an OpenCode (hx) model"})
            continue
        why = "opencode CLI not found" if not exe else _ready(c, roster, start_local)
        if why:
            out.tried.append({"target": c["target"], "skipped": why})
            continue
        p = subprocess.run([exe, "run", "--auto", "-m", f"hx/{c['model']}", prompt], capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=timeout, cwd=paths.repo_root())
        if p.returncode != 0:
            out.tried.append({"target": c["target"], "error": (p.stderr or p.stdout).strip()[-200:]})
            continue
        out.tried.append({"target": c["target"], "ok": True})
        out.target, out.model, out.verdict = c["target"], c["model"], c["verdict"]
        out.needs_review = True  # agent edits are always reviewed
        out.text = p.stdout
        break
    out.latency_s = round(time.perf_counter() - t0, 2)
    _log(out, level, task_class, size)
    return out


def _log(out: Outcome, level: str, task_class: str | None, size: str) -> None:
    """Raw record (data/raw/delegate/<day>.jsonl); the prompt and output text are not kept."""
    d = paths.data_dir() / "raw" / "delegate"
    d.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    row = {"ts": now.isoformat(timespec="seconds"), "level": level, "task_class": task_class, "size": size,
           "route": out.route, "match": out.match, "target": out.target, "model": out.model,
           "verdict": out.verdict, "escalate": out.escalate, "tried": out.tried,
           "input_tokens": out.input_tokens, "output_tokens": out.output_tokens, "latency_s": out.latency_s}
    with (d / f"{now:%Y%m%d}.jsonl").open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(row) + "\n")
