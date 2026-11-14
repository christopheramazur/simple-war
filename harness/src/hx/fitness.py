"""AI factory fitness (GDD 05 §5.4, Round B1): criteria library v1, schedule
gates and the fitness formula, scored from a batch's metrics and per-turn
series in DuckDB. No Godot needed, so old batches can be re-scored when the
spec changes.

  F = result + 0.25 x speed (wins only) + 0.1 x margin + lambda x shaping

`shaping` is the weighted mean of the strategic criteria (data/sim/criteria.json),
each weighted by base x the product of its gates (data/sim/fitness/<spec>.json),
averaged over the run's turns. A gate is a piecewise-linear curve over one
condition; its value changes at most once per `hold_turns` turns (hysteresis).
The decision-time forms of the same criteria live in the game (SimCriteria).
"""

from __future__ import annotations

import json
from pathlib import Path

import duckdb

CRITERIA = "data/sim/criteria.json"
SPEC_DIR = "data/sim/fitness"
NEUTRAL = 30
CHANGE_EPS = 1e-9

SCHEMA = """
CREATE TABLE IF NOT EXISTS sim_fitness (
    run_id TEXT, spec TEXT, player INTEGER, component TEXT, value DOUBLE);
"""


# --- data ------------------------------------------------------------------

def load_criteria(root: Path) -> dict:
    return json.loads((root / CRITERIA).read_text(encoding="utf-8"))


def specs(root: Path) -> list[str]:
    d = root / SPEC_DIR
    return sorted(p.stem for p in d.glob("*.json") if p.stem != "gate_cases") if d.is_dir() else []


def load_spec(root: Path, name: str) -> dict:
    p = Path(name) if name.endswith(".json") else root / SPEC_DIR / f"{name}.json"
    if not p.is_file():
        raise FileNotFoundError(f"no fitness spec {p}")
    return json.loads(p.read_text(encoding="utf-8"))


# --- gates -----------------------------------------------------------------

def curve(points: list, x: float) -> float:
    """Piecewise-linear over (x, y) points, flat beyond the ends."""
    if x <= points[0][0]:
        return float(points[0][1])
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return float(y0) if x1 == x0 else float(y0) + (float(y1) - float(y0)) * (x - x0) / (x1 - x0)
    return float(points[-1][1])


class Schedule:
    """One criterion's weight over a game: base x the product of its gates,
    each gate held at least `hold` turns once it changes. Mirrors the game's
    SimCriteria.Schedule (checked by data/sim/fitness/gate_cases.json)."""

    def __init__(self, entry: dict, hold: int):
        self.base = float(entry.get("base", 1.0))
        self.gates = list(entry.get("gates", []))
        self.hold = hold
        self._held: list[float | None] = [None] * len(self.gates)
        self._since: list[int] = [0] * len(self.gates)

    def weight(self, conditions: dict, turn: int) -> float:
        w = self.base
        for i, g in enumerate(self.gates):
            raw = curve(g["points"], float(conditions.get(g["condition"], 0.0)))
            if self._held[i] is None or (abs(raw - self._held[i]) > CHANGE_EPS and turn - self._since[i] >= self.hold):
                self._held[i], self._since[i] = raw, turn
            w *= self._held[i]
        return w


# --- one run ---------------------------------------------------------------

class Run:
    """A run's metrics and series, read from DuckDB."""

    def __init__(self, kind: str, turns: int, metrics: dict, series: dict):
        self.kind = kind
        self.turns = turns
        self.m = metrics  # (metric, player) -> value
        self.s = series  # (metric, player) -> {turn: value}
        self.players = sorted({p for (k, p) in metrics if k in ("won", "drew", "lost", "forfeited")})
        self.pre = "battle." if kind == "overworld" else ""

    def get(self, metric: str, player: int = 0, default: float = 0.0) -> float:
        return self.m.get((metric, player), default)

    def series(self, metric: str, player: int) -> dict:
        return self.s.get((metric, player), {})

    def others(self, p: int) -> list[int]:
        return [q for q in self.players if q != p]


def _share(own: float, total: float) -> float:
    return 0.5 if total <= 0 else own / total


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def _worth(r: Run, p: int) -> float:
    return r.get("value", p) + r.get("force", p)


def result(r: Run, p: int) -> float:
    if r.get("forfeited", p):
        return -1.0
    return 1.0 if r.get("won", p) else 0.0


def speed(r: Run, p: int) -> float:
    cap = r.get("turn_cap", 0, 0.0)
    if not r.get("won", p) or cap <= 0:
        return 0.0
    return _clamp(1.0 - r.turns / cap)


def margin(r: Run, p: int) -> float:
    key = "vp" if r.kind == "battle" else None
    own = r.get(key, p) if key else _worth(r, p)
    best = max((r.get(key, q) if key else _worth(r, q) for q in r.others(p)), default=0.0)
    total = own + best
    return 0.0 if total <= 0 else _clamp((own - best) / total, -1.0, 1.0)


def value_efficiency(r: Run, p: int) -> float:
    d = r.get(r.pre + "value_destroyed.player", p)
    lost = r.get(r.pre + "value_lost", p)
    return _share(d, d + lost)


def _enemy_force(r: Run, p: int, t: int) -> float:
    if r.kind == "overworld":
        return r.series("enemy_force_seen", p).get(t, 0.0)
    return sum(r.series("force", q).get(t, 0.0) for q in r.others(p))


def force_ratio(r: Run, p: int) -> float:
    own = r.series("force", p)
    if not own:
        return 0.5
    vals = [_share(v, v + _enemy_force(r, p, t)) for t, v in own.items()]
    return sum(vals) / len(vals)


def objective_control(r: Run, p: int) -> float:
    key = "zone_ticks" if r.kind == "battle" else "feature_turns"
    return _share(r.get(key, p), sum(r.get(key, q) for q in r.players))


def economy(r: Run, p: int) -> float:
    return _share(r.get("value_earned", p), sum(r.get("value_earned", q) for q in r.players))


def exploration(r: Run, p: int, target_pct: float = 60.0) -> float:
    return _clamp(r.get("fog_revealed_pct", p) / max(target_pct, 1e-9))


def commander_safety(r: Run, p: int) -> float:
    start = r.get("commanders_start", p)
    return 1.0 if start <= 0 else _clamp(r.get("commanders_alive", p) / start)


def tempo(r: Run, p: int) -> float:
    first = r.get("first_capture_turn", p, -1.0)
    return 0.0 if first < 0 else _clamp(1.0 - first / max(r.turns, 1))


def _low_morale_share(r: Run, p: int) -> float | None:
    ticks = {b: r.get(f"{r.pre}band.morale.{b}", p) for b in ("broken", "fraying", "neutral", "primed", "surging")}
    total = sum(ticks.values())
    return None if total <= 0 else (ticks["broken"] + ticks["fraying"]) / total


def pressure(r: Run, p: int) -> float:
    own = _low_morale_share(r, p)
    foes = [s for s in (_low_morale_share(r, q) for q in r.others(p)) if s is not None]
    if own is None or not foes:
        return 0.5
    return _clamp((sum(foes) / len(foes) - own + 1.0) / 2.0)


STRATEGIC = {
    "value_efficiency": value_efficiency, "force_ratio": force_ratio, "objective_control": objective_control,
    "economy": economy, "exploration": exploration, "commander_safety": commander_safety, "tempo": tempo,
    "pressure": pressure,
}


def criteria(r: Run, p: int, library: dict) -> dict[str, float]:
    """End-of-game forms of every strategic criterion that applies to the run's kind."""
    out = {}
    for cid, fn in STRATEGIC.items():
        spec = library["criteria"].get(cid, {})
        if r.kind not in spec.get("kinds", [r.kind]):
            continue
        out[cid] = fn(r, p, **spec.get("params", {}))
    return out


def conditions(r: Run, p: int, t: int, contact_turn: int | None) -> dict[str, float]:
    """The schedule conditions for player p at the end of turn t (B1Q6)."""
    force = r.series("force", p).get(t, 0.0)
    enemy = _enemy_force(r, p, t)
    if r.kind == "battle":
        own = r.series("vp", p).get(t, 0.0)
        best = max((r.series("vp", q).get(t, 0.0) for q in r.others(p)), default=0.0)
    else:
        own = r.series("value", p).get(t, 0.0) + force
        best = max((r.series("value", q).get(t, 0.0) + r.series("force", q).get(t, 0.0) for q in r.others(p)), default=0.0)
    return {
        "turn": t,
        "contact": 1.0 if contact_turn is not None and t >= contact_turn else 0.0,
        "since_contact": -1.0 if contact_turn is None or t < contact_turn else float(t - contact_turn),
        "fog_pct": r.series("fog_pct", p).get(t, 0.0),
        "force_ratio": _share(force, force + enemy),
        "threat": r.series("threat", p).get(t, 0.0),
        "bank": r.series("value", p).get(t, 0.0) if r.kind == "overworld" else 0.0,
        "ahead": 0.0 if own + best <= 0 else (own - best) / (own + best),
    }


def mean_weights(r: Run, p: int, spec: dict, names: list[str]) -> dict[str, float]:
    """Each criterion's weight averaged over the run's turns."""
    shaping = spec.get("shaping", {})
    hold = int(spec.get("hold_turns", 3))
    scheds = {c: Schedule(shaping.get(c, {"base": 0.0}), hold) for c in names}
    contact = r.series("contact", p)
    turns = sorted(r.series("force", p))
    if not turns:
        return {c: s.base for c, s in scheds.items()}
    first = next((t for t in turns if contact.get(t, 0.0) > 0), None)
    sums = dict.fromkeys(names, 0.0)
    for t in turns:
        cond = conditions(r, p, t, first)
        for c, s in scheds.items():
            sums[c] += s.weight(cond, t)
    return {c: v / len(turns) for c, v in sums.items()}


def descriptors(r: Run, p: int, crit: dict) -> dict[str, float]:
    """Behaviour descriptors for the MAP-Elites archive (B1Q8)."""
    lost = r.get(r.pre + "value_lost", p)
    start = r.get(r.pre + "force_start", p)
    if r.kind == "overworld":
        aggression = r.get("battles", p) / max(r.turns, 1)
        expansion = r.get("fog_revealed_pct", p) / 100.0 * crit.get("objective_control", 0.5)
    else:
        enemy = sum(r.get("force_start", q) for q in r.others(p))
        aggression = _clamp(r.get("value_destroyed", p) / max(enemy, 1.0))
        expansion = crit.get("objective_control", 0.5)
    return {"aggression": aggression, "expansion": expansion, "caution": _clamp(1.0 - lost / max(start, 1.0))}


def score(r: Run, p: int, spec: dict, library: dict) -> dict[str, float]:
    """Every fitness component for one player of one run (lambda applied later)."""
    crit = criteria(r, p, library)
    w = mean_weights(r, p, spec, list(crit))
    total = sum(w.values())
    shaping = 0.0 if total <= 0 else sum(w[c] * crit[c] for c in crit) / total
    out = {"result": result(r, p), "speed": speed(r, p), "margin": margin(r, p), "shaping": shaping}
    out.update({f"crit.{c}": v for c, v in crit.items()})
    out.update({f"w.{c}": v for c, v in w.items()})
    out.update({f"desc.{k}": v for k, v in descriptors(r, p, crit).items()})
    return out


def lam(spec: dict, generation: int = 0, hof_win_rate: float | None = None) -> float:
    """The shaping weight: anneals start -> 0 over `generations`, and is 0 once
    the population beats the hall of fame more than `hof_win_rate` (B1Q2)."""
    cfg = spec.get("lambda", {})
    if hof_win_rate is not None and hof_win_rate > float(cfg.get("hof_win_rate", 0.6)):
        return 0.0
    gens = max(int(cfg.get("generations", 50)), 1)
    return float(cfg.get("start", 0.3)) * max(0.0, 1.0 - generation / gens)


def fitness(components: dict, spec: dict, lam_value: float) -> float:
    o = spec.get("outcome", {})
    return (components["result"] + float(o.get("speed", 0.25)) * components["speed"]
            + float(o.get("margin", 0.1)) * components["margin"] + lam_value * components["shaping"])


# --- DuckDB ----------------------------------------------------------------

def load_runs(con: duckdb.DuckDBPyConnection, batch_id: str) -> dict[str, Run]:
    runs = {}
    rows = con.execute("SELECT run_id, kind, turns FROM sim_run WHERE batch_id = ? AND status = 'ok'", [batch_id]).fetchall()
    for run_id, kind, turns in rows:
        m = {(k, p): v for k, p, v in con.execute(
            "SELECT metric, player, value FROM sim_metric WHERE run_id = ?", [run_id]).fetchall()}
        s: dict = {}
        for k, p, t, v in con.execute(
                "SELECT metric, player, turn, value FROM sim_series WHERE run_id = ?", [run_id]).fetchall():
            s.setdefault((k, p), {})[t] = v
        runs[run_id] = Run(kind or "battle", int(turns or 0), m, s)
    return runs


def score_batch(con: duckdb.DuckDBPyConnection, batch_id: str, spec: dict, library: dict) -> int:
    """Scores every run of a batch under a spec into sim_fitness (replacing)."""
    con.execute(SCHEMA)
    name = spec.get("name", "default")
    runs = load_runs(con, batch_id)
    rows = []
    for run_id, r in runs.items():
        con.execute("DELETE FROM sim_fitness WHERE run_id = ? AND spec = ?", [run_id, name])
        for p in r.players:
            for comp, v in score(r, p, spec, library).items():
                rows.append((run_id, name, p, comp, float(v)))
    if rows:
        con.executemany("INSERT INTO sim_fitness VALUES (?, ?, ?, ?, ?)", rows)
    return len(runs)


def table(con: duckdb.DuckDBPyConnection, batch_id: str, spec: dict, lam_value: float) -> list[dict]:
    """Per scenario x variant x player: mean fitness and its parts."""
    name = spec.get("name", "default")
    o = spec.get("outcome", {})
    rows = con.execute("""
        SELECT r.scenario, r.variant, f.player, count(DISTINCT f.run_id) AS runs,
               avg(value) FILTER (WHERE component = 'result') AS result,
               avg(value) FILTER (WHERE component = 'speed') AS speed,
               avg(value) FILTER (WHERE component = 'margin') AS margin,
               avg(value) FILTER (WHERE component = 'shaping') AS shaping,
               avg(value) FILTER (WHERE component = 'desc.aggression') AS aggression,
               avg(value) FILTER (WHERE component = 'desc.expansion') AS expansion,
               avg(value) FILTER (WHERE component = 'desc.caution') AS caution
        FROM sim_fitness f JOIN sim_run r USING (run_id)
        WHERE r.batch_id = ? AND f.spec = ?
        GROUP BY r.scenario, r.variant, f.player ORDER BY r.scenario, r.variant, f.player""",
        [batch_id, name]).fetchall()
    out = []
    for sc, va, p, n, res, spd, mar, sh, ag, ex, ca in rows:
        f = res + float(o.get("speed", 0.25)) * spd + float(o.get("margin", 0.1)) * mar + lam_value * sh
        out.append({"scenario": sc, "variant": va, "player": p, "runs": n, "fitness": round(f, 3),
                    "result": round(res, 2), "speed": round(spd, 2), "margin": round(mar, 2),
                    "shaping": round(sh, 2), "aggr": round(ag, 2), "expan": round(ex, 2), "caution": round(ca, 2)})
    return out
