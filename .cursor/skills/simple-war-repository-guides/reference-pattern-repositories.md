# Genre and pattern reference repositories

These are **learning and mining** references listed in Repositories.md — not required addons. Use them for UX patterns, folder structure, and feature ideas; **do not assume** API compatibility with Simple War’s stack (GECS, G.U.I.D.E, etc.).

---

## RTS selection / movement demo

- **URL:** [github.com/LeProfesseurStagiaire/rtsSelectionMoveDemo](https://github.com/LeProfesseurStagiaire/rtsSelectionMoveDemo)
- **Simple War usage:** Unit selection, movement previews, formation-facing, ghost/path visuals; selection and drag patterns.
- **Docs:** No stable `README.md` was available via raw GitHub at documentation time — clone the repo and read in-repo README, scenes, and scripts directly.
- **Study focus:** Input → selection rect → unit grouping → move/ghost line rendering.

---

## Godot RTS Entity Controller (addon)

- **URL:** [github.com/philipbeaucamp/godot-rts-entity-controller](https://github.com/philipbeaucamp/godot-rts-entity-controller)
- **Simple War usage:** Reference for entity-heavy battlefield control, selection/move/attack composition (StarCraft/Warcraft-style baseline).
- **Documentation:** [philipbeaucamp.github.io/godot-rts-entity-controller](https://philipbeaucamp.github.io/godot-rts-entity-controller/) (MkDocs; build locally with `mkdocs` if needed)
- **Demos:** Sample unit + playable scene in repo; expanded demo on [itch.io](https://philipbeaucamp.itch.io/godot-rts-entity-controller)
- **Caution:** Uses its own **entity-component** toolkit — **conceptually** comparable to GECS but **not** the same API. Mine **patterns**, not code verbatim.

---

## Territory Conquest Idle

- **URL:** [github.com/hhy0111/-territory-conquest-idle](https://github.com/hhy0111/-territory-conquest-idle)
- **Simple War usage:** Automated progression cadence; map/battlefield state loops; hybrid idle/battlefield ideas.
- **Docs:** README not fetched from default raw path (repo layout or default branch may differ) — open the repo in browser or clone.

---

## Godot official 2D demos

- **URL:** [github.com/godotengine/godot-demo-projects/tree/master/2d](https://github.com/godotengine/godot-demo-projects/tree/master/2d)
- **Simple War usage:** Canonical Godot patterns for 2D, UI, navigation.
- **How to use:** Pick a demo closest to the subsystem (e.g. navigation, particles) and read `README` inside that demo folder.

---

## GDQuest Open RPG (Godot 4)

- **URL:** [github.com/gdquest-demos/godot-open-rpg](https://github.com/gdquest-demos/godot-open-rpg)
- **Simple War usage:** Turn-based combat, inventory, progression, maps/transitions, dialogues, grid movement, UI menus — **structure** reference.
- **Documentation:** [README](https://github.com/gdquest-demos/godot-open-rpg/blob/main/README.md) — targets **Godot 4.5**; emphasizes teaching over framework.
- **Guidelines:** [GDScript guidelines](https://gdquest.gitbook.io/gdquests-guidelines/godot-gdscript-guidelines) linked from README.
- **Caution:** Not a framework drop-in; align with Simple War rules/skills when borrowing patterns.

---

## Nezvers Godot Game Template (top_down + great_games_library)

- **URL:** [github.com/nezvers/Godot-GameTemplate](https://github.com/nezvers/Godot-GameTemplate)
- **Simple War usage:** Menu/audio/pause/rebind, shader scene transitions, boot preload, pooling, save resources, sound manager, AStar waves — **feature recipe** reference.
- **Documentation:** [README](https://github.com/nezvers/Godot-GameTemplate/blob/master/README.md) — main content under `addons/top_down/`; shared utilities under `addons/great_games_library/`.
- **Suggested entry scenes (README):** `addons/top_down/scenes/ui/screens/title.tscn`, `levels/room_0.tscn`, `actors/actor.tscn`, `weapons/weapon.tscn`, `projectiles/projectile.tscn`
- **Video:** README embeds YouTube project breakdown.
- **Caution:** Template author warns it is not beginner-friendly and evolves with author’s game; **audio bus** layout caveat in README.

---

## Battle for Wesnoth (C++)

- **URL:** [github.com/wesnoth/wesnoth/tree/master/src](https://github.com/wesnoth/wesnoth/tree/master/src)
- **Simple War usage:** **Feature mining** and structural inspiration from a mature hex/strategy game — **not** Godot code.
- **How to use:** Search/read by subsystem (AI, pathfinding, game state, WML parser) as architectural reference only; expect heavy C++.

---

## Cross-reference

When implementing a feature inspired by these repos, prefer mapping behavior into **Simple War’s chosen stack** (see `reference-gecs.md`, `reference-guide.md`, etc.) rather than copying foreign architectures wholesale.
