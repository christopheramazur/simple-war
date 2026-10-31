# Simple War — Agent Routing & General Instructions
**What this is:** This file is routing for agents. It should always be read. When checking if agent files are relevant, read the first 20 lines as well as the content of the # and ## .md headers to determine if the file should be read further. 

## 1. Environment (read before running any command)
- **OS / shell:** Windows 10. The default shell is cmd.
- **Working directory:** `C:/Users/chris/Documents/simple-war`
- **PowerShell:** Create and store useful powershell scripts for PowerShell work. Don't try to pass to powershell directly from cmd.
- **Godot binary:** `Godot_v4.7-stable_win64.exe` (console variant: `Godot_v4.7-stable_win64_console.exe`) at project root. Main scene is `res://src/ui/main_menu.tscn`.

## 2. Where things live
| Path | What it is |
|---|---|
| `project.godot` | Engine config: version, autoloads, main scene, rendering. |
| `src/` | **Game code** (`.gd` + `.tscn`). GDD defines the target design. |
| `data/defaults/*.json` | The **data model** (content-as-data). All gameplay data should live here, as `Resource`-serializable structures (see §5). |
| `Game Design Document/` | The **GDD** — the authoritative directive for game design direction. |
| `docs/godot-skill-distillation.md` | Source of truth for Godot rules/patterns in THIS project. Read first before writing engine code (see §3). |
| `GD-Agentic-Skills/` | The `godot-*` skill modules. Each has `SKILL.md`, `references/*.md`, and `scripts/`. **You do NOT need to read all of these** — pick via the reading map in `docs/godot-skill-distillation.md` §12. |
| `scripts/` | **Project automation helpers** (see `scripts/README.md`). E.g. `scripts/status.bat`. |
| `addons/` | Third-party: `gecs`, `dialogic`, `gut` (testing), `custom_graph_editor`, `godot-rts-entity-controller`, `guide`. Update this when adding or removing addons.|
| `.agents\skills-general\skills\` | Other skills not directly related to the game, used when called for. `grill-me` is in productivity, for example. |

## 3. The single source of truth for Godot rules → `docs/godot-skill-distillation.md`
This is the condensed "Godot Master" skill for *this* project. Its sections:

- **§1 Non-negotiable architecture rules** — *read first, keep verbatim*: Who-Owns-What, the Layer Cake (presentation is a read-only signal listener), tiered Signal Bus, "when not to use a Node".
- **§10 The NEVER list** — the items you must never violate (absolute node paths, `String` keys in hot paths, `load()` in loops, `_process` on 1000+ entities, etc.).
- **§12 Module Reading Map** — the router: *goal → which skill module + reference + reference scripts to load*. **Use this to pick ONLY what you need.**
- **§14 Top 10 takeaways** — the short version if you read nothing else.
- Then pull **only** the specific module referenced by §12 (`GD-Agentic-Skills/skills/<module>/SKILL.md` + its `references/*.md` + `scripts/`). Do **not** read `SKILL.md` or all skills top-to-bottom.

## 4. Classify the request, then read only this
Match the task to a row. Read the "Start here" column. Do the "Avoid" column.

| Request type | Start here | Avoid |
|---|---|---|
| "How does the game work / what's the design?" | `Game Design Document/` (GDD) | Engine skill scripts |
| "What are the architecture rules / patterns / never-dos?" | `docs/godot-skill-distillation.md` §1, §10, §14 | Re-reading `SKILL.md` or all skills |
| "Build a system / feature" (new engine code) | `docs/godot-skill-distillation.md` §12 → load the specific module (SKILL + references + its scripts); GDD for the game rules | Reading every module; absolute `$`/`get_node` paths; UI holding state |
| "Author/edit content" (squads, units, attacks, campaigns, maps) | `data/defaults/*.json` | Putting data in the scene tree |
| "UI / scene layout / combat window / tab / minimap" | `distillation.md` §4 (F6 principle, safe signal handler, no direct button→gameplay wiring) | Connecting UI buttons directly to gameplay; holding state in UI nodes; `STOP` on transparent containers |
| "Multiplayer / ranked / net" | `distillation.md` §6 + `multiplayer-networking`, `server-architecture` skills | Trusting the client for authoritative state; JSON on the wire |
| "Save / load / campaign persistence" | `distillation.md` §7 + `save-load-systems` skill | Saving whole `Node`/`Object` instances; JSON for typed data |
| "Isometric camera / 2D assets in 3D scene" | `distillation.md` §5 + `camera-systems`, `adapt-2d-to-3d` | Linear zoom; per-frame position set; real-time GI |
| "Performance / frame spikes / GC" | `distillation.md` §9, §10 #12 + `performance-optimization` | Optimizing before profiling |
| "Mods / Steam Workshop" | `distillation.md` §8 | Executing untrusted `.gd` |
| "Test" | `gut` addon + `testing-patterns` skill | — |
| "Build / export / Steam upload" | `export-builds` skill | — |

## 5. Non-negotiable architecture rules
1. **Who owns what** — for *every* state variable, before writing a system: (1) who owns the data, (2) who may change it (owner via a public method only), (3) who must know it changed (signal listener). If you can't answer all three, you have a coupling problem. **Signals are the enforcement mechanism — Godot has no access modifiers.**
2. **Layer Cake:** PRESENTATION (UI/VFX) <- LOGIC (state machines) <- DATA (Resources/`.tres`) <- INFRASTRUCTURE (autoloads). **Presentation must never mutate Data directly.** Signals travel **up** as a general rule.
3. **Scoped Signal Bus per combat event** (global bus only for lifecycle e.g.`match_started`/`match_ended`). This is how N simultaneous combats stay decoupled. Displays can remain stateless read-only projections.
4. **`RefCounted`** for logic packets, **`Resource`** for data, **`Node`** only for spatial/per-frame. **All gameplay data as `Resource`s** — what makes Workshop mods (data+assets) possible.
5. **Determinism is a requirement** (ranked multiplayer depends on it): same inputs + seed → same result.
6. **F6 principle:** every scene (entity, UI, combat window) must run standalone — no scene-external dependencies.

## 6. Working principles (keep true)
- **Read the reading map (§12) before reading a skill module.** Load only the modules the goal names.
- **Composition is easier to read** if inheritance goes beyond 3 levels, consider refactor.
- **UI emits signals; the sim/controller listens.** UI never holds game state.
- **Data as data.** Content belongs in `data/defaults/*.json` / `Resource`s, not in node properties or the scene tree.
- **When you're stuck:** use a web search to simplify the problem. If you approach the context limit, write a **hand-off document** for the next agent (summary, current branch, what's done, what's next, open risks).
- **Experiments are Cheap:** It's alright to try things that might be risky, as long as there's a plan in place to backup and rollback. 

## 7. Build & Test (PowerShell)
Run from the project root:

- **Orient:** `.\scripts\status.bat` — branch, dirty files, engine version, autoloads, data assets.
- **Editor / run:** `.\Godot_v4.7-stable_win64.exe` — opens the editor; F5/F6 to run `res://src/ui/main_menu.tscn`.
- **Headless asset-import check:** `.\Godot_v4.7-stable_win64_console.exe --headless --import-only` — verifies all asset imports with no errors; may take a few minutes on a cold `.godot` cache.
- **Tests:** `gut` addon — route via `docs/godot-skill-distillation.md` §12 → `testing-patterns`.
- **Export / builds:** `export-builds` skill (route via §12).

## 8. Beads Issue Tracker
This project uses **bd (beads)** for issue tracking. Check the beads skill for more information when looking to perform task management.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:46cd31e7 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```powershell
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```powershell
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```powershell
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.
<!-- END BEADS SETUP -->
