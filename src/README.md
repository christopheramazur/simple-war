# Simple War - Runtime Structure

This directory now hosts a rebuilt PoC baseline aligned with the latest ECS and movement rules.

## Layout

- `autoload/` campaign session (`CampaignRuntime`) and GECS world bootstrap (`EcsWorldBootstrap`)
- `battle/runtime/` battle state and unit runtime wrappers
- `battle/systems/` movement, deployment, and minimal combat systems
- `ui/` scene flow: main menu -> campaign planning -> sector map -> armybuilding -> battle planning -> battlefield
- `docs/` implementation notes and PoC audits

## Design Notes from Reference Repos

- `rtsSelectionMoveDemo`: influenced movement preview (ghost destination + path line) and selection-centric controls.
- `godot-open-rts`: influenced separation of battle systems from scene/UI scripts.
- `massive-ecs`: influenced component/system naming and marker-component guidance in rules docs.
