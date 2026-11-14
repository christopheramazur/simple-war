"""AI factory fitness: criteria, schedule gates, lambda and batch scoring (no Godot)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from hx import fitness, sim

ROOT = Path(__file__).resolve().parents[2]


def test_curve():
    pts = [[0, 1.0], [10, 3.0], [20, 3.0]]
    assert fitness.curve(pts, -5) == 1.0
    assert fitness.curve(pts, 5) == 2.0
    assert fitness.curve(pts, 99) == 3.0


def test_gate_cases_shared_with_the_game():
    cases = json.loads((ROOT / fitness.SPEC_DIR / "gate_cases.json").read_text())
    s = fitness.Schedule(cases["entry"], cases["hold_turns"])
    for step in cases["turns"]:
        assert s.weight(step["conditions"], step["turn"]) == pytest.approx(step["weight"]), step


def test_shipped_data_is_consistent():
    library = fitness.load_criteria(ROOT)
    spec = fitness.load_spec(ROOT, "default")
    assert set(fitness.STRATEGIC) <= set(library["criteria"])
    assert set(spec["shaping"]) <= set(fitness.STRATEGIC), "shaping weights name known criteria"
    conds = set(fitness.conditions(_battle(), 1, 1, None))
    for entry in spec["shaping"].values():
        for g in entry.get("gates", []):
            assert g["condition"] in conds, g
    assert fitness.specs(ROOT) == ["default"]


def _battle(winner: int = 1, turns: int = 4, forfeit: int = 0) -> fitness.Run:
    m = {("turn_cap", 0): 10.0}
    for p in (1, 2):
        m[("won", p)] = 1.0 if p == winner and not forfeit else 0.0
        m[("forfeited", p)] = 1.0 if p == forfeit else 0.0
        m[("won", p)] = 1.0 if forfeit and p != forfeit else m[("won", p)]
    m.update({("vp", 1): 6, ("vp", 2): 2, ("value_destroyed.player", 1): 300, ("value_lost", 1): 100,
              ("value_destroyed.player", 2): 100, ("value_lost", 2): 300, ("zone_ticks", 1): 30, ("zone_ticks", 2): 10,
              ("band.morale.broken", 2): 50, ("band.morale.neutral", 2): 50, ("band.morale.neutral", 1): 100,
              ("first_capture_turn", 1): 1, ("first_capture_turn", 2): -1, ("force_start", 1): 400,
              ("force_start", 2): 400, ("value_destroyed", 1): 300})
    s = {("force", 1): {0: 400, 1: 400, 2: 350, 3: 300, 4: 300}, ("force", 2): {0: 400, 1: 400, 2: 200, 3: 100, 4: 100},
         ("contact", 1): {0: 0, 1: 0, 2: 1, 3: 1, 4: 1}, ("vp", 1): {t: t for t in range(5)}, ("vp", 2): {t: 0 for t in range(5)}}
    return fitness.Run("battle", turns, m, s)


def test_outcome_components():
    r = _battle()
    assert fitness.result(r, 1) == 1.0 and fitness.result(r, 2) == 0.0
    assert fitness.speed(r, 1) == pytest.approx(0.6) and fitness.speed(r, 2) == 0.0, "speed counts on wins only"
    assert fitness.margin(r, 1) == pytest.approx(0.5) and fitness.margin(r, 2) == pytest.approx(-0.5)
    q = _battle(forfeit=2)
    assert fitness.result(q, 2) == -1.0 and fitness.result(q, 1) == 1.0, "a forfeit scores below a loss"
    draw = _battle(winner=0)
    assert fitness.result(draw, 1) == 0.0 == fitness.result(draw, 2), "a draw scores as a loss (B1Q3)"


def test_strategic_criteria_and_guards():
    r = _battle()
    lib = fitness.load_criteria(ROOT)
    c = fitness.criteria(r, 1, lib)
    assert set(c) == {"value_efficiency", "force_ratio", "objective_control", "tempo", "pressure"}, "battle kinds only"
    assert c["value_efficiency"] == pytest.approx(0.75)
    assert c["objective_control"] == pytest.approx(0.75)
    assert c["tempo"] == pytest.approx(0.75)
    assert c["pressure"] == pytest.approx(0.75), "the enemy spent half its time broken, we never did"
    assert fitness.criteria(r, 2, lib)["tempo"] == 0.0
    idle = fitness.Run("battle", 3, {("won", 1): 0.0, ("won", 2): 0.0}, {})
    assert fitness.value_efficiency(idle, 1) == 0.5, "no fighting is neutral (B1Q7)"
    ow = fitness.Run("overworld", 10, {("fog_revealed_pct", 1): 90.0, ("won", 1): 0.0}, {})
    assert fitness.exploration(ow, 1, 60) == 1.0, "exploration saturates at the target"


def test_gated_weights_and_shaping():
    r = _battle()
    spec = fitness.load_spec(ROOT, "default")
    w = fitness.mean_weights(r, 1, spec, ["pressure", "force_ratio"])
    assert w["force_ratio"] == 1.0
    assert 0.0 < w["pressure"] < 0.5, "pressure is gated off until first contact, then held"
    comp = fitness.score(r, 1, spec, fitness.load_criteria(ROOT))
    assert 0.0 <= comp["shaping"] <= 1.0
    assert {"desc.aggression", "desc.expansion", "desc.caution", "w.tempo", "crit.pressure"} <= set(comp)
    f0 = fitness.fitness(comp, spec, 0.0)
    assert f0 == pytest.approx(1.0 + 0.25 * 0.6 + 0.1 * 0.5)
    assert fitness.fitness(comp, spec, 0.3) == pytest.approx(f0 + 0.3 * comp["shaping"])


def test_lambda_anneals():
    spec = fitness.load_spec(ROOT, "default")
    assert fitness.lam(spec, 0) == pytest.approx(0.3)
    assert fitness.lam(spec, 25) == pytest.approx(0.15)
    assert fitness.lam(spec, 80) == 0.0
    assert fitness.lam(spec, 0, hof_win_rate=0.7) == 0.0, "off once the population beats the hall of fame"


def test_score_batch(tmp_path: Path):
    con = sim.connect(tmp_path / "s.duckdb")
    con.execute("INSERT INTO sim_run (run_id, batch_id, scenario, variant, seed, kind, status, turns, winner) "
                "VALUES ('r1', 'b', 'duel', 'base', 1, 'battle', 'ok', 4, 1)")
    r = _battle()
    con.executemany("INSERT INTO sim_metric VALUES ('r1', ?, ?, ?)", [(k, p, v) for (k, p), v in r.m.items()])
    con.executemany("INSERT INTO sim_series VALUES ('r1', ?, ?, ?, ?)",
                    [(k, p, t, v) for (k, p), pts in r.s.items() for t, v in pts.items()])
    spec = fitness.load_spec(ROOT, "default")
    assert fitness.score_batch(con, "b", spec, fitness.load_criteria(ROOT)) == 1
    fitness.score_batch(con, "b", spec, fitness.load_criteria(ROOT))  # re-scoring replaces
    assert con.execute("SELECT count(*) FROM sim_fitness WHERE component = 'result'").fetchone()[0] == 2
    rows = fitness.table(con, "b", spec, 0.0)
    assert [x["player"] for x in rows] == [1, 2]
    assert rows[0]["fitness"] == pytest.approx(1.2)
