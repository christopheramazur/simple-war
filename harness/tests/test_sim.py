"""hx sim: matrices, launching (Godot faked), DuckDB ingest and summaries."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from hx import sim


def test_parse_seeds():
    assert sim.parse_seeds("3") == [1, 2, 3]
    assert sim.parse_seeds("4-6") == [4, 5, 6]
    assert sim.parse_seeds("1,5, 9") == [1, 5, 9]


def test_matrix_and_run_ids():
    jobs = sim.matrix("b1", ["duel", "vale"], {"baseline": "", "fast": "data/sim/variants/fast.json"}, [1, 2])
    assert len(jobs) == 8
    assert len({j.run_id for j in jobs}) == 8
    assert jobs[0].run_id == "b1-duel-baseline-s1"


def test_variant_files(tmp_path: Path):
    (tmp_path / "data/sim/variants").mkdir(parents=True)
    (tmp_path / "data/sim/variants/fast.json").write_text("{}")
    assert sim.variant_file(tmp_path, "baseline") == ""
    assert sim.variant_file(tmp_path, "fast") == "data/sim/variants/fast.json"
    assert sim.variants(tmp_path) == ["baseline", "fast"]
    with pytest.raises(FileNotFoundError):
        sim.variant_file(tmp_path, "nope")


def _fake_godot(monkeypatch, outcome_by_seed):
    """subprocess.run stand-in: writes the report a runner would."""
    def fake(cmd, **kwargs):
        args = dict(zip(cmd[::1], cmd[1::1]))
        out = Path(args["--out"])
        seed = int(args["--seed"])
        run_id = args["--run-id"]
        if outcome_by_seed.get(seed) == "timeout":
            raise subprocess.TimeoutExpired(cmd, 1)
        if outcome_by_seed.get(seed) == "silent":
            return subprocess.CompletedProcess(cmd, 1, "", "")
        report = {"run": {"run_id": run_id, "status": "ok", "kind": "battle", "turns": 10, "winner": 1 if seed % 2 else 2,
                          "reason": "turn_limit", "wall_ms": 100, "state_hash": "h"},
                  "metrics": [{"metric": "vp", "player": 1, "value": 10 + seed},
                              {"metric": "vp", "player": 2, "value": 5},
                              {"metric": "value_lost", "player": 1, "value": 100},
                              {"metric": "band.morale.neutral", "player": 1, "value": 2000}],
                  "series": [{"metric": "force", "player": 1, "turn": t, "value": 100 - t} for t in range(3)]}
        (out / f"{run_id}.json").write_text(json.dumps(report))
        (out / f"{run_id}.sav").write_bytes(b"x")
        return subprocess.CompletedProcess(cmd, 0, "", "")
    monkeypatch.setattr(sim.subprocess, "run", fake)


def test_launch_ingest_and_summarise(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    _fake_godot(monkeypatch, {3: "timeout", 4: "silent"})
    jobs = sim.matrix("b9", ["duel"], {"baseline": ""}, [1, 2, 3, 4])
    reports, wall = sim.launch(Path("godot.exe"), tmp_path, jobs, 2, 5)
    assert [r["run"]["status"] for r in reports] == ["ok", "ok", "error", "error"]
    assert "timed out" in reports[2]["run"]["error"]
    assert reports[3]["run"]["error"] == "the runner wrote no report"
    assert reports[0]["run"]["replay"].endswith(".sav")
    con = sim.connect(tmp_path / "sim.duckdb")
    sim.ingest(con, {"batch_id": "b9", "started_at": "2026-11-13 10:00:00+00", "scenarios": ["duel"],
                     "variants": ["baseline"], "seeds": "4", "jobs": 2, "wall_s": wall}, reports)
    row = sim.summary(con, "b9")[0]
    assert row["runs"] == 4 and row["failed"] == 2
    assert row["p1_vp"] == 11.5  # seeds 1 and 2
    assert row["p1_win"] == 0.25
    bands = sim.metric_table(con, "b9", "band.%")
    assert bands[0]["metric"] == "band.morale.neutral" and bands[0]["runs"] == 2
    assert sim.latest_batch(con) == "b9"
    assert sim.batches(con)[0]["runs"] == 4
    # Re-ingesting a run replaces its rows instead of duplicating them.
    sim.ingest(con, {"batch_id": "b9", "started_at": "2026-11-13 10:00:00+00", "scenarios": ["duel"],
                     "variants": ["baseline"], "seeds": "4", "jobs": 2, "wall_s": wall}, reports)
    assert con.execute("SELECT count(*) FROM sim_metric").fetchone()[0] == 8
    assert con.execute("SELECT count(*), min(value) FROM sim_series").fetchone() == (6, 98.0), "per-turn series"


def test_command_line(tmp_path: Path):
    job = sim.Job("b1", "duel", "fast", "data/sim/variants/fast.json", 3)
    cmd = sim.command(Path("g.exe"), tmp_path, job, tmp_path / "out")
    assert cmd[:6] == ["g.exe", "--headless", "--path", str(tmp_path), "-s", sim.RUNNER]
    assert cmd[cmd.index("--variant") + 1] == str(tmp_path / "data/sim/variants/fast.json")
    assert cmd[cmd.index("--seed") + 1] == "3"
