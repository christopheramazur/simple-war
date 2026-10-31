"""Budget and free-tier quota enforcement (Q16, Q30). Pure logic: no LiteLLM imports.

The gateway process keeps one Tracker in memory, seeded from today's raw call log,
and asks it before every call. A refusal is never silent: the reason names the limit.
"""

from __future__ import annotations

import json
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from hx.paths import data_dir
from hx.providers import Provider


def log_dir() -> Path:
    return data_dir() / "raw" / "gateway"


@dataclass
class Decision:
    allowed: bool
    reason: str = ""


class Tracker:
    """Counts requests/tokens/spend per provider in the windows its limits use."""

    def __init__(self, roster: dict[str, Provider]):
        self.roster = roster
        self.minute: dict[str, deque] = defaultdict(deque)  # request timestamps (epoch) in the last 60s
        self.day: dict[str, dict] = defaultdict(lambda: {"key": None, "requests": 0, "tokens": 0})
        self.month: dict[str, dict] = defaultdict(lambda: {"key": None, "usd": 0.0})

    # ----- windows -----
    def _tz(self, p: Provider):
        return ZoneInfo(p.reset_tz) if p.reset_tz else timezone.utc

    def _keys(self, p: Provider, ts: float) -> tuple[str, str]:
        local = datetime.fromtimestamp(ts, self._tz(p))
        return local.strftime("%Y-%m-%d"), local.strftime("%Y-%m")

    def _roll(self, pid: str, ts: float) -> None:
        p = self.roster[pid]
        dkey, mkey = self._keys(p, ts)
        if self.day[pid]["key"] != dkey:
            self.day[pid] = {"key": dkey, "requests": 0, "tokens": 0}
        if self.month[pid]["key"] != mkey:
            self.month[pid] = {"key": mkey, "usd": 0.0}
        q = self.minute[pid]
        while q and ts - q[0] >= 60:
            q.popleft()

    # ----- API -----
    def check(self, pid: str, now: float) -> Decision:
        p = self.roster.get(pid)
        if p is None:
            return Decision(False, f"provider {pid!r} is not in config/providers.toml")
        if p.kind == "subscription":
            return Decision(False, f"{pid} is a subscription and must not be routed through the gateway")
        self._roll(pid, now)
        lim = p.limits or {}
        if p.hard_stop and self.month[pid]["usd"] > p.monthly_budget_usd:
            return Decision(False, f"{pid}: monthly budget ${p.monthly_budget_usd:g} spent "
                                   f"(${self.month[pid]['usd']:.4f}); raising it needs the user's approval")
        if "rpm" in lim and len(self.minute[pid]) >= lim["rpm"]:
            return Decision(False, f"{pid}: free-tier rpm {lim['rpm']} reached")
        if "rpd" in lim and self.day[pid]["requests"] >= lim["rpd"]:
            return Decision(False, f"{pid}: free-tier rpd {lim['rpd']} reached (resets midnight {p.reset_tz or 'UTC'})")
        if "tpd" in lim and self.day[pid]["tokens"] >= lim["tpd"]:
            return Decision(False, f"{pid}: free-tier tpd {lim['tpd']} reached")
        return Decision(True)

    def record(self, pid: str, ts: float, tokens: int = 0, usd: float = 0.0) -> None:
        if pid not in self.roster:
            return
        self._roll(pid, ts)
        self.minute[pid].append(ts)
        self.day[pid]["requests"] += 1
        self.day[pid]["tokens"] += tokens or 0
        self.month[pid]["usd"] += usd or 0.0

    def snapshot(self) -> dict:
        return {pid: {"day": dict(self.day[pid]), "month": dict(self.month[pid]), "last_minute": len(self.minute[pid])}
                for pid in self.roster if pid in self.day or pid in self.month}

    def seed(self, rows) -> int:
        """Replay logged calls (oldest first) so limits survive a gateway restart."""
        n = 0
        for row in rows:
            if row.get("provider") and row.get("status") == "success":
                ts = datetime.fromisoformat(row["ts"]).timestamp()
                self.record(row["provider"], ts, (row.get("prompt_tokens") or 0) + (row.get("completion_tokens") or 0),
                            row.get("cost_usd") or 0.0)
                n += 1
        return n


def read_log(since_days: int = 32) -> list[dict]:
    """Calls from the last `since_days` daily files (enough for monthly budgets)."""
    d = log_dir()
    if not d.exists():
        return []
    cutoff = (datetime.now(timezone.utc) - timedelta(days=since_days)).strftime("%Y-%m-%d")
    rows = []
    for f in sorted(d.glob("*.jsonl")):
        if f.stem < cutoff:
            continue
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def append_log(row: dict) -> None:
    d = log_dir()
    d.mkdir(parents=True, exist_ok=True)
    day = row["ts"][:10]
    with (d / f"{day}.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
