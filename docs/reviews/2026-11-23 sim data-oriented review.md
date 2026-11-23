# Code-health review: src/sim, data-oriented convergence (sw-l4d)

Recorded 2026-11-23 on branch `autopilot/sw-l4d`. Scope: maintainability, performance, extensibility and readability of `src/sim` (13,729 lines in 109 files). This is a read-only review. No sim behaviour changed. The four candidate changes in the bead (one writer per column, typed inboxes, zones/players/ledger as tables, a stats system) are **not** implemented: the bead and decision E4Q1 say to decide them with the user first. Section 4 lists what the user needs to decide.

Evidence is by file and line on this branch. Line numbers may drift.

## 1. What is already sound

- **Column store.** `SoaTable` (`src/sim/core/soa_table.gd`) does what GDD 04 §4.2 asks: Packed integer columns, generational 64-bit IDs, a slot→row map, a free list and swap-remove. Columns are taken and put back, so writes stay in place and do not copy. Integer-only columns are asserted.
- **Determinism plumbing.** Every table, and both contexts, have `snapshot`, `restore` and `state_hash`. Overworld and battle hash their extra fields too (`overworld_state.gd:234`). Overworld hash coverage was checked field by field against `_snapshot_extra`: no gaps found.
- **Stats read path.** `battle/stats.gd` returns the base value with no allocation when no modifier exists (`squad_mods.is_empty()` early return). Traces are built only when the inspection window asks for them. Read-side effective values already exist, which is most of what the "stats system" candidate would add.
- **Layering.** `src/sim` has no Node or scene references. Only `triggers.gd` mentions `$`, and that is a string prefix, not a node path.

## 2. Findings

Ranked by how much they will hurt the next change, not by severity.

### F1. Writers are a comment convention, not an enforced rule (maintainability, high)

Six table headers say "Written only through X" (`battle_abilities.gd:5`, `battle_effects.gd:3`, `overworld_commanders.gd:3`, and three more). Nothing checks it. Column writes happen in **27 files** through `take_column`/`set_value` (`convoys.gd` alone has 23 sites). The `take_column`/`put_column` protocol also has to be remembered by every caller: forgetting `put_column` silently drops the column. A single writer per column would make ownership checkable, but it needs a rule the lint can read, such as "only a file listed in the table's header may call `take_column` for it". That is a design choice, not a refactor.

### F2. Adding one overworld field means four coordinated edits (maintainability, high)

`OverworldState` has 24 `var` fields. About 16 are Dictionaries or Arrays (`routes`, `convoy_routes`, `activities`, `drops`, `supply_lines`, `vars`, `fired`, `dialogues`, `value`, `offers`, `memory`, `teams`, `battleforces`, `presets`, `outcome`, `plot_features`). Each saved field must be touched in four places: the declaration, `_snapshot_extra` (line 193), `_restore_extra` (line 208) and `state_hash` (line 234). Nothing ties them together. The current code is correct, but forgetting one place gives a save that loads wrong, or a hash that misses a difference, and the tests would only catch it if a test covered that field. The "zones/players/ledger as tables" candidate fixes this for those fields by making them columns, which `SoaTable` already snapshots and hashes for free.

### F3. Dictionary-keyed modifier lookups in the stat read path (performance, medium)

`battle/stats.gd` keys modifiers by `squad ID → {stat → Array[StatModifier]}`. Every `_squad_mods`/`_unit_mods` call allocates a new `Array[StatModifier]` and copies into it (`stats.gd:76-89`). `restores()` builds two formatted string keys on each call (`stats.gd:63`: `"%s|%d|-1" % [...]`). Both run per stat read per tick once any modifier exists. The fix would be a per-stat column, or a modifier table, and that belongs to the stats-system candidate. It should be measured first (see section 4).

### F4. Three files per concept, with unclear names (readability, medium)

Each battle mechanic has a table, a logic module and a system, and the names do not say which is which:

- `battle_abilities.gd` (`BattleAbilities`, table) · `abilities.gd` (`Abilities`, logic) · `ability_system.gd` (`AbilitySystem`, 14-line wrapper that calls `Abilities.tick`).
- `battle_effects.gd` (`BattleEffects`, table) · `effects.gd` (`Effects`, logic) · `effect_system.gd` (`EffectSystem`, 127 lines).
- Overworld: `overworld_commanders.gd` (`OverworldCommanders`, table) · `commanders.gd` (`Commanders`, logic). The same pattern holds for squads, items, detachments and engagements.

The `*System` wrappers add a file and a name without adding a rule. A rename or a merge of each wrapper into its logic file would be a small, safe change. Deciding the naming scheme is a user call (the GDD does not fix one).

### F5. Large rule files (readability, low to medium)

`battle/battle_rules.gd` (822 lines, 29 functions) and `effects/data_schema.gd` (770) are the two largest. Neither is in the candidate list. They can be split by concern later, without changing their data shape.

### F6. Small documentation mistake (readability, low)

`soa_table.gd:188` holds the doc line "Feeds the table's full state (ID mapping and columns) into a hash." directly above `snapshot()`. That text belongs to `hash_into()` (`:225`). `snapshot()` has no doc line of its own. The fix is a two-line move. It is not done here because it is not part of the agreed scope, and it would be an unrequested edit to a file the candidate changes will rewrite anyway.

### F7. Event inboxes are one shared queue (extensibility, low)

`SimContext.events` is one `EventQueue` per context. Systems push events and later systems read them with `of_type()`, a linear scan (`event_queue.gd:29`). At today's scale that costs nothing, and the within-tick order is deterministic and tested. Typed inboxes would give owners a drain point and make "who consumes what" explicit. It is a real improvement, but not a bug, and the cost is a second event path that the replay log must still follow.

## 3. Candidate changes, assessed

| Candidate | Fixes | Cost and risk | Recommendation |
|---|---|---|---|
| One enforced writer per column | F1 | Touches 27 files. A lint rule is cheap; moving the writes is not. Risk is low if done table by table. | Start with a lint that checks the "Written only through" headers, with no code moved. |
| Typed event inboxes drained by owners | F7 | Changes the replay path and ordering. Medium risk to determinism tests. | Defer until a feature needs it. Not needed for maintainability now. |
| Zones / players / ledger into SoaTables | F2 | Ledger and zones are per-battle and per-overworld records; players and teams are small maps. Each move changes the save format, which needs a migration (`SoaTable.restore` already fills missing columns, sw-uyv). | Highest payoff for F2. Do one field group at a time, starting with `value` and `teams` (both simple maps). |
| Stats system owning effective values | F3 | Needs a benchmark first, because the current early return already makes the common case free. Changes the modifier shape that inspection reads. | Measure before deciding. The read path is correct today. |

Two smaller items do not need a decision and could be filed later as separate beads: F4's `*System` wrapper merges and F6's doc move.

## 4. Decisions needed from the user

1. **Which of the four candidates to pursue**, and in what order. The review suggests: lint for writers (F1), then the `OverworldState` field-group moves (F2), with the stats system only after a benchmark (F3).
2. **Naming scheme** for the table / logic / system triplets (F4): keep three names, or fold each system into its logic file.
3. **Save-format policy** for moving Dictionary fields into tables: is a migration step per change acceptable, or should the change wait for a save version bump?
4. **Benchmark target** for F3: which battle size (the research notes cite 600 units a side) should decide whether the stats path is worth a column rewrite.

No design decision here is settled by the GDD or `harness/DESIGN.md`; E4Q1 defers all four candidates.
