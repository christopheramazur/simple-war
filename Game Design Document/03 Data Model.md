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
- **Stat registry:** derived from the schemas. Each stat has a glossary name, unit, rounding, min/max and scope (unit or squad). Every stat the rules use has a data field with a default; for example, a reaction's cost is `instinct_cost`.
- **Effect:** `op`, `target` (selector), `magnitude` (constant, or per stack plus a stack source), `condition`, `duration` (time, distance in hexes, or a campaign bank), `stacking` (refresh, stack, independent or strongest; per source or per target), `tags`, `source`. Optional flags such as `restores`.
- **Bundle:** a named list of effects. Statuses, items, traits, features, zone conditions and Ruin effects are bundles. Bundles are package templates: referenced by ID, inheritable, schema-validated.
- **Accumulator:** starting value, value, step size, counted event, threshold, reset condition.
- **Ability:** a bundle plus an activation: costs, cooldown, charges, ready time, range, targeting, toggle.
  - **Detection source** (R7Q4): radius; how Instinct affects it; Instinct sink per tick (0 means on by default).
  - **Concealment source** (R7Q4): how terrain traits, activities and Instinct affect it; Instinct sink per tick (0 means on by default).
  - **Readied state** (R7Q3, E3Q6): ready time; what the state does; how long it lasts; the conditions that lose it; Prowess Vacuum while readying.
  - **Auto-off defaults** (R8Q2): the band that breaks the effect (default Broken), plus player-overridable rules.
- **Tags:** a moddable registry with glossary entries.
- **Banks:** per profile and namespaced; cross-campaign reads are declared in the manifest.

## 3.5 Battle and campaign content
- **Scenario:** battlefield, deployment, zones, victory conditions, scoring mode (primary and tiebreaker), turn limit, and end-of-battle hooks (R7Q5, R7Q6).
- **Zone:** decay, threshold, buffer, scoring VP, and magic condition (Law, Ruined or Null) (R7Q5, R4Q21).
- **Hex feature:** activities, production output and options, sight radius, controllability, garrison or guard, and interaction kind (stable or uncertain) (R4Q12, R5Q10, R6Q14).
- **Map template:** seeded generation passes (R3Q13).
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
