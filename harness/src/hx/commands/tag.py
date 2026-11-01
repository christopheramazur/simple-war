"""hx tag: session tags (DESIGN.md §3).

  hx tag <session_id> [--force]     tag one session (plus the audit if it falls in the audit share)
  hx tag --untagged [--limit N]     backfill sessions without a tag
  hx tag --report                   tag counts and tagger-vs-audit agreement
"""

from __future__ import annotations

import sys
from collections import Counter

from hx.output import FAIL, WARN, Check, Result

HELP = "Session tagging: tag a session, backfill, or report tagger accuracy"


def add_args(p) -> None:
    p.add_argument("session_id", nargs="?")
    p.add_argument("--untagged", action="store_true", help="tag every session without a tag yet")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--force", action="store_true", help="tag again even if already tagged")
    p.add_argument("--report", action="store_true")


def run(args) -> Result:
    from hx import tagging
    r = Result("tag")
    if args.report:
        return _report(r)
    if args.session_id:
        ids = [args.session_id]
    elif args.untagged:
        from hx import ledger
        con = ledger.read_only()
        try:
            ids = tagging.untagged_sessions(con)[: args.limit]
        finally:
            con.close()
    else:
        r.checks.append(Check("args", FAIL, "give a session id, --untagged or --report"))
        return r
    rows = []
    for sid in ids:
        try:
            got = tagging.tag_session(sid, force=args.force)
        except Exception as e:
            r.checks.append(Check(sid[:12], WARN, f"{type(e).__name__}: {e}"[:200]))
            continue
        rows += got
        for g in got:
            print(f"[tag] {sid[:12]} {g['role']} {g.get('kind')}/{g.get('outcome')} "
                  f"c{g.get('complexity')} {g.get('problem') or ''}", file=sys.stderr, flush=True)
    r.data["sessions"] = len(ids)
    r.tables["tags"] = [{"session": x["session_id"][:12], "role": x["role"], "kind": x.get("kind"),
                         "area": x.get("area"), "cx": x.get("complexity"), "outcome": x.get("outcome"),
                         "conf": x.get("confidence"), "friction": x["friction"]["score"], "valid": x["valid"]}
                        for x in rows]
    bad = sum(not x["valid"] for x in rows)
    if bad:
        r.checks.append(Check("invalid tags", WARN, f"{bad} tag(s) failed validation; see `problem`"))
    return r


def _report(r: Result) -> Result:
    from hx import tagging
    rows = tagging.read_rows()
    tagger = [x for x in rows if x["role"] == "tagger"]
    valid = [x for x in tagger if x["valid"]]
    r.data["tagged_sessions"] = len({x["session_id"] for x in valid})
    r.data["invalid"] = len(tagger) - len(valid)
    r.data["accuracy"] = tagging.accuracy(rows)
    r.tables["by kind"] = [{"kind": k, "sessions": n,
                            "avg_friction": round(sum(x["friction"]["score"] for x in valid if x["kind"] == k) / n, 3)}
                           for k, n in Counter(x["kind"] for x in valid).most_common()]
    return r
