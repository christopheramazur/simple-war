# Game Design Document

## Where to start

**Single source of direction: `Overview/Design-Overview.md`** — the consolidated design for what Simple War is, its architecture (layers + ECS + non-negotiables), the turn/timer model, combat contracts, the data model, the audit/event contract, user experience, and the **Tight Scope Digital Prototype** (scope, build order, and acceptance criteria). Read this first; it superseded the source documents it consolidates.

## Folder map

| Folder | What it is |
|---|---|
| `Overview/` | **Direction.** `Design-Overview.md` (consolidated single doc). `Main Concepts.md` is a source doc, superseded by `Design-Overview.md`, retained for history. |
| `About/` | Project framing (`Introduction.md`): positioning, the digital-first pivot. |
| `Foundation/` | **Source design docs, superseded by `Overview/Design-Overview.md` on 2026-10-29**, retained for provenance: `Foundation.md` (design), `Framework-Requirements.md` (confirmed v1 implementation spec), `campaign_sector_gecs_architecture.md` (GECS campaign/sector runtime architecture + migration map). |
| `Gameplay Rules/` | **Formal rules, authoritative over the Overview for the rule itself.** Battle Rules (100.x), Entity System Rules (200.x), Movement & Positioning Rules (300.x), Campaign Rules (800.x), `Terminology.md`, `Combat Resolution Brainstorming.md`, plus validation reports. v1 implements a *subset* of these rules (see `Design-Overview.md` §12). |
| `Narrative Elements/` | Story context: factions (`Gardeners/`, `Kraken/`), `Overarching Narrative.md`, `Timeline.md`. |
| `Useful Examples/` | Reference material: `Repositories.md`, `Scene_Routing_Spike.md`, `Tooling and Foundation Plan.md`, `Tooling Suitability Matrix.md`. |

## How the documents relate (priority)

1. **`Overview/Design-Overview.md`** — design direction, architecture, v1 scope.
2. **`Gameplay Rules/*`** — formal rule definitions. When a rule and the Overview disagree, the rule document is authoritative for that rule; fix the Overview.
3. **`docs/godot-skill-distillation.md`** — how to build engine code in this repo (architecture rules, never-lists, skill module reading map).

## Maintenance

- New design decisions: write them into `Design-Overview.md` first, then propagate to the relevant `Gameplay Rules/` doc (and `docs/godot-skill-distillation.md` if it changes implementation rules).
- Keep rule references (e.g. "see rule 850.1 in Campaign Rules") pointing at rules that actually exist in the target document.
- The v1 definition of done is the **Tight Scope acceptance criteria** in `Design-Overview.md` §12; any scope change requires updating that section and the build order.
- Superseded source docs live in `Foundation/` — do not edit them for ongoing work; they are history.
