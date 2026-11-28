# 3. Data Model

Gameplay lives in data, never in scenes (AGENTS.md §5). Official content ships in the same package format as mods (R6Q26). The old `data/defaults/*.json` is archived in `History/data/defaults/`. It used the factions Human, Xenos, Chaos and "Concord", none of which match the setting, and its item IDs dangled. It gets rebuilt from this model: the Humanity Duel roster first, then Angelfall content (R8Q12).

## 3.1 Archetype templates (R5Q17, R6Q18)
- **What an archetype is:** a template, the designer's sense of the word ("an infantry archetype with x variants"). It is not an ECS storage table.
- **Inheritance:** a template has a parent plus overrides, at most **3 levels deep**. Cycles are checked.
- **Load and spawn:** at load, every template is flattened into an immutable template table that records provenance (where each value came from). At spawn, the values are **copied** into the runtime stores. There is no live inheritance.
- **Library:** a repository of archetypes is a goal in its own right, used both for composition and for communication.

## 3.2 Unit (per model) (R5Q8)
| Field | Notes |
|---|---|
| Hit Points | Base HP; temporary HP is a separate layer |
| Defensive Profile | Evasion, Block (chance + amount), Resistances, Flat DR, % DR, Floor per damage type, healing and Absorption, other typical stats (R5Q7, R7Q1) |
| Size Class | `small`, `medium` (default), `large`, `huge`. Sets the unit's separation radius (ruleset `separation_m`; 0.4, 0.6, 1.2, 2.4 m; Rules Spec §2.14 Separation and coherency) |
| Movement Profile | Movement types and speeds, acceleration, deceleration, turning rate; feature cost tables (R6Q8) |
| Offensive Profile | Base proficiencies plus equipped weapon stats; fire modes, reload cycles (R6Q8) |
| Traits | |
| Equipment | Per-unit gear (R3Q7); items in War Chests override a unit's weapon or defense, or add bundles |
| Tags | e.g. `leader` (R6Q5) |

## 3.3 Squad (command unit) (R5Q8)
| Field | Notes |
|---|---|
| SIMPL pools | Stamina, Instinct, Morale, Prowess, Legend. Each has a starting value, neutral value, drift rate and sensitivity profile; band ranges can be bespoke (R5Q3) |
| Total Hit Points | |
| Formation Profile | Formation, coherence, stance or mode. Spacing (proposed, U1Q10), and a coherency radius per formation (U1Q29; default proposed: half-width + 4 m) that bounds units' firing positions (Rules Spec §2.15) |
| Behaviours | `behaviours`: per battle order (`hold`, `move`, `attack_move`, `attack`, `fall_back`, `withdraw`), a behaviour template ID (Rules Spec §2.15; U1Q12, built sw-txnj.9). Inherited and merged like any map. Unset orders, and components a behaviour leaves out, use the default behaviour (today's closing to fire); core `humanity_squad` names `line_attack_move` and `line_attack` |
| Fire discipline | Proposed (U1Q17): `fire.discipline_pct` (default 60) and `fire.coordination_pct` (default 70); squad stats `squad.fire.discipline_pct`, `squad.fire.coordination_pct` (Rules Spec §2.8 Prowess) |
| Keywords | Static (R6Q9) |
| Statuses | Transient, produced by the effect language (R6Q9) |
| Value | Recruitment and scoring value; may later split battleforce value from purchase value (R6Q15) |
| Capture Rate | Contesting objectives; human infantry default 10 (R6Q10) |
| Abilities | Including Detection and Concealment sources, readying behaviours |
| Units | Composition; a `leader`-tagged unit is validated at instantiation (R6Q5) |

**Retired:** the old Statline, `weapon_skill` and Baseline Competence (R3Q7, R5Q8).

## 3.4 Effects, bundles and abilities (§2.13)
- **Stat registry:** derived from the schemas. Each stat has a glossary name, unit, rounding, min/max and scope (unit or squad). Every stat the rules use has a data field with a default; for example, a reaction's cost is the ability's `activation.costs.instinct` (stat `ability.activation.costs.instinct`).
- **Effect:** `op`, `target` (selector), `magnitude` (constant, or per stack plus a stack source), `condition`, `duration` (time, distance in hexes, or a campaign bank), `stacking` (refresh, stack, independent or strongest; per source or per target), `tags`, `source`. Optional flags such as `restores`.
- **Bundle:** a named list of effects. Statuses, items, traits, features, zone conditions and Ruin effects are bundles. Bundles are package templates: referenced by ID, inheritable, schema-validated.
- **Accumulator:** starting value, value, step size, counted event, threshold, reset condition.
- **Ability:** a bundle plus an activation: costs, cooldown, charges, ready time, range, targeting, toggle.
  - **Activation fields:**
    - `timing`: order or reaction.
    - Costs: `costs` (per pool, paid on use) and `upkeep_per_s` (per pool, while a toggle is on).
    - `auto_off_band`.
    - Limits: `cooldown_s`, `charges`.
    - Readying: `ready_s`, `readying_prowess_per_s`, `lose_on`.
    - Targeting: `range`, `targeting` (none, self or squad; point is not supported yet), `toggle`.
  - **Detection source** (R7Q4): a toggle whose bundle raises the squad stat `detection_radius`. Instinct efficacy scales the radius. Zero upkeep means it is on by default.
  - **Concealment source** (R7Q4): a toggle whose bundle raises the squad stat `concealment_pct`. Terrain uses the `on_feature` condition; activities use the `moving` and `firing` conditions. Instinct shifts the result. Zero upkeep means it is on by default.
  - **Reactions:** abilities with reaction timing. Their bundles use the `order` operation (hold, fall_back or attack).
  - **Readied state** (R7Q3, E3Q6): ready time; what the state does; how long it lasts; the conditions that lose it; Prowess Vacuum while readying.
  - **Auto-off defaults** (R8Q2): the band that breaks the effect (default Broken), plus player-overridable rules.
- **Behaviour** (`kind: "behaviour"`, U1Q12, U1Q29; built sw-txnj.9): `{"name": ..., "text": ..., "components": [{"c": "firing_position", "extra_m": 3, "stand_off_m": 5}, {"c": "leash", "chase_m": 25}, ...]}`. Components come from the closed vocabulary in Rules Spec §2.15 (`DataSchema.BEHAVIOUR_COMPONENTS`): `firing_position(coherency_m | extra_m, stand_off_m, cadence_ticks, hysteresis_s)`, `keep_distance(min_m, max_m)`, `leash(chase_m)`, `fire_on_move(allow)`, `stand_while(firing, reloading)`, `separate(radius_m)`. An unknown component, an unknown parameter, a wrong type, a repeated component, `coherency_m` with `extra_m`, or `min_m` above `max_m` fails package validation. `BattleRules` compiles them to packed `bh_*` arrays indexed by squad template × order (`bh_at`); a parameter left out takes the default.
- **Ruleset `fire` block** (U1Q15; proposed): `"fire": {"policy": "nearest", "discipline_pct": 60, "coordination_pct": 70}` in the `standard` ruleset. The policy is `nearest` today and has no data field yet; the proposed ids are `nearest` (today's) and `prowess` (Rules Spec §2.8 Prowess). The default stays `nearest` until the Pressure Lab sweep (D6), then switches to `prowess` in one commit with a new baseline era (D7) (U1Q33). Squad templates override the two percentages. The per-unit accumulators `acc_focus` and `acc_coord` (beside `acc_hit`) are runtime state, not data.
- **Tags:** a moddable registry with glossary entries.
- **Banks:** per profile and namespaced; cross-campaign reads are declared in the manifest.

## 3.5 Battle and campaign content
- **Scenario:** battlefield, deployment, zones, victory conditions, scoring mode (primary and tiebreaker), turn limit, and end-of-battle hooks (R7Q5, R7Q6).
  - **Deployment** (U1Q9, U1Q30, U1Q31; Rules Spec §2.4 Deployment): `deployment` is `open` (default: sides place their squads in their areas before turn 1) or `fixed` (no deployment step) (U1Q30). Each side's `deploy` rectangle is where it may place.
  - **Placed squads** (U1Q31, sw-tdz):
    - **Storage:** the scenario's `placed` list, entries `{side, squad, x, y, facing?}`; `facing` defaults to the side's.
    - **Inside the area:** a placed point must lie inside its side's deployment area.
    - **Dealing:** unplaced squads deal evenly over the rest of the area; placed ones go to their cell, or the nearest one they can enter.
    - **Overworld battles** ignore `placed` (a map's `battle_scenario` lends terrain, zones and areas only).
    - **Planner:** the AI planner reads positions from the battle state after deployment, not from `placed`.
    - **Validation:** two entries on one cell, or a squad placed twice, are refused.
    - **Defaults, not pins:** placed entries are the squads' automatic places, which the player may move in deployment; `locked: true` pins one.
- **Zone:** decay, threshold, buffer, scoring VP, and magic condition (Law, Ruined or Null) (R7Q5, R4Q21).
- **Hex feature** (`hex_feature`): activities, production output and options, sight radius, controllability, garrison or guard, and interaction kind (stable or uncertain) (R4Q12, R5Q10, R6Q14).
  - **Fields:** `move_cost` (added to the map's base cost), `impassable`, `sight` (hexes), `controllable`, `interaction`, `activities` (refit, recruit, battle, convert, hire), `value_per_turn`, `cache_value` (picked up once, then removed), `guard` (neutral squads), `activity_cost` (Value per activity), `converts_to` (required by the convert activity), `recruits` (squad and Value cost per option; goes with the recruit activity), `hires` (commander template and Value cost per option; goes with the hire activity: the new commander arrives on the hex with its own squad and starting army, sw-kys.2), `refit_cost` (Value per unit restored), `produces` (a squad or an `item` with a `count`, `turns` per batch, Value `cost`; the owner selects one), `dispersal_turns` (a guard a commander with no battleforce disperses for this many turns; 0 = never), `choices` (answers to its offer), `items` (an item cache: item and `count` pairs, picked up once, then removed), `battlefield` (scenario its battles use), `bundles`.
  - **One of each per plot:** a plot holds any number of features but at most one instance of each template. Template IDs are global, so core hex features are prefixed `hex_`.
  - **Proposed fields (Round U1, awaiting review):**
    - **Drawing only** (U1Q20–U1Q22; the rules never read them): `layer` (`ground`, `path` or `site`; default `site`), `draw_order` (int, ground and path stacking; default 0), `layout_priority` (int; sites with higher values take the first slots; default 0), `connects` (hex features a path joins besides itself; empty = only itself), `color` (six hex digits; the war room's hex colours, new with the hex view).
    - **Owner actions** (U1Q24): `owner_actions` (a closed list: `buy`, `rally`, `output`; default `["rally", "output"]` for features with `produces`, else empty), `sells` (item options: `item`, `count`, `cost`), `remote_markup` (percent added to a remote buy; default 25), `purchases_per_turn` (default 1).
    - **Sight** (U1Q26): `sight` counts hexes beyond its own hex (default 0 = its own hex only). It counts only while the feature is owned.
- **Commander** (`commander`): `movement_points` per turn (same units as move costs), `sight` (hexes), `squad` (its own squad in battles), `army` (starting squads besides its own), `army_cap` (squads besides its own, default 6), `tags`, `icon`. Abilities and battleforces arrive with sw-o1m.2.
- **Band** (`band`, U1Q27; sw-63wt.2): the kinds of commander-less squad groups. A package without the two core kinds gets them built in (garrison sight 1, caravan sight 3, both 30 points).
  - **Fields:** `name`, `sight` (hexes), `movement_points` (per turn, the same units as move costs), `payload_stats` (which overworld stats its payload may raise: `sight`, `movement_points`), `caps` (stat → most its payload may add), `icon`.
  - **Core kinds:** `band_garrison` (sight 1, 30 points, payload raises nothing) and `band_caravan` (sight 3, 30 points, payload raises `sight`, cap +2).
  - **Overrides:** a map's `detachment_sight` and `convoy_movement` still override the garrison's sight and the caravan's movement points when set (older maps).
- **Overworld contributions** (`overworld` on a squad or an item, U1Q27; proposed): stat → amount, e.g. `{"sight": 1}`. A band whose kind lists the stat in `payload_stats` adds the contributions of its squads and their equipped items, summed in squad-ID order and capped by its `caps`. Chest items carry nothing. Core data: `scout_team` and `marksman_team` carry `{"sight": 1}`.
- **Item** (`item`, R3Q7, R4Q10): `name`, `text`, `icon`, `tags`, `value`, and one slot: `weapon` (replaces the unit's), `defense` (replaces the unit's) or neither (a kit). `bundles` apply to the carrying unit. `fits` lists unit template IDs, unit tags or squad factions that may carry it (empty = any).
- **Term** (`term`, GDD 07): `name`, `text` (English fallbacks for `term.<id>.name` / `.text`), `category`, `aliases`, `see`, `decisions`, `context` (`stat:<id>`, `pool:<name>`, `bad_hit`, `band`, `units`) and `lower_is_better`. The source of glossary tooltips.
- **Battleforce preset** (`battleforce_preset`): `name`, `prefer` and `avoid` lists of squad features (legend archetype, doctrine, keywords) for auto-fill (R2Q1).
- **Map template** (`overworld_map`): seeded generation passes (R3Q13).
  - **Grid:** pointy-top hexes in a `width` × `height` rectangle of "odd-r" offset coordinates (`col`, `row`; odd rows shifted half a hex right). Maths runs in axial coordinates.
  - **Movement cost:** `base_move_cost` (default 10) plus the plot's feature costs, at least 1. Commanders' movement points use the same units.
  - **Passes**, in order: `fill`, `rect`, `place`, `line` (a hex line between two plots) and `scatter` (`count` seeded picks, with `avoid` features and `spacing`). `owner` pre-assigns a controllable feature.
  - **Battles:** `battle_scenario` is the default battlefield. A scenario used this way supplies terrain, zones, victory and two deployment areas; its listed squads are ignored.
  - **Battleforce caps:** `battleforce` (`squads`, default 4; `value`, the most total strength, 0 = no limit).
  - **Bands:** `detachment_sight` and `convoy_movement` are optional overrides of the `band_garrison` sight and the `band_caravan` movement points (unset = the band template's; the core template defaults are 1 and 30).
  - **Site placement** (U1Q21; proposed, Round U1, awaiting review): a `place` pass may carry `at`, `[x, y]` in thousandths of the hex radius from its centre (y down, each within −700..700). It pins that site there instead of its slot. On a mirror map the partner's `at` is negated (a half turn). Drawing only.
  - **Win condition:** `elimination` (default false) makes the map a skirmish. When every commander of all teams but one has been defeated, that team wins; if the last commanders of every team fall together, the game is a draw. The outcome reads from player 1's view (won, lost or drew) and names its `winner` (0 for a draw). Story maps end through their triggers' `end_mission` instead.
  - **Mirror maps:** `mirror` (default false) makes a fair two-player map. Every pass except `fill`, and every start, is repeated on the hex rotated 180°, with players 1 and 2 swapped, so authors write one half. A scatter's `count` is per side. The height must be even, which makes the rotation an exact hex symmetry (distances are preserved).
  - **Starts:** `starts` lists each player's starting commanders (`player`, `commander`, `col`, `row`). A match's players are those with a start or a pre-owned feature.
- **Battle map** (`battle_map`, O1Q5 as revised by O1Q11; in play, sw-ll4.2): a battlefield, separate from the scenario so one map serves several scenarios. It is an ordered list of shapes with explicit coordinates, the same idea as the overworld's passes, so an empty map is valid and every entry can carry its own properties.
  - **Size and base:** `width` × `height` in 1-metre cells, origin top-left, `y` down. `base` is the feature every cell starts as.
  - **Art (sw-kys.3):** drawing-only fields naming a package asset (`"pkg:id"`, or a bare id: the last package in load order with it wins). `icon` on units, squads, commanders and hex features; `tile` on hex features (the hex's ground, clipped to the hex); `texture` on battle terrain features (tiled, a few pixels a metre). An unknown asset is a load error. Art without a field falls back to colours. Package art stays raw files (`.gdignore`), loaded by PackageLoader, never imported as Godot resources.
  - **Feature colour:** a feature's optional `color` (six hex digits, like `4a4840`) is what the map editor draws it in. It has no effect on rules. The war room still uses its own colour table (sw-ll4.8 moves it to this field).
  - **Cells:** `cells` is a list applied in order; a later entry overwrites an earlier one where they overlap. Each entry has `x`, `y` and optional `w`, `h` (default 1), and is one of:
    - **A fill:** `feature` (a feature ID) painted over the rectangle. Optional `facing` (`n`, `e`, `s`, `w`) is stored per cell.
    - **A stamp:** `stamp` names another `battle_map`, placed with its top-left corner at `x`, `y` and turned by `rotate` (0, 90, 180 or 270, clockwise). Only the cells the stamped map's own entries paint are copied; its `base` is not. Facings turn with it. Stamps nest three deep. A building is a small map: floor, walls, doors.
  - **One feature per cell** in v1. Shapes clip at the map edge. Elevation and a second, structure layer are reserved (Rules Spec §2.14).
  - **Facing** is data the rules don't read yet: it is there for drawing and for later rules (doors, directional cover). Whether a wall or road piece is straight, a corner or an end is not authored: it follows from its neighbours (a feature's `connects` list of other feature IDs it joins besides itself, drawing only; `ConnectShape`, sw-96x).
  - **Why a shape list, not painted rows** (O1Q11): properties ride on the entry, so there's no `door_left` and `door_right` in a palette; composition by stamps replaces long palettes; a sparse map stays short; and it extends the rectangle list scenarios already used. The cost is that the file doesn't look like the map, which the editor's view covers. The editor saves painted cells as merged rectangles, in a fixed order, so files diff.
  - **Scenario use:** a scenario names its `map` and then leaves out `width`, `height` and `terrain_default`. Its own `terrain` rectangles are applied after the map, for changes one scenario needs. A scenario with no `map` works as before. Zones, deployment areas, placed squads (`placed`, §3.5 Scenario, U1Q31) and triggers stay in the scenario.
- **Authored overworld maps** (O1Q5 as revised): no new format. `passes` are already a shape list (`fill`, `rect`, `line`, `place` with `owner`), so the editor writes passes. A map with no `scatter` pass is fully authored.
- **Campaign / mission:** missions, scripted triggers, story-essential commanders, carried armies (R2Q1, R2Q13).
- **Triggers:** the declarative trigger and effect layer, which covers about 90% of campaign scripting. Angel behaviour is data here (R6Q17).
  - **In play (sw-cgl.2):** a `trigger` template has `on` (an event type, or `turn_resolved`), `where` (event fields to match, with `col` + `row` matching the event's plot), `if` (checks, each optionally `not`), `do` (actions) and `max_fires` (default 1; 0 = unlimited).
  - **Attached to:** an `overworld_map` and a `scenario` each list their `triggers`. They run at the end of each overworld turn and each battle turn, in ID order per event.
  - **Checks:**
    - **Any context:** `var`, `turn`, `fired`, `any` (one of `of`). Comparisons use `op` (==, !=, <, <=, >, >=) against `value`.
    - **Overworld:** `value`, `owns`, `feature_at`, `commander_at` (commanders on col,row, optionally of a `player` / `commander` template).
    - **Battle:** `zone_owner`, `zone_locked`.
  - **Actions:**
    - **Any context:** `set_var`, `add_var`, `message` (a translation `key` with `text` fallback, to a `player` or 0 = all).
    - **Overworld:** `add_value`, `add_feature`, `remove_feature`, `spawn_commander`, `give_squad`, `give_item` (to a `target` commander ID, or the `player`'s commander on col,row; `give_squad` respects the army cap), `start_engagement` (col,row).
    - **Battle:** `unlock_zone`, `lock_zone`, `end_battle`, `apply_bundle` (`bundle`; every squad, or of a `player` and/or `squad` template), `reveal_area` (`player`, `x`, `y`, `radius` in cells, `turns`; 0 = permanent; squads inside count as seen).
  - **Using the event:** a `"$field"` value reads the triggering event's data, e.g. `"player": "$player"`.
  - **Editor vocabulary** (O1Q7, sw-ll4.5). The vocabulary stays closed and engine-provided; it grows to what a custom-map author needs:
    - **Built (battle actions):** `spawn_squad` (squad, player, optional x/y in cells, else the middle of the player's deployment area), `remove_squad` (every living squad of a template for a player), `order_squad` (hold, move, attack_move, fall_back or withdraw, validated like a player's order), `add_score` (value or influence). **Built (overworld action):** `set_owner` (a feature at a plot).
    - **Built (battle checks):** `squad_alive`, `strength` (a side's living units), `squads_in_zone`.
    - **Built (timers):** `after_turns` on a trigger delays its actions by whole turns, as a `~due.<trigger>.<n>` state variable (so it is saved and hashed). `"$field"` values read as their defaults when the delayed actions run.
    - **Still to build:** `apply_bundle`, `reveal_area`, and the overworld `spawn_commander`, `give_squad`, `give_item`, `start_engagement`, plus the `commander_at` check.
  - **No chains:** triggers see only their own step's events, not the ones their actions make.
  - **State:** variables and fire counts live in the state, so they're saved, hashed and replayed.
  - **Locked zones:** a scenario zone can start `locked`. A locked zone neither accrues influence nor scores until a trigger unlocks it.
  - **Offers:** uncertain features take `choices` (default accept, decline). The session's `answer_offer(player, feature, choice)` emits `offer_answered`, which triggers handle.
  - **Examples in the data:** the `trigger_vale` map (Angels gather, the shrine's blessing, a capture reward) and the `hangar_drill` scenario.
- **Dialogue:** Dialogic is presentation only. Disposition and relationship state live in the sim (R3Q18).
- **Factions:** Humanity, with three splinters as a doctrine layer on a shared core roster (Humanity First, CHI, Enlightened); then Lawbringers (R5Q12, R5Q16, R1Q11).
- **Hex layout table** (`data/ui/hex_layout.json`, U1Q21–U1Q22; proposed, Round U1, awaiting review): UI data like `styles.json`, not a package template.
  - **Slots:** the slot points for 1–7 sites, in thousandths of the hex radius, and the site radius.
  - **Roads:** the road half-width, the group shift and scale on a road hex, and the clearance a pushed site keeps.
  - **Movers:** the lane where commanders and bands stand.
  - **Labels:** the zoom bands where labels appear.

## 3.6 Controller profiles (AI) (R7Q15)
A profile is data: a decision process + parameters + a fuzz seed.
- **Decision processes:** scripted order list, activity-preference weights (utility), rule-based, and later search.
- **Composition:** profiles can be layered, for example a scripted opening handing over to utility weights.
- **In play (sw-884.3):** the `controller_profile` kind (`data/packages/core/defs/profiles.json`), played by `ProfileController`.
  - **Layers:** `overworld` and `battle` sections, each a `process` (utility, expand, zone, evacuation, scripted, idle) with `params`. A missing section gets its default, so every profile plays both layers (A2Q5).
  - **Opening:** a scripted section's `then` names the section that takes over after its last step.
  - **Mask:** criterion → {`base`, `gates`}, the fitness spec's shaping format. Without one, the profile sees the default fitness shaping.
  - **Other fields:** `hold_turns`; `fuzz`, a percent of the best candidate's score; `fuzz_seed`; `think_ms`, the per-decision limit, default 2000.
  - **Numbers:** fractional values are decimal strings, as in all package data.
  - **Factory genomes:** the same fields as plain data (a variant's `genome`).

See [Harness and AI Factory](05%20Harness%20and%20AI%20Factory.md).

## 3.7 Mod packages (R6Q25, R6Q26)
- **v1 contents:** data plus assets. Each package has a manifest, schema validation and declared dependencies and load order. The game uses its own asset loader, not `.pck` files, because `.pck` files can contain scripts.
- **Patching:** data packages patch through parent/override rules. The merged data is hashed.
- **"Play with Mods" mode:** separate saves, no achievements, no ranked. Replays record the mod list.
- **Later:** Lua 5.4 scripting behind an opt-in, with instruction budgets and a declared serialisable store (see research notes).
- **Never:** executing untrusted `.gd` from mods.

## 3.8 Persisted formats (R8Q5)
- **Save:** a versioned snapshot of every state store at a pulse boundary, plus the mod list, the data hash and the input/telemetry log. A save can be rebuilt by re-simulation if the snapshot is damaged. It never contains Nodes.
- **Replay:** the initial snapshot plus the input log.
- **Harness results:** stored in DuckDB (R5Q21).
