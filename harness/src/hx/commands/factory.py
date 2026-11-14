"""hx factory: the AI factory's evolution loop (GDD 05 §5.4), results in DuckDB.

  hx factory run [--generations N] [--seed S] [--scenario MAP] [--pairings P]
                 [--seeds K] [--population N] [--jobs J] [--set KEY=VALUE]...
      start a factory run: a population of controller-profile genomes plays
      age-weighted pairings on both sides (one harness batch per generation),
      is scored under the default fitness spec, and evolves (hx.factory).
      Every generation is saved before the next one starts.
  hx factory report [--run ID]    per-generation stats, the MAP-Elites archive,
      the hall of fame and the scoring-gain rate (default: the latest run)
  hx factory list    factory runs

Intensity levels, a clean stop and resume come with sw-884.10.
"""

from __future__ import annotations

import argparse
import json
import subprocess

from hx import factory, fitness, paths, sim
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "AI factory: evolve controller profiles by co-evolution (run | report | list)"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    sp = sub.add_parser("run")
    sp.add_argument("--generations", type=int, default=1)
    sp.add_argument("--seed", type=int, default=1, help="run seed: the whole run is reproducible from it")
    sp.add_argument("--scenario", default=factory.DEFAULTS["scenario"])
    sp.add_argument("--pairings", type=int, default=factory.DEFAULTS["pairings"])
    sp.add_argument("--seeds", type=int, default=factory.DEFAULTS["seeds"], help="match seeds per pairing side")
    sp.add_argument("--population", type=int, default=factory.DEFAULTS["population"])
    sp.add_argument("--jobs", type=int, default=factory.DEFAULTS["jobs"], help="parallel Godot processes")
    sp.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                    help="any other factory setting (hx.factory.DEFAULTS), JSON value")
    sp = sub.add_parser("report")
    sp.add_argument("--run", help="factory run ID (default: the latest)")
    sub.add_parser("list")
    for sp in sub.choices.values():
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    return {"run": _run, "report": _report, "list": _list}[args.action](args)


def _config(args) -> dict:
    cfg = {"scenario": args.scenario, "pairings": args.pairings, "seeds": args.seeds,
           "population": args.population, "jobs": args.jobs}
    for kv in args.set:
        k, _, v = kv.partition("=")
        if k not in factory.DEFAULTS:
            raise ValueError(f"unknown factory setting '{k}'")
        cfg[k] = json.loads(v)
    return cfg


def _run(args) -> Result:
    r = Result("factory run")
    from hx import godot
    root = paths.repo_root()
    exe = godot.binaries(root).get("console")
    if not exe:
        r.checks.append(Check("godot", FAIL, "no Godot console binary at the repo root"))
        return r
    try:
        cfg = _config(args)
        spec = fitness.load_spec(root, cfg.get("spec", factory.DEFAULTS["spec"]))
        library = fitness.load_criteria(root)
    except (ValueError, FileNotFoundError, json.JSONDecodeError) as e:
        r.checks.append(Check("config", FAIL, str(e)))
        return r
    con = factory.connect()
    state = factory.new_state(factory.new_run_id(), args.seed, cfg, spec.get("shaping", {}))
    factory.create(con, state)
    rows = []
    for _ in range(args.generations):
        stats = factory.play_generation(con, state, exe, root, spec, library, _git_rev(root))
        rows.append(stats)
    r.data["run"] = state.run
    r.data["generations"] = state.generation
    r.data["results"] = str(sim.db_path())
    r.tables["generations"] = rows
    failed = sum(s["failed"] for s in rows)
    total = sum(s["runs"] for s in rows)
    con.close()
    r.checks.append(Check("runs", FAIL if total and failed == total else (WARN if failed else OK),
                          f"{total - failed}/{total} ok"))
    return r


def _latest(con) -> str | None:
    row = con.execute("SELECT run FROM factory_run ORDER BY started_at DESC LIMIT 1").fetchone()
    return row[0] if row else None


def _report(args) -> Result:
    r = Result("factory report")
    con = factory.connect()
    run_id = args.run or _latest(con)
    if run_id is None:
        r.checks.append(Check("runs", WARN, "no factory runs yet"))
        return r
    r.data["run"] = run_id
    r.data.update(factory.gain_rate(con, run_id))
    r.tables["generations"] = factory.table(con, run_id)
    r.tables["archive"] = factory.elites(con, run_id)
    r.tables["hall_of_fame"] = [{"profile": pid, "born": b, "retired": ret, "parents": ps}
                                for pid, b, ret, ps in con.execute(
                                    "SELECT profile_id, born, retired, parents FROM factory_profile "
                                    "WHERE run = ? AND hof = 1 ORDER BY profile_id", [run_id]).fetchall()]
    con.close()
    return r


def _list(args) -> Result:
    r = Result("factory list")
    con = factory.connect()
    r.tables["runs"] = [{"run": run_id, "seed": s, "generations": g}
                        for run_id, s, g in con.execute(
                            "SELECT run, seed, generations FROM factory_run ORDER BY started_at DESC LIMIT 20").fetchall()]
    con.close()
    return r


def _git_rev(root) -> str:
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=root, capture_output=True,
                              text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
