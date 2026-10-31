# Simple War — Agent Instructions

Canonical instructions for every agent client (Claude Code reads this via `CLAUDE.md` → `@AGENTS.md`; Codex and OpenCode read it directly). Read the `#`/`##` headings first, then only the sections your task needs.

## 1. Environment
- **OS:** Windows 11. **Repo root:** `C:/Users/chris/Documents/simple-war`.
- **Shell:** use **Git Bash** (the Bash tool) by default; output compression and command metrics only apply there. Use PowerShell only for Windows-only operations.
- **Godot 4.7.2:** `Godot_v4.7.2-stable_win64.exe` (editor) and `Godot_v4.7.2-stable_win64_console.exe` (headless) at the repo root.
- **Game code is a clean slate:** `src/` is empty, and `project.godot` still points at the removed `res://src/ui/main_menu.tscn` (tracked as `sw-m7o`).

## 2. Start of every session
1. `harness/bin/hx status`: branch, dirty files, Godot version, autoloads, in-progress and ready tasks.
2. Pick or confirm a task, then **claim it before working**: `bd update <id> --claim`. Run `bd close <id>` when done.
   Telemetry assigns token spend to tasks from these two commands, so unclaimed work counts as `(none)`.
3. Read only what the task needs (§4).

## 3. Where things live
| Path | What it is |
|---|---|
| `Game Design Document/` | The **GDD**: the authority on game design. |
| `GD-Agentic-Skills/godot-skill-distillation.md` | **Godot rules for this project.** Read §1 (architecture), §10 (NEVER list), §14 (top 10) before writing engine code; §12 routes you to skill modules. |
| `GD-Agentic-Skills/skills/godot-*/` | Skill modules (`SKILL.md`, `references/`, `scripts/`). Load **only** the module §12 names, never all of them. |
| `data/defaults/*.json` | The data model: Attacks, Campaigns, Scenarios, Sector_Maps, Squads, Units. Gameplay data lives here, not in scenes. |
| `src/` | Game code (`.gd` + `.tscn`). |
| `addons/` | `gecs` (ECS), `dialogic`, `gut` (tests), `custom_graph_editor`, `godot-rts-entity-controller`, `guide`. Update this row when adding or removing addons. |
| `harness/` | Agent harness: the `hx` CLI, telemetry ledger, benchmarks. See `harness/README.md`; decisions and reasons are in `harness/DESIGN.md`. |
| `.agents/skills/` | Client-agnostic agent skills (e.g. `beads`). |

## 4. Classify the request, then read only this
`dist` = `GD-Agentic-Skills/godot-skill-distillation.md`. Skill names below are `GD-Agentic-Skills/skills/godot-<name>/`.

| Request | Start here | Avoid |
|---|---|---|
| Game design / how the game works | GDD | Engine skill scripts |
| Architecture rules / never-dos | `dist` §1, §10, §14 | Reading whole skill modules |
| Build a system / feature | `dist` §12 → the one named module; GDD for the rules | Absolute `$`/`get_node` paths; UI holding state |
| Author content (squads, units, attacks, campaigns, maps) | `data/defaults/*.json` | Data in the scene tree |
| UI / combat window / tabs / minimap | `dist` §4 | Wiring buttons straight to gameplay; `STOP` on transparent containers |
| Multiplayer / ranked | `dist` §6 + `multiplayer-networking`, `server-architecture` | Trusting the client; JSON on the wire |
| Save / load | `dist` §7 + `save-load-systems` | Saving whole `Node`s; JSON for typed data |
| Isometric camera / 2D-in-3D | `dist` §5 + `camera-systems`, `adapt-2d-to-3d` | Linear zoom; per-frame position set |
| Performance | `dist` §9, §10 + `performance-optimization` | Optimizing before profiling |
| Mods / Workshop | `dist` §8 | Executing untrusted `.gd` |
| Tests | `testing-patterns` (GUT is installed) | — |
| Build / export | `export-builds` | — |
| Agent harness / tooling / metrics | `harness/README.md`, `harness/DESIGN.md` | Editing `harness/data/` by hand |

## 5. Non-negotiable game architecture
1. **Who owns what:** for every state variable, know who owns it, who may change it (the owner, via a public method), and who must hear about it (a signal). If you can't answer all three, there's a coupling problem.
2. **Layer cake:** presentation ← logic ← data (Resources) ← infrastructure (autoloads). Presentation never mutates data. Signals travel up.
3. **A scoped signal bus per combat.** The global bus is for lifecycle only (`match_started`, `match_ended`).
4. **`RefCounted` for logic packets, `Resource` for data, `Node` only for spatial or per-frame work.** All gameplay data is in `Resource`s, which is what makes Workshop mods possible.
5. **Determinism:** same inputs plus same seed gives the same result. Ranked multiplayer depends on it.
6. **F6 principle:** every scene runs standalone.

## 6. Working rules
- **Agents may change things freely**, including commits and `git push` to `origin`. Never force-push or rewrite history.
- **Ask the user first** for any of these:
  - spending money or raising any budget in `harness/config/`
  - deleting ledger, transcript or tracker history
  - publishing or posting anything externally
  - changing this list
- **Tools over tokens:** prefer an `hx` verb to an ad-hoc command, and keep command output short (`| head`, `--short`, `-q`). If you repeat the same multi-step command, file a task to make it an `hx` verb.
- **Data as data.** UI emits signals and the simulation listens; UI never holds game state.
- **Composition over deep inheritance:** refactor beyond 3 levels.
- **Experiments are cheap**, as long as there's a way to roll back.
- **Stuck:** search the web to simplify the problem.
- **Near the context limit:** write a hand-off (summary, branch, done, next, risks) into the task with `bd update <id> --append-notes "…"`.

## 7. Build & test (Git Bash, from the repo root)
| Do | Command |
|---|---|
| Orient | `harness/bin/hx status` |
| Check toolchain and secrets | `harness/bin/hx doctor` |
| Spend and usage report | `harness/bin/hx report` (`--since all`, `--html --open`); the ledger updates after every turn |
| Open the editor | `./Godot_v4.7.2-stable_win64.exe` |
| Headless import check | `./Godot_v4.7.2-stable_win64_console.exe --headless --import-only` (slow on a cold `.godot` cache) |
| Game tests | GUT; see `testing-patterns` |
| Harness tests | `uv run --project harness pytest -q` |

## 8. Task tracking
The two blocks below are generated by `bd`. Leave the marker comments intact. Prefer `hx task …` once it exists (`sw-lbm.8`).

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
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
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
<!-- END BEADS CODEX SETUP -->
