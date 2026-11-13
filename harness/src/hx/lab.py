"""Pressure Lab (GDD 05 §5.3, R5Q3, R6Q6): sweep SIMPL parameters against
scenarios and see which tropes emerge.

A lab file (data/sim/labs/<name>.json) names scenarios, seeds and axes:
    {"scenarios": [...], "seeds": 2,
     "axes": {"<template>.<field>[.<key>...]": [value, ...], ...},
     "base": {...variant fields every setting shares, e.g. controllers...}}
Every combination of axis values becomes a generated variant (v1, v2, ...)
whose patches set those values; the runs go through hx.sim as usual.

Tropes (data/sim/tropes.json) are rules over a run's features, computed from
its metrics: share of squad-ticks per pool band, surge/break/band-change
counts, turns, whether it was decided, the VP gap and the Value-lost ratio.
"""

from __future__ import annotations

import itertools
import json
from pathlib import Path

import duckdb

LAB_DIR = "data/sim/labs"
TROPES = "data/sim/tropes.json"
BANDS = ["broken", "fraying", "neutral", "primed", "surging"]
OPS = {">": lambda a, b: a > b, ">=": lambda a, b: a >= b, "<": lambda a, b: a < b,
       "<=": lambda a, b: a <= b, "==": lambda a, b: a == b, "!=": lambda a, b: a != b}

LAB_SCHEMA = """
CREATE TABLE IF NOT EXISTS sim_lab_variant (batch_id TEXT, lab TEXT, variant TEXT, setting TEXT);
CREATE TABLE IF NOT EXISTS sim_trope (run_id TEXT, trope TEXT);
"""


def labs(root: Path) -> list[str]:
    d = root / LAB_DIR
    return sorted(p.stem for p in d.glob("*.json")) if d.is_dir() else []


def load(root: Path, name: str) -> dict:
    f = Path(name) if name.endswith(".json") else root / LAB_DIR / f"{name}.json"
    if not f.is_file():
        raise FileNotFoundError(f"no lab '{name}' ({LAB_DIR}/{name}.json)")
    lab = json.loads(f.read_text(encoding="utf-8"))
    if not lab.get("axes"):
        raise ValueError(f"lab '{name}' has no axes")
    lab.setdefault("name", f.stem)
    return lab


def settings(lab: dict) -> list[dict[str, object]]:
    """Every combination of axis values, in axis order: [{path: value}]."""
    paths = list(lab["axes"])
    return [dict(zip(paths, combo)) for combo in itertools.product(*(lab["axes"][p] for p in paths))]


def patch(setting: dict[str, object]) -> dict:
    """{"standard.a.b": 1} -> {"standard": {"a": {"b": 1}}}."""
    out: dict = {}
    for path, value in setting.items():
        parts = path.split(".")
        node = out.setdefault(parts[0], {})
        for k in parts[1:-1]:
            node = node.setdefault(k, {})
        node[parts[-1]] = value
    return out


def write_variants(lab: dict, out_dir: Path) -> dict[str, tuple[str, dict]]:
    """Generated variant files: name -> (absolute path, setting)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    made = {}
    for i, s in enumerate(settings(lab), 1):
        name = f"v{i}"
        data = dict(lab.get("base", {}))
        data["name"] = name
        data["patches"] = _merge(dict(data.get("patches", {})), patch(s))
        f = out_dir / f"{name}.json"
        f.write_text(json.dumps(data, indent=1), encoding="utf-8")
        made[name] = (str(f), s)
    return made


def _merge(into: dict, over: dict) -> dict:
    for k, v in over.items():
        into[k] = _merge(dict(into.get(k, {})), v) if isinstance(v, dict) and isinstance(into.get(k), dict) else v
    return into


def short(setting: dict[str, object]) -> str:
    """A compact label: the last two path parts per axis."""
    return ", ".join(f"{'.'.join(p.split('.')[-2:])}={v}" for p, v in setting.items())


# --- tropes ------------------------------------------------------------------

def load_tropes(root: Path) -> list[dict]:
    return json.loads((root / TROPES).read_text(encoding="utf-8"))["tropes"]


def features(con: duckdb.DuckDBPyConnection, run_id: str) -> dict[str, float | str]:
    """A run's features for trope rules."""
    run = con.execute("SELECT turns, winner, reason FROM sim_run WHERE run_id = ?", [run_id]).fetchone()
    rows = con.execute("SELECT metric, player, value FROM sim_metric WHERE run_id = ?", [run_id]).fetchall()
    f: dict[str, float | str] = {}
    bands: dict[str, dict[str, float]] = {}
    per_player: dict[str, dict[int, float]] = {}
    for metric, player, value in rows:
        if metric.startswith("band."):
            _, pool, band = metric.split(".")
            bands.setdefault(pool, {}).setdefault(band, 0.0)
            bands[pool][band] += value
        elif metric.split(".")[0] in ("breaks", "surges", "band_changes"):
            f[metric] = float(f.get(metric, 0.0)) + value
        elif metric in ("vp", "value_lost"):
            per_player.setdefault(metric, {})[player] = value
    for pool, by_band in bands.items():
        total = sum(by_band.values()) or 1.0
        for band in BANDS:
            f[f"share.{pool}.{band}"] = by_band.get(band, 0.0) / total
        f[f"share.{pool}.extremes"] = (by_band.get("broken", 0.0) + by_band.get("surging", 0.0)) / total
    for pool in ("stamina", "instinct", "morale", "prowess", "legend"):
        for kind in ("breaks", "surges", "band_changes"):
            f.setdefault(f"{kind}.{pool}", 0.0)
    if run:
        turns, winner, reason = run
        f["turns"] = float(turns or 0)
        f["reason"] = reason or ""
        f["decided"] = 1.0 if winner and reason != "turn_limit" else 0.0
    vp = list(per_player.get("vp", {}).values())
    f["vp_gap"] = abs(max(vp) - min(vp)) if len(vp) >= 2 else 0.0
    lost = sorted(per_player.get("value_lost", {}).values())
    f["value_lost_ratio"] = (lost[-1] / lost[0] if lost and lost[0] > 0 else (1.0 if not lost or lost[-1] == 0 else 99.0))
    return f


def matches(rule: dict, feats: dict) -> bool:
    for cond in rule.get("all", []):
        v = feats.get(cond["feature"])
        if v is None or not OPS[cond.get("op", ">=")](v, cond["value"]):
            return False
    return True


def tag(con: duckdb.DuckDBPyConnection, batch_id: str, tropes: list[dict]) -> None:
    """(Re)computes the tropes of every ok run in a batch into sim_trope."""
    con.execute(LAB_SCHEMA)
    ids = [r[0] for r in con.execute("SELECT run_id FROM sim_run WHERE batch_id = ? AND status = 'ok'", [batch_id]).fetchall()]
    for run_id in ids:
        con.execute("DELETE FROM sim_trope WHERE run_id = ?", [run_id])
        feats = features(con, run_id)
        for t in tropes:
            if matches(t, feats):
                con.execute("INSERT INTO sim_trope VALUES (?, ?)", [run_id, t["id"]])


def record_settings(con: duckdb.DuckDBPyConnection, batch_id: str, lab: str, made: dict[str, tuple[str, dict]]) -> None:
    con.execute(LAB_SCHEMA)
    con.execute("DELETE FROM sim_lab_variant WHERE batch_id = ?", [batch_id])
    for name, (_, s) in made.items():
        con.execute("INSERT INTO sim_lab_variant VALUES (?, ?, ?, ?)", [batch_id, lab, name, short(s)])


def table(con: duckdb.DuckDBPyConnection, batch_id: str, tropes: list[dict]) -> list[dict]:
    """Per scenario x variant: its setting, outcomes, Morale pressure, and how often each trope showed."""
    con.execute(LAB_SCHEMA)
    rows = con.execute("""
        SELECT r.scenario, r.variant, coalesce(any_value(l.setting), '') AS setting, count(*) AS runs,
               round(avg(CASE WHEN r.winner = 1 OR r.outcome = 'won' THEN 1.0 ELSE 0.0 END), 2) AS p1_win,
               round(avg(r.turns), 1) AS turns
        FROM sim_run r LEFT JOIN sim_lab_variant l ON l.batch_id = r.batch_id AND l.variant = r.variant
        WHERE r.batch_id = ? AND r.status = 'ok'
        GROUP BY 1, 2 ORDER BY 1, length(r.variant), 2""", [batch_id]).fetchall()
    out = []
    for scenario, variant, setting, runs, p1_win, turns in rows:
        ids = [x[0] for x in con.execute(
            "SELECT run_id FROM sim_run WHERE batch_id = ? AND scenario = ? AND variant = ? AND status = 'ok'",
            [batch_id, scenario, variant]).fetchall()]
        feats = [features(con, i) for i in ids]
        neutral = sum(float(f.get("share.morale.neutral", 0.0)) for f in feats) / max(len(feats), 1)
        breaks = sum(float(f.get("breaks.morale", 0.0)) for f in feats) / max(len(feats), 1)
        found = con.execute(f"""
            SELECT trope, count(*) FROM sim_trope WHERE run_id IN ({','.join('?' * len(ids))}) GROUP BY 1 ORDER BY 1""",
                            ids).fetchall() if ids else []
        out.append({"scenario": scenario, "variant": variant, "setting": setting, "runs": runs, "p1_win": p1_win,
                    "turns": turns, "morale_neutral": round(neutral, 2), "morale_breaks": round(breaks, 1),
                    "tropes": [f"{t} {n}/{runs}" for t, n in found]})
    return out
