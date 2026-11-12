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
| Size Class | |
| Movement Profile | Movement types and speeds, acceleration, deceleration, turning rate; feature cost tables (R6Q8) |
| Offensive Profile | Base proficiencies plus equipped weapon stats; fire modes, reload cycles (R6Q8) |
| Traits | |
| Equipment | Per-unit gear (R3Q7) |
| Tags | e.g. `leader` (R6Q5) |

## 3.3 Squad (command unit) (R5Q8)
| Field | Notes |
|---|---|
| SIMPL pools | Stamina, Instinct, Morale, Prowess, Legend. Each has a starting value, neutral value, drift rate and sensitivity profile; band ranges can be bespoke (R5Q3) |
| Total Hit Points | |
| Formation Profile | Formation, coherence, stance or mode |
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
- **Tags:** a moddable registry with glossary entries.
- **Banks:** per profile and namespaced; cross-campaign reads are declared in the manifest.

## 3.5 Battle and campaign content
- **Scenario:** battlefield, deployment, zones, victory conditions, scoring mode (primary and tiebreaker), turn limit, and end-of-battle hooks (R7Q5, R7Q6).
- **Zone:** decay, threshold, buffer, scoring VP, and magic condition (Law, Ruined or Null) (R7Q5, R4Q21).
- **Hex feature** (`hex_feature`): activities, production output and options, sight radius, controllability, garrison or guard, and interaction kind (stable or uncertain) (R4Q12, R5Q10, R6Q14).
  - **Fields:** `move_cost` (added to the map's base cost), `impassable`, `sight` (hexes), `controllable`, `interaction`, `activities` (refit, recruit, battle, convert), `value_per_turn`, `cache_value` (picked up once, then removed), `guard` (neutral squads), `activity_cost` (Value per activity), `converts_to` (required by the convert activity), `recruits` (squad and Value cost per option; goes with the recruit activity), `refit_cost` (Value per unit restored), `battlefield` (scenario its battles use), `bundles`.
  - **One of each per plot:** a plot holds any number of features but at most one instance of each template. Template IDs are global, so core hex features are prefixed `hex_`.
- **Commander** (`commander`): `movement_points` per turn (same units as move costs), `sight` (hexes), `squad` (its own squad in battles), `army` (starting squads besides its own), `army_cap` (squads besides its own, default 6), `tags`. Abilities and battleforces arrive with sw-o1m.2.
- **Battleforce preset** (`battleforce_preset`): `name`, `prefer` and `avoid` lists of squad features (legend archetype, doctrine, keywords) for auto-fill (R2Q1).
- **Map template** (`overworld_map`): seeded generation passes (R3Q13).
  - **Grid:** pointy-top hexes in a `width` × `height` rectangle of "odd-r" offset coordinates (`col`, `row`; odd rows shifted half a hex right). Maths runs in axial coordinates.
  - **Movement cost:** `base_move_cost` (default 10) plus the plot's feature costs, at least 1. Commanders' movement points use the same units.
  - **Passes**, in order: `fill`, `rect`, `place`, `line` (a hex line between two plots) and `scatter` (`count` seeded picks, with `avoid` features and `spacing`). `owner` pre-assigns a controllable feature.
  - **Battles:** `battle_scenario` is the default battlefield. A scenario used this way supplies terrain, zones, victory and two deployment areas; its listed squads are ignored.
  - **Battleforce caps:** `battleforce` (`squads`, default 4; `value`, the most total strength, 0 = no limit).
  - **Starts:** `starts` lists each player's starting commanders (`player`, `commander`, `col`, `row`). A match's players are those with a start or a pre-owned feature.
- **Campaign / mission:** missions, scripted triggers, story-essential commanders, carried armies (R2Q1, R2Q13).
- **Triggers:** the declarative trigger and effect layer, which covers about 90% of campaign scripting. Angel behaviour is data here (R6Q17).
- **Dialogue:** Dialogic is presentation only. Disposition and relationship state live in the sim (R3Q18).
- **Factions:** Humanity, with three splinters as a doctrine layer on a shared core roster (Humanity First, CHI, Enlightened); then Lawbringers (R5Q12, R5Q16, R1Q11).

## 3.6 Controller profiles (AI) (R7Q15)
A profile is data: a decision process + parameters + a fuzz seed.
- **Decision processes:** scripted order list, activity-preference weights (utility), rule-based, and later search.
- **Composition:** profiles can be layered, for example a scripted opening handing over to utility weights.

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
