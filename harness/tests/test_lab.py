"""Pressure Lab: sweeps, generated variants, features and tropes (no Godot)."""

from __future__ import annotations

import json
from pathlib import Path

from hx import lab, sim

LAB = {"name": "t", "scenarios": ["duel"], "seeds": 1,
       "axes": {"standard.pool_defaults.morale.drift_pct_per_s": ["0.1", "2"], "standard.morale_rate_per_s": ["0.4"]},
       "base": {"controllers": {"2": {"profile": "idle"}}, "patches": {"standard": {"morale_leech_pct": 5}}}}


def test_settings_and_patches(tmp_path: Path):
    s = lab.settings(LAB)
    assert len(s) == 2
    assert lab.patch(s[0]) == {"standard": {"pool_defaults": {"morale": {"drift_pct_per_s": "0.1"}}, "morale_rate_per_s": "0.4"}}
    made = lab.write_variants(LAB, tmp_path)
    assert list(made) == ["v1", "v2"]
    v2 = json.loads(Path(made["v2"][0]).read_text())
    assert v2["controllers"] == {"2": {"profile": "idle"}}, "base fields carried over"
    assert v2["patches"]["standard"]["morale_leech_pct"] == 5, "base patches merged, not replaced"
    assert v2["patches"]["standard"]["pool_defaults"]["morale"]["drift_pct_per_s"] == "2"
    assert lab.short(s[1]) == "morale.drift_pct_per_s=2, standard.morale_rate_per_s=0.4"


def test_load(tmp_path: Path):
    (tmp_path / lab.LAB_DIR).mkdir(parents=True)
    (tmp_path / lab.LAB_DIR / "x.json").write_text(json.dumps(LAB))
    assert lab.labs(tmp_path) == ["x"]
    assert lab.load(tmp_path, "x")["name"] == "t"


def _seed(con, run_id: str, rows: list[tuple[str, int, float]], winner=1, reason="annihilation", turns=6):
    con.execute("INSERT INTO sim_run (run_id, batch_id, scenario, variant, seed, status, turns, winner, reason) "
                "VALUES (?, 'b', 'duel', ?, 1, 'ok', ?, ?, ?)", [run_id, run_id[:2], turns, winner, reason])
    con.executemany("INSERT INTO sim_metric VALUES (?, ?, ?, ?)", [(run_id, m, p, v) for m, p, v in rows])


def test_features_and_tropes(tmp_path: Path):
    con = sim.connect(tmp_path / "s.duckdb")
    _seed(con, "v1-a", [("band.morale.neutral", 1, 95), ("band.morale.primed", 2, 5), ("vp", 1, 4), ("vp", 2, 3),
                        ("value_lost", 1, 10), ("value_lost", 2, 10)], winner=1, reason="turn_limit", turns=10)
    _seed(con, "v2-a", [("band.morale.broken", 1, 30), ("band.morale.surging", 2, 20), ("band.morale.neutral", 1, 50),
                        ("breaks.morale", 1, 3), ("breaks.morale", 2, 2), ("value_lost", 1, 300), ("value_lost", 2, 50),
                        ("vp", 1, 0), ("vp", 2, 9)], winner=2)
    f1 = lab.features(con, "v1-a")
    assert f1["share.morale.neutral"] == 0.95 and f1["decided"] == 0.0 and f1["vp_gap"] == 1
    f2 = lab.features(con, "v2-a")
    assert f2["breaks.morale"] == 5 and f2["value_lost_ratio"] == 6 and f2["share.morale.extremes"] == 0.5
    tropes = json.loads((Path(__file__).resolve().parents[2] / lab.TROPES).read_text())["tropes"]
    lab.tag(con, "b", tropes)
    found = {r for r in con.execute("SELECT run_id || ':' || trope FROM sim_trope").fetchall()}
    assert ("v1-a:flatline",) in found and ("v1-a:stalemate",) in found
    assert ("v2-a:rout_cascade",) in found and ("v2-a:death_spiral",) in found and ("v2-a:pressure_cooker",) in found
    assert ("v2-a:flatline",) not in found
    lab.record_settings(con, "b", "t", {"v1": ("f", {"standard.x": 1}), "v2": ("f", {"standard.x": 2})})
    rows = lab.table(con, "b", tropes)
    assert [r["variant"] for r in rows] == ["v1", "v2"]
    assert rows[0]["setting"] == "standard.x=1"
    assert "flatline 1/1" in rows[0]["tropes"]
    lab.tag(con, "b", tropes)  # re-tagging replaces, never duplicates
    assert con.execute("SELECT count(*) FROM sim_trope WHERE run_id = 'v1-a' AND trope = 'flatline'").fetchone()[0] == 1


def test_matches():
    rule = {"all": [{"feature": "a", "op": ">=", "value": 2}, {"feature": "reason", "op": "==", "value": "x"}]}
    assert lab.matches(rule, {"a": 2, "reason": "x"})
    assert not lab.matches(rule, {"a": 1, "reason": "x"})
    assert not lab.matches(rule, {"reason": "x"}), "a missing feature never matches"
