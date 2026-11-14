"""hx factory: the AI factory's evolution loop (GDD 05 §5.4), results in DuckDB.

  hx factory run [--generations N] [--intensity background|normal|max] [--seed S]
                 [--scenario MAP] [--pairings P] [--seeds K] [--population N]
                 [--jobs J] [--set KEY=VALUE]...
      start a factory run: a population of controller-profile genomes plays
      age-weighted pairings on both sides (one harness batch per generation),
      is scored under the default fitness spec, and evolves (hx.factory).
      Intensity (A2Q9): background = 1-2 Godot processes at below-normal
      priority; normal = half the cores; max = about 90% of them (--jobs
      overrides).
  hx factory stop [--run ID]
      ask a running factory to stop (Ctrl+C in its terminal does the same):
      matches already running finish and are saved, no new one starts, and
      the run exits. A second Ctrl+C aborts at once.
  hx factory resume [--run ID] [--generations N] [--intensity ...] [--jobs J]
      continue a stopped run: the interrupted generation plays only its
      missing matches, then the run goes on to its target (or N more).
      Resuming gives the same results as never stopping (A2Q10).
  hx factory report [--run ID]    per-generation stats, the MAP-Elites archive,
      the hall of fame and the scoring-gain rate (default: the latest run)
  hx factory list    factory runs

The database is open only between matches, so report and list work while a
run is playing.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

from hx import factory, fitness, paths, sim
from hx.output import FAIL, OK, WARN, Check, Result

HELP = "AI factory: evolve controller profiles by co-evolution (run | stop | resume | report | list)"


def add_args(p) -> None:
    sub = p.add_subparsers(dest="action", required=True, metavar="<action>")
    sp = sub.add_parser("run")
    sp.add_argument("--generations", type=int, default=1)
    sp.add_argument("--intensity", choices=factory.INTENSITIES, default="normal")
    sp.add_argument("--seed", type=int, default=1, help="run seed: the whole run is reproducible from it")
    sp.add_argument("--scenario", default=factory.DEFAULTS["scenario"])
    sp.add_argument("--pairings", type=int, default=factory.DEFAULTS["pairings"])
    sp.add_argument("--seeds", type=int, default=factory.DEFAULTS["seeds"], help="match seeds per pairing side")
    sp.add_argument("--population", type=int, default=factory.DEFAULTS["population"])
    sp.add_argument("--jobs", type=int, help="parallel Godot processes (default: by intensity)")
    sp.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                    help="any other factory setting (hx.factory.DEFAULTS), JSON value")
    sp = sub.add_parser("stop")
    sp.add_argument("--run", help="factory run ID (default: every running one)")
    sp = sub.add_parser("resume")
    sp.add_argument("--run", help="factory run ID (default: the latest)")
    sp.add_argument("--generations", type=int, help="play N more generations (default: up to the run's target)")
    sp.add_argument("--intensity", choices=factory.INTENSITIES)
    sp.add_argument("--jobs", type=int)
    sp = sub.add_parser("report")
    sp.add_argument("--run", help="factory run ID (default: the latest)")
    sub.add_parser("list")
    for sp in sub.choices.values():
        sp.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
        sp.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS)


def run(args) -> Result:
    return {"run": _run, "stop": _stop, "resume": _resume, "report": _report, "list": _list}[args.action](args)


def _config(args) -> dict:
    cfg = {"scenario": args.scenario, "pairings": args.pairings, "seeds": args.seeds,
           "population": args.population, "intensity": args.intensity, "target": args.generations,
           "jobs": args.jobs or factory.intensity_jobs(args.intensity, os.cpu_count())}
    for kv in args.set:
        k, _, v = kv.partition("=")
        if k not in factory.DEFAULTS:
            raise ValueError(f"unknown factory setting '{k}'")
        cfg[k] = json.loads(v)
    return cfg


def _run(args) -> Result:
    r = Result("factory run")
    try:
        cfg = _config(args)
    except (ValueError, json.JSONDecodeError) as e:
        r.checks.append(Check("config", FAIL, str(e)))
        return r
    root = paths.repo_root()
    try:
        spec = fitness.load_spec(root, cfg.get("spec", factory.DEFAULTS["spec"]))
    except (FileNotFoundError, json.JSONDecodeError) as e:
        r.checks.append(Check("config", FAIL, str(e)))
        return r
    state = factory.new_state(factory.new_run_id(), args.seed, cfg, spec.get("shaping", {}))
    con = factory.connect()
    factory.create(con, state)
    con.close()
    return _play(r, state)


def _resume(args) -> Result:
    r = Result("factory resume")
    con = factory.connect()
    try:
        run_id = args.run or _latest(con)
        if run_id is None:
            r.checks.append(Check("runs", WARN, "no factory runs yet"))
            return r
        state = factory.load(con, run_id)
        if args.generations:
            state.config["target"] = state.generation + args.generations
        if args.intensity:
            state.config["intensity"] = args.intensity
            state.config["jobs"] = factory.intensity_jobs(args.intensity, os.cpu_count())
        if args.jobs:
            state.config["jobs"] = args.jobs
        factory.save_config(con, state)
    finally:
        con.close()
    return _play(r, state)


def _markers() -> Path:
    d = paths.data_dir() / "sim" / "factory"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _play(r: Result, state: factory.State) -> Result:
    """Plays generations up to the run's target, stopping cleanly on Ctrl+C
    or `hx factory stop` (a stop file next to a running marker)."""
    from hx import godot
    root = paths.repo_root()
    exe = godot.binaries(root).get("console")
    if not exe:
        r.checks.append(Check("godot", FAIL, "no Godot console binary at the repo root"))
        return r
    spec = fitness.load_spec(root, state.config.get("spec", factory.DEFAULTS["spec"]))
    library = fitness.load_criteria(root)
    marker = _markers() / f"{state.run}.running"
    stop_file = _markers() / f"{state.run}.stop"
    stop_file.unlink(missing_ok=True)
    marker.write_text(str(os.getpid()), encoding="utf-8")
    asked = {"stop": False}

    def on_sigint(_sig, _frame) -> None:
        if asked["stop"]:
            raise KeyboardInterrupt
        asked["stop"] = True
        print("factory: stopping after the running matches (Ctrl+C again to abort)", file=sys.stderr, flush=True)

    def stop() -> bool:
        if stop_file.exists():
            asked["stop"] = True
        return asked["stop"]

    old = signal.signal(signal.SIGINT, on_sigint)
    rows = []
    try:
        while state.generation < state.config.get("target", 1) and not stop():
            stats = factory.play_generation(None, state, exe, root, spec, library, _git_rev(root), stop)
            if stats is None:
                break
            rows.append(stats)
    finally:
        signal.signal(signal.SIGINT, old)
        marker.unlink(missing_ok=True)
        stop_file.unlink(missing_ok=True)
    done = state.generation >= state.config.get("target", 1)
    r.data["run"] = state.run
    r.data["generations"] = f"{state.generation}/{state.config.get('target', 1)}"
    r.data["intensity"] = f"{state.config.get('intensity', 'normal')} ({state.config['jobs']} jobs)"
    r.data["results"] = str(sim.db_path())
    if not done:
        r.data["stopped"] = f"finished matches are saved; continue with: hx factory resume --run {state.run}"
    r.tables["generations"] = rows
    failed = sum(s["failed"] for s in rows)
    total = sum(s["runs"] for s in rows)
    r.checks.append(Check("runs", FAIL if total and failed == total else (WARN if failed or not done else OK),
                          f"{total - failed}/{total} ok" + ("" if done else ", stopped")))
    return r


def _stop(args) -> Result:
    r = Result("factory stop")
    runs = [args.run] if args.run else [m.stem for m in _markers().glob("*.running")]
    if not runs:
        r.checks.append(Check("runs", WARN, "no factory run is running"))
        return r
    for run_id in runs:
        (_markers() / f"{run_id}.stop").write_text("stop", encoding="utf-8")
    r.data["stopping"] = ", ".join(runs)
    r.checks.append(Check("stop", OK, "running matches finish, then the run exits"))
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
