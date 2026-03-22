# GUT — Godot Unit Test

- **Repository:** [github.com/bitwes/Gut](https://github.com/bitwes/Gut)
- **Simple War usage (from Repositories.md):** Unit tests for component/system behavior and campaign rule evaluators; integration smoke tests for PoC flow; event-log replay tests for save/replay.

## Project integration

- **Vendored:** `addons/gut/`
- **Plugin:** enabled (`project.godot` → `editor_plugins`)
- **Pinned intent:** `addons/gut/versions.json` lists Asset Library **9.6.0** with Godot **4.6.x** on `main` (verify after upgrades)

## Authoritative documentation

- **Wiki (primary):** [gut.readthedocs.io](https://gut.readthedocs.io/) — version-specific links also appear in the upstream [README](https://github.com/bitwes/Gut/blob/main/README.md) (e.g. [9.6.0 docs](https://gut.readthedocs.io/en/v9.6.0/))

## Topics to bookmark (RTD)

| Topic | Use for Simple War |
|--------|---------------------|
| [Install](https://gut.readthedocs.io/en/latest/Install.html) | CI/editor setup |
| [Quick Start](https://gut.readthedocs.io/en/latest/Quick-Start.html) | First test scene |
| [Creating Tests](https://gut.readthedocs.io/en/latest/Creating-Tests.html) | Test layout |
| [Asserts and Methods](https://gut.readthedocs.io/en/latest/Asserts-and-Methods.html) | Assertions |
| [Inner Test Classes](https://gut.readthedocs.io/en/latest/Inner-Test-Classes.html) | Grouping related tests |
| [Doubles](https://gut.readthedocs.io/en/latest/Doubles.html) / [Partial Doubles](https://gut.readthedocs.io/en/latest/Partial-Doubles.html) / [Stubbing](https://gut.readthedocs.io/en/latest/Stubbing.html) / [Spies](https://gut.readthedocs.io/en/latest/Spies.html) | Isolating ECS systems and I/O |
| [Command Line](https://gut.readthedocs.io/en/latest/Command-Line.html) | Headless/CI |
| [Parameterized Tests](https://gut.readthedocs.io/en/latest/Parameterized-Tests.html) | Rule tables |
| [Export Test Results](https://gut.readthedocs.io/en/latest/Export-Test-Results.html) | JUnit XML in pipelines |

## Editor / IDE

- **VS Code:** [gut-extension](https://marketplace.visualstudio.com/items?itemName=bitwes.gut-extension) — run suite or single test from the editor
- **Godot:** GUT dock UI under `addons/gut/gui/`

## Examples in vendored addon

- Use the GUT panel to run tests; sample patterns are often copied from RTD. The addon ships editor scenes such as `addons/gut/gui/run_from_editor.tscn` for in-editor runs.

## License

- `addons/gut/LICENSE.md` (MIT)
