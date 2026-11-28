# Behaviour workshop scenarios

One file per scenario, `data/sim/workshop/<id>.json`: a hand-placed micro-battle that isolates one part of unit behaviour (targeting, closing to fire, spacing, fire modes, retargeting). The same file drives the API check (here) and the visual check (the workshop scene, U1 B7). GDD `05 Harness and AI Factory.md` §5.7; built in sw-tho3.3 (U1 B3).

- **Code:** `src/api/workshop/`: `WorkshopScenario` (load, validate, quantize), `WorkshopRun` (build and play one variant), `WorkshopProbes` (measure and check), `WorkshopReport` (grade, compare, report), `ScenarioBuilder` (placement, shared with the sim tests), `workshop_cli.gd`.
- **Gate:** `tests/sim/test_workshop_scenarios.gd` runs every file in this folder in `hx godot test`.
- **By hand:** `harness/bin/hx godot run res://src/api/workshop/workshop_cli.gd -- --scenario <id|all> [--variant <name>] [--json] [--verbose]`.

## How a run works

1. The package's battle scenario `map` is compiled. Its sides lose their squads, its score target is switched off, and its turn limit moves past `turns`, so only annihilation or withdrawal ends a run early (the report's `turns_run` says when). Its zones still exist and still score. With `"open": true` every cell becomes the package's `open` ground.
2. The squads are placed exactly where the file says, in file order, with `ScenarioBuilder.place` (a cell the squad cannot enter moves it to the nearest one it can, as in deployment). Dummies and patches are applied. Vision runs once, as a new battle session does.
3. Each turn, that turn's scripted orders are checked by `BattleOrders.validate` (the check `BattleSession.submit_orders` makes) and applied per player in player order (as the session's Reveal does). A rejected order is a run error. There is no reaction window.
4. Every tick, a read-only hook records a playback frame (`ReplayRecorder` format), the tick's events, per-squad firing duty, and a `BattleProbe` snapshot (viewer 0) every `probe_stride` ticks. Snapshots are also taken at every tick an `at` probe names, at the start, and after each turn resolves. Shot and hit traces are on; they are write-only and never hashed.
5. The state hash is taken after every turn. Same file, same variant and same data give the same hashes on every machine.

## Schema

All positions are metres; `at` is `[x, y]` with x east and y south. Unknown fields are errors.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `id` | string | required | Must match the file name. |
| `component` | string | required | What behaviour it isolates (free text, e.g. `fire`, `targeting`). |
| `doc` | string | — | What it shows and why. |
| `status` | `gate` \| `pending` \| `explore` | `gate` | See Status. |
| `package` | `rules-fixture` \| `core` | `rules-fixture` | Content. `rules-fixture` (frozen) for gates, `core` for feel work. |
| `map` | string | `duel_crossroads` | A battle scenario in the package: its map, ruleset, ticks per turn and sides (players) are used. |
| `open` | bool | false | Flatten the map to `open` ground. |
| `seed` | whole ≥ 0 | 1 | The battle seed. |
| `turns` | whole ≥ 1 | 1 | Turns to run. |
| `probe_stride` | whole ≥ 1 | 1 | A snapshot every N ticks (bounds the cost of long runs). Window probes do not need snapshots; they read frames and events. |
| `squads` | list | required | See Squads. |
| `script` | `{"<turn>": [order], "<turn>@<tick>": [order]}` | `{}` | Orders given at the start of that turn (`"1"`), or after `<tick>` ticks of it (`"1@50"`, 1 to ticks-1: a mid-turn order, as the Retarget reaction gives one). A turn with no entry gives no new orders (squads keep theirs). |
| `variants` | `{name: {script, patch, place, doc}}` | `{}` | See Variants. `base` is reserved: the file's own script, patches and placement. |
| `probes` | list | `[]` | See Probes. |
| `compare` | list | `[]` | See Compare. |

### Squads

`{"key", "player", "squad", "at", "facing", "dummy", "patch"}`

- `key`: the name orders, probes and patches use. `player`: a side of `map` (1, 2). `squad`: a squad template ID in the package.
- `facing`: degrees, 0 = east, 90 = south, 180 = west. Default 0.
- `dummy`: `{"armed": bool (default true; false takes every weapon away), "hp": number (every unit's HP and maximum), "stationary": bool (it takes no orders; scripting one is an error)}`.
- `patch`: `{stat: value}` set on placement. `hp` (every unit's HP and maximum), `ammo` (whole; every armed unit), `stamina`, `instinct`, `morale`, `prowess`, `legend` (the pool; the cap rises to it if needed). A patch applies after `dummy`.

### Orders

`BattleOrders` format with squad keys instead of IDs: `{"squad": key, "type": "hold"|"move"|"attack_move"|"attack"|"fall_back"|"withdraw", "x": m, "y": m, "target": key, "run": bool, "abilities": [...], "unchecked": bool}`. `attack` targets must be visible at the turn's start, as in a game (a mid-turn order is checked against the sight at its tick).

`unchecked: true` is for cross-checks only. It grants the target's sighting for that one check. 01's table B was measured by setting orders without the sight check; the table B scenarios use it for their attack-from-44 m column, where the assault squad does not see the dummy. No other order uses it.

### Variants

- `script`: each turn it names **replaces** that turn's base orders entirely. Turns it does not name keep the base orders.
- `patch`: `{squad key: {stat: value}}`, merged **shallowly** over that squad's base `patch`: stat by stat, the variant's value wins, other base stats stay. A variant cannot change a squad's `dummy` block.
- `place`: `{squad key: [x, y]}` moves a squad at the start (the table B scenarios use it: one squad, four starts).
- A turn a variant names replaces that turn's base orders, mid-turn ones included.

### Probes

`{"id", "at" | "over", "squad", "target", "<kind>": expectation, "pending", "variants", "doc"}`

- `id`: unique, no dots. Exactly one kind key; its value is the expectation (`null` = report the value only).
- `at`: `"end"` (the last frame), `"t<turn>"` (after the turn resolved), `"t<turn>:<tick>"` (after that tick of the turn, from 0).
- `over`: `"all"`, `"t<turn>"`, `"t<a>-t<b>"`, `"t<turn>:<k0>-<k1>"`. Both ends inclusive.
- `squad`: the squad measured (required). `target`: a squad key (required for `fire`, `distance`, `within`, `first_kill`, `mean_kill`, `wipe`, `waste`; a filter for `damage`, `dps`, `shots`, `kills`, `victims`; for `spacing`, the gap to that squad's units).
- `pending`: true makes this probe non-gating in a gate scenario.
- `variants`: the variants the expectation holds in: a list, or `"all"`. Default `["base"]`. The value is measured and reported in every variant either way (comparisons use it).

| Kind | When | Value | Expectation |
|---|---|---|---|
| `activity` | at | the squad's `BattleActivity.Squad` name (`IDLE`, `MOVING`, `CLOSING_IN`, `ENGAGED`, `READY`, `HOLDING`, `FALLING_BACK`, `WITHDRAWING`; `GONE` when out of action) | a name or a list of names |
| `hold` | at | `{reason: units}` over the squad's living units (`BattleActivity.Hold` names) | a name or list: every unit's reason must be in it |
| `fire` | at | `LineOfFire` code to the target: `SHOT`, `BLOCKED`, `OUT_OF_RANGE`, `MIN_RANGE`, `NO_TARGET` | a name or a list of names |
| `distance` | at | centroid to centroid, m | number |
| `within` | at | the target's centroid is inside the squad's longest living weapon range | true / false |
| `spacing` | at or over | the nearest two living units of the squad, m; with `target`, the nearest living unit of the squad to a living unit of the target (sw-txnj.12) (over: the window's minimum) | number |
| `damage` | over | HP dealt by the squad (`squad_damaged`) | number |
| `dps` | over | damage per second: damage × ticks per second ÷ ticks in the window | number |
| `shots` | over | shots fired (`squad_fired`) | number |
| `kills` | over | enemy units killed by the squad (`unit_killed`) | number |
| `duty` | over | share of armed living unit-ticks on which the unit fired (0..1; a weapon's cooldown caps it) | number |
| `victims` | over | `{distinct, max_per_victim, overkill}` from the shot trace: distinct units shot at, most shots at one, and hits that dealt nothing (the victim was already dead when the hit was applied that tick) | `{sub: number}` for any subset |
| `moved` | over | centroid displacement from just before the window to its last tick, m | number |
| `dps_engaged` | over | `dps` counted from the squad's first shot at the target (ticks before it are not in the denominator): the approach does not dilute it | number |
| `first_shot` | over | seconds from the window's first tick to the squad's first shot at the target (`null` when it never fires) | number |
| `shooters` | over | distinct living units that fired in the window (at the target when given) | number |
| `first_shot_ticks` | over | distinct ticks on which a unit fired its first shot in the window (1 is a lockstep volley) | number |
| `first_kill` | over | battle tick of the squad's first kill of `target` in the window; `null` when none (ticks, 0 = the first tick) | number |
| `mean_kill` | over | mean battle tick of the squad's kills of `target`, whole ticks, half up; `null` when none | number |
| `wipe` | over | battle tick of the squad's last kill of `target`, when no unit of `target` is alive at the window's last tick; else `null` | number |
| `waste` | over | share of the squad's raw queued damage on `target` that did not reduce HP: (raw − dealt) ÷ raw, mitigation included (0..1) | number |

A number expectation is either a number (equal after quantizing) or `{"min": a, "max": b}` (either end optional, inclusive).

### Compare

`{"metric", "lhs", "rhs", "rel", "factor", "pending", "doc"}`: passes when `value(lhs) rel factor × value(rhs)`.

- `metric`: a numeric probe's id; for a `victims` probe, `<id>.distinct`, `<id>.max_per_victim` or `<id>.overkill`.
- `lhs`, `rhs`: variant names (`base` included). `rel`: `>=` (default), `<=`, `>`, `<`, `==`. `factor`: number, default 1.
- Graded like a probe: gating in a gate scenario unless `pending`.

## Status

- `gate`: its probes and comparisons must pass; a miss fails `hx godot test` and `workshop_cli` exits 1.
- `pending`: behaviour the owner wants but the game does not do yet. Every check is reported, none fails. A check that passes is reported as **unexpected pass**: time to promote it to `gate`. (One `pending: true` probe in a gate scenario works the same way.)
- `explore`: no probes allowed; for watching only. Its runs still have to load and play.

## Fixed point

The sim never sees a float. Every decimal in a file is quantized once, on load, by one rule:

1. **To thousandths:** `milli = round(v × 1000)`, ties away from zero (the only float step: one IEEE multiply and a round, the same on every machine).
2. **To fixed** (positions, order points, `hp`, pools): `Fixed.round_div(milli × Fixed.ONE, 1000)`.
3. **Angles** (`facing`): `Fixed.round_div(posmod(milli, 360000) × Fixed.ANGLE_FULL, 360000)`.
4. **Probe bounds and compare factors** stay in thousandths, the unit every probe value is measured in (metres, HP, counts, shares, per-second rates). Comparisons are integer: `lhs × 1000 rel factor × rhs`.

So `70.0004` is `70.000`, and the same file gives the same hash everywhere. `ammo` must be whole.

## Runs and exit codes

`workshop_cli.gd -- --scenario <id|path|all> [--variant <name>] [--json] [--verbose]`

- Text: one header line per scenario (`PASS|FAIL|ERROR <id> [<status>] <variant> <hash prefix>, ...`), then one line per probe or comparison that is not a plain pass (`--verbose`: all of them).
- `--variant` runs only that variant; comparisons that need another one are skipped.
- **Exit code:** 0 when every scenario passed its gate checks; 1 when any gate check failed, or any scenario could not load or run (a broken file is a bug, whatever its status); 2 on bad arguments. Pending checks never change it.

## `--json` schema (frozen; version 1)

Printed as one line between `WORKSHOP_JSON_BEGIN` and `WORKSHOP_JSON_END`. Any change to the shape bumps `WorkshopReport.SCHEMA`; the `hx workshop` verb (U1 B5) tests against this.

```json
{
  "schema": 1,
  "ok": true,
  "scenarios": [{
    "schema": 1,
    "scenario": "rifle_vs_dummy", "path": "res://data/sim/workshop/rifle_vs_dummy.json",
    "component": "fire", "status": "gate", "doc": "...",
    "package": "rules-fixture", "data_hash": "<sha256 of the content package>",
    "engine": "4.7.2-stable (official)", "map": "duel_crossroads", "open": true,
    "seed": 1, "turns": 2, "probe_stride": 1,
    "result": "pass",
    "gate_failures": 0, "pending": 0, "unexpected_passes": 0,
    "errors": [],
    "variants": [{
      "name": "base", "hash": "<sha256 state hash at the end>", "turn_hashes": ["<after turn 1>", "..."],
      "turns_run": 2, "frames": 203, "errors": [],
      "probes": [{
        "id": "duty", "kind": "duty", "squad": "rifles", "target": "",
        "when": "over t1:0-t1:end", "value": 0.1, "expect": {"min": 0.09},
        "result": "pass", "error": ""
      }]
    }],
    "compare": [{
      "metric": "duty", "lhs": "base", "rhs": "run_away", "rel": ">", "factor": 2.0,
      "lhs_value": 0.1, "rhs_value": 0.03, "result": "pass"
    }]
  }]
}
```

- `result` (scenario): `pass`, `fail` (a gate check failed) or `error` (did not load or run; `errors` says why, as `<file>: <field path>: <problem>`).
- `result` (probe, comparison): `pass`, `fail`, `error` (gate checks); `pending`, `unexpected_pass` (non-gate checks); `report` (no expectation, or a variant its expectation does not cover).
- `value`: numbers as decimals (3 places); `activity` and `fire` a name; `within` a bool; `hold` `{reason: units}`; `victims` `{distinct, max_per_victim, overkill}`; `null` when not measurable (`error` says why). `expect` is `null` when the probe only reports; ranges are `{"min", "max"}`, names a list.
- `data_hash` identifies the content package and `engine` the Godot build, so two reports are comparable only when both match.

## Examples

- `rifle_vs_dummy` (gate): a rifle squad against an unarmed, unkillable dummy; variants `run_away` and `tough_dummy`; every probe kind that reads one squad.
- `rifles_kill_unarmed` (gate): two rifle squads kill an unarmed squad; kills, victims and overkill; a `pending` probe that wants wider fire spread.
- `dps_orders` (gate, sw-tho3.4): 01 table A's start (44 m) for the rifles under attack, attack-move, move-then-attack, run and move-then-hold; `dps_engaged`, `damage`, `duty` each within 0.9 of `attack`.
- `dps_retarget` (gate): two stacked dummies; turn-boundary switch from A to B (`retarget`: turn-2 damage within 0.9 of the constant target); mid-turn switch 5 s into turn 1 (`retarget_mid`: total damage within 0.9 of the constant target, measured +1%; the first shot at B follows at once).
- `overkill_killable` (gate, sw-tho3.4): 8 rifles against 8 killable dummies (6 HP each): every dummy dies; victims and overkill reported (overkill is 0 in both variants).
- `table_b_assault`, `table_b_heavy_weapons`, `table_b_rocket_team` (gate, core, sw-tho3.4): 01 table B's twelve cells (hold at 12 m, move from 60 m, attack-move from 60 m, attack from 44 m, DPS1), each within 5% of the table. Pinned to current behaviour: A3 changes them on purpose.
- `fire_modes_moving` (gate): standing fire against moving fire over 35 m; moving keeps at least 0.85 of standing `dps_engaged`.
- `attack_move_firing_position` (pending, U1Q11/U1Q29): per-unit firing positions by the turn's end. At its geometry every unit already fires, so the checks report an unexpected pass: the geometry does not separate the old and new behaviour yet.
- `staggered_opening` (pending, U1Q28): first-shot ticks across the squad; today one tick (lockstep).
- `mixed_range_orders` (pending, core): 01 table B's assault squad under attack-move, move, attack and hold-at-12 m; the pending compare is B3's acceptance (attack-move at least 0.9 of hold).
- `mixed_range_hold` (pending, core): table B's hold column with the table's own placement (12 m, holding from the start); reproduces 6.7.
- `fire_range_rifle_rifle`, `fire_range_hwt_rifle`, `fire_range_marksman_scout`, `fire_range_mortar_rifle`, `fire_range_rifle_chi` (gate, rules-fixture, U1 D2): the draft 04 §1.3 fire-range matchups under today's picker, shooters on HOLD in line, 30 m (40 m marksman, 36 m mortar), passive no_armour targets (`bare_*` templates in `tests/fixtures/rules/defs/workshop.json`; CHI keeps its carapace). `first_kill`, `mean_kill`, `wipe` and `waste` are pinned to the draft's numbers. `fire_range_rifle_rifle` also has an `attack_move` variant (shooters start 30 m west and attack-move in): its numbers are reported, not pinned, and `am_first_shot_ticks` shows the opening is still lockstep (1 tick).
- `focus_fire_spread` (gate, U1 D2): one rifle squad against two killable squads; pins the current pick (prey_a first: first kill tick 10, wiped at 60; then prey_b: 80 and 130) and overkill 4. The focus policy changes these on purpose.
- `separation_clump` (gate, sw-txnj.12): two squads ordered onto one point; the `spacing` probe with a `target` pins the gap between their units at the size-class distance (0.6 m medium) over the settled turn and at the end, 0.3 m while arriving.
