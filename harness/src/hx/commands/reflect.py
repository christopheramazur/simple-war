"""hx reflect: weekly reflection, proposals only (DESIGN.md §9).

  hx reflect --evidence     print this week's evidence pack (no model call)
  hx reflect                run now: propose, probe, file survivors as bd tasks (label reflection)
  hx reflect --dry-run      same, but file nothing
The worker runs it after sessions, at most once every 7 days.
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from hx.output import WARN, Check, Result

HELP = "Weekly reflection: evidence -> proposals -> bd tasks (nothing applied)"


def add_args(p) -> None:
    p.add_argument("--evidence", action="store_true", help="only print the evidence pack")
    p.add_argument("--dry-run", action="store_true", help="propose but file nothing")


def run(args) -> Result:
    from hx import ledger, reflection
    r = Result("reflect")
    con = ledger.read_only()
    try:
        if args.evidence:
            since = datetime.now(timezone.utc) - timedelta(days=reflection.INTERVAL_DAYS)
            r.raw = json.dumps(reflection.evidence(con, since), indent=1, default=str) if not args.json else None
            if args.json:
                r.data = reflection.evidence(con, since)
            return r
        out = reflection.run(con, force=True, file=not args.dry_run)
    finally:
        con.close()
    if out.get("error"):
        r.checks.append(Check("model", WARN, out["error"][:200]))
    r.tables["proposals"] = [{"issue": p.get("issue") or "-", "area": p.get("area"), "title": p["title"][:70],
                              "rejected": p["rejected"] or ""} for p in out.get("proposals", [])]
    return r
