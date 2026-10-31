"""hx report: spend, tokens, tools, friction and time from the ledger."""

from __future__ import annotations

import webbrowser
from collections import defaultdict
from datetime import datetime

import duckdb

from hx import ledger, report
from hx.output import WARN, Check, Result

HELP = "Spend, tokens, tools, friction and time from the ledger (run hx ingest first)"


def add_args(p) -> None:
    p.add_argument("--since", default="7d", help="7d, 24h, all, or a local date like 2026-10-01 (default 7d)")
    p.add_argument("--top", type=int, default=5, help="rows per table in text output (default 5)")
    p.add_argument("--html", action="store_true", help="also write the static HTML dashboard")
    p.add_argument("--open", action="store_true", help="open the HTML dashboard in a browser (implies --html)")


def run(args) -> Result:
    r = Result("report")
    db = ledger.path()
    if not db.exists():
        r.checks.append(Check("ledger", WARN, "no ledger yet; run hx ingest"))
        return r
    since = report.parse_since(args.since)
    con = duckdb.connect(str(db), read_only=True)
    try:
        d = report.build(con, since)
    finally:
        con.close()

    t, f, tm = d["totals"], d["friction"], d["time"]
    r.data.update({
        "since": args.since,
        "est_usd": t["est_usd"],
        "calls": f"{t['calls']:,} in {t['sessions']} session(s)",
        "tokens": f"out {t['output_tokens']:,} / cache read {t['cache_read_tokens']:,} / "
                  f"cache write {t['cache_write_tokens']:,} / uncached in {t['input_tokens']:,}",
        "cache_hit": t["cache_hit"],
        "closed_tasks": f"{t['tasks_closed']} at ${t['usd_per_closed_task']}/task" if t["tasks_closed"] else 0,
        "friction": ", ".join(f"{k} {v}" for k, v in f.items()),
        "time": f"agent {tm['agent_work_h']}h / waiting on you {tm['human_wait_h']}h / away {tm['away_h']}h",
        "quota": "; ".join(
            f"{q['provider']} {q['window']} {q['used_pct']}% (resets {q['resets']}"
            + (f", ⚠ full ~{q['projected_full']}" if q["hits_limit_before_reset"] else "") + ")"
            for q in d["quota"]) or "no snapshots yet (status line records them)",
    })
    n = args.top
    r.tables = {
        "by day": _days(d["by_day"])[-n:],
        "by model": d["by_model"][:n],
        "by task": d["by_task"][:n],
        "tools by output": [{k: v for k, v in row.items() if k != "denied"} for row in d["tools"][:n]],
        "top commands": d["commands"][:n],
    }
    if args.html or args.open:
        from hx import report_html
        out = report_html.write(d, args.since, datetime.now().astimezone())
        r.data["html"] = str(out)
        if args.open:
            webbrowser.open(out.as_uri())
    if args.json:  # machine readers get everything, untrimmed
        r.tables = {k: v for k, v in d.items() if isinstance(v, list) and k != "pending"}
        r.data.update({"totals": t, "friction_counts": f, "time_detail": tm, "pending": d["pending"]})
    return r


def _days(rows: list[dict]) -> list[dict]:
    """Collapse per-model day rows to one row per day."""
    agg: dict = defaultdict(lambda: {"calls": 0, "output_tokens": 0, "est_usd": 0.0})
    for row in rows:
        a = agg[row["day"]]
        a["calls"] += row["calls"]
        a["output_tokens"] += row["output_tokens"] or 0
        a["est_usd"] += row["est_usd"] or 0
    return [{"day": str(day), **{k: (round(v, 4) if isinstance(v, float) else v) for k, v in a.items()}}
            for day, a in sorted(agg.items())]
