"""Deterministic generator for the frozen task suite (`hx bench build`).

Tasks are written once to bench/tasks/<level>/<id>.json and committed. Regenerating
must produce identical files for the same SUITE_VERSION; change the suite by bumping
SUITE_VERSION so results from different suites are never compared.

Task file shape:
  {id, level, task_class, size, suite_version, system, prompt, check: {type, ...}}
"""

from __future__ import annotations

import csv
import io
import json
import random
import re
import shutil
from pathlib import Path

from hx.bench import BENCH_ROOT, SUITE_VERSION, TASKS_DIR
from hx.paths import repo_root

SEED = 20261031
SIZES = {"s": 8, "m": 40, "l": 160}
SYSTEM = "You are a precise data assistant. Follow the output format exactly. Output only what is asked, no commentary."
ROW_KEYS = ["name", "faction", "role", "hp", "armor", "speed", "cost"]
FACTIONS = ["Human", "Iron Bastion", "Maw", "Arcanist", "Swarm"]
ROLES = ["infantry", "scout", "heavy", "support", "artillery", "elite"]


def _rows(rng: random.Random, n: int) -> list[dict]:
    syll = ["ka", "ro", "vex", "tal", "mir", "dun", "sha", "gor", "eli", "zan", "quo", "ber", "ith", "ul"]
    names = set()
    rows = []
    while len(rows) < n:
        name = "".join(rng.choice(syll) for _ in range(rng.randint(2, 3))).capitalize() + " " + rng.choice(
            ["Guard", "Pack", "Choir", "Lancers", "Wardens", "Brood", "Battery", "Cell"])
        if name in names:
            continue
        names.add(name)
        rows.append({"name": name, "faction": rng.choice(FACTIONS), "role": rng.choice(ROLES),
                     "hp": rng.randint(10, 120), "armor": rng.randint(0, 12), "speed": rng.randint(3, 14),
                     "cost": rng.randint(5, 60) * 5})
    return rows


def _csv(rows: list[dict]) -> str:
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=ROW_KEYS, lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def _task(tid, level, cls, size, prompt, check) -> dict:
    return {"id": tid, "level": level, "task_class": cls, "size": size, "suite_version": SUITE_VERSION,
            "system": SYSTEM, "prompt": prompt, "check": check}


# ---------------- L1: reformat / transform (exact checks) ----------------

def level1(rng: random.Random) -> list[dict]:
    out = []
    for size, n in SIZES.items():
        rows = _rows(rng, n)
        data = json.dumps(rows, indent=1)
        out.append(_task(
            f"L1-csv_to_json-{size}", "L1", "csv_to_json", size,
            "Convert this CSV to a JSON array of objects. Keys: " + ", ".join(ROW_KEYS) + ". hp, armor, speed and "
            "cost are integers. Keep row order. Output only the JSON array.\n\n" + _csv(rows),
            {"type": "json_equal", "expected": rows}))
        cols = ["name", "role", "hp", "cost"]
        out.append(_task(
            f"L1-json_to_table-{size}", "L1", "json_to_table", size,
            "Convert this JSON array to a Markdown table with exactly these columns in this order: "
            + " | ".join(cols) + ". Header row, then a separator row, then one row per object in the same order. "
            "Output only the table.\n\n" + data,
            {"type": "table_equal", "expected": [cols] + [[str(r[c]) for c in cols] for r in rows]}))
        mapping = {"hp": "health", "armor": "armour", "cost": "points"}
        renamed = [{mapping.get(k, k): v for k, v in r.items() if k != "speed"} for r in rows]
        out.append(_task(
            f"L1-rename_drop-{size}", "L1", "rename_drop", size,
            "Transform this JSON array: rename keys hp→health, armor→armour, cost→points; remove the key speed; "
            "keep all other keys, values and the object order. Output only the JSON array.\n\n" + data,
            {"type": "json_equal", "expected": renamed}))
        faction = rng.choice(FACTIONS)
        min_hp = 40
        kept = sorted((r for r in rows if r["faction"] == faction and r["hp"] >= min_hp),
                      key=lambda r: (-r["cost"], r["name"]))
        out.append(_task(
            f"L1-filter_sort-{size}", "L1", "filter_sort", size,
            f'From this JSON array keep only objects with faction "{faction}" and hp >= {min_hp}. Sort by cost '
            "descending, then name ascending. Output only the resulting JSON array of full objects "
            "(an empty array if none match).\n\n" + data,
            {"type": "json_equal", "expected": kept}))
    return out


# ---------------- L2: schema data-fill ----------------

ATTACK_SPECS = [
    ("Plasma Lance", "ranged", "rifle", "energy", 5, 1, (4, 12, 36, 48)),
    ("Bone Saw", "melee", "melee", "kinetic", 4, 2, (0, 1, 1, 1)),
    ("Shock Grenade", "ranged", "launcher", "concussive", 3, 3, (2, 6, 14, 18)),
    ("Spine Volley", "ranged", "natural_ranged", "kinetic", 2, 4, (3, 8, 20, 26)),
    ("Hex Bolt", "ranged", "magic", "energy", 6, 1, (5, 15, 40, 50)),
    ("Crushing Maw", "melee", "natural_melee", "kinetic", 7, 1, (0, 1, 1, 1)),
    ("Flak Burst", "ranged", "launcher", "kinetic", 2, 6, (6, 14, 30, 40)),
    ("Arc Pistol", "ranged", "rifle", "energy", 3, 2, (1, 5, 12, 16)),
    ("Thunder Maul", "melee", "melee", "concussive", 6, 1, (0, 1, 1, 1)),
    ("Acid Spit", "ranged", "natural_ranged", "energy", 3, 1, (2, 5, 10, 14)),
    ("Ward Pulse", "ranged", "magic", "concussive", 2, 5, (0, 3, 8, 10)),
    ("Rail Rifle", "ranged", "rifle", "kinetic", 8, 1, (10, 30, 70, 90)),
    ("Claw Rake", "melee", "natural_melee", "kinetic", 3, 3, (0, 1, 1, 1)),
    ("Mortar Shell", "ranged", "launcher", "concussive", 5, 2, (15, 30, 60, 80)),
    ("Soul Lash", "melee", "magic", "energy", 4, 2, (0, 2, 3, 4)),
]


def _snake(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def level2(rng: random.Random) -> list[dict]:
    attacks = json.loads((repo_root() / "data" / "defaults" / "Attacks.json").read_text(encoding="utf-8"))["attacks"]
    examples = json.dumps(attacks[:2], indent=4)
    out = []
    for size, n in {"s": 2, "m": 6, "l": 15}.items():
        specs = ATTACK_SPECS[:n]
        lines = [f"- {name}: {cat} attack, skill_category {skill}, {dtype} damage value {val} count {cnt}, "
                 f"range min {r[0]} short {r[1]} long {r[2]} max {r[3]}"
                 for name, cat, skill, dtype, val, cnt, r in specs]
        expect = [{"id": _snake(name), "display_name": name, "category": cat, "skill_category": skill,
                   "range": dict(zip(("min", "short", "long", "max"), r)),
                   "damage": {"type": dtype, "value": val, "count": cnt}}
                  for name, cat, skill, dtype, val, cnt, r in specs]
        out.append(_task(
            f"L2-attacks-{size}", "L2", "attack_datafill", size,
            "Here are two attack entries from our game data:\n\n" + examples + "\n\n"
            f"Write {n} new attack entries in exactly the same JSON shape, one per spec below, in the same order. "
            "id is the display name in snake_case. description is one short sentence you write. "
            "Output only a JSON array of the entries.\n\n" + "\n".join(lines),
            {"type": "attacks", "schema": "attack.schema.json", "expected": expect}))
    return out


# ---------------- L3: classify / tag ----------------

LOG_INFO = ["Godot Engine v4.7.2.stable.official - https://godotengine.org",
            "Vulkan 1.3.2 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 3060",
            "Loading scene res://src/combat/combat_window.tscn", "ECS: registered 14 component types",
            "Squad human_riflemen spawned (10 units)", "Combat 3 resolved in 4 rounds",
            "Saved campaign slot 1 (12.4 KB)", "Autoload RTS_EventBus ready"]
LOG_WARN = ["WARNING: The parameter 'delta' is never used in the function '_process()'.",
            "WARNING: Integer division, decimal part will be discarded.",
            "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
            "WARNING: Node 'Minimap' has no owner; it will not be saved."]
LOG_ERR = ["ERROR: Cannot open file 'res://data/defaults/Models.json'.",
           "SCRIPT ERROR: Invalid access to property or key 'morale' on a base object of type 'Nil'.",
           "ERROR: Condition \"!is_inside_tree()\" is true. Returning: Transform3D()",
           "SCRIPT ERROR: Parse Error: Identifier \"SquadData\" not declared in the current scope.",
           "ERROR: Failed loading resource: res://assets/units/maw_fiend.tres."]
LOG_AT = ["   at: _ready (res://src/combat/combat_window.gd:42)", "   at: load (core/io/resource_loader.cpp:291)",
          "   GDScript backtrace (most recent call first):"]


def _log(rng: random.Random, n: int) -> tuple[str, list[int]]:
    lines, errors = [], []
    n_err = 1 + n // 60
    err_at = set(rng.sample(range(2, n - 2), n_err))
    while len(lines) < n:
        i = len(lines)
        if i in err_at:
            lines.append(rng.choice(LOG_ERR))
            errors.append(len(lines))  # 1-based
            if len(lines) < n:
                lines.append(rng.choice(LOG_AT))
        else:
            lines.append(rng.choice(LOG_WARN) if rng.random() < 0.25 else rng.choice(LOG_INFO))
    return "\n".join(f"{k}: {line}" for k, line in enumerate(lines[:n], 1)), errors


SESSIONS = [  # (summary, kind) — kinds from config taxonomy
    ("Added a morale stat to squads, wired it into combat resolution and wrote GUT tests.", "feature"),
    ("Combat window crashed when a squad was destroyed mid-round; fixed null access and added a regression test.", "bugfix"),
    ("Split the 600-line combat_resolver.gd into three classes without changing behaviour.", "refactor"),
    ("Wrote 12 new unit entries in Units.json and balanced their point values.", "content-data"),
    ("Compared GECS and a hand-rolled ECS for 2,000 entities; wrote up findings, no code.", "research"),
    ("Added a new hx verb that summarises GUT output for agents.", "harness"),
    ("Upgraded bd, rotated the local Dolt server and fixed the CI cache path.", "ops"),
    ("User asked what the Layer Cake rule means; answered with an example.", "chat"),
    ("Implemented the sector map screen with node selection and travel.", "feature"),
    ("Saves from v0.3 failed to load; added a migration for the renamed field.", "bugfix"),
    ("Filled in the Scenarios.json entries for the second campaign act.", "content-data"),
    ("Added a burn-rate projection to the agent status line.", "harness"),
]
KINDS = ["feature", "bugfix", "refactor", "content-data", "research", "harness", "ops", "chat"]
KIND_DEFS = {
    "feature": "new game behaviour or screens", "bugfix": "fixing broken game behaviour",
    "refactor": "restructuring code without changing behaviour", "content-data": "editing game data/content files",
    "research": "investigation or comparison with no code shipped", "harness": "agent tooling, metrics or workflow",
    "ops": "infrastructure, dependencies, CI, trackers", "chat": "answering a question, no changes",
}

COMMANDS = [  # (command, mutates?) for a read-only vs mutating classifier
    ("git status --short", False), ("git log --oneline -5", False), ("git commit -m 'x'", True),
    ("git push origin main", True), ("ls -la src", False), ("rm -rf .godot", True), ("cat project.godot", False),
    ("grep -rn 'class_name' src", False), ("sed -i 's/a/b/' file.gd", True), ("sed -n '1,20p' file.gd", False),
    ("bd ready", False), ("bd close sw-1", True), ("bd show sw-1", False), ("python --version", False),
    ("mkdir -p build", True), ("cp a.json b.json", True), ("find . -name '*.tscn'", False),
    ("npm install", True), ("echo hi > out.txt", True), ("head -n 5 log.txt", False),
    ("git checkout -- file.gd", True), ("git diff --stat", False), ("mv old.gd new.gd", True), ("wc -l *.gd", False),
]


def level3(rng: random.Random) -> list[dict]:
    out = []
    for size, n in {"s": 20, "m": 80, "l": 300}.items():
        log, errs = _log(rng, n)
        out.append(_task(
            f"L3-log_triage-{size}", "L3", "log_triage", size,
            "Below is a numbered Godot log. Which line numbers are errors (lines whose message starts with ERROR: or "
            'SCRIPT ERROR:)? Warnings, info lines and "at:" continuation lines are not errors. '
            'Output only JSON like {"error_lines": [3, 17]}.\n\n' + log,
            {"type": "set_equal", "key": "error_lines", "expected": errs}))
    items = {f"s{i + 1}": s for i, (s, _) in enumerate(SESSIONS)}
    out.append(_task(
        "L3-session_kind-m", "L3", "session_kind", "m",
        "Classify each agent session summary into exactly one kind:\n"
        + "\n".join(f"- {k}: {KIND_DEFS[k]}" for k in KINDS) + "\n"
        'Output only JSON mapping id to kind, like {"s1": "feature"}.\n\n'
        + "\n".join(f"{k}: {v}" for k, v in items.items()),
        {"type": "labels", "expected": {f"s{i + 1}": k for i, (_, k) in enumerate(SESSIONS)}, "pass_at": 0.9}))
    cmds = {f"c{i + 1}": c for i, (c, _) in enumerate(COMMANDS)}
    out.append(_task(
        "L3-command_mutates-m", "L3", "command_mutates", "m",
        "For each shell command, answer whether running it changes files, repository state or tracker state "
        '("mutating") or only reads ("read-only"). Output only JSON mapping id to "mutating" or "read-only".\n\n'
        + "\n".join(f"{k}: {v}" for k, v in cmds.items()),
        {"type": "labels", "pass_at": 0.9,
         "expected": {f"c{i + 1}": ("mutating" if m else "read-only") for i, (_, m) in enumerate(COMMANDS)}}))
    return out


def build(force: bool = False) -> list[Path]:
    rng = random.Random(SEED)
    tasks = level1(rng) + level2(rng) + level3(rng)
    if TASKS_DIR.exists():
        if not force:
            raise FileExistsError(f"{TASKS_DIR} exists; the suite is frozen (use --force only with a new SUITE_VERSION)")
        shutil.rmtree(TASKS_DIR)
    written = []
    for t in tasks:
        p = TASKS_DIR / t["level"] / f"{t['id']}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(t, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
        written.append(p)
    _freeze_filler()
    return written


def _freeze_filler() -> Path:
    """Context padding: a frozen concatenation of the GDD (domain-relevant distractor text)."""
    out = BENCH_ROOT / "filler" / "gdd.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    gdd = repo_root() / "Game Design Document"
    parts = [p.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n") for p in sorted(gdd.rglob("*.md"))]
    out.write_text("\n\n".join(parts), encoding="utf-8", newline="\n")  # LF everywhere, see runner._filler
    return out


def load_tasks(levels: list[str] | None = None, pattern: str | None = None) -> list[dict]:
    import fnmatch
    tasks = []
    for p in sorted(TASKS_DIR.rglob("*.json")):
        t = json.loads(p.read_text(encoding="utf-8"))
        if levels and t["level"] not in levels:
            continue
        if pattern and not fnmatch.fnmatch(t["id"], pattern):
            continue
        tasks.append(t)
    return tasks
