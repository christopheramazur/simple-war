"""hx sim: game harness runs (GDD 05 §5.1-5.2), results in DuckDB.

  hx sim run <scenario>... [--variant NAME]... [--seeds 4|3-6|1,5] [--jobs 4]
      play scenario x variant x seed headless (one Godot process per run, in
      parallel); store runs and metrics in data/sim.duckdb; print the summary
  hx sim report [--batch ID] [--metric PATTERN]
      a batch's summary, or one metric (SQL LIKE, e.g. 'band.morale.%')
  hx sim list    recent batches
  hx sim variants    the variants in data/sim/variants (plus baseline)

Scenarios are battle scenario IDs or overworld map IDs from the core package.
Replays: <data>/sim/runs/<batch>/<run_id>.sav (battles open in the replay
viewer with --replay=<path> [--variant=<variant file>]).
"""

from __future__ import annotations

import argparse
import subprocess
from datetime import datetime, timezone

from hx import paths, sim
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "Game harness runs: run scenario x variant x seed headless (DuckDB results) | report | list | variants"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    sp = sub.add_parser("run")
    sp.add_argument("scenarios", nargs="+", help="battle scenario or overworld map IDs")
    sp.add_argument("--variant", action="append", help="variant name (data/sim/variants/<name>.json) or 'baseline'; repeatable")
    sp.add_argument("--seeds", default="3", help="N (1..N), A-B, or a,b,c (default 3)")
    sp.add_argument("--jobs", type=int, default=4, help="parallel Godot processes (default 4)")
    sp.add_argument("--timeout", type=float, default=600, help="seconds per run")
    sp = sub.add_parser("report")
    sp.add_argument("--batch", help="batch ID (default: the latest)")
    sp.add_argument("--metric", help="one metric across the batch (SQL LIKE pattern)")
    sp = sub.add_parser("list")
    sp.add_argument("--limit", type=int, default=10)
    sub.add_parser("variants")
    for sp in sub.choices.values():
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    return {"run": _run, "report": _report, "list": _list, "variants": _variants}[args.action](args)


def _run(args) -> Result:
    r = Result("sim run")
    from hx import godot
    root = paths.repo_root()
    exe = godot.binaries(root).get("console")
    if not exe:
        r.checks.append(Check("godot", FAIL, "no Godot console binary at the repo root"))
        return r
    names = args.variant or [sim.BASELINE]
    try:
        files = {v: sim.variant_file(root, v) for v in names}
        seeds = sim.parse_seeds(args.seeds)
    except (FileNotFoundError, ValueError) as e:
        r.checks.append(Check("matrix", FAIL, str(e)))
        return r
    batch_id = sim.new_batch_id()
    jobs = sim.matrix(batch_id, args.scenarios, files, seeds)
    started = datetime.now(timezone.utc)
    reports, wall = sim.launch(exe, root, jobs, args.jobs, args.timeout)
    con = sim.connect()
    sim.ingest(con, {"batch_id": batch_id, "started_at": started, "scenarios": args.scenarios, "variants": names,
                     "seeds": args.seeds, "jobs": args.jobs, "wall_s": wall, "git_rev": _git_rev(root)}, reports)
    r.data["batch"] = batch_id
    r.data["runs"] = len(jobs)
    r.data["wall_s"] = round(wall, 1)
    r.data["results"] = str(sim.db_path())
    r.tables["summary"] = sim.summary(con, batch_id)
    errors = [f"{rep['run']['run_id']}: {rep['run'].get('error')}" for rep in reports if rep["run"].get("status") != "ok"]
    con.close()
    if errors:
        r.data["errors"] = "\n  " + "\n  ".join(errors[:10])
    r.checks.append(Check("runs", FAIL if len(errors) == len(jobs) else (WARN if errors else OK),
                          f"{len(jobs) - len(errors)}/{len(jobs)} ok"))
    return r


def _report(args) -> Result:
    r = Result("sim report")
    con = sim.connect()
    batch = args.batch or sim.latest_batch(con)
    if batch is None:
        r.checks.append(Check("batches", WARN, "no runs yet: hx sim run <scenario>"))
        return r
    r.data["batch"] = batch
    if args.metric:
        r.tables[args.metric] = sim.metric_table(con, batch, args.metric)
    else:
        r.tables["summary"] = sim.summary(con, batch)
    con.close()
    return r


def _list(args) -> Result:
    r = Result("sim list")
    con = sim.connect()
    r.tables["batches"] = sim.batches(con, args.limit)
    con.close()
    return r


def _variants(args) -> Result:
    r = Result("sim variants")
    r.data["variants"] = sim.variants(paths.repo_root())
    return r


def _git_rev(root) -> str:
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=root, capture_output=True,
                              text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
