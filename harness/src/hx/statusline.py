"""Claude Code status line (DESIGN.md §2). Run as `python -m hx.statusline` with the
status-line JSON on stdin. Must stay fast and must never crash: stdlib only, no ledger
access (it reads the summary cache that `hx ingest` writes).

Example output:
  Opus 5.5 · 5h 42% ↺14:20 · 7d 18% ↺Thu · ctx 34% · sess $1.20 · today $8.45 · $1.12/task
"""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime

from hx import quota
from hx.paths import data_dir

GREEN, YELLOW, RED, DIM, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[2m", "\033[0m"
SEP = f" {DIM}·{RESET} "
STALE_AFTER = 6 * 3600


def summary_path():
    return data_dir() / "cache" / "summary.json"


def _color(pct: float) -> str:
    return GREEN if pct < 50 else YELLOW if pct < 80 else RED


def _when(epoch: float, now: float) -> str:
    t = datetime.fromtimestamp(epoch)
    return t.strftime("%H:%M") if epoch - now < 20 * 3600 else t.strftime("%a")


def _window(label: str, p: quota.Projection, now: float) -> str:
    s = f"{label} {_color(p.used_pct)}{p.used_pct:.0f}%{RESET} ↺{_when(p.resets_at, now)}"
    if p.will_hit_limit:
        s += f" {RED}⚠ full ~{_when(p.full_at, now)}{RESET}"
    return s


def render(inp: dict, now: float | None = None, record: bool = True) -> str:
    now = now or time.time()
    parts = [((inp.get("model") or {}).get("display_name") or "?")]

    snaps = quota.from_statusline(inp, now)
    if snaps:
        history = quota.read_tail(quota.log_path())
        if record:
            history += quota.record(snaps, history)
        for s in snaps:
            parts.append(_window("5h" if s.window == "five_hour" else "7d", quota.project(s, history), now))

    ctx = (inp.get("context_window") or {}).get("used_percentage")
    if ctx is not None:
        parts.append(f"ctx {ctx:.0f}%")
    cost = (inp.get("cost") or {}).get("total_cost_usd")
    if cost:
        parts.append(f"sess ${cost:.2f}")

    try:
        summ = json.loads(summary_path().read_text(encoding="utf-8"))
        stale = now - summ.get("generated_at", 0) > STALE_AFTER
        today = f"today ${summ.get('today_usd', 0):.2f}"
        parts.append(f"{DIM}{today}?{RESET}" if stale else today)
        if summ.get("usd_per_closed_task"):
            parts.append(f"${summ['usd_per_closed_task']:.2f}/task")
    except (OSError, ValueError):
        pass
    return SEP.join(parts)


def main() -> None:
    try:
        raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        inp = json.loads(raw) if raw.strip() else {}
        out = render(inp)
    except Exception as e:  # a broken status line must never break the session
        out = f"hx statusline error: {type(e).__name__}"
        if os.environ.get("HX_DEBUG"):
            raise
    sys.stdout.buffer.write(out.encode("utf-8"))


if __name__ == "__main__":
    main()
