"""AI factory evolution loop (hx.factory): genomes, pairings, evaluation,
selection, hall of fame, archive, lineage and resume state (no Godot)."""

from __future__ import annotations

import json
import random
from pathlib import Path

import pytest

from hx import factory, fitness

ROOT = Path(__file__).resolve().parents[2]


def _mask() -> dict:
    return fitness.load_spec(ROOT, "default")["shaping"]


def _in_bounds(g: dict) -> None:
    for (sec, key), (lo, hi, kind) in factory.GENES.items():
        v = factory._get(g, sec, key)
        if kind == "bool":
            assert isinstance(v, bool)
        else:
            assert lo <= v <= hi, (sec, key, v)
    for c in factory.STRATEGIC:
        assert factory.MASK_RANGE[0] <= g["mask"][c]["base"] <= factory.MASK_RANGE[1]


def test_genomes_are_profiles_in_bounds():
    g = factory.random_genome(random.Random(1), _mask(), hidden=0.5)
    _in_bounds(g)
    assert g["overworld"]["process"] == "utility" and g["battle"]["process"] == "utility"
    assert set(g["mask"]) == set(factory.STRATEGIC)
    assert g["mask"]["exploration"]["gates"] == _mask()["exploration"]["gates"], "default gates kept"
    assert factory.random_genome(random.Random(1), _mask(), 0.5) == g, "same rng, same genome"
    hidden = sum(1 for s in range(20) for c in factory.STRATEGIC
                 if factory.random_genome(random.Random(s), _mask(), 0.5)["mask"][c]["base"] == 0.0)
    assert 30 < hidden < 130, "about half hidden at hidden=0.5"


def test_mutation_and_crossover():
    rng = random.Random(3)
    a = factory.random_genome(rng, _mask())
    b = factory.random_genome(rng, _mask())
    for i in range(30):
        m = factory.mutate(random.Random(i), a, rate=1.0, mask_rate=0.0)
        _in_bounds(m)
        assert m["mask"] == a["mask"], "the mask mutates only at mask_rate"
    assert factory.mutate(random.Random(1), a, rate=1.0, mask_rate=1.0)["mask"] != a["mask"]
    c = factory.crossover(random.Random(5), a, b)
    for sec, key in factory.GENES:
        assert factory._get(c, sec, key) in (factory._get(a, sec, key), factory._get(b, sec, key))
    assert c["mask"]["economy"] in (a["mask"]["economy"], b["mask"]["economy"])
    assert a == factory.crossover(random.Random(5), a, a), "parents are not changed"


def _state(seed: int = 7, **cfg) -> factory.State:
    return factory.new_state("f", seed, {"population": 4, "pairings": 6, "seeds": 2, **cfg}, _mask())


def test_runs_are_reproducible_from_the_seed():
    a, b = _state(7), _state(7)
    assert [p.genome for p in a.population] == [p.genome for p in b.population]
    assert factory.draw_pairings(a) == factory.draw_pairings(b)
    assert factory.match_seeds(a) == factory.match_seeds(b)
    assert [p.genome for p in _state(8).population] != [p.genome for p in a.population]


def test_pairings_are_age_weighted_and_draw_the_hall_of_fame():
    s = _state(pairings=400)
    s.population[3].age = 20
    counts = {p.profile_id: 0 for p in s.population}
    for pr in factory.draw_pairings(s):
        counts[pr.a] += 1
    assert counts["f-g0-p3"] > 2 * counts["f-g0-p0"], counts
    s.hof = [factory.Profile("h", s.population[0].genome, 0)]
    s.config["hof_draw"] = 1.0
    assert all(pr.b == "h" for pr in factory.draw_pairings(s))


def test_variants_play_both_sides(tmp_path: Path):
    s = _state()
    made = factory.write_variants(s, [factory.Pairing("f-g0-p0", "f-g0-p1")], tmp_path)
    assert set(made) == {"m00a", "m00b"}
    assert made["m00a"][1:] == ("f-g0-p0", "f-g0-p1") and made["m00b"][1:] == ("f-g0-p1", "f-g0-p0")
    data = json.loads(Path(made["m00b"][0]).read_text())
    assert data["controllers"]["1"]["genome"] == s.population[1].genome
    assert data["turns"] == s.config["turns"]


def _fake_batch(con, s: factory.State, made: dict, batch: str, winner_of: dict) -> None:
    """One run per variant; the profile named in winner_of[variant] wins."""
    for name, (_, p1, p2) in made.items():
        run_id = f"{batch}-{name}"
        con.execute("INSERT INTO sim_run (run_id, batch_id, scenario, variant, seed, kind, status) "
                    "VALUES (?, ?, 'map', ?, 1, 'overworld', 'ok')", [run_id, batch, name])
        for player, pid in ((1, p1), (2, p2)):
            won = 1.0 if winner_of.get(name) == pid else 0.0
            for comp, v in {"result": won, "speed": 0.5 * won, "margin": 0.2 if won else -0.2, "shaping": 0.5,
                            "desc.aggression": 0.9 if pid.endswith("p0") else 0.1, "desc.expansion": 0.5,
                            "desc.caution": 0.3}.items():
                con.execute("INSERT INTO sim_fitness VALUES (?, 'default', ?, ?, ?)", [run_id, player, comp, v])


def test_a_generation_scores_evolves_and_resumes(tmp_path: Path):
    con = factory.connect(tmp_path / "s.duckdb")
    s = _state(replace=1, max_age=2)
    factory.create(con, s)
    made = factory.write_variants(s, [factory.Pairing("f-g0-p0", "f-g0-p1"), factory.Pairing("f-g0-p2", "f-g0-p0")],
                                  tmp_path / "v")
    _fake_batch(con, s, made, "b0", {"m00a": "f-g0-p0", "m00b": "f-g0-p0", "m01a": "f-g0-p0", "m01b": "f-g0-p0"})
    spec = fitness.load_spec(ROOT, "default")
    scores, hof_rate, lam = factory.evaluate(con, "b0", made, spec, 0, set())
    assert hof_rate is None and lam == pytest.approx(0.3)
    assert scores["f-g0-p0"]["matches"] == 4 and scores["f-g0-p0"]["result"] == 1.0
    assert scores["f-g0-p0"]["fitness"] == pytest.approx(1.0 + 0.25 * 0.5 + 0.1 * 0.2 + 0.3 * 0.5)
    assert "f-g0-p3" not in scores, "p3 did not play"
    factory.record(con, s, scores, "b0", lam, hof_rate, 1.0, 4, 0, None)
    born = factory.advance(con, s, scores)
    assert len(born) == 1 and s.generation == 1, "the worst played profile is replaced"
    ids = {p.profile_id for p in s.population}
    assert "f-g0-p0" in ids and "f-g0-p3" in ids, "the best and the unplayed stay"
    assert born[0].parents and born[0].born == 1
    assert {p.profile_id: p.age for p in s.population if p.born == 0} == {pid: 1 for pid in ids if "g0" in pid}
    back = factory.load(con, "f")
    assert back.generation == 1 and [p.profile_id for p in back.population] == sorted(ids)
    assert {p.profile_id: p.age for p in back.population} == {p.profile_id: p.age for p in s.population}
    elites = factory.elites(con, "f")
    assert {(e["aggression"], e["profile"]) for e in elites} >= {(4, "f-g0-p0")}, "MAP-Elites cell by descriptors"
    # Generation 1: the founders reach max_age; only the best of them retires, into the hall of fame.
    scores1 = {p.profile_id: {**scores.get(p.profile_id, scores["f-g0-p1"])} for p in s.population}
    factory.record(con, s, scores1, "b1", lam, None, 1.0, 4, 0, 0.5)
    factory.advance(con, s, scores1)
    assert [h.profile_id for h in s.hof] == ["f-g0-p0"], "one retirement a generation; a top profile joins the hall"
    assert "f-g0-p0" not in {p.profile_id for p in s.population}
    assert len(s.population) == 4
    assert factory.load(con, "f").hof[0].profile_id == s.hof[0].profile_id
    assert [r["gen"] for r in factory.table(con, "f")] == [0, 1]


def test_hall_of_fame_rate_turns_lambda_off(tmp_path: Path):
    con = factory.connect(tmp_path / "s.duckdb")
    s = _state()
    s.hof = [factory.Profile("h", s.population[0].genome, 0)]
    made = factory.write_variants(s, [factory.Pairing("f-g0-p1", "h")], tmp_path / "v")
    _fake_batch(con, s, made, "b0", {"m00a": "f-g0-p1", "m00b": "f-g0-p1"})
    scores, hof_rate, lam = factory.evaluate(con, "b0", made, fitness.load_spec(ROOT, "default"), 0, {"h"})
    assert hof_rate == 1.0 and lam == 0.0, "beating the hall of fame switches shaping off (B1Q2)"
    assert scores["h"]["matches"] == 2


def test_archive_and_gain_rate(tmp_path: Path):
    arc = factory.archive_update({}, {"a": {"aggression": 0.1, "expansion": 0.9, "fitness": 1.0},
                                      "b": {"aggression": 0.15, "expansion": 0.95, "fitness": 1.2},
                                      "c": {"aggression": 1.0, "expansion": 0.0, "fitness": 0.1}}, 5, 3)
    assert arc[(0, 4)] == ("b", 1.2, 3) and arc[(4, 0)] == ("c", 0.1, 3)
    assert factory.archive_update(arc, {"d": {"aggression": 0.1, "expansion": 0.9, "fitness": 0.5}}, 5, 4)[(0, 4)][0] == "b"
    con = factory.connect(tmp_path / "s.duckdb")
    for g, bench in ((0, None), (1, 0.2), (2, 0.5)):
        con.execute("INSERT INTO factory_gen VALUES ('r', ?, 'b', 0.3, NULL, 1, 1, 1800, 4, 0, ?)", [g, bench])
    rate = factory.gain_rate(con, "r")
    assert rate["hours"] == 1.5 and rate["gain_per_hour"] == pytest.approx(0.2)
