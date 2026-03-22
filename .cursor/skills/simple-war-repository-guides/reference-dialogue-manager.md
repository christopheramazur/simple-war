# Dialogue Manager (Godot 4.4+)

- **Repository:** [github.com/nathanhoad/godot_dialogue_manager](https://github.com/nathanhoad/godot_dialogue_manager)
- **Simple War usage (from Repositories.md):** Narrative activities, event nodes, branching choices with conditions tied to campaign state.

## Project status

- **Not vendored** here — install via Asset Library or GitHub zip when narrative tooling is scheduled.

## Authoritative documentation (upstream `docs/`)

| Doc | Topic |
|-----|--------|
| [FAQ.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/FAQ.md) | Common questions |
| [Basic_Dialogue.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Basic_Dialogue.md) | Syntax basics |
| [Conditions_Mutations.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Conditions_Mutations.md) | Branching state, side effects |
| [Settings.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Settings.md) | Project settings |
| [Using_Dialogue.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Using_Dialogue.md) | Runtime integration |
| [Dialogue_Balloons.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Dialogue_Balloons.md) | UI balloons |
| [Translations.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Translations.md) | i18n |
| [API.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/API.md) | `DialogueManager`, `DialogueLine`, etc. |
| [CSharp.md](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/CSharp.md) | C# wrapper |

## Runtime essentials (from Using_Dialogue)

- **Global** `DialogueManager` autoload (after install)
- **Quick UI:** `DialogueManager.show_dialogue_balloon(resource, label)`
- **Line-by-line:** `await DialogueManager.get_next_dialogue_line(resource, "start")` then follow `dialogue_line.next_id` for subsequent lines; responses expose `next_id` per option
- **Resource type:** `*.dialogue` files (compiled resource)
- **DialogueLabel** node: typing, BBCode, `wait` / `speed` / `inline_mutation`; signals `started_typing`, `finished_typing`, `paused_typing`, `spoke`
- **Custom current scene:** `DialogueManager.get_current_scene` callable if not using default tree current scene
- **Runtime compile:** `DialogueManager.create_resource_from_text(string)` for generated dialogue (fails on syntax errors)

## Example projects

- Multiple **Itch.io** samples linked from upstream README (portraits, VN, voices, balloons, scroll + text input)

## Version matrix (README)

- Current main targets **Godot 4.4+**; older Godot builds map to tagged releases (v3.3 for 4.3, v2.x, v1.x for 3.x)

## Video guides

- Linked from README: dialogue basics, cut-scenes, balloons (YouTube)

## License

- MIT — see upstream `LICENSE`
