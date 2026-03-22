# Dialogic 2

- **Repository:** [github.com/dialogic-godot/dialogic](https://github.com/dialogic-godot/dialogic)
- **Simple War usage (from Repositories.md):** Campaign narrative and branching choices as data-driven timelines; tie conditions and outcomes to campaign state via variables, built-in events, signals, and custom events when needed.

## Project integration

- **Vendored:** `addons/dialogic/`
- **Autoload:** `Dialogic` (UID in `project.godot`)
- **Plugin:** enabled under Editor → Project Settings → Plugins
- **Project settings:** `[dialogic]` section in `project.godot` (e.g. `dch_directory`, `dtl_directory`, `layout/style_directory`)

## Authoritative documentation

- **Manual (primary):** [Dialogic 2 Documentation](https://docs.dialogic.pro/) — introduction, [getting started](https://docs.dialogic.pro/getting-started), timelines, events, [variables](https://docs.dialogic.pro/variables.html), [translation](https://docs.dialogic.pro/translation.html), [creating timelines in code](https://docs.dialogic.pro/creating-timelines-in-code), [custom extensions / events](https://docs.dialogic.pro/creating-extensions.html)
- **Class reference:** linked from the upstream [README](https://github.com/dialogic-godot/dialogic/blob/main/README.md) (“Class Reference” on the doc site)
- **Source doc repo:** [github.com/dialogic-godot/documentation](https://github.com/dialogic-godot/documentation) (edit links on doc pages point here)

## Version and engine

- **Dialogic 2** requires **Godot 4.3+** (README). Simple War targets **4.6** in `project.godot` — compatible.
- Dialogic 2 is still marked **Alpha** in docs; expect occasional workflow/API shifts — follow upstream changelogs on release.

## Core concepts (for Simple War)

| Concept | Role |
|--------|------|
| **Timelines** | Ordered **events** = dialog flow (text, choices, conditions, animations, signals, etc.) |
| **Text + visual editors** | Same timeline editable as blocks or text (portable `.dtl` / project layout per your setup) |
| **Characters** | Editor-managed characters and portraits; use or bypass per campaign UI needs |
| **Variables** | Branching and game state hooks without hardcoding-only scripts |
| **Custom events** | GDScript-backed events for campaign-specific hooks (e.g. consult GECS or rule evaluators) |

## Code and API stability

- Upstream treats methods/vars **prefixed with `_`** as **private** — may break between versions; prefer **public** APIs from the **class reference**.
- Alpha/Beta: review **changelogs** when upgrading; plugin includes an **auto-updater** (per README).

## Testing (upstream)

- Dialogic’s own tests use **gdUnit4** under `/Tests/Unit` ([README](https://github.com/dialogic-godot/dialogic/blob/main/README.md)). Simple War can still use **GUT** for game code; no requirement to match Dialogic’s test framework.

## Community / support

- [Discord](https://github.com/dialogic-godot/dialogic/blob/main/README.md), GitHub **Issues** and **Discussions** (links in README).

## License

- MIT (upstream `LICENSE`); note bundled **Roboto** font (Apache 2.0) mentioned in README.
