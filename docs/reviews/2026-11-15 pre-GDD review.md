# Pre-GDD review: what we think before reading the design

Recorded 2026-11-15, after reading about 14,000 lines of `src/` and before opening `Game Design Document/`. All 329 game tests passed at commit `07fbf9b`. The purpose is to compare these views with what we think after reading the GDD.

One caveat: code comments cite GDD decisions (`R6Q19` and similar), so we saw the design's fingerprints but not its reasoning.

## What we think is done well

- **Layering.** `src/sim` (rules) → `src/api` (sessions) → `src/presentation` (UI). The sim runs with no scene tree, so tests, replays and AI-vs-AI runs work headless.
- **Determinism.** Fixed-point integers only, a fixed system order per tick, state hashing, snapshot and restore. Chance is an accumulator (25% evasion evades every fourth hit).
- **One Game API.** The human UI, AI controllers and tests all use `OverworldSession` / `BattleSession`. Orders are validated server-side and observations are filtered by visibility.
- **Content as data.** JSON packages with template inheritance, patches, schema validation, provenance and a content hash. Mods never run code.
- **Explainable maths.** Stat traces, the damage step list, and `Inspection.squad` with generated rules text.
- **Telemetry by replay.** Saves hold the seed, content hash, input log, per-turn hashes and a snapshot.

## What we think should be better

- **Battle movement has no pathfinding.** Straight lines only, no collision. A squad whose line crosses a cell that is impassable for its movement type stalls forever.
- **No real map format.** Battlefields are rectangle lists; overworld maps are generation passes.
- **The trigger vocabulary is tiny.** About seven actions per context; no spawning, orders or timers.
- **Adding a field costs three edits** (schema, rules compiler, table columns). Damage types and the five pools are hard-coded.
- **The data editor is a validated text editor** with a read-only trigger graph.
- **The UI is one large script.** `war_room.gd` (1,080 lines) builds controls in code and also creates the session, drives the AI and writes match logs. No theme, no translation files, some keys hard-coded.
- **Session duplication.** `OverworldSession` and `BattleSession` carry parallel save, replay and observe code.
- **Loose ends.** Unused RTS-controller addon and autoloads; empty `assets/`; `AGENTS.md` says data lives in Resources but it lives in JSON; the project description promises 3D combat but everything is 2D.
- **Nothing has been profiled.**

## Decisions we are leaning toward

| Topic | Current view |
|---|---|
| Priority order | Tools and core systems first, UI second, content third, with two changes: pull one thin slice of real content forward, and do the cheap UI foundations early. |
| Order within the primary goal | Map format → battle pathfinding → wider trigger vocabulary → map editor. |
| Map format | JSON template with a palette and one text row per map row, in named layers (`terrain`, later `elevation`). Scenario is a separate template. Generation passes stay as an optional base layer. Tiled as an importer only. Palette width (one or two characters) still open. |
| Battle pathfinding | Our own integer A* on a coarse grid (about 4 m), planned once per order, waypoints stored on the squad, replan when an attack target moves. Unit collision deferred. Godot's built-in pathfinding rejected because it uses floats. Cell size to be set by measurement. |
| Overworld pathfinding | Keep Dijkstra. Add an A* heuristic only if profiling on a large map justifies it. |
| Tests | Keep them running. Leave engine invariants alone, move rule tests onto a frozen fixture package, expect content tests to change with content. |
| UI foundations | Godot built-ins: `Theme`, `TranslationServer` with CSV or PO, `ConfigFile`, split containers. Extend the installed GUIDE addon to all keys. Remove the unused RTS addon. |
| Telemetry | Move `MatchLog` from the UI to the API layer. Add periodic snapshots. |
| 2D versus 3D | Start in 2D. Separate the map view from the panels so the renderer can be swapped. Gameplay height would be a sim change, so reserve an elevation layer in the map format. |

## Open questions going into the GDD

- Does the design need gameplay elevation?
- How large are maps and battles meant to get? This sets the pathfinding and performance budget.
- How much scripting does the campaign need? This sets the trigger vocabulary.
- Is the closed vocabulary (four damage types, five pools) a design commitment or an implementation shortcut?
- What does the design say about 3D combat?
