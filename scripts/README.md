# scripts/ — Project Automation Helpers

Project-level automation scripts that agents can run to orient themselves and drive the project.

- **Convention:** Keep these **idempotent and side-effect-free** by default (status/query scripts). Any script that mutates state (writes files, runs the engine) must be explicitly named for it (e.g. `*_create.bat`, `*_build.bat`) and documented here.
- **Shell:** These are Windows `.bat` (cmd) scripts — run with `scripts\status.bat`. They work regardless of the `powershell -c` quirk (see `AGENTS.md` § Environment).
- **Reference scripts are NOT here.** The 1,700+ *reference* GDScript/Python builder scripts live under `GD-Agentic-Skills/skills/godot-master/scripts/` (e.g. `builder_create_scene.py`, `builder_run_project.py`, `builder_get_godot_version.py`). Use `docs/godot-skill-distillation.md` §12 to pick which module's scripts to pull, and read `GD-Agentic-Skills/skills/godot-master/SKILL.md` + the matching `references/*.md` for their contract.

## What to add
When a repetitive agent task appears twice, promote it to a `.bat`/`.ps1` here, document it in this file, and add a one-line pointer in `AGENTS.md` § Where things are.
