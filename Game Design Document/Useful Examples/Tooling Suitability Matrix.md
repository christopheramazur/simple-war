# Tooling Suitability Matrix

**Status**: Draft  
**Last Updated**: 2026-03-21  
**Purpose**: Discovery output for `simple-war-uuh.1` covering adoption decisions for core tools/addons.

---

## 1. Decision Summary

- **Adopt now**: GECS, GUT, GUIDE
- **Adopt soon (phase-gated)**: Dialogue Manager, Beehave
- **Evaluate prototype first**: Custom Graph Editor, Scene Manager
- **Hold for later**: Rapier Physics
- **Reference-only**: RTS/Open RPG/demo repositories

## 2. Matrix

| Tool / Repo | Fit for PoC + long-term | Risk | Cost | Decision | Why |
|---|---|---|---|---|---|
| GECS | Very high | Medium | Medium | Adopt now | Replaces custom ECS runtime with mature entity/component/system foundation |
| GUT | Very high | Low | Low | Adopt now | Enables regression coverage for campaign systems and replay/audit logic |
| GUIDE | High | Medium | Medium | Adopt now | Future-proofs input for KBM/gamepad/touch and prompt abstraction |
| godot-custom-graph-editor | Medium-high | Medium | Medium | Evaluate prototype first | Strong map-authoring fit, but needs validation against campaign data pipeline |
| Beehave | High | Medium | Medium | Adopt soon | Good fit for scalable AI behavior trees in campaign and battle |
| Dialogue Manager | High | Low-medium | Low-medium | Adopt soon | Good fit for branching narrative events and campaign choices |
| GodotSceneManager | Medium | Medium | Medium | Evaluate prototype first | Useful for scene flow, but may overlap with lightweight custom flow management. **Spike**: [Scene_Routing_Spike.md](./Scene_Routing_Spike.md) — defer plugin until branching/transitions justify it; prefer thin in-repo path helper first. |
| Rapier Physics | Low-medium (current scope) | Medium | Medium-high | Hold for later | Not needed for current campaign map foundation; revisit for deterministic collision-heavy simulation |
| rtsSelectionMoveDemo | Medium (reference) | Low | Low | Reference-only | Useful movement/selection patterns and visual preview ideas |
| godot-rts-entity-controller | Medium (reference) | Medium | Low | Reference-only | Useful architecture ideas for entity-heavy control loops |
| territory-conquest-idle | Medium (reference) | Medium | Low | Reference-only | Event cadence/progression ideas; no direct foundation dependency |
| godot-demo-projects (2d) | High (reference) | Low | Low | Reference-only | Canonical implementation examples for targeted subsystems |
| gdquest open-rpg | High (reference) | Low | Low | Reference-only | Strong repo organization and content-driven gameplay patterns |

## 3. Adoption Sequence

### Phase 1 (immediate)
1. Integrate GECS and migrate sector map runtime baseline.
2. Integrate GUT and add tests for GECS systems.
3. Integrate GUIDE and route key gameplay inputs through abstraction layer.

### Phase 2 (after GECS baseline stable)
1. Add Dialogue Manager for campaign event activities.
2. Add Beehave for strategic commander/battle AI behavior authoring.

### Phase 3 (prototype validation)
1. Build small spike for graph authoring workflow with custom graph editor.
2. Scene routing: [Scene_Routing_Spike.md](./Scene_Routing_Spike.md) documents GodotSceneManager vs in-repo router; prototype **GodotSceneManager** only if branching/transitions outgrow thin helpers.

### Phase 4 (conditional)
1. Evaluate Rapier if deterministic physics serialization becomes a hard requirement.

## 4. Compatibility Notes

- Project currently targets Godot `4.6` in `project.godot`, aligning with GECS and GUT current Godot 4.x support.
- Keep plugin integrations modular and optional where possible (feature flags or integration wrappers).
- Do not couple core campaign data model to plugin-specific runtime types.

## 5. Discovery Exit Criteria

- Clear adopt/hold decisions recorded for each candidate tool.
- Integration order agreed and sequenced to reduce migration risk.
- GECS-first architecture remains the core direction for sector map and campaign systems.
