# PoC Audit vs Current `src/`

## Scope

This audit maps `Game Design Document/PoC.md` requirements to the current Godot `src/` implementation after the refactor baseline.

## Findings

- Existing codebase content under `src/` had been removed, leaving only `src/README.md`.
- Data JSON files in `data/` remain present and reusable (`Units.json`, `Models.json`, `Items.json`, `Attacks.json`, `Scenarios.json`).
- New baseline scenes and scripts now exist for:
  - Main Menu (`Quick Play`, `Quit Game`)
  - Campaign Planning
  - Sector Map with Armybuilding/Battle progression gate
  - Armybuilding selection (Militia)
  - Battle Planning
  - Battlefield with deployment, engagement, movement previews, and simple enemy behavior

## Reuse Opportunities

- Keep using `data/*.json` as source-of-truth content assets.
- Incrementally migrate JSON fields into ECS-like runtime Components.
- Reuse battle system modules as scaffolding:
  - `movement_system.gd`
  - `deployment_system.gd`
  - `combat_system_minimal.gd`
  - `battle_state.gd`

## Missing/Partial vs PoC

- Campaign map interaction is simplified to button flow; right-click menus and all alternate controls are not fully implemented yet.
- Battlefield deployment currently places units in a minimal way; drag-select/multi-select deployment is partial.
- Full order taxonomy (Advance/Run/Charge/etc.) is not yet modeled; engagement currently uses destination movement + minimal ranged attack.
- Battle scoring/audit is minimal (destroyed counts) and not yet a full audit ledger.
- No dedicated ralph-tui adapter yet; this pass focuses on deterministic runtime scaffolding and bead-driven milestones.

## Next Technical Steps

1. Replace simplified movement execution with order-specific movement budgets and pivot costs.
2. Add battle audit/event log Component for scoring and post-battle reporting.
3. Expand input model to match PoC controls (context menus, drag-select, keyboard shortcuts).
4. Add pathfinding around blockers and formation-aware movement execution.
