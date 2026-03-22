# Simple War - Runtime Structure

This directory now hosts a rebuilt PoC baseline aligned with the latest ECS and movement rules.

## Layout

- `autoload/` campaign session (`CampaignRuntime` spawns `Entity` nodes with GECS `Component`s) and `EcsWorldBootstrap`
- `campaign/components/` campaign flow, commander state, audit log, battle session (`extends Component`)
- `battle/runtime/` battle state, unit runtime, `BattlefieldSimulation`, `BattleWorldHost` (second GECS world), `BattlefieldCoordinateMapper` / `BattlefieldLayout`
- `battle/README.md` campaign vs battle ECS boundaries
- `battle/systems/` movement, deployment, and minimal combat systems
- `ui/` scene flow: main menu -> campaign planning -> sector map -> armybuilding -> battle planning -> battlefield
- `docs/` implementation notes and PoC audits

## Design Notes from Reference Repos

- `rtsSelectionMoveDemo`: influenced movement preview (ghost destination + path line) and selection-centric controls.
- `godot-open-rts`: influenced separation of battle systems from scene/UI scripts.
- `massive-ecs`: influenced component/system naming and marker-component guidance in rules docs.
