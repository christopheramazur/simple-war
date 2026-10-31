"""Result rendering shared by every verb.

Contract: a verb's run() returns a Result. The CLI renders it either as
compact text (default, token-cheap for agents) or as JSON (--json).
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

OK, WARN, FAIL = "ok", "warn", "fail"
_MARK = {OK: "ok", WARN: "WARN", FAIL: "FAIL"}


@dataclass
class Check:
    name: str
    status: str
    detail: str = ""


@dataclass
class Result:
    verb: str
    data: dict[str, Any] = field(default_factory=dict)
    checks: list[Check] = field(default_factory=list)
    tables: dict[str, list[dict]] = field(default_factory=dict)

    @property
    def exit_code(self) -> int:
        return 1 if any(c.status == FAIL for c in self.checks) else 0

    def to_json(self) -> str:
        return json.dumps(
            {
                "verb": self.verb,
                "ok": self.exit_code == 0,
                "data": self.data,
                "checks": [c.__dict__ for c in self.checks],
                **({"tables": self.tables} if self.tables else {}),
            },
            indent=None,
            default=str,
        )

    def to_text(self, verbose: bool = False) -> str:
        lines = [f"{k}: {_fmt(v)}" for k, v in self.data.items()]
        for name, rows in self.tables.items():
            lines.append(f"\n{name}:")
            lines.extend(table(rows) or ["  (none)"])
        for c in self.checks:
            # Compact mode hides passing checks; agents only need problems.
            if c.status == OK and not verbose:
                continue
            lines.append(f"[{_MARK[c.status]}] {c.name}" + (f": {c.detail}" if c.detail else ""))
        passed = sum(c.status == OK for c in self.checks)
        if self.checks and not verbose:
            lines.append(f"checks: {passed}/{len(self.checks)} ok")
        return "\n".join(lines)


def table(rows: list[dict]) -> list[str]:
    """Aligned plain-text table, two-space indent. Numbers right-aligned."""
    if not rows:
        return []
    cols = list(rows[0])
    cells = [[_fmt(r.get(c)) for c in cols] for r in rows]
    width = [max(len(c), *(len(row[i]) for row in cells)) for i, c in enumerate(cols)]
    numeric = [all(isinstance(r.get(c), (int, float)) or r.get(c) is None for r in rows) for c in cols]

    def line(vals):
        return "  " + "  ".join(v.rjust(w) if n else v.ljust(w)
                                for v, w, n in zip(vals, width, numeric)).rstrip()
    return [line(cols), *map(line, cells)]


def _fmt(v: Any) -> str:
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, float):
        return f"{v:,.4f}".rstrip("0").rstrip(".") if v else "0"
    if isinstance(v, int):
        return f"{v:,}"
    if isinstance(v, (list, tuple)):
        return ", ".join(map(str, v)) if v else "-"
    if v is None:
        return "-"
    return str(v)
