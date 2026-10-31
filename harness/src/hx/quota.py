"""Subscription quota snapshots and burn projection (DESIGN.md §2, Q4/Q17).

Snapshots are appended to data/raw/quota/<provider>.jsonl (raw record, cheap to
write from the status line). `hx ingest` loads them into the ledger. Stdlib only:
the status line imports this on every refresh.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from hx.paths import data_dir

WINDOWS = ("five_hour", "seven_day")
MIN_INTERVAL = 300  # seconds between snapshots when nothing changed
MIN_SPAN = 600  # need this much history in a window before projecting
TAIL_BYTES = 256 * 1024


def log_path(provider: str = "claude-pro") -> Path:
    return data_dir() / "raw" / "quota" / f"{provider}.jsonl"


@dataclass
class Snapshot:
    ts: float
    window: str
    used_pct: float
    resets_at: float
    session_id: str | None = None
    provider: str = "claude-pro"


def from_statusline(inp: dict, now: float | None = None) -> list[Snapshot]:
    now = now or time.time()
    out = []
    for w in WINDOWS:
        d = (inp.get("rate_limits") or {}).get(w) or {}
        if d.get("used_percentage") is not None and d.get("resets_at"):
            out.append(Snapshot(now, w, float(d["used_percentage"]), float(d["resets_at"]), inp.get("session_id")))
    return out


def read_tail(path: Path, max_bytes: int = TAIL_BYTES) -> list[Snapshot]:
    if not path.exists():
        return []
    with path.open("rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - max_bytes))
        chunk = f.read().decode("utf-8", errors="replace")
    lines = chunk.splitlines()[1 if size > max_bytes else 0:]  # first line may be partial
    out = []
    for line in lines:
        try:
            out.append(Snapshot(**json.loads(line)))
        except (json.JSONDecodeError, TypeError):
            continue
    return out


def record(snaps: list[Snapshot], history: list[Snapshot], path: Path | None = None) -> list[Snapshot]:
    """Append snapshots that changed, or whose window was last logged > MIN_INTERVAL ago."""
    path = path or log_path()
    last = {}
    for s in history:
        last[s.window] = s
    new = [s for s in snaps
           if (p := last.get(s.window)) is None or p.used_pct != s.used_pct
           or abs(p.resets_at - s.resets_at) > 60 or s.ts - p.ts >= MIN_INTERVAL]
    if new:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            for s in new:
                f.write(json.dumps(s.__dict__) + "\n")
    return new


@dataclass
class Projection:
    used_pct: float
    resets_at: float
    full_at: float | None  # projected time to hit 100%, None if no burn data
    rate_per_h: float | None

    @property
    def will_hit_limit(self) -> bool:
        return self.full_at is not None and self.full_at < self.resets_at


def project(current: Snapshot, history: list[Snapshot]) -> Projection:
    """Linear burn from the earliest snapshot in the same window instance."""
    same = [s for s in history if s.window == current.window and abs(s.resets_at - current.resets_at) <= 60]
    first = min(same, key=lambda s: s.ts, default=None)
    if first is None or current.ts - first.ts < MIN_SPAN or current.used_pct <= first.used_pct:
        return Projection(current.used_pct, current.resets_at, None, None)
    rate = (current.used_pct - first.used_pct) / (current.ts - first.ts)  # pct per second
    full_at = current.ts + (100 - current.used_pct) / rate
    return Projection(current.used_pct, current.resets_at, full_at, round(rate * 3600, 2))
