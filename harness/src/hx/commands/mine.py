"""hx mine: repeated command shapes -> hx verb candidates (DESIGN.md §5).

  hx mine                 list candidates (nothing filed)
  hx mine --file          file new candidates as bd tasks (max 3 per run; the worker does this after sessions)
  hx mine --report        hx verb usage, and mined shapes with their baseline cost
"""

from __future__ import annotations

from hx.output import Result

HELP = "Mine repeated shell commands into hx verb candidates; --report shows verb usage"


def add_args(p) -> None:
    p.add_argument("--file", action="store_true", help="file new candidates as bd tasks")
    p.add_argument("--report", action="store_true")


def run(args) -> Result:
    import duckdb

    from hx import ledger, mining
    r = Result("mine")
    con = duckdb.connect(str(ledger.path()), read_only=True)
    try:
        if args.report:
            r.tables["hx verb usage"] = mining.verb_usage(con)
            r.tables["mined shapes"] = [{"shape": s[:50], "issue": v["issue"], "verb": v["verb"][:30],
                                         "baseline_tokens_per_use": v["baseline_tokens_per_use"]}
                                        for s, v in mining.load_state()["filed"].items()]
            return r
        if args.file:
            out = mining.run(con, file=True, force=True)
            r.data.update({k: v for k, v in out.items() if k != "filed"})
            r.tables["filed"] = [{"issue": f["issue"], "shape": f["shape"][:50], "verb": f["verb"][:40],
                                  "uses": f["uses"], "sessions": f["sessions"]} for f in out["filed"]]
            return r
        filed = mining.load_state()["filed"]
        r.tables["candidates"] = [{"shape": c["shape"][:60], "uses": c["uses"], "sessions": c["sessions"],
                                   "tokens_per_use": c["tokens_per_use"], "filed": filed.get(c["shape"], {}).get("issue", "")}
                                  for c in mining.candidates(con)]
    finally:
        con.close()
    return r
