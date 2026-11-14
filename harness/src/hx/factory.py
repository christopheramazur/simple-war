"""The AI factory's evolution loop (GDD 05 §5.4; R7Q16, A1Q5, A2Q7, A2Q8, A2Q10,
B1Q2, B1Q8, B1Q11): a genetic algorithm with competitive co-evolution over
controller-profile genomes, a hall of fame, a MAP-Elites behaviour archive and
full lineage, results in DuckDB next to the harness runs.

A genome is a controller profile as plain data (ProfileController's format,
passed to Godot through a generated variant's "genome"):
  - overworld utility params: risk, outcome_weight, explore, cache_scale;
  - battle utility params: fall_back_pct, leader_margin, outcome_weight, run;
  - mask: a base weight per strategic criterion (0 = hidden), on top of the
    default fitness spec's gates; random at birth, rarely mutated (A2Q8);
  - fuzz (0-30 % strength) and fuzz_seed (A1Q4).

One generation:
  1. draw `pairings` pairings: side A from the population weighted by age
     (1 + generations survived, A1Q5); side B likewise, or from the hall of
     fame with probability `hof_draw`;
  2. play every pairing on both sides on `seeds` match seeds (B1Q11) as a
     harness batch (sim.launch), score it (fitness.score_batch);
  3. a profile's fitness is its mean over its matches, with lambda annealed by
     generation and switched off once the population beats the hall of fame
     (fitness.lam, B1Q2);
  4. update the MAP-Elites archive (cells over the aggression x expansion
     descriptors, B1Q8);
  5. the oldest profile that reached `max_age` retires (one per generation,
     so the founders don't all leave at once), joining the hall of fame if it
     ranked in the top half; the worst `replace` (and the retired) are
     replaced by children of the best: uniform crossover of two tournament
     winners, then mutation;
  6. survivors age by one; everything is written before the next generation,
     so a run can stop between generations and resume.
Every random choice comes from Random(f"{seed}:{generation}:{purpose}"), so a
whole factory run is reproducible from its run seed (A2Q10); Godot runs are
deterministic, except think-time faults (wall-clock).
"""

from __future__ import annotations

import json
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import duckdb

from hx import fitness, sim

SCHEMA = """
CREATE TABLE IF NOT EXISTS factory_run (
    run TEXT PRIMARY KEY, seed BIGINT, config TEXT, started_at TIMESTAMPTZ, generations INTEGER);
CREATE TABLE IF NOT EXISTS factory_profile (
    run TEXT, profile_id TEXT, genome TEXT, born INTEGER, parents TEXT, retired INTEGER, hof INTEGER);
CREATE TABLE IF NOT EXISTS factory_member (
    run TEXT, generation INTEGER, profile_id TEXT, age INTEGER, matches INTEGER, fitness DOUBLE,
    result DOUBLE, aggression DOUBLE, expansion DOUBLE, caution DOUBLE);
CREATE TABLE IF NOT EXISTS factory_gen (
    run TEXT, generation INTEGER, batch_id TEXT, lam DOUBLE, hof_rate DOUBLE, best DOUBLE, mean DOUBLE,
    wall_s DOUBLE, runs INTEGER, failed INTEGER, bench DOUBLE);
CREATE TABLE IF NOT EXISTS factory_archive (
    run TEXT, cell_a INTEGER, cell_e INTEGER, profile_id TEXT, fitness DOUBLE, generation INTEGER);
"""

STRATEGIC = ["value_efficiency", "force_ratio", "objective_control", "economy", "exploration",
             "commander_safety", "tempo", "pressure"]

# Gene bounds: (section, key) -> (lo, hi, kind)
GENES: dict[tuple[str, str], tuple[float, float, str]] = {
    ("overworld", "risk"): (0.6, 1.6, "float"),
    ("overworld", "outcome_weight"): (0.3, 2.0, "float"),
    ("overworld", "explore"): (2, 10, "int"),
    ("overworld", "cache_scale"): (2.0, 40.0, "float"),
    ("battle", "fall_back_pct"): (0, 80, "int"),
    ("battle", "leader_margin"): (1.0, 2.5, "float"),
    ("battle", "outcome_weight"): (0.3, 2.0, "float"),
    ("battle", "run"): (0, 1, "bool"),
    ("profile", "fuzz"): (0, 30, "int"),
}
MASK_RANGE = (0.0, 2.0)

DEFAULTS = {
    "scenario": "skirmish_seeded", "population": 10, "pairings": 20, "seeds": 3, "turns": 30,
    "replace": 2, "max_age": 8, "hof_draw": 0.2, "hof_size": 20, "mutation": 0.25, "mask_mutation": 0.05,
    "sigma": 0.15, "hidden": 0.2, "grid": 5, "spec": "default", "bench_every": 5,
    "bench_profile": "profile_utility", "jobs": 4, "timeout": 600.0,
}


# --- genomes ---------------------------------------------------------------

def _rng(seed: int, generation: int, purpose: str) -> random.Random:
    return random.Random(f"{seed}:{generation}:{purpose}")


def _draw(rng: random.Random, lo: float, hi: float, kind: str):
    if kind == "int":
        return rng.randint(int(lo), int(hi))
    if kind == "bool":
        return rng.random() < 0.5
    return round(rng.uniform(lo, hi), 4)


def random_genome(rng: random.Random, default_mask: dict, hidden: float = 0.2) -> dict:
    """A newborn genome: every gene drawn in range, each criterion hidden with
    probability `hidden`, the default spec's gates kept."""
    g: dict = {"overworld": {"process": "utility", "params": {}}, "battle": {"process": "utility", "params": {}},
               "mask": {}, "fuzz_seed": rng.randint(0, 2**31 - 1)}
    for (sec, key), (lo, hi, kind) in GENES.items():
        v = _draw(rng, lo, hi, kind)
        if sec == "profile":
            g[key] = v
        else:
            g[sec]["params"][key] = v
    for c in STRATEGIC:
        base = 0.0 if rng.random() < hidden else round(rng.uniform(*MASK_RANGE), 4)
        entry = {"base": base}
        if "gates" in default_mask.get(c, {}):
            entry["gates"] = default_mask[c]["gates"]
        g["mask"][c] = entry
    return g


def _get(g: dict, sec: str, key: str):
    return g[key] if sec == "profile" else g[sec]["params"][key]


def _set(g: dict, sec: str, key: str, v) -> None:
    if sec == "profile":
        g[key] = v
    else:
        g[sec]["params"][key] = v


def crossover(rng: random.Random, a: dict, b: dict) -> dict:
    """Uniform crossover: each gene (and each mask criterion) from either parent."""
    child = json.loads(json.dumps(a))
    for sec, key in GENES:
        if rng.random() < 0.5:
            _set(child, sec, key, _get(b, sec, key))
    for c in STRATEGIC:
        if rng.random() < 0.5 and c in b["mask"]:
            child["mask"][c] = json.loads(json.dumps(b["mask"][c]))
    child["fuzz_seed"] = rng.choice([a["fuzz_seed"], b["fuzz_seed"]])
    return child


def mutate(rng: random.Random, g: dict, rate: float = 0.25, mask_rate: float = 0.05, sigma: float = 0.15) -> dict:
    """Gaussian steps of sigma x range per gene with probability `rate`; mask
    bases mutate with the much lower `mask_rate` (A2Q8)."""
    out = json.loads(json.dumps(g))
    for (sec, key), (lo, hi, kind) in GENES.items():
        if rng.random() >= rate:
            continue
        if kind == "bool":
            _set(out, sec, key, not _get(out, sec, key))
            continue
        v = float(_get(out, sec, key)) + rng.gauss(0.0, sigma * (hi - lo))
        v = min(max(v, lo), hi)
        _set(out, sec, key, int(round(v)) if kind == "int" else round(v, 4))
    for c in STRATEGIC:
        if rng.random() < mask_rate:
            base = float(out["mask"][c]["base"]) + rng.gauss(0.0, sigma * (MASK_RANGE[1] - MASK_RANGE[0]))
            out["mask"][c]["base"] = round(min(max(base, MASK_RANGE[0]), MASK_RANGE[1]), 4)
    return out


# --- population ------------------------------------------------------------

@dataclass
class Profile:
    profile_id: str
    genome: dict
    born: int
    parents: list[str] = field(default_factory=list)
    age: int = 0


@dataclass
class State:
    run: str
    seed: int
    config: dict
    generation: int = 0  # the next generation to play
    population: list[Profile] = field(default_factory=list)
    hof: list[Profile] = field(default_factory=list)


def new_state(run: str, seed: int, config: dict, default_mask: dict) -> State:
    cfg = {**DEFAULTS, **config}
    rng = _rng(seed, 0, "birth")
    pop = [Profile(f"{run}-g0-p{i}", random_genome(rng, default_mask, cfg["hidden"]), 0)
           for i in range(cfg["population"])]
    return State(run, seed, cfg, 0, pop, [])


@dataclass(frozen=True)
class Pairing:
    a: str
    b: str


def draw_pairings(state: State) -> list[Pairing]:
    """Age-weighted pairings (A1Q5): older profiles more likely, duplicates
    allowed; side B sometimes from the hall of fame."""
    cfg = state.config
    rng = _rng(state.seed, state.generation, "pairings")
    ids = [p.profile_id for p in state.population]
    weights = [1 + p.age for p in state.population]
    out = []
    for _ in range(cfg["pairings"]):
        a = rng.choices(ids, weights)[0]
        if state.hof and rng.random() < cfg["hof_draw"]:
            b = rng.choice([h.profile_id for h in state.hof])
        else:
            b = rng.choices(ids, weights)[0]
        out.append(Pairing(a, b))
    return out


def match_seeds(state: State) -> list[int]:
    rng = _rng(state.seed, state.generation, "seeds")
    return [rng.randint(1, 10**6) for _ in range(state.config["seeds"])]


def write_variants(state: State, pairings: list[Pairing], out_dir: Path) -> dict[str, tuple[str, str, str]]:
    """Variant files, both sides of every pairing: name -> (path, player-1 id, player-2 id)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    genomes = {p.profile_id: p.genome for p in state.population + state.hof}
    made = {}
    for i, pr in enumerate(pairings):
        for side, (p1, p2) in (("a", (pr.a, pr.b)), ("b", (pr.b, pr.a))):
            name = f"m{i:02d}{side}"
            data = {"name": name, "turns": state.config["turns"],
                    "controllers": {"1": {"genome": genomes[p1]}, "2": {"genome": genomes[p2]}}}
            f = out_dir / f"{name}.json"
            f.write_text(json.dumps(data), encoding="utf-8")
            made[name] = (str(f), p1, p2)
    return made


# --- evaluation ------------------------------------------------------------

def _components(con: duckdb.DuckDBPyConnection, batch_id: str, spec: dict) -> dict[tuple[str, int], dict]:
    """(run_id, player) -> fitness components, for the batch's finished runs."""
    per: dict[tuple[str, int], dict] = {}
    for run_id, player, comp, value in con.execute("""
            SELECT r.run_id, f.player, f.component, f.value FROM sim_fitness f JOIN sim_run r USING (run_id)
            WHERE r.batch_id = ? AND f.spec = ? AND r.status = 'ok'""",
            [batch_id, spec.get("name", "default")]).fetchall():
        per.setdefault((run_id, player), {})[comp] = value
    return per


def evaluate(con: duckdb.DuckDBPyConnection, batch_id: str, made: dict, spec: dict, generation: int,
             hof_ids: set[str]) -> tuple[dict[str, dict], float | None, float]:
    """Per profile: matches, mean fitness, result and descriptors; also the
    population's win rate against the hall of fame and the lambda used."""
    variant_of = dict(con.execute("SELECT run_id, variant FROM sim_run WHERE batch_id = ? AND status = 'ok'",
                                  [batch_id]).fetchall())
    per = {k: v for k, v in _components(con, batch_id, spec).items() if "result" in v}

    def who(run_id: str, player: int) -> tuple[str, str]:
        _, p1, p2 = made[variant_of[run_id]]
        return (p1, p2) if player == 1 else (p2, p1)

    hof_games = hof_wins = 0
    for (run_id, player), comps in per.items():
        me, them = who(run_id, player)
        if them in hof_ids and me not in hof_ids:
            hof_games += 1
            hof_wins += 1 if comps["result"] >= 1.0 else 0
    hof_rate = hof_wins / hof_games if hof_games else None
    lam = fitness.lam(spec, generation, hof_rate)
    acc: dict[str, dict] = {}
    for (run_id, player), comps in sorted(per.items()):
        pid = who(run_id, player)[0]
        a = acc.setdefault(pid, {"matches": 0, "fitness": 0.0, "result": 0.0, "aggression": 0.0,
                                 "expansion": 0.0, "caution": 0.0})
        a["matches"] += 1
        a["fitness"] += fitness.fitness(comps, spec, lam)
        a["result"] += comps["result"]
        for d in ("aggression", "expansion", "caution"):
            a[d] += comps.get(f"desc.{d}", 0.0)
    for a in acc.values():
        for k in ("fitness", "result", "aggression", "expansion", "caution"):
            a[k] /= a["matches"]
    return acc, hof_rate, lam


def archive_update(archive: dict[tuple[int, int], tuple[str, float, int]], scores: dict[str, dict],
                   grid: int, generation: int) -> dict[tuple[int, int], tuple[str, float, int]]:
    """MAP-Elites (B1Q8): the best profile per aggression x expansion cell, as
    (profile, fitness, generation it was set)."""
    out = dict(archive)
    for pid, s in sorted(scores.items()):
        cell = (min(int(s["aggression"] * grid), grid - 1), min(int(s["expansion"] * grid), grid - 1))
        if cell not in out or s["fitness"] > out[cell][1]:
            out[cell] = (pid, s["fitness"], generation)
    return out


def _tournament(rng: random.Random, ranked: list[Profile], k: int = 3) -> Profile:
    picks = [rng.randrange(len(ranked)) for _ in range(min(k, len(ranked)))]
    return ranked[min(picks)]


def evolve(state: State, scores: dict[str, dict]) -> tuple[list[Profile], list[Profile], list[Profile]]:
    """Selection and replacement (A2Q7). Returns (new population, retired, born).
    Unplayed profiles keep their place; the worst `replace` played ones and
    any that reached max_age are replaced by children of the best."""
    cfg = state.config
    rng = _rng(state.seed, state.generation, "evolve")
    played = [p for p in state.population if p.profile_id in scores]
    ranked = sorted(played, key=lambda p: (-scores[p.profile_id]["fitness"], p.profile_id))
    top_half = {p.profile_id for p in ranked[:max(1, len(ranked) // 2)]}
    old = [p for p in state.population if p.age + 1 >= cfg["max_age"]]
    old.sort(key=lambda p: (-p.age, -scores.get(p.profile_id, {}).get("fitness", -9.0), p.profile_id))
    retired = old[:1]
    worst = [p for p in reversed(ranked) if p not in retired][:cfg["replace"]]
    out_ids = {p.profile_id for p in retired + worst}
    parents = [p for p in ranked if p.profile_id not in out_ids] or ranked or state.population
    survivors = [p for p in state.population if p.profile_id not in out_ids]
    born = []
    for i in range(len(out_ids)):
        a = _tournament(rng, parents)
        if rng.random() < 0.5 and len(parents) > 1:
            b = _tournament(rng, parents)
            g = crossover(rng, a.genome, b.genome)
            ps = [a.profile_id, b.profile_id]
        else:
            g = a.genome
            ps = [a.profile_id]
        g = mutate(rng, g, cfg["mutation"], cfg["mask_mutation"], cfg["sigma"])
        born.append(Profile(f"{state.run}-g{state.generation + 1}-p{i}", g, state.generation + 1, ps))
    for p in survivors:
        p.age += 1
    hall = [p for p in retired if p.profile_id in top_half]
    return survivors + born, hall, born


# --- DuckDB ----------------------------------------------------------------

def connect(path: Path | None = None) -> duckdb.DuckDBPyConnection:
    con = sim.connect(path)
    con.execute(SCHEMA)
    con.execute(fitness.SCHEMA)
    return con


def save_profiles(con: duckdb.DuckDBPyConnection, run: str, profiles: list[Profile]) -> None:
    con.executemany("INSERT INTO factory_profile VALUES (?, ?, ?, ?, ?, -1, 0)",
                    [(run, p.profile_id, json.dumps(p.genome), p.born, ",".join(p.parents)) for p in profiles])


def save_state(con: duckdb.DuckDBPyConnection, state: State) -> None:
    """The population entering `state.generation` (members with fitness NULL)."""
    con.execute("DELETE FROM factory_member WHERE run = ? AND generation = ? AND fitness IS NULL",
                [state.run, state.generation])
    con.executemany("INSERT INTO factory_member VALUES (?, ?, ?, ?, 0, NULL, NULL, NULL, NULL, NULL)",
                    [(state.run, state.generation, p.profile_id, p.age) for p in state.population])
    con.execute("UPDATE factory_run SET generations = ? WHERE run = ?", [state.generation, state.run])


def create(con: duckdb.DuckDBPyConnection, state: State) -> None:
    con.execute("INSERT INTO factory_run VALUES (?, ?, ?, ?, 0)",
                [state.run, state.seed, json.dumps(state.config), datetime.now(timezone.utc)])
    save_profiles(con, state.run, state.population)
    save_state(con, state)


def load(con: duckdb.DuckDBPyConnection, run: str) -> State:
    """A factory run as saved after its last finished generation."""
    row = con.execute("SELECT seed, config, generations FROM factory_run WHERE run = ?", [run]).fetchone()
    if row is None:
        raise KeyError(f"no factory run '{run}'")
    seed, config, gen = row
    genomes = {pid: (json.loads(g), born, parents, hof) for pid, g, born, parents, hof in con.execute(
        "SELECT profile_id, genome, born, parents, hof FROM factory_profile WHERE run = ?", [run]).fetchall()}

    def prof(pid: str, age: int = 0) -> Profile:
        g, born, parents, _ = genomes[pid]
        return Profile(pid, g, born, [x for x in parents.split(",") if x], age)

    pop = [prof(pid, age) for pid, age in con.execute(
        "SELECT profile_id, age FROM factory_member WHERE run = ? AND generation = ? AND fitness IS NULL "
        "ORDER BY profile_id", [run, gen]).fetchall()]
    hof = [prof(pid) for pid, (_, _, _, h) in sorted(genomes.items()) if h]
    return State(run, seed, json.loads(config), gen, pop, hof)


def archive(con: duckdb.DuckDBPyConnection, run: str) -> dict[tuple[int, int], tuple[str, float, int]]:
    return {(a, e): (pid, f, g) for a, e, pid, f, g in con.execute(
        "SELECT cell_a, cell_e, profile_id, fitness, generation FROM factory_archive WHERE run = ?", [run]).fetchall()}


def record(con: duckdb.DuckDBPyConnection, state: State, scores: dict, batch_id: str, lam: float,
           hof_rate: float | None, wall: float, runs: int, failed: int, bench: float | None) -> None:
    """A finished generation: member scores, the archive, generation stats."""
    g = state.generation
    con.execute("DELETE FROM factory_member WHERE run = ? AND generation = ?", [state.run, g])
    con.executemany("INSERT INTO factory_member VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
        (state.run, g, p.profile_id, p.age, s.get("matches", 0), s.get("fitness"), s.get("result"),
         s.get("aggression"), s.get("expansion"), s.get("caution"))
        for p in state.population for s in [scores.get(p.profile_id, {})]])
    arc = archive_update(archive(con, state.run), {k: v for k, v in scores.items()
                                                   if k in {p.profile_id for p in state.population}},
                         state.config["grid"], g)
    con.execute("DELETE FROM factory_archive WHERE run = ?", [state.run])
    con.executemany("INSERT INTO factory_archive VALUES (?, ?, ?, ?, ?, ?)",
                    [(state.run, a, e, pid, f, gen) for (a, e), (pid, f, gen) in sorted(arc.items())])
    fits = [scores[p.profile_id]["fitness"] for p in state.population if p.profile_id in scores]
    con.execute("INSERT INTO factory_gen VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [state.run, g, batch_id, lam, hof_rate, max(fits) if fits else None,
                 sum(fits) / len(fits) if fits else None, wall, runs, failed, bench])


def advance(con: duckdb.DuckDBPyConnection, state: State, scores: dict) -> list[Profile]:
    """Evolves the population after a recorded generation and saves the next one."""
    pop, hall, born = evolve(state, scores)
    retired = {p.profile_id for p in state.population} - {p.profile_id for p in pop}
    for pid in retired:
        con.execute("UPDATE factory_profile SET retired = ? WHERE run = ? AND profile_id = ?",
                    [state.generation, state.run, pid])
    for p in hall:
        con.execute("UPDATE factory_profile SET hof = 1 WHERE run = ? AND profile_id = ?", [state.run, p.profile_id])
    state.hof = (state.hof + [Profile(p.profile_id, p.genome, p.born, p.parents) for p in hall])[-state.config["hof_size"]:]
    save_profiles(con, state.run, born)
    state.population = pop
    state.generation += 1
    save_state(con, state)
    return born


# --- one generation with Godot ---------------------------------------------

def bench_jobs(state: State, champion: Profile, root: Path, batch_id: str, out_dir: Path) -> list[sim.Job]:
    """The champion against a fixed reference profile on both sides, to measure
    scoring gains against something that doesn't evolve (R7Q18)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    ref = {"profile": state.config["bench_profile"]}
    jobs = []
    for side, ctl in (("a", {"1": {"genome": champion.genome}, "2": ref}),
                      ("b", {"1": ref, "2": {"genome": champion.genome}})):
        f = out_dir / f"bench{side}.json"
        f.write_text(json.dumps({"name": f"bench{side}", "turns": state.config["turns"], "controllers": ctl}),
                     encoding="utf-8")
        for seed in match_seeds(state):
            jobs.append(sim.Job(batch_id, state.config["scenario"], f"bench{side}", str(f), seed))
    return jobs


def play_generation(con: duckdb.DuckDBPyConnection, state: State, exe: Path, root: Path, spec: dict,
                    library: dict, git_rev: str = "") -> dict:
    """Plays, scores, records and evolves one generation. Returns its stats."""
    cfg = state.config
    t0 = time.monotonic()
    pairings = draw_pairings(state)
    batch_id = f"{state.run}-g{state.generation:03d}"
    made = write_variants(state, pairings, sim.runs_dir() / batch_id / "variants")
    seeds = match_seeds(state)
    jobs = [sim.Job(batch_id, cfg["scenario"], name, path, seed)
            for name, (path, _, _) in made.items() for seed in seeds]
    bench = None
    bench_ok = cfg["bench_every"] > 0 and state.generation % cfg["bench_every"] == 0
    started = datetime.now(timezone.utc)
    reports, _ = sim.launch(exe, root, jobs, cfg["jobs"], cfg["timeout"])
    sim.ingest(con, {"batch_id": batch_id, "started_at": started, "scenarios": [cfg["scenario"]],
                     "variants": list(made), "seeds": ",".join(map(str, seeds)), "jobs": cfg["jobs"],
                     "wall_s": time.monotonic() - t0, "git_rev": git_rev}, reports)
    fitness.score_batch(con, batch_id, spec, library)
    hof_ids = {h.profile_id for h in state.hof}
    scores, hof_rate, lam = evaluate(con, batch_id, made, spec, state.generation, hof_ids)
    pop_scores = {k: v for k, v in scores.items() if k in {p.profile_id for p in state.population}}
    if bench_ok and pop_scores:
        champ_id = max(pop_scores, key=lambda k: (pop_scores[k]["fitness"], k))
        champ = next(p for p in state.population if p.profile_id == champ_id)
        bid = f"{batch_id}-bench"
        bjobs = bench_jobs(state, champ, root, bid, sim.runs_dir() / bid / "variants")
        breports, bwall = sim.launch(exe, root, bjobs, cfg["jobs"], cfg["timeout"])
        sim.ingest(con, {"batch_id": bid, "started_at": datetime.now(timezone.utc), "scenarios": [cfg["scenario"]],
                         "variants": ["bencha", "benchb"], "seeds": ",".join(map(str, seeds)), "jobs": cfg["jobs"],
                         "wall_s": bwall, "git_rev": git_rev}, breports)
        fitness.score_batch(con, bid, spec, library)
        bench = benchmark(con, bid, spec)
    failed = sum(1 for rep in reports if rep["run"].get("status") != "ok")
    wall = time.monotonic() - t0
    record(con, state, scores, batch_id, lam, hof_rate, wall, len(jobs), failed, bench)
    fits = [s["fitness"] for s in pop_scores.values()]
    stats = {"generation": state.generation, "batch": batch_id, "runs": len(jobs), "failed": failed,
             "wall_s": round(wall, 1), "lam": round(lam, 3), "hof_rate": hof_rate,
             "best": round(max(fits), 3) if fits else None, "mean": round(sum(fits) / len(fits), 3) if fits else None,
             "bench": bench}
    advance(con, state, scores)
    return stats


def benchmark(con: duckdb.DuckDBPyConnection, batch_id: str, spec: dict) -> float | None:
    """The champion's mean outcome fitness (lambda 0) against the reference."""
    variant_of = dict(con.execute("SELECT run_id, variant FROM sim_run WHERE batch_id = ? AND status = 'ok'",
                                  [batch_id]).fetchall())
    vals = [fitness.fitness(c, spec, 0.0) for (run_id, player), c in _components(con, batch_id, spec).items()
            if "result" in c and player == (1 if variant_of[run_id] == "bencha" else 2)]
    return round(sum(vals) / len(vals), 4) if vals else None


def gain_rate(con: duckdb.DuckDBPyConnection, run: str) -> dict:
    """Scoring-gain rate (R7Q18): benchmark fitness gained per wall-clock hour."""
    rows = con.execute("SELECT generation, bench, wall_s FROM factory_gen WHERE run = ? ORDER BY generation",
                       [run]).fetchall()
    hours = sum(w or 0.0 for _, _, w in rows) / 3600.0
    marks = [(g, b) for g, b, _ in rows if b is not None]
    out = {"generations": len(rows), "hours": round(hours, 3), "bench_points": len(marks)}
    if len(marks) >= 2 and hours > 0:
        out["gain_per_hour"] = round((marks[-1][1] - marks[0][1]) / hours, 4)
    return out


def table(con: duckdb.DuckDBPyConnection, run: str) -> list[dict]:
    return [{"gen": g, "runs": n, "failed": f, "wall_s": round(w or 0, 1), "lambda": round(lam or 0, 3),
             "hof_rate": None if h is None else round(h, 2), "best": None if b is None else round(b, 3),
             "mean": None if m is None else round(m, 3), "bench": bench}
            for g, n, f, w, lam, h, b, m, bench in con.execute(
                "SELECT generation, runs, failed, wall_s, lam, hof_rate, best, mean, bench FROM factory_gen "
                "WHERE run = ? ORDER BY generation", [run]).fetchall()]


def elites(con: duckdb.DuckDBPyConnection, run: str) -> list[dict]:
    return [{"aggression": a, "expansion": e, "profile": pid, "fitness": round(f, 3), "gen": g}
            for a, e, pid, f, g in con.execute(
                "SELECT cell_a, cell_e, profile_id, fitness, generation FROM factory_archive WHERE run = ? "
                "ORDER BY cell_a, cell_e", [run]).fetchall()]


def new_run_id() -> str:
    return datetime.now(timezone.utc).strftime("f%Y%m%d-%H%M%S")
