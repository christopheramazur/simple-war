"""hx ab: compare the arms of a per-session A/B experiment (DESIGN.md §6).

  hx ab rtk     Bash output tokens and error rate with rtk on vs off

Keep rule (Q27): the 'on' arm saves >= 20% of Bash output tokens per call without a higher error
rate (more retries). Needs MIN_SESSIONS sessions per arm (forced sessions excluded) before a verdict.
"""

from __future__ import annotations

from hx.output import OK, WARN, Check, Result

HELP = "A/B experiments: compare arms (rtk: Bash output tokens and errors, on vs off)"
MIN_SESSIONS = 10
SAVING = 0.20
ERROR_TOLERANCE = 0.02  # absolute error-rate increase still counted as "no more retries"


def add_args(p) -> None:
    p.add_argument("experiment", choices=["rtk"])


def arms(con, experiment: str) -> dict[int, dict]:
    rows = con.execute("""
        SELECT e.value::INT AS arm, count(DISTINCT e.session_id) AS sessions, count(u.tool_use_id) AS bash_calls,
               coalesce(sum(r.result_chars), 0) / 4 AS output_tokens,
               count(*) FILTER (WHERE r.is_error) AS errors
        FROM event e
        LEFT JOIN tool_use u ON u.session_id = e.session_id AND u.tool = 'Bash'
        LEFT JOIN tool_result r USING (tool_use_id)
        WHERE e.kind = ? AND e.detail IS DISTINCT FROM 'forced'
        GROUP BY 1""", [f"ab_{experiment}"]).fetchall()
    out = {}
    for arm, sessions, calls, tokens, errors in rows:
        out[arm] = {"sessions": sessions, "bash_calls": calls,
                    "tokens_per_call": round(tokens / calls, 1) if calls else None,
                    "error_rate": round(errors / calls, 3) if calls else None}
    return out


def verdict(a: dict[int, dict]) -> tuple[str, str]:
    on, off = a.get(1), a.get(0)
    if not on or not off or min(on["sessions"], off["sessions"]) < MIN_SESSIONS or not on["bash_calls"] or not off["bash_calls"]:
        have = f"on {on['sessions'] if on else 0}, off {off['sessions'] if off else 0}"
        return "collecting", f"need {MIN_SESSIONS} sessions per arm ({have})"
    saving = 1 - on["tokens_per_call"] / off["tokens_per_call"] if off["tokens_per_call"] else 0.0
    more_errors = on["error_rate"] - off["error_rate"] > ERROR_TOLERANCE
    detail = f"saves {saving:.0%} of Bash output tokens per call; error rate {on['error_rate']:.1%} vs {off['error_rate']:.1%}"
    return ("keep" if saving >= SAVING and not more_errors else "drop"), detail


def run(args) -> Result:
    from hx import ledger
    r = Result(f"ab {args.experiment}")
    con = ledger.read_only()
    try:
        a = arms(con, args.experiment)
    finally:
        con.close()
    r.tables["arms"] = [{"arm": "on" if k else "off", **v} for k, v in sorted(a.items(), reverse=True)]
    v, detail = verdict(a)
    r.data["verdict"] = v
    r.checks.append(Check("experiment", OK if v != "collecting" else WARN, detail))
    return r
