# GECS Campaign and Sector Architecture

**Status**: Draft
**Last Updated**: 2026-03-20
**Purpose**: Define a GECS runtime architecture for Campaign and Sector Map flow, including deterministic flow gating, audit/event replay, and save/load validation.

---

## Overview

This design outlines a GECS implementation where:

- Game state is represented by Entities and Components.
- Changes to the state are computed by Systems using component data. 
- Every action produces an append-only Event record for audit and replay.

We also want to consider how different systems will hook into our data models. For example, if an entity's data has been mutated by multiple components, we should be able to cleanly display the final value and precisely how it was calculated.

e.g. we should be able to show an aggregated view along the lines of 
- `Damage: 30 (Base 10, Increase 100%, Multiplier x1.50)`
or a detailed breakdown along the lines of
- `Damage: 30 (Base 10, Increases: {"source": "x", "value": y}, Multipliers: {"source": "x", "value": y})`

We also don't need everything to be ECS. Configuration, loaders, and various meta or orchestration components can sit outside of the ECS world where it would make sense, such as for input mapping and player-specific game settings, or multiplayer lobbies handling connections.

The architecture is split into major layers to support this:

- `Meta Layer` - This layer handles overall management of the game's lifetime across multiple launches by reviewing audit logs and savefiles. Player progression such as achievements, lifetime stats, unlockables, etc. are flagged by this layer. It has minimal communication with other components and layers.

- `Input Layer` - This layer handles input configuration and mapping. We want there to be an interface the game uses, and an interface that defines how the player interacts with that interface; the GUIDE addon mostly handles one side of this so we just need to ensure that all the actions a player can make accept inputs appropriately without being hardcoded. 

- `Configuration Layer` - This layer handles game and player settings such as Audio, Graphical, and other preferences. Some of these preferences such as game difficulty or game speed may be wired to the audit, while others such as changing the game's brightness or music volume don't need to be. Settings that are auditable can also be set to specific values or ranges that are imposed by game types (Ranked multiplayer, for example) or campaign rules. This layer does not directly action the settings, instead acting as the source of truth for persisting and conveying them.

- `Persistence Layer` - This layer is responsible for validating, reading, and writing audits and savegames. Other layers communicate events as appropriate to this layer for audit and saving. This layer is repsonsible for managing replayability artifacts such as the random seed, for notifying the meta layer if gameplay is currently in a valid state or not (for achievement and progress purposes), and similar activities that might involve writing to savefiles and audits. 

- `Game System Management Layer` - System composers that handle the actual management of systems during the game runtime. The game's systems live here and the layer acts primarily as a bus and interface allowing other layers to speak to the systems, as well as allowing the systemst to speak to each other. Systems fingerprint mutations to state for audit.  

  - `Game State Layer` - A sublayer of the system management layer, entities and components are kept here as a complete representation of the game's current state, without regard for audit or validity. This layer's purpose is to provide access to any entity or component

- `Presentation Layer` - This layer is responsible for matching scenes and configurations to the appropriate UI/UX. Graphics, Fonts, Audio, etc. -- if the player sees or hears something, this layer is what's showing it to them. This layer interfaces heavily with the configuration, input, and game state layers to map the underlying game state 


---

## Entity Archetypes

### Player Root Entity
- `PlayerTag` - Marks entity as a Player
- `PlayerProfileRefComponent` - Inherited from the Player's profile, unique ID that references them. 
- `PlayerConnectedComponent` - Given to a Player while they're connected to the game. 
- `PlayerSeatComponent` - Given to the player to denote which role they're playing as. A player could for example leave a game as seat 1 and reconnect in seat 2 to control different Players from the same profile
- `PlayerFactionComponent`
- `PlayerStateComponent`
- `PlayerFocusComponent`


### Campaign Root Entity

- `CampaignTag` - Marks entity as a Campaign
- `CampaignRefComponent` - Hashed datasource the campaign is built from, used for validity
- `StageComponent` - Information about the current stage, used to track player modifications to settings 
- `TurnComponent` - Information about the player's activity during the current turn, 
- `GlobalModifierComponent` 
- `RosterModifierComponent`
- `EventModifierComponent`
- `ObjectiveComponent`


### Sector Map Entity

- `SectorMapTag`
- `SectorMapRefComponent`
- `PlotIndexComponent`
- `ConnectionIndexComponent`
- 

### Plot Entity

- `PlotTag`
- `IdComponent`
- `DisplayNameComponent`
- `ActivityRefComponent`
- `PlotPositionComponent`
- `PlotGateRulesComponent`

### Connection Entity

- `ConnectionTag`
- `IdComponent`
- `SourcePlotRefComponent`
- `DestPlotRefComponent`
- `TravelCostComponent`
- `RequirementsComponent`

### Commander Entity

- `CommanderTag`
- `OwnerRefComponent`
- `CurrentPlotRefComponent`
- `TransitComponent`
- `CommanderIntentComponent`
- `CommanderProgressFlagsComponent`

### Activity Instance Entity

- `ActivityTag`
- `ActivityTypeComponent`
- `ActivityStatusComponent`
- `ActivityParticipantsComponent`
- `ActivityOutcomeComponent`

### Audit Event Entity

- `AuditEventTag`
- `EventSequenceComponent`
- `EventTypeComponent`
- `EventPayloadComponent`
- `EventActorComponent`
- `EventTickComponent`
- `EventHashComponent`

---

## Core Components

### Flow Gating Components

- `FlowStateComponent`
  - `phase: Opening | SectorTraversal | BattlePreparation | BattleActive | BattleResolved | CampaignConclusion`
  - `active_gate_set_id: String`
- `GateSetComponent`
  - list of gate predicates evaluated by `FlowGateSystem`
- `GateResultComponent`
  - latest per-gate pass/fail plus failure reason strings
- `CommanderProgressFlagsComponent`
  - normalized progress markers replacing ad hoc booleans
  - initial Quickplay markers:
    - `army_selected`
    - `moved_to_battle_plot`
    - `battle_planning_ready`

### Audit and Replay Components

- `EventSequenceComponent`
  - monotonically increasing integer for total ordering
- `EventPayloadComponent`
  - serializable dictionary containing deterministic input and outcome fields
- `ReplayCheckpointComponent`
  - snapshot metadata (`checkpoint_seq`, `checksum`, `save_path`)
- `AuditCursorComponent`
  - last applied sequence for incremental replay

### Sector Runtime Components

- `PlotPositionComponent`
  - UI position hint (`x`, `y`) for map rendering
- `CommanderIntentComponent`
  - requested action, for example `move_to_plot` or `start_activity`
- `ActivityOutcomeComponent`
  - normalized result from `Armybuilding` or `Battle` activity completion

---

## System Set

### Bootstrap and Data Systems

- `CampaignBootstrapSystem`
  - loads Campaign data, creates root/sector/plot/connection entities
- `QuickplaySeedSystem`
  - creates deterministic initial commander state for quickplay flow

### Flow Systems

- `CommanderIntentValidationSystem`
  - validates intents against requirements, ownership, and stage constraints
- `SectorTraversalSystem`
  - resolves legal plot moves and transit updates
- `ActivityLifecycleSystem`
  - creates/starts/completes activity instances
- `FlowGateSystem`
  - computes gate results and updates the campaign phase
- `SceneRouteSystem`
  - exposes a single route target for UI; UI follows route rather than owning transitions

### Audit and Replay Systems

- `EventCaptureSystem`
  - writes append-only Audit Event entities for all accepted intents and all state mutations
- `EventProjectionSystem`
  - builds read units for UI (button enabled state, note text, current route)
- `ReplaySystem`
  - rebuilds campaign state by replaying event sequence from checkpoint + tail
- `AuditIntegritySystem`
  - validates event sequence continuity and per-event hash chaining

---

## Deterministic Event Unit

### Event Contract

Each campaign mutation produces one event with:

- `seq`: strict sequence id
- `type`: namespaced event type (`campaign.intent.accepted`, `sector.commander.moved`)
- `actor_id`: commander/player/system origin
- `payload`: deterministic fields only
- `tick`: campaign tick/round reference
- `prev_hash` and `hash`: chain for tamper evidence

### Required Quickplay Events

- `campaign.started`
- `armybuilding.selected`
- `sector.move.requested`
- `sector.commander.moved`
- `battleplanning.started`
- `battle.started`
- `battle.resolved`
- `campaign.phase.changed`

### Replay Guarantees

- Replaying the same event stream from the same checkpoint must produce identical `FlowStateComponent` and route output.
- UI-specific artifacts are excluded from payloads.
- Time/randomness fields are forbidden unless seeded and recorded.

---

## Migration Map (Current -> GECS Runtime)

| Current location | Current behavior | GECS target | Migration step |
|---|---|---|---|
| `src/autoload/game_state.gd` `armybuilding_complete` | Global bool toggled in UI callback | `CommanderProgressFlagsComponent.army_selected` + `armybuilding.selected` event | Add component and event write in Armybuilding completion path, then remove bool reads |
| `src/autoload/game_state.gd` `commander_at_battle` | Global bool toggled in Sector Map button | `CurrentPlotRefComponent` + `sector.commander.moved` event | Replace `Move Here` bool write with move intent dispatch |
| `src/autoload/game_state.gd` `selected_army_name` | Global string selected in Armybuilding | `ArmySelectionComponent` on Commander and activity outcome event | Move selection into activity result projection |
| `src/ui/sector_map.gd` `_refresh_ui` | Button visibility from global flags | `EventProjectionSystem` read unit (`can_begin_activity`, `can_move`, `can_start_battle`) | Query projection to render controls |
| `src/ui/sector_map.gd` `_on_move_pressed` | Direct state mutation | Intent submit -> `CommanderIntentValidationSystem` -> `SectorTraversalSystem` | Route all actions through systems |
| `src/ui/campaign_planning.gd` | Direct scene transition to sector | `SceneRouteSystem` route update after `campaign.started` | Replace direct route logic with route projection |
| `src/ui/armybuilding.gd` | Direct `GameState` writes and return | `ActivityLifecycleSystem` for Armybuilding activity | Complete activity through system and emit outcome |
| `src/ui/battle_planning.gd` | Reads global selected army and toggles Deploy | Projection of activity outcome + gate result | Use read unit for selected force and deploy enabled |
| `src/ui/battlefield.gd` counters in `GameState` | Writes destroyed counters globally | `battle.resolved` payload and campaign projection update | Keep battle runtime, project result into campaign event |

---

## Incremental Delivery Plan

1. Introduce `Campaign Runtime` singleton with entity store and event append API.
2. Mirror existing quickplay booleans into components while keeping UI behavior unchanged.
3. Switch `sector_map` to projection-backed button state.
4. Route movement and army selection through intent + system execution.
5. Emit and persist quickplay event stream; add replay command for deterministic rebuild.
6. Remove obsolete `GameState` flow flags once projections fully cover UI needs.

---

## Validation and Quality Gates

- `Flow determinism`: same seed and inputs produce same event stream hash chain.
- `Replay fidelity`: replay reaches same route and gate state as live run.
- `No direct flow mutation`: UI scripts do not write campaign progression state.
- `Gate coverage`: each phase transition has explicit gate predicates and failure reasons.

---

## Risks and Mitigations

- **Dual-write drift during migration**: temporary mismatch between `GameState` and components.
  - Mitigation: add assertion checks while dual-write is active.
- **Replay payload bloat**: oversized payloads from UI-centric data.
  - Mitigation: enforce compact payload schema and projection-only UI fields.
- **Route thrash between systems and UI**: duplicated transition logic.
  - Mitigation: `SceneRouteSystem` is single route authority.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 0.1 | 2026-03-20 | Initial GECS campaign/sector architecture with entities/components/systems, event replay unit, and migration map from current UI/flag flow |
