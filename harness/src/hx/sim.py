"""Game harness runs (GDD 05 §5.1-5.2): scenario x variant x seed matrices played
headless by Godot (res://src/api/sim_runner.gd), one process per run, results in
DuckDB (`data/sim.duckdb`, separate from the ledger: DuckDB locks its file).

Each run writes <runs>/<batch>/<run_id>.json ({"run": {...}, "metrics": [...]})
and a replay <run_id>.sav. This module expands matrices, launches runs in
parallel, ingests their JSON and summarises batches; commands/sim.py is the CLI.
"""

from __future__ import annotations

import itertools
import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import duckdb

from hx import paths

RUNNER = "res://src/api/sim_runner.gd"
VARIANT_DIR = "data/sim/variants"
BASELINE = "baseline"

SCHEMA = """
CREATE TABLE IF NOT EXISTS sim_batch (
    batch_id TEXT PRIMARY KEY, started_at TIMESTAMPTZ, scenarios TEXT, variants TEXT,
    seeds TEXT, jobs INTEGER, wall_s DOUBLE, git_rev TEXT);
CREATE TABLE IF NOT EXISTS sim_run (
    run_id TEXT PRIMARY KEY, batch_id TEXT, scenario TEXT, variant TEXT, seed INTEGER,
    kind TEXT, status TEXT, error TEXT, turns INTEGER, winner INTEGER, reason TEXT,
    outcome TEXT, wall_ms INTEGER, state_hash TEXT, replay TEXT, variant_file TEXT);
CREATE TABLE IF NOT EXISTS sim_metric (
    run_id TEXT, metric TEXT, player INTEGER, value DOUBLE);
"""


@dataclass(frozen=True)
class Job:
    batch_id: str
    scenario: str
    variant: str
    variant_file: str  # repo-relative, "" for the baseline
    seed: int

    @property
    def run_id(self) -> str:
        return f"{self.batch_id}-{self.scenario}-{self.variant}-s{self.seed}"


def db_path() -> Path:
    return paths.data_dir() / "sim.duckdb"


def runs_dir() -> Path:
    return paths.data_dir() / "sim" / "runs"


def connect(path: Path | None = None) -> duckdb.DuckDBPyConnection:
    path = path or db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(path))
    con.execute(SCHEMA)
    return con


def variant_file(root: Path, name: str) -> str:
    """Repo-relative path of a named variant ("" for the baseline); raises if missing."""
    if name == BASELINE:
        return ""
    rel = f"{VARIANT_DIR}/{name}.json"
    if not (root / rel).is_file():
        raise FileNotFoundError(f"no variant '{name}' ({rel})")
    return rel


def variants(root: Path) -> list[str]:
    d = root / VARIANT_DIR
    return [BASELINE] + sorted(p.stem for p in d.glob("*.json")) if d.is_dir() else [BASELINE]


def parse_seeds(spec: str) -> list[int]:
    """'4' -> 1..4; '3-6' -> 3..6; '1,5,9' -> those."""
    spec = spec.strip()
    if "," in spec:
        return [int(x) for x in spec.split(",") if x.strip()]
    if "-" in spec:
        a, b = spec.split("-", 1)
        return list(range(int(a), int(b) + 1))
    return list(range(1, int(spec) + 1))


def matrix(batch_id: str, scenarios: list[str], variant_files: dict[str, str], seeds: list[int]) -> list[Job]:
    return [Job(batch_id, s, v, variant_files[v], seed)
            for s, v, seed in itertools.product(scenarios, variant_files, seeds)]


def new_batch_id() -> str:
    return datetime.now(timezone.utc).strftime("b%Y%m%d-%H%M%S")


def command(exe: Path, root: Path, job: Job, out_dir: Path) -> list[str]:
    cmd = [str(exe), "--headless", "--path", str(root), "-s", RUNNER, "--",
           "--scenario", job.scenario, "--seed", str(job.seed), "--out", str(out_dir), "--run-id", job.run_id]
    if job.variant_file:
        cmd += ["--variant", str(root / job.variant_file)]
    return cmd


def launch(exe: Path, root: Path, jobs: list[Job], parallel: int, timeout: float) -> tuple[list[dict], float]:
    """Runs every job (parallel Godot processes); returns the run reports and wall seconds."""
    if not jobs:
        return [], 0.0
    out_dir = runs_dir() / jobs[0].batch_id
    out_dir.mkdir(parents=True, exist_ok=True)

    def one(job: Job) -> dict:
        try:
            subprocess.run(command(exe, root, job, out_dir), capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        except subprocess.TimeoutExpired:
            return failed(job, f"timed out after {timeout:g} s")
        return read_report(out_dir, job)

    t0 = time.monotonic()
    with ThreadPoolExecutor(max_workers=max(1, parallel)) as pool:
        reports = list(pool.map(one, jobs))
    return reports, time.monotonic() - t0


def failed(job: Job, error: str) -> dict:
    return {"run": {"run_id": job.run_id, "scenario": job.scenario, "variant": job.variant, "seed": job.seed,
                    "status": "error", "error": error}, "metrics": [], "_job": job}


def read_report(out_dir: Path, job: Job) -> dict:
    f = out_dir / f"{job.run_id}.json"
    if not f.is_file():
        return failed(job, "the runner wrote no report")
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return failed(job, f"unreadable report: {e}")
    data["_job"] = job
    replay = out_dir / f"{job.run_id}.sav"
    data["run"]["replay"] = str(replay) if replay.is_file() else ""
    return data


def ingest(con: duckdb.DuckDBPyConnection, batch: dict, reports: list[dict]) -> None:
    con.execute("INSERT OR REPLACE INTO sim_batch VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [batch["batch_id"], batch["started_at"], ",".join(batch["scenarios"]), ",".join(batch["variants"]),
                 batch["seeds"], batch["jobs"], batch["wall_s"], batch.get("git_rev", "")])
    for rep in reports:
        r, job = rep["run"], rep["_job"]
        con.execute("DELETE FROM sim_metric WHERE run_id = ?", [job.run_id])
        con.execute("INSERT OR REPLACE INTO sim_run VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
            job.run_id, job.batch_id, job.scenario, job.variant, job.seed, r.get("kind"), r.get("status"),
            r.get("error") or None, r.get("turns"), r.get("winner"), r.get("reason"), r.get("outcome") or None,
            r.get("wall_ms"), r.get("state_hash"), r.get("replay") or None, job.variant_file or None])
        rows = [(job.run_id, m["metric"], int(m["player"]), float(m["value"])) for m in rep.get("metrics", [])]
        if rows:
            con.executemany("INSERT INTO sim_metric VALUES (?, ?, ?, ?)", rows)


def summary(con: duckdb.DuckDBPyConnection, batch_id: str) -> list[dict]:
    """Per scenario x variant: runs, failures, mean turns, outcomes and mean key metrics."""
    rows = con.execute("""
        SELECT r.scenario, r.variant, count(*) AS runs,
               count(*) FILTER (WHERE r.status <> 'ok') AS failed,
               round(avg(r.turns), 1) AS turns,
               round(avg(CASE WHEN r.winner = 1 OR r.outcome = 'won' THEN 1.0 ELSE 0.0 END), 2) AS p1_win,
               round(avg(m.vp1), 1) AS p1_vp, round(avg(m.vp2), 1) AS p2_vp,
               round(avg(m.lost1), 0) AS p1_value_lost, round(avg(m.lost2), 0) AS p2_value_lost,
               round(avg(r.wall_ms) / 1000.0, 2) AS wall_s
        FROM sim_run r
        LEFT JOIN (
            SELECT run_id,
                   max(value) FILTER (WHERE metric = 'vp' AND player = 1) AS vp1,
                   max(value) FILTER (WHERE metric = 'vp' AND player = 2) AS vp2,
                   max(value) FILTER (WHERE metric = 'value_lost' AND player = 1) AS lost1,
                   max(value) FILTER (WHERE metric = 'value_lost' AND player = 2) AS lost2
            FROM sim_metric GROUP BY run_id) m USING (run_id)
        WHERE r.batch_id = ?
        GROUP BY 1, 2 ORDER BY 1, 2""", [batch_id]).fetchall()
    cols = ["scenario", "variant", "runs", "failed", "turns", "p1_win", "p1_vp", "p2_vp",
            "p1_value_lost", "p2_value_lost", "wall_s"]
    return [dict(zip(cols, r)) for r in rows]


def metric_table(con: duckdb.DuckDBPyConnection, batch_id: str, metric: str) -> list[dict]:
    """One metric (SQL LIKE pattern) across a batch: mean, min, max per scenario x variant x player."""
    rows = con.execute("""
        SELECT r.scenario, r.variant, m.metric, m.player, count(*) AS runs,
               round(avg(m.value), 2) AS mean, min(m.value) AS min, max(m.value) AS max
        FROM sim_metric m JOIN sim_run r USING (run_id)
        WHERE r.batch_id = ? AND m.metric LIKE ?
        GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4""", [batch_id, metric]).fetchall()
    cols = ["scenario", "variant", "metric", "player", "runs", "mean", "min", "max"]
    return [dict(zip(cols, r)) for r in rows]


def batches(con: duckdb.DuckDBPyConnection, limit: int = 10) -> list[dict]:
    rows = con.execute("""
        SELECT b.batch_id, strftime(b.started_at, '%Y-%m-%d %H:%M') AS started_at, b.scenarios, b.variants, b.seeds, count(r.run_id) AS runs,
               count(*) FILTER (WHERE r.status <> 'ok') AS failed, round(b.wall_s, 1) AS wall_s
        FROM sim_batch b LEFT JOIN sim_run r USING (batch_id)
        GROUP BY ALL ORDER BY max(b.started_at) DESC LIMIT ?""", [limit]).fetchall()
    cols = ["batch_id", "started_at", "scenarios", "variants", "seeds", "runs", "failed", "wall_s"]
    return [dict(zip(cols, r)) for r in rows]


def latest_batch(con: duckdb.DuckDBPyConnection) -> str | None:
    row = con.execute("SELECT batch_id FROM sim_batch ORDER BY started_at DESC LIMIT 1").fetchone()
    return row[0] if row else None
