---
name: simple-war-gecs
description: >-
  Directs Godot 4 gameplay implementation through GECS (Godot Entity Component System).
  Use when adding or changing game simulation logic—units, combat, campaign entities,
  AI, movement, resources, save/load of play state—or when the user mentions ECS,
  entities, components, systems, GECS, or addons/gecs. Ensures data lives in
  Components, logic in Systems, and naming matches GECS conventions.
---

# Simple War — GECS (ECS) Development

This project uses **[GECS](https://github.com/csprance/gecs)** (`addons/gecs/`). The `ECS` autoload is configured in `project.godot`. Upstream docs and examples live in the addon: start from `addons/gecs/README.md` and the guides under `addons/gecs/docs/`.

## When to apply this skill

**Read and follow this skill before writing or refactoring code that:**

- Represents units, factions, map objects, timers, or other **simulation state**
- Runs **per-frame or per-tick** gameplay logic at scale (many entities)
- Needs **queries** (e.g. “all units with health and position”) or **relationships** between entities
- Must **serialize** entity state or support **deterministic** stepping (fits audit/replay goals in `godot-development.mdc`)

**Plain Godot nodes without GECS are fine for:** main menu and HUD wiring, asset loaders, editor-only tools, and thin view layers that **read** ECS-backed state to drive visuals (see “Presentation vs simulation” below).

## Architecture rules

1. **Components = data only** — `@export` fields, optional `_init` with **defaults on every parameter**. No gameplay methods on components (no `take_damage()` on `C_Health`; put that in a system).
2. **Systems = behavior** — Implement `query()` / `process(entities, components, delta)` (or the project’s current GECS `System` API). One primary concern per system when practical.
3. **Entities = composition** — Prefer `define_components()` and/or entity scenes with an `Entity` root. Avoid deep inheritance trees for “kinds of unit.”
4. **World drive** — Ensure `ECS.world` is set to the active `World` before `ECS.process(delta)`. Do not bypass the world for simulation objects that belong in ECS.
5. **Structural changes during iteration** — Use GECS **CommandBuffer** (`cmd`) for add/remove entity or component while systems run; do not ad-hoc mutate collections you are iterating.

## Naming and files (match GECS docs)

| Kind        | Class style   | File pattern        |
|------------|---------------|---------------------|
| Entity     | `ClassCase`   | `e_entity_name.gd`  |
| Component  | `C_Name`      | `c_name.gd`         |
| System     | `NameSystem`  | `s_name.gd`         |
| Observer   | `NameObserver`| `o_name.gd`         |

**Component export rule:** Every `@export` on a `Component` needs a **default** (Godot errors on export otherwise).

**Component `_init` rule:** All constructor parameters must have defaults—GECS may instantiate components internally.

## Entity scenes vs code-only entities

- **Spatial entities:** Scene root must be `Node2D` / `Node3D` if you use `global_position` / `global_transform` on the entity. `Entity` extends `Node`, not `Node2D`/`Node3D`.
- **Data-only entities:** `extends Entity` with no scene is valid for timers, abstract campaign data, etc.
- **Prefab pattern:** Entity scenes can hold visual children; **sync transforms or other state in `on_ready()` or systems**, and keep long-term behavior in systems (GECS v5+ guidance: entity methods are lifecycle hooks, not the main logic home).

## Queries and performance

- Use `QueryBuilder` (`with_all`, `with_any`, `with_relationship`, property filters per **Component Queries** doc) instead of manually scanning the scene tree for gameplay entities.
- Component order in `with_all` / `with_any` is **order-insensitive** for caching—do not rely on it for semantics.
- Prefer documented batch APIs (e.g. `.iterate` where applicable) when processing large sets; see `addons/gecs/docs/PERFORMANCE_OPTIMIZATION.md`.

## Presentation vs simulation

- **Simulation state** (HP, grid position, orders, buffs) → components on entities.
- **Views** (sprites, VFX, audio players) → child nodes of entity scenes or separate view nodes updated from system/observer code.
- **Global cross-cutting events** — still use signals or a small EventBus where appropriate; do not duplicate large state in singletons when it belongs on entities.

## Optional addons

- **Multiplayer:** If sync is required, evaluate **GECS Network** (`addons/gecs_network/` in upstream repo) per upstream README—not assumed present unless the project adds it.

## Verification checklist (before finishing a change)

- [ ] New gameplay state is modeled as **components**, not as ad-hoc dictionaries on random nodes.
- [ ] New behavior is in a **system** (or observer where reactive updates are correct), not scattered across `_process` on many nodes.
- [ ] Entities are registered through **`ECS.world.add_entity`** (and relationship APIs when linking entities)—not only `add_child` without world awareness.
- [ ] **Defaults** on component exports and `_init` parameters are satisfied.
- [ ] Structural edits mid-tick use **`cmd`** / documented deferred patterns.

## Deeper reference

For API details, relationships, observers, serialization, debug viewer, and troubleshooting, read the indexed guides in [reference.md](reference.md) under `addons/gecs/docs/`.
