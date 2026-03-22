# G.U.I.D.E — Godot Unified Input Detection Engine

- **Repository:** [github.com/godotneers/G.U.I.D.E](https://github.com/godotneers/G.U.I.D.E)
- **Simple War usage (from Repositories.md):** Abstract actions behind context-aware bindings; prompts/icons for UI; keep gameplay independent of raw devices (keyboard, mouse, gamepad, touch).

## Project integration

- **Vendored:** `addons/guide/`
- **Autoload:** `GUIDE` (UID reference in `project.godot`)
- **Plugin:** enabled
- **Note:** Upstream README warns the plugin may have rough edges; report issues on the repo.

## Authoritative documentation

- **Doc site (primary):** [godotneers.github.io/G.U.I.D.E](https://godotneers.github.io/G.U.I.D.E/)
- **Quick start (web):** [Quick Start](https://godotneers.github.io/G.U.I.D.E/quick-start.html) — actions as `GUIDEAction` resources, `GUIDEMappingContext`, modifiers (e.g. negate, swizzle for WASD → axis), triggers (e.g. `Pressed` for one-shot), `GUIDE.enable_mapping_context()` in `_ready`, `@export var move_action: GUIDEAction` and `move_action.value_axis_2d`, `say_hi_action.triggered` signal
- **Upstream README:** [github.com/godotneers/G.U.I.D.E/blob/main/README.md](https://github.com/godotneers/G.U.I.D.E/blob/main/README.md)

## Local examples

- Upstream quick start refers to a **`guide_examples/quick_start`** folder bundled with some releases; this project’s `addons/guide/` may omit it—if missing, clone [G.U.I.D.E](https://github.com/godotneers/G.U.I.D.E) or use the doc site’s walkthrough.

## Conceptual model (for Simple War)

| Concept | Role |
|---------|------|
| **GUIDEAction** | Resource representing an abstract action (bool, axis 2D, etc.) |
| **GUIDEMappingContext** | Bindings from hardware events → actions; enable/disable per mode (menu vs battle vs map) |
| **Modifiers** | Dead zone, invert, swizzle, sensitivity — keep logic out of gameplay scripts |
| **Triggers** | Tap, hold, combo, press-once behavior |
| **Prompts** | Text/icons that reflect active device (keyboard vs Xbox vs PlayStation icons, CC0 set from Those Awesome Guys) |

## Compatibility

- Works **alongside** Godot’s built-in `Input`; can inject into Godot actions if needed.

## License

- `addons/guide/LICENSE.md`
