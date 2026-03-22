# Battle runtime layers

## `BattlefieldSimulation` (RefCounted)

Authoritative PoC rules: deployment legality, engagement turns, combat resolution, unit arrays (`UnitRuntime`). No nodes, no drawing. Used by tests without loading UI scenes.

## `BattleWorldHost` (Node) + battle GECS world

A **second** GECS `World` parented under the battlefield scene. It does **not** assign `ECS.world` (the singleton remains the campaign/meta-game world from `EcsWorldBootstrap`).

- Battle systems and unit **components** can attach here later.
- `C_BattleScope` marks the root entity for this world.
- `BattleWorldHost._process` calls `world.process(delta)` on that world only.

## Campaign vs battle

| Concern | Location |
|--------|-----------|
| Commander flow, audit, sector | `ECS.world` + `CampaignRuntime` |
| Tactical units, combat steps | `BattlefieldSimulation` + (eventually) entities under `BattleWorldHost.world` |
