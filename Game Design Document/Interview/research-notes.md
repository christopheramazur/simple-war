# Design Interview: Research Notes

Findings gathered by research agents during the interview. Reference material, not decisions.

## Facts found
- Global "unit"→"squad" replace corrupted 16+ words.
- No Kraken/ folder; Gardeners/Gameplay Notes.md empty; PoC.md missing.
- data/defaults factions Human/Xenos/Chaos/"Concord" match nothing in setting.
- Timeline: Humanity encountered ~50 Ma ("reached the stars only a few thousand years before"); Legivore ~10 Ma; Fracturing ~5 Ma–present. Zone table defines Second Magic as "Law cracking; uncontrolled leakage" and Ruin as "all story and structure consumed" — both contradict R1Q15.

## Research: modding architecture (done)
Layers: (1) data/prototype (Factorio data/updates/final-fixes 3-round patch, SC2 child-overrides inheritance, schema validation, merged-data hash) (2) declarative trigger/effect (Paradox/SC2; ~90% of campaign scripting; editor emits it) (3) sandboxed synced script runtime (Recoil gadgets; event-driven, nth-tick, per-mod instruction budgets, state only in declared serialisable store) (4) unsynced UI layer (widgets; read-only, commands via input stream).
Mod rules: no time/IO/OS/load; declared store + heavy-mode save/reload hash check; sim-owned seeded RNG; no floats in sim API; sorted-id iteration; instruction (not time) budgets; unsynced never writes sim; same mod list + data hash.
VM options: gilzoide lua-gdextension (Lua 5.4, ints, active; no budgets documented → custom count-hook + allocator GDExtension), Luau GDExtension (best sandbox primitives, doubles only), Wasm (strongest isolation, needs toolchain), godot-sandbox RISC-V. Avoid archived godot_luaAPI, godot-luau-script.
Early decisions: VM choice; fixed-point everywhere + deterministic trig; trigger vs script split & versioned event API; mod state/save/replay checkpoint+hash cadence; ranked mod policy; VM per battle vs shared, cross-battle visibility; manifest/deps/load order, campaigns-as-mods; desync tooling before mod API.

## Research: sim-core performance (done; bench in scratchpad/bench, gobench)
gecs v7.0.1: Entity/World/System are Nodes, Components are Resources, archetype columns of object refs, global ECS.world singleton (no clean multi-world / threaded battles), no determinism features.
ms/tick (both sides, fixed-point int, grid targeting, no pathfinding): 2,000 models → GDScript SoA 7.9 · RefCounted 8.8 · gecs iterate ~11-13.6 · gecs idiomatic ~16-18.5 · Go native 0.33 (≈24x faster than GDScript SoA). Spatial query/targeting dominates, not ECS layer. Heavy case 4 battles×1,200 → SoA ~16 ms/tick; at placeholder 300 ticks/turn ≈ 4.7 s CPU (native ≈0.2 s). Pathfinding not included.
Recommendation: drop gecs as sim core (maybe campaign/UI only); start GDScript SoA BattleSim (RefCounted, no Nodes/floats, own PRNG, state hash, step(orders)->events / snapshot() interface) so native core (Rust/C++ GDExtension, Lua embedded via mlua/sol2) can swap in; decide via spike (real loop incl. pathfinding/LOS/deaths at 600/side, threading 4-6 sims on WorkerThreadPool, MultiMesh snapshot cost, Lua hook cost, native toolchain friction — no cargo/gcc installed).

## Research: Slay the Spire modding (done, haiku)
StS1: ModTheSpire loader + BaseMod content API + SpirePatch bytecode patches (break on updates); jar + ModTheSpireInfo.json; Workshop since 2019 with "vanilla vs modded" launch choice.
StS2 (Godot, C#): mods = C# DLL + .pck assets + manifest.json; Harmony patching; BaseLib/ModConfig deps; official Workshop since June 2026 (~420 mods at launch); "Play with Mods" launch; first-run untrusted-code warning, no sandbox; separate modded saves; achievements off with mods; co-op needs same mods/order.
Godot: load_resource_pack (pck/zip; replaces same paths by default; load in autoload _init); packs can contain scripts → security risk; sign official packs.
Takeaways: data-first schema-validated mods; manifest (id, version, target API, deps) refuse on mismatch; hard official/modded line (separate saves, badge, no ranked/achievements with mods); record mod list in replays; no code mods in v1 (no internal patching); Workshop subscribe + Steam Cloud sync; reject packs with scripts/DLLs; if code later: explicit opt-in warning + signed official packs.
