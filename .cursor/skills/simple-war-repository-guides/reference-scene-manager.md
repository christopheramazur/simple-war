# Godot Scene Manager

- **Repository:** [github.com/esdg/GodotSceneManager](https://github.com/esdg/GodotSceneManager)
- **Simple War usage (from Repositories.md):** Visualize and maintain global scene transition graph; reduce hardcoded scene-change logic in UI scripts.

## Project status

- **Not vendored** in this repo as of the last check — treat as an **optional** or future addon. Evaluate before adding: **C# / .NET**-first implementation.

## Authoritative documentation (upstream paths)

- **README:** [GodotSceneManager/README.md](https://github.com/esdg/GodotSceneManager/blob/main/README.md) — feature list, transition table, beta notice
- **Install:** `addons/ScenesManager/Docs/installation.md`
- **Quick start:** `addons/ScenesManager/Docs/quick-start.md` — signals on scene roots, graph editor tab, `ScenesManagerController` autoload, schema save
- **Full index:** `addons/ScenesManager/Docs/README.md`
- **Also referenced:** `transitions.md`, `configuration.md`, `troubleshooting.md`

## Prerequisites (from quick start)

- **Godot 4.5+ with .NET (Mono)** and **.NET SDK 8.0** for the maintained plugin path
- **GDScript** scene roots are supported in docs with `signal` / `emit_signal` examples alongside C#

## Runtime model (summary)

1. Define **signals** on each navigable scene’s **root** script (e.g. `start_game`, `player_died`).
2. In the **Scene Manager** editor tab, add **Scene** nodes, assign `.tscn`, add **out slots** bound to those signals, pick **transition** resources (or “none” for jump cut).
3. Connect graph edges from signal slots to target scenes.
4. Save schema; plugin updates **`SceneManagerSettings.tres`**. At run, autoload loads **Game start** scene and listens for configured signals to drive transitions.

## Transitions (README highlights)

Built-in library includes fade, cross-fade, curtains, zoom shapes, pixel effects, color-enhanced variants — files under `addons/ScenesManager/TransitionsLibrary/` (e.g. `cross_fade.tscn`).

## Simple War adoption notes

- Fits **menu → campaign → battle → game over** flows if the project uses a **.NET-capable** Godot build or acceptable GDScript-only workflow per current plugin support.
- **Web export caveat:** upstream notes C# limits for WASM; see README discussion on GDScript port / Issue #104.

## Links

- [Releases](https://github.com/esdg/GodotSceneManager/releases), [Issues](https://github.com/esdg/GodotSceneManager/issues)
