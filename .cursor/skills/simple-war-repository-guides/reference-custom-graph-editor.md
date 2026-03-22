# Godot Custom Graph Editor (CGE)

- **Repository:** [github.com/tehelka-gamedev/godot-custom-graph-editor](https://github.com/tehelka-gamedev/godot-custom-graph-editor)
- **Simple War usage (from Repositories.md):** Sector maps as graphs; author node/link topology and metadata; export/import for campaign JSON; optional editor validation.

## Project integration

- **Vendored layout:** `addons/custom_graph_editor/` (nested plugin path: `addons/custom_graph_editor/addons/custom_graph_editor/` per current tree)
- **Plugin:** `res://addons/custom_graph_editor/addons/custom_graph_editor/plugin.cfg` enabled in `project.godot`

## Documentation

- **Primary (local):** `addons/custom_graph_editor/README.md` — features, install, quick start, toolbar, save/load (Ctrl+S / Ctrl+L), limitations
- **Web demo:** [tehelka.itch.io/godot-custom-graph-editor](https://tehelka.itch.io/godot-custom-graph-editor)

## Core workflow (editor)

- **Stock editor:** `custom_graph_editor.tscn` for visual linking without custom code
- **Selection:** click / box select; drag nodes; links anchor to nodes
- **Create link:** right-drag between nodes
- **Inspector:** `_setup_inspector(inspector: CGEInspectorPanel)` on custom **UI** classes — `add_property`, `add_enum_property`, `add_range_property`, `add_flags_property` (undo/redo integrated)

## Extension classes (custom sector tooling)

| Class | Purpose |
|--------|---------|
| `CGEGraphEditor` | Main editor behavior |
| `CGEGraphNode` / `CGEGraphNodeUI` | Node logic / visuals |
| `CGEGraphLink` / `CGEGraphLinkUI` | Link logic / visuals |

## Examples in this repo

| Example | Path | Shows |
|---------|------|--------|
| Minimal | `addons/custom_graph_editor/addons/custom_graph_editor/examples/minimal/` | Custom node + UI, serialize/deserialize, README in folder |
| Location map | `addons/custom_graph_editor/addons/custom_graph_editor/examples/location_map/` | Node + link types, travel cost on links, inspector, sample `.gegraph` |

## Known limitations (README)

- No multi-edges (two nodes linked only once)
- Effectively one node type and one link type per editor instance (multi-type “considered for future”)
- No grid snapping

## License

- MIT — see `addons/custom_graph_editor/LICENSE.md` / nested `addons/custom_graph_editor/addons/custom_graph_editor/LICENSE.md` as applicable
