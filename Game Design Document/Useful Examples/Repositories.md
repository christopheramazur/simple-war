# Useful Repositories

This document tracks external tools and examples we are intentionally using to build a scalable Simple War foundation.

## Core Foundation Addons

### ECS - https://github.com/csprance/gecs
**Why**: We want production-ready ECS patterns, query systems, relationships, and editor-facing workflows instead of maintaining a custom ECS runtime.

**How we use it**:
We want composition to heavily replace inheritance patterns, and to prioritize ensuring entities have the appropriate context and listening/emitting capabilities to manage the game state. Instead of a CampaignBattleList with CampaignBattles that have CampaignBattleBattlefields and CampaignBattleScores, all of which have to have their configuration and behavior be built beforehand, we build the Battle when it's appropriate, and give it the components it needs as it needs them such as the battlefield, and it tells everything that is listening for it that a battle is ready to take place on it. 

### Unit Testing - https://github.com/bitwes/Gut
**Why**: We need reliable regression coverage while building systemic campaign logic and battle resolution.

**How we use it**:
- Unit tests for component/system behavior and campaign rule evaluators.
- Integration smoke tests for PoC gameplay flow.
- Event log replay tests to lock save/replay behavior.

### Input Management - https://github.com/godotneers/G.U.I.D.E
**Why**: Input prompts and mappings must support keyboard/mouse, gamepad, touchscreen/mobile, and future rebinding.

**How we use it**:
- Abstract input actions behind context-aware bindings.
- Use prompt/icon capabilities for UI hints and accessibility.
- Keep gameplay code independent from raw input devices.

### Graph Authoring - https://github.com/tehelka-gamedev/godot-custom-graph-editor
**Why**: Sector maps are graph-based. Authoring, editing, and validating directed/undirected graph content benefits from dedicated graph tooling.

**How we use it**:
- Mapmaker workflow to author node/link topology and metadata.
- Export/import graph data for campaign JSON pipelines.
- Optional editor-side validation for invalid links or missing node metadata.

### Scene Flow - https://github.com/esdg/GodotSceneManager
**Why**: Campaigns and battles involve branching scene transitions that become harder to manage with manual path wiring alone.

**How we use it**:
- Visualize and maintain global scene transition graph.
- Reduce hardcoded scene change logic in UI scripts.

### Behavior Trees - https://github.com/bitbrain/beehave
**Why**: Campaign AI and tactical battle decision logic benefit from modular, inspectable behavior trees.

**How we use it**:
- Commander/NPC strategic behavior in campaign activities.
- Battle AI decision loops for movement, targeting, and order priorities.

### Dialogue/Narrative Events - https://github.com/nathanhoad/godot_dialogue_manager
**Why**: Campaign events and branching narrative choices should be data-driven and maintainable.

**How we use it**:
- Narrative activity plots and event nodes.
- Choice/result branching with condition checks tied to campaign state.

### Optional Physics Upgrade - https://github.com/appsinacup/godot-rapier-physics
**Why**: Potentially useful if deterministic and serialized collision-heavy simulation becomes central in battle order resolution.

**How we use it**:
- Evaluate only if native physics limits deterministic replay requirements.
- Keep as optional until battle collision depth justifies adoption.

## Genre and Pattern References

### RTS Selection/Movement - https://github.com/LeProfesseurStagiaire/rtsSelectionMoveDemo
**Why**: Good reference for unit selection, movement previews, formation-facing controls.

**How we use it**:
- Sector map and battle movement preview UX (ghost/path visuals).
- Selection model and drag interaction patterns.

### Real-time Strategy Structure - https://github.com/philipbeaucamp/godot-rts-entity-controller
**Why**: Useful architecture references for entity-heavy battlefield control loops.

**How we use it**:
- Reuse patterns for unit orchestration and system separation from UI.

### Idle/Battlefield Hybrid - https://github.com/hhy0111/-territory-conquest-idle
**Why**: Useful reference for automated progression and map/battlefield state loops.

**How we use it**:
- Event cadence ideas and passive progression patterns for campaign flow options.

### Godot Official Demos - https://github.com/godotengine/godot-demo-projects/tree/master/2d
**Why**: Canonical Godot implementation patterns for 2D systems, UI, navigation, and architecture.

**How we use it**:
- Targeted implementation references for specific subsystems.

### RPG Architecture Reference - https://github.com/gdquest-demos/godot-open-rpg
**Why**: Mature Godot project organization for content-heavy gameplay loops.

**How we use it**:
- Patterns for data-driven content, scene separation, and gameplay state management.

### Godot Game Template - https://github.com/nezvers/Godot-GameTemplate/blob/master/addons/top_down
**Why**: Mature Godot project template for a variety of feature implementations.
Menu system
Full Screen
Audio (Master, Music, Sounds)
Button state style tweaning
Pausing system
Input Rebinding
Frame by frame debug pausing (P - pause and advance, [ + P to unpause)
Scene transition using shader on a screenshot
precompile (Shader, CanvasMaterial, ParticleProcessMaterial) and preload scenes boot_load.tscn
Node reference managment ReferenceNodeResource
Easy instancing with configuration callbacks and dynamic instance pooling InstanceResource
Static functions for threaded loading ThreadUtility
Sound effect system SoundResource with autoloaded SoundManager
Resource saving SaveableResource
Data transmission system used for damage, pickups, obstacles AreaTransmitter
Scene central data collection ResourceNode
Enemy AI Astar grid path finding
Enemy wave spawning

**How we use it**:
- Patterns for features.


### Battle for Wesnoth - https://github.com/wesnoth/wesnoth/tree/master/src
**Why** While not a godot game, Battle for Wesnoth is a fully mature game with many of the features we want.

**How we use it**: 
- Feature mining, structural inspiration