# GECS — Godot Entity Component System

- **Repository:** [github.com/csprance/gecs](https://github.com/csprance/gecs)
- **Simple War usage (from Repositories.md):** Composition over deep inheritance; entities gain context and listening/emitting patterns; build battles from components when needed rather than prefabricated class hierarchies.

## Project integration

- **Vendored:** `addons/gecs/`
- **Autoload:** `ECS` → `res://addons/gecs/ecs/ecs.gd` (`project.godot`)
- **Plugin:** enabled in Editor → Project Settings → Plugins

## Documentation (read order)

1. **Local hub:** `addons/gecs/README.md` (index into `addons/gecs/docs/`)
2. **Essential guides:** `docs/GETTING_STARTED.md`, `docs/CORE_CONCEPTS.md`, `docs/BEST_PRACTICES.md`
3. **Advanced:** `docs/COMPONENT_QUERIES.md`, `docs/RELATIONSHIPS.md`, `docs/OBSERVERS.md`, `docs/SERIALIZATION.md`, `docs/DEBUG_VIEWER.md`, `docs/PERFORMANCE_OPTIMIZATION.md`, `docs/TROUBLESHOOTING.md`
4. **Optional networking addon (upstream):** `addons/gecs/network/README.md` and `addons/gecs/docs/network/` (if multiplayer sync is added)

## Examples in this repo

- **Framework tests:** `addons/gecs/tests/` (systems under `tests/systems/`, e.g. velocity-style processing patterns)

## Agent skill

Implementation conventions for Simple War are centralized in **`.cursor/skills/simple-war-gecs/SKILL.md`**. Use that skill for day-to-day ECS coding; this file is the repository-guide cross-link.
