# Tooling and Foundation Plan

**Status**: Draft  
**Last Updated**: 2026-03-20  
**Purpose**: Define the GECS-first architecture and compare it against current implementation.

---

## 1. Ralph Loop: Adoption and Redesign

### Phase A: Suitability Review
- Validate each candidate addon/tool against PoC and long-term campaign goals.
- Prefer proven addons for ECS, testing, input abstraction, and narrative.

### Phase B: Current-State Review
- Inspect existing campaign/sector map implementation and data structures.
- Identify hardcoded behaviors that block scalability.

### Phase C: Target Pattern Selection
- Choose a coherent stack: GECS + GUT + GUIDE + selected editor/runtime helpers.
- Define integration boundaries (what each addon owns).

### Phase D: Refactor Plan
- Convert sector map state into ECS entities/components/systems.
- Keep PoC behavior intact while replacing brittle logic paths.

### Phase E: Validation
- Add tests and smoke checks for campaign flow + replayable event logs.
- Verify controls stay abstracted from raw devices.

## 2. Current Implementation (Observed)

- `src/ui/sector_map.gd` is currently UI-driven and hardcoded to two points (`ARMYBUILDING_POINT`, `BATTLE_POINT`).
- `src/autoload/game_state.gd` stores campaign flow as global booleans.
- `src/ui/armybuilding.gd` directly toggles state flags without system-level validation.
- `data/Sector_Maps.json` already contains ECS-shaped map/entity/component data.
- `data/Campaigns.json` includes campaign options but runtime does not yet consistently consume them.

### Main Gap
Data has moved toward component-driven structure, but runtime behavior still mostly lives in scene scripts and global flags. This mismatch is the primary scalability risk.

## 3. Original Approach vs New Foundation

### Original Direction (Custom Runtime First)
- Build custom ECS-like runtime and grow features manually.
- Fast for prototyping but long-term maintenance risk.
- Higher likelihood of reinventing core tooling (queries, editor support, testing ergonomics).

### New Direction (Tooling First, GECS-First)
- Use GECS as authoritative entity/component/system runtime.
- Use GUT for systemic test coverage.
- Use GUIDE to isolate gameplay from physical input devices.
- Introduce graph/dialogue/behavior plugins where they clearly reduce custom complexity.

### Why This Wins
- Faster path to robust architecture without ad-hoc framework growth.
- Better maintainability and testability for story mode depth.
- Cleaner separation between authored data, runtime logic, and UI presentation.

## 4. Target Sector Map Architecture

### Entities
- `SectorMap` aggregate entity or world context
- `ActivityPlot` entities
- `CommanderMeeple` entities
- `ArmyRepresentation` entities
- Optional `Connection` entities for richer link metadata

### Components (initial)
- `C_GraphNodeRef` (current node, position metadata)
- `C_Activity` (type, completion rules, rewards/results)
- `C_Commander` (owner, faction, progression state)
- `C_Army` (roster refs, readiness, followers)
- `C_Follows` (entity relationship)
- `C_Requirements` (conditions for traversal/activity)
- `C_AuditEmitter` (what events this entity emits)

### Systems (initial)
- `S_CampaignLoad` (build world from campaign/map JSON)
- `S_PathRequirementEval` (connection gate checks)
- `S_ActivityLifecycle` (begin/complete/fail activity transitions)
- `S_CommanderMovement` (move requests and state transitions)
- `S_AuditLog` (record all relevant sector-map events)

## 5. Implementation Priorities (PoC-Compatible)

1. Introduce GECS and migrate sector map entities/components/systems.
2. Replace direct boolean gating with requirement evaluation systems.
3. Keep PoC UX flow intact (Armybuilding -> Move -> Battle).
4. Add GUT tests for system behavior and event emission.
5. Add GUIDE-backed input abstraction layer for keybinds and controls.
6. Extend from two-node map to generalized graph traversal/events without changing core systems.

## 6. Acceptance Criteria

- PoC flow works end-to-end using ECS systems, not UI booleans.
- Sector map progression is data-driven from campaign/map JSON.
- Movement/activity restrictions are evaluated by reusable systems.
- All key sector map actions emit replay-friendly audit events.
- Core systems have automated tests and can evolve without scene-level rewrites.
