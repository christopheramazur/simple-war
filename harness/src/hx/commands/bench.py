"""hx bench: the benchmark ladder (DESIGN.md §8).

  hx bench list                       tasks in the frozen suite
  hx bench run --target bonsai        run tasks, append results to data/raw/bench/
  hx bench report                     pass rates and routing verdicts
  hx bench build --force              regenerate the suite (only with a new SUITE_VERSION)
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter

from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Benchmark ladder: list | run | report | build"

AUTO, REVIEW = 0.9, 0.7  # routing thresholds (Q15)


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    for name in ("list", "run", "report", "build"):
        sp = sub.add_parser(name)
        # SUPPRESS: don't clobber the flags if given before the action (hx bench --json report).
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)
        if name in ("list", "run"):
            sp.add_argument("--level", help="comma list, e.g. L1,L2")
            sp.add_argument("--task", help="glob on task id, e.g. 'L1-*-s'")
        if name == "run":
            sp.add_argument("--target", required=True)
            sp.add_argument("--context", default="0", help="comma list of padded prompt sizes, e.g. 0,8k,32k")
            sp.add_argument("--repeat", type=int, default=1)
            sp.add_argument("--timeout", type=float, default=900, help="seconds per call")
        if name == "report":
            sp.add_argument("--run", help="only this run id")
            sp.add_argument("--target")
            sp.add_argument("--by", default="level,task_class,size,context_tokens",
                            help="grouping columns (default level,task_class,size,context_tokens)")
        if name == "build":
            sp.add_argument("--force", action="store_true")


def run(args) -> Result:
    return {"list": _list, "run": _run, "report": _report, "build": _build}[args.action](args)


def _levels(args):
    return [x.strip() for x in args.level.split(",")] if getattr(args, "level", None) else None


def _list(args) -> Result:
    from hx.bench import SUITE_VERSION, fixtures
    r = Result("bench list")
    tasks = fixtures.load_tasks(_levels(args), args.task)
    r.data["suite_version"] = SUITE_VERSION
    r.data["tasks"] = len(tasks)
    r.data["by_level"] = ", ".join(f"{k} {v}" for k, v in sorted(Counter(t["level"] for t in tasks).items()))
    r.tables["tasks"] = [{"id": t["id"], "class": t["task_class"], "size": t["size"],
                          "prompt_tokens_est": len(t["prompt"]) // 4, "check": t["check"]["type"]} for t in tasks]
    return r


def _run(args) -> Result:
    from hx.bench import adapters, fixtures, runner
    r = Result("bench run")
    targets = adapters.load_targets()
    target = targets.get(args.target)
    if target is None:
        r.checks.append(Check("target", FAIL, f"unknown target; known: {', '.join(targets)}"))
        return r
    problem = adapters.health(target)
    if problem:
        r.checks.append(Check("target reachable", FAIL, problem))
        return r
    tasks = fixtures.load_tasks(_levels(args), args.task)
    if not tasks:
        r.checks.append(Check("tasks", FAIL, "no tasks match"))
        return r
    contexts = [runner.parse_context(c) for c in args.context.split(",")]
    total = len(tasks) * len(contexts) * args.repeat

    def progress(row):  # stderr so --json output stays clean
        mark = "pass" if row["passed"] else "FAIL"
        print(f"[{mark}] {row['task_id']} ctx={row['context_tokens']} {row['latency_s']}s {row['detail'] or ''}"[:200],
              file=sys.stderr, flush=True)

    run_id, path = runner.run(args.target, target, tasks, contexts, args.repeat, args.timeout, progress)
    r.data.update({"run_id": run_id, "results": str(path), "calls": total})
    rep = _report_rows(run_id=run_id)
    r.tables["results"] = rep
    errors = sum(row["errors"] for row in rep)
    if errors:
        r.checks.append(Check("call errors", WARN, f"{errors} call(s) errored; see {path}"))
    return r


def _report_rows(run_id=None, target=None, by="level,task_class,size,context_tokens") -> list[dict]:
    import duckdb
    from hx.bench.runner import results_dir
    files = list(results_dir().glob("*.jsonl")) if results_dir().exists() else []
    if not files:
        return []
    cols = [c.strip() for c in by.split(",") if c.strip()]
    allowed = {"target", "model", "level", "task_class", "size", "context_tokens", "thinking", "run_id", "task_id"}
    bad = set(cols) - allowed
    if bad:
        raise ValueError(f"cannot group by {bad}; choose from {sorted(allowed)}")
    group = ", ".join(["target", *[c for c in cols if c != "target"]])
    where, params = ["suite_version = ?"], []
    from hx.bench import SUITE_VERSION
    params.append(SUITE_VERSION)
    if run_id:
        where.append("run_id = ?")
        params.append(run_id)
    if target:
        where.append("target = ?")
        params.append(target)
    pattern = (results_dir() / "*.jsonl").as_posix()
    con = duckdb.connect()
    cur = con.execute(f"""
        SELECT {group}, count(*) AS n, round(avg(passed::INT), 3) AS pass_rate, round(avg(score), 3) AS avg_score,
               sum((error IS NOT NULL)::INT) AS errors, round(median(latency_s), 1) AS p50_s,
               round(avg(output_tokens)) AS avg_out_tokens
        FROM read_json_auto('{pattern}', union_by_name = true, format = 'newline_delimited')
        WHERE {' AND '.join(where)} GROUP BY ALL ORDER BY ALL""", params)
    names = [d[0] for d in cur.description]
    rows = [dict(zip(names, row)) for row in cur.fetchall()]
    for row in rows:
        pr = row["pass_rate"] or 0
        row["route"] = "auto" if pr >= AUTO else "review" if pr >= REVIEW else "no"
    return rows


def _report(args) -> Result:
    r = Result("bench report")
    rows = _report_rows(args.run, args.target, args.by)
    if not rows:
        r.checks.append(Check("results", WARN, "no results yet; run hx bench run --target <name>"))
    r.tables["pass rates"] = rows
    r.data["routing"] = f"auto >= {AUTO:.0%}, review >= {REVIEW:.0%} (DESIGN.md §8)"
    return r


def _build(args) -> Result:
    from hx.bench import fixtures
    r = Result("bench build")
    try:
        written = fixtures.build(force=args.force)
    except FileExistsError as e:
        r.checks.append(Check("build", FAIL, str(e)))
        return r
    r.data["written"] = len(written)
    r.checks.append(Check("build", OK))
    return r
