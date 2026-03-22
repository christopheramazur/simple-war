---
name: simple-war-repository-guides
description: >-
  Summarizes how Simple War uses each external repository listed in Game Design
  Document/Useful Examples/Repositories.md, with documentation links, local addon
  paths, and study examples. Use when implementing features tied to those tools,
  onboarding, or when the user asks about GUT, G.U.I.D.E, custom graph editor,
  Scene Manager, Beehave, Dialogic, Rapier, or genre reference repos.
---

# Simple War — external repository guides

Canonical list of tools and references: [Repositories.md](../../../Game%20Design%20Document/Useful%20Examples/Repositories.md) (from repo root: `Game Design Document/Useful Examples/Repositories.md`).

This skill is a **hub**: each tool has a dedicated reference file with doc URLs, local paths (when vendored), Simple War usage notes, and where to read examples.

## Core foundation addons

| Tool | Reference file |
|------|----------------|
| GECS | [reference-gecs.md](reference-gecs.md) (see also `.cursor/skills/simple-war-gecs/SKILL.md`) |
| GUT | [reference-gut.md](reference-gut.md) |
| G.U.I.D.E | [reference-guide.md](reference-guide.md) |
| Godot Custom Graph Editor | [reference-custom-graph-editor.md](reference-custom-graph-editor.md) |
| Godot Scene Manager | [reference-scene-manager.md](reference-scene-manager.md) |
| Beehave | [reference-beehave.md](reference-beehave.md) |
| Dialogic | [reference-dialogic.md](reference-dialogic.md) |
| Godot Rapier Physics | [reference-godot-rapier.md](reference-godot-rapier.md) |

## Genre and pattern references (not vendored)

| Area | Reference file |
|------|----------------|
| RTS demos, Open RPG, Game Template, official demos, Wesnoth | [reference-pattern-repositories.md](reference-pattern-repositories.md) |

## How to use these guides

1. Open the **reference-* file** for the tool you are touching.
2. Prefer **local** `addons/...` README and examples when the addon is in-tree; use **upstream** links for authoritative docs and version matrices.
3. Align new code with the **“Simple War usage”** bullets in each reference (derived from Repositories.md).

No Cursor rules are required to activate these guides; load this skill when work intersects the listed repositories.
