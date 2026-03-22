# Godot Rapier Physics

- **Repository:** [github.com/appsinacup/godot-rapier-physics](https://github.com/appsinacup/godot-rapier-physics)
- **Simple War usage (from Repositories.md):** **Optional** — evaluate only if native physics limits **deterministic replay**; keep optional until battle collision depth justifies adoption.

## Project status

- **Not installed** — candidate for evaluation, not a default dependency.

## Authoritative documentation

- **README:** [github.com/appsinacup/godot-rapier-physics/blob/main/README.md](https://github.com/appsinacup/godot-rapier-physics/blob/main/README.md)
- **Docs site:** [godot.rapier.rs](https://godot.rapier.rs/) — implementation progress, feature parity
- **Changelog / architecture:** linked from README

## Why consider it (README)

- **2D and 3D** drop-in replacement using **Rapier** (+ **Salva** for fluids)
- Emphasis on **stability**, **performance**, **fluids**, **determinism**, **state serialization**, reduced ghost collisions
- **Determinism:** local deterministic simulation; **optional cross-platform deterministic** builds called out (separate AssetLib entries for “fast” vs “cross platform deterministic”)

## Installation (summary)

- **AssetLib** entries for Rapier 2D/3D, fast vs deterministic variants — README lists asset IDs
- **Manual:** GitHub release → copy `addons` into project
- **Project settings:** Advanced Settings → Physics → 2D or 3D → set engine to **Rapier2D** / **Rapier3D**

## Limitations (README)

- Double-precision builds disabled until Salva supports them
- Asymmetric collision pairs follow Rapier’s mask rule: `(A.layer & B.mask) != 0 || (B.layer & A.mask) != 0`

## Simple War decision checklist

- [ ] Does battle resolution **require** physics replay from event logs?
- [ ] Is **GodotPhysics** insufficient for stacking / tunneling / stability?
- [ ] Are we OK maintaining **platform-specific** or **deterministic build** constraints?
- [ ] Review [implementation progress](https://godot.rapier.rs/docs/progress/) for 3D gaps if using 3D combat

## Module builds

- Separate repos for module form: `godot-rapier-physics-module-2d` / `module-3d` (README links)
