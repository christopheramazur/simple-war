# Beehave — behaviour trees for Godot

- **Repository:** [github.com/bitbrain/beehave](https://github.com/bitbrain/beehave)
- **Simple War usage (from Repositories.md):** Commander/NPC strategic behavior in campaign; battle AI loops for movement, targeting, order priorities.

## Project status

- **Not vendored** here — add `addons/beehave` from the **godot-4.x** branch zip when needed.

## Installation (upstream README)

1. Download [godot-4.x branch zip](https://github.com/bitbrain/beehave/archive/refs/heads/godot-4.x.zip)
2. Copy `beehave` folder into project `addons/`
3. Enable plugin: Project → Project Settings → Plugins

## Documentation

- **Primary:** [github.com/bitbrain/beehave/blob/main/README.md](https://github.com/bitbrain/beehave/blob/main/README.md) (Godot 3 tutorial video linked; concepts apply to 4.x with branch-appropriate API)
- **Discord:** linked from README

## Core concepts

| Piece | Role |
|--------|------|
| **Behaviour tree** | `Node` in scene tree; ticks each frame; drives **parent** (actor) |
| **Leaf tick** | `tick(actor, blackboard)` → `SUCCESS`, `FAILURE`, or `RUNNING` |
| **ConditionLeaf** | Simple checks; prefer one concern per condition |
| **ActionLeaf** | Mutations / long tasks; return `RUNNING` across frames until done |
| **Blackboard** | Shared data between nodes |
| **Selector** | Try children until one succeeds |
| **Selector Star** | Like selector but skips prior children while one is `RUNNING` |
| **Sequence** | All children must succeed |
| **Sequence Star** | Like sequence but skips completed children while one is `RUNNING` |
| **Decorators** | Failer, Succeeder, Inverter, Limiter (cap tick count) |

## Simple War integration pattern

- **Actor** = unit or commander node (or an ECS-facing adapter that reads/writes components in leaf nodes).
- Keep leaves **small** and **reusable**; compose campaign vs battle differences with different trees or blackboard keys.
- **Debug:** editor debug view mentioned in README (issue #1 lineage).

## Branching

- **godot-3.x** vs **godot-4.x** — PRs should target the matching branch per upstream guidelines.
