name: simple-war-code-generator
description: Converts validated Simple War rules into code scaffolding, data structures, state machines, and test cases. Use when implementing validated rules in code, creating entity classes, generating API specifications, or producing unit tests. Trigger when user mentions "generate code from rules", "implement this mechanic", "create entity class", "write tests for rule", or when working with validated rules that need digital implementation. Always use after Rules Validator has approved the rule.
---

# Simple War Code Generator (Godot 4.6+ / GDScript)

Transforms validated Simple War rules into production-ready Godot 4.6+ scaffolding that matches the Game Design Document: Players, Rosters, Armies, Units/Models, Campaigns, Battles, Zones, Timings, and Orders.

Use this skill when you need to turn a Simple War rule or overview section into:
- GDScript `Resource` definitions for entities (Armies, Units, Models, Items, Campaigns).
- Runtime GDScript scripts/nodes for Battle flow, Turn/Phase structure, and Orders.
- Validation helpers for Rosters, Armies, Zones, and state transitions.
- Focused test scripts that exercise those rules at the engine level.

## 1. Generation Workflow

1. **Identify Domain** — Determine which part of the GDD the rule lives in:
   - Campaigns, Rosters & Armies, Units & Models, Zones & State, Timings & Orders.
2. **Extract Structure** — From the text, pull out:
   - Entities and relationships (e.g. Army → Units, Unit → Models, Zones like Battlefield/Reserves).
   - States, tags, and keywords (e.g. Morale states, Faction keywords, Unit/Model keywords, Zones).
   - Allowed transitions and invariants (e.g. Stage/Turn/Phase order; zone rules like “Removed from Play cannot move zones”).
3. **Choose Godot Shape**:
   - Static data → `Resource` script (definitions for Campaigns, Armies, Units, Models, Items).
   - Runtime flow/state → `Node`/autoload script (Battle state, Turn loop, Order resolution).
   - Cross-cutting logic → Utility script with pure functions (e.g. statline helpers, army value calculation).
4. **Generate Scaffolding** — Produce typed GDScript with:
   - Clear types and docstrings referencing rule sections.
   - Explicit fields for tags, zones, statlines, morale, relationships.
   - Methods for legal transitions (e.g. advancing stages, moving zones, resolving orders).
5. **Generate Tests** — For each rule, add:
   - Minimal GDScript test scripts (e.g. with GUT) that cover the happy path and a few key edge cases.
   - Assertions that encode the rule’s invariants (e.g. “Units removed from play cannot change zone”).
6. **Implementation Notes** — Record:
   - Any approximations vs tabletop intent.
   - Extension points for later (e.g. richer combat or order types).

## 2. Core Principles

- **Rule Fidelity**: Code and tests must reflect the GDD terminology and constraints (Campaigns, Rosters, Armies, Units, Zones, Timings, Orders) without inventing new mechanics.
- **Explicit State**: Represent Stage/Turn/Phase, Zones, Morale, and Unit/Army state as explicit fields or enums/constants, not implicit booleans.
- **Separation of Concerns**:
  - Definitions (`Resource` data) vs runtime state (Battle/Unit instances).
  - Engine rules (Battle flow, Zones, Orders) vs content (specific factions, scenarios).
- **Testability First**: Prefer deterministic functions that can be tested without a full scene tree; isolate node-tree interactions behind small methods.
- **Extensibility**: Design so Campaigns can modify battles (turn count, stage rules, victory conditions, restrictions) without changing core engine types.

## 3. Generation Categories (from the GDD)

| Category | GDD source | Typical output |
|----------|-----------|----------------|
| **Campaign & Activities** | `Main Concepts – Campaigns`, Generic Campaign | `CampaignDefinition` resource, basic flow config, hooks to modify battles |
| **Rosters & Armies** | `Main Concepts – Rosters and Armies` | `RosterDefinition` and `ArmyDefinition` resources, simple validation helpers |
| **Units, Models, Items & Statlines** | `Terminology – Units, Models, Timings`, statline and abilities | `UnitDefinition`, `ModelDefinition`, `ItemDefinition` resources; GDScript helpers for statline and keywords |
| **Zones & State** | `Terminology – Zones`, In Play / Removed / Casualty Report / KIA / Rosters | Zone/tag enums/constants, zone-management helpers that enforce invariants |
| **Battle Flow & Timings** | `Terminology – Timings`, `Main Concepts – Battle stages` | `BattleState` script with Stage/Turn/Phase representation and transitions |
| **Orders, Actions & Reactions** | `Terminology – Fighting a Battle`, Order System & Actions | GDScript order structs/types and resolution pipeline skeletons |
| **Tests** | Any of the above | Focused GDScript tests for zones, battle flow, orders, and army validation |

## 4. Output Structure (Godot 4.6+ friendly)

Generate code under a consistent layout that can be dropped into the Godot project:

```
generated/
├── campaign/        # CampaignDefinition.gd, GenericCampaign.gd
├── roster/          # RosterDefinition.gd, ArmyDefinition.gd, ArmyValidator.gd
├── entities/        # UnitDefinition.gd, ModelDefinition.gd, ItemDefinition.gd, Keywords.gd
├── battle/          # BattleState.gd, BattleStage.gd, TurnPhase.gd, Battlefield.gd
├── zones/           # Zones.gd, ZoneRules.gd
├── orders/          # OrderTypes.gd, OrderResolver.gd, ReactionResolver.gd
├── tests/           # test_battle_flow.gd, test_zones.gd, test_rosters.gd
└── docs/            # state_diagrams.md, implementation_notes.md
```

## 5. Godot / GDScript Conventions

- Use **typed GDScript** (`var speed: int`, `var stage: BattleStage`) and `class_name` for globally reusable types.
- For **definitions**, prefer `extends Resource` with exported fields so they can be edited in the inspector.
- For **runtime state**, prefer `extends Node` or an autoload for global Battle/Campaign management.
- Represent key enums (Stages, Phases, Zones, Morale states, Order types) with enums or constant dictionaries.
- Keep rule numbers or section references from the GDD in comments/docstrings for traceability.

## 6. Additional Reference

- See [reference.md](reference.md) for concrete GDScript patterns for:
  - Unit/Army definitions,
  - Battle stage/turn/phase state,
  - Zones and state transitions,
  - Orders and basic tests.
