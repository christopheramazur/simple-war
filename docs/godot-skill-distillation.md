# Godot Master — Project Distillation (Simple War)

**Audience:** AI agents and humans. Read this first; then pull ONLY the modules in §12. Do not re-read SKILL.md top-to-top.

---

## 1. Non-Negotiable Architecture Rules (keep verbatim)

### 1.1 "Who Owns What?" — the architecture sanity check (Part 1)
Before writing any system, answer these three for **every** state variable:
1. **Who owns the data?** (`StatsComponent` owns health, NOT `CombatSystem`)
2. **Who is allowed to change it?** (Only the owner via a public method, e.g. `apply_damage()`)
3. **Who needs to know it changed?** (Anyone listening to the `health_changed` signal)

If you can't answer all three for a state variable, you have a coupling problem. Godot-specific note: **signals ARE the enforcement mechanism** — there are no access modifiers.

### 1.2 The Godot "Layer Cake" (Part 1)
```
┌──────────────────────────────┐
│  PRESENTATION (UI / VFX)     │  ← Listens to signals, NEVER owns data
├──────────────────────────────┤
│  LOGIC (State Machines)      │  ← Orchestrates transitions, queries data
├──────────────────────────────┤
│  DATA (Resources / .tres)    │  ← Single source of truth, serializable
├──────────────────────────────┤
│  INFRASTRUCTURE (Autoloads)  │  ← Signal Bus, SaveManager, AudioBus
└──────────────────────────────┘
```
**Critical rule:** Presentation MUST NOT modify Data directly. Infrastructure speaks exclusively through signals. Signals travel **UP, never down**.

> This is the load-bearing principle for "sim decoupled from presentation" + "tabs/windows into any ongoing combat." Each combat event is a LOGIC subtree with its own data; the tab UI is a read-only projection.

### 1.3 The Signal Bus Tiered Architecture (Part 1)
- **Global Bus (Autoload):** ONLY lifecycle events (`match_started`, `player_died`, `settings_changed`). Cap at < 15 events.
- **Scoped Feature Bus:** Each feature folder has its own bus (e.g. a `CombatBus` per combat event). *This is the scalable compromise — the key to many simultaneous combats.*
- **Direct Signals:** Parent-child communication WITHIN a single scene. Never across scene boundaries.

### 1.4 The "When NOT to Use a Node" Decision (Part 2)
| Type | Use for | Expert use case |
|------|---------|-----------------|
| `Object` | Custom data structures, manual `.free()` | Custom spatial hash maps, ECS-like data stores |
| `RefCounted` | Transient logic objects, auto-freed when unreferenced | `DamageRequest`, `PathQuery`, `AbilityEffect` — logic packets that never need the scene tree |
| `Resource` | Serializable data with Inspector support | `ItemData`, `EnemyStats`, `AbilityData` — any designer/mod-editable data |
| `Node` | Needs `_process`/`_physics_process`, must live in scene tree | Entities with spatial transforms only |

**Expert pattern:** `RefCounted` subclasses for all logic packets and data containers; reserve `Node` for the spatial tree. Halves scene tree overhead on complex systems.

### 1.5 Smart Interconnects (Part 1)
- **Data → Reactivity:** Serialized `Resource`s emit signals when modified → UI updates automatically, no tight coupling.
- **Networking → Bandwidth:** Bit-pack into `PackedByteArray` (not JSON/Strings) to keep packets under 100 bytes.
- **Physics → Performance:** `PhysicsServer2D`/`RenderingServer` bypass SceneTree for 1,000+ bullets/particles (O(1)).
- **Simulation (genre synthesis):** `Tick Manager` batch processing; avoid per-entity `_process` to sustain thousands of units.

---

## 2. DOTS / ECS Data Layer

**Primary references:** [composition.md](../GD-Agentic-Skills/skills/godot-master/references/composition.md) → [patterns/component_registry.md](../GD-Agentic-Skills/skills/godot-master/references/patterns/component_registry.md) → Part 2 §1.4 → Part 4 items #8, #10, #21.

### 2.1 Composition principles (composition.md — mandatory first read)
- Composition over inheritance ("Has-a" vs "Is-a"). In Godot, **Nodes ARE components**: a complex entity is an Orchestrator managing specialized Worker Nodes.
- Golden rules: (1) one script = one job; (2) components are "selfish" — they don't know who owns them; (3) the root orchestrator does **no logic** — it manages state and passes data; (4) decouple via **signals up / methods down**.
- Decision tree: gameplay entity behaviors → **Composition**; cross-scene services (net, save, economy, audio) → **Autoload**; true is-a engine specialization → inheritance (rare, never for "adds HP").
- **Mandatory first script:** `scripts/composition_composition_root_init.gd` — orchestrator wiring via typed `@export` + `%UniqueNames`. NEVER `$` paths / `get_node` to components.
- Available component scripts: `health_component.gd`, `hit_box_component.gd`, `hurt_box_component.gd`, `velocity_component.gd`, `interaction_component.gd`, `follower_component.gd`, `state_component_vsm.gd` (component-based FSM), `status_effect_component.gd` (stacked buff/debuff scenes — useful for rank/flank modifiers).

### 2.2 Entity orchestration contract (Workflow 2)
- State Machine queries an `InputComponent`; never handles input directly (allows AI/Player swap with zero refactoring — relevant to skirmish vs campaign vs AI opponents).
- State Machine ONLY handles transitions; **logic lives in components** (`MoveState` tells `MoveComponent` to act).
- **F6 test:** pressing "Run Current Scene" on any entity scene must work without crashing. If it doesn't, the entity has scene-external dependencies.

### 2.3 Data-oriented hot paths (Part 4 items)
- **#10** NEVER use `_process` on 1,000+ entities. One `Manager._process` that iterates an array of data structs (Data-Oriented pattern), or Server APIs (§2.4).
- **#8 / #18** NEVER use `String` keys in hot-path dict lookups. Use `StringName` (`&"key"`, O(1) pointer compare) or int enums.
- **#21** NEVER ignore Local-to-Scene on exported resources → shared-memory bugs across all instances of an enemy/ability.
- **#22** NEVER use `float` for currency — integer cents.
- **turn-system NEVERs (determinism core):**
  - NEVER use the Node hierarchy as source of truth — use a **Dictionary board state** for logical grid coordinates.
  - NEVER recalculate turn order every action — sort **once per round** or only when a speed-relevant stat changes (avoid O(n log n) per action).
  - NEVER use random tie-breaking for initiative — use a static secondary attribute (Agility, ID, "luck") for **deterministic replays**.
  - NEVER modify an active turn-order queue while iterating — iterate a `duplicate()` or apply mutations after the loop.
  - NEVER broadcast global turn state with immediate `call_group()` — use `call_group_flags(SceneTree.GROUP_CALL_DEFERRED)` when notifying hundreds of units.

### 2.4 Interaction with GECS
The project already has the **gecs** addon as the ECS backbone (autoload `ECS`). Use it for the attribute/entity/system core of the simulation layer; layer the skill's patterns **at the boundary**:
- GECS attributes = the owned data (§1.1 owners).
- `RefCounted`/`Resource` for logic packets and designer data that leave the ECS.
- Scoped Signal Bus per combat event for sim→presentation (§1.3).
- GECS systems = the "Tick Manager batch processing" — iterate attributes in bulk per intent phase, no per-entity `_process`.

### 2.5 The escape hatch — Server APIs (Part 6)
When SceneTree becomes the bottleneck (it will, at many simultaneous events):
| Trigger | Drop to |
|---------|---------|
| 10K+ rendered instances (sprites/meshes) | `RenderingServer` + RIDs |
| 1,000+ bullets/particles with script interaction | `PhysicsServer2D` body creation |
| Mass physics sim | `PhysicsServer3D` direct |

- **RIDs** are opaque 24-byte handles: 50K+ objects vs ~1–5K for nodes; <200B memory vs 2–10KB/node; O(1) direct access; **manually** alloc/free.
- **CRITICAL:** RIDs don't count as references — keep the `Texture`/resource object alive or the RID silently invalidates.
- **Threading:** SceneTree is NOT thread-safe; Server APIs ARE (when enabled in Project Settings). You may build scene chunks off-tree on a worker thread, but MUST attach via `add_child.call_deferred()`. Array resizing across threads needs a `Mutex`. NEVER load the same `Resource` from two threads — one loading thread.
- **Part 8 gotcha #7:** NEVER query `RenderingServer`/`PhysicsServer` getters in `_process` — forces a synchronous pipeline flush. Hot-path servers are **write-only**.

---

## 3. Simultaneous "Intent" Resolution (SOVL-style rank & flank)

**Primary references:** Part 2 decision matrix (rows: *Server-Auth Multi → Deterministic*; *Simulation/RTS → Batch Processing*; *Card/Board → Rule Enforcement*) → [turn-system.md](../GD-Agentic-Skills/skills/godot-master/references/turn-system.md) → [turn-system-elite-turn-patterns.md](../GD-Agentic-Skills/skills/godot-master/references/turn-system-elite-turn-patterns.md) → [combat-system.md](../GD-Agentic-Skills/skills/godot-master/references/combat-system.md) → [combat-system-elite-combat-patterns.md](../GD-Agentic-Skills/skills/godot-master/references/combat-system-elite-combat-patterns.md) → [ability-system.md](../GD-Agentic-Skills/skills/godot-master/references/ability-system.md).

### 3.1 Turn model decision (turn-system.md)
| Need | Model | Script |
|------|-------|--------|
| Discrete rounds + intent queue + AP | Round + initiative queue + AP phases | `turn_system_turn_system_patterns.gd` |
| CTB/timeline with interrupts + prediction UI | Event timeline + predictive UI | `turn_system_timeline_turn_manager.gd` |
| Continuous gauges (ATB) | Per-actor gauge in `_process` | `turn_system_active_time_battle.gd` (probably NOT applicable) |

> Don't invent a fourth model inline — read the matching script first.
> For simultaneous intents: the **timeline/CTB** path is closest (interrupts, pre-visualization). Use `turn_predictor.gd` to simulate intents for preview UI, and `combat_stats_resource.gd` (deterministic damage-preview Resource) so hover/preview panels can show exact projected outcomes — the preview is deterministic, the resolution is the same code path.

### 3.2 Determinism is a requirement, not a bonus (ranked multiplayer depends on it)
- All intent resolution: same inputs + same seed → same result. Integer math where possible; no `rand()` in resolution (seeded PRNG if needed).
- Phase transitions: **enum + match** or a dedicated FSM — NEVER `if phase == 0`.
- AP economy: call `can_perform_action(cost)` **before** `current_ap -= cost`; never `==`-compare floats for AP (`>=` / `is_equal_approx()`).
- Board grid: `AStarGrid2D` (not `AStar2D`) for pathfinding; call `update()` after any `set_point_solid()` change.
- UI input: `is_action_just_pressed()` (frame-locked menu input), never `is_action_pressed()`.
- Multiplayer: **server-side turn timeout with a default "pass"** so a stalled/disconnected client can't grief or freeze the resolution.

### 3.3 Combat & abilities
- [combat-system.md](../GD-Agentic-Skills/skills/godot-master/references/combat-system.md) + elite for damage pipeline, hitbox/hurtbox separation (matches `hit_box_component.gd`/`hurt_box_component.gd`), status effects (rank/flank modifiers → `status_effect_component.gd`).
- [ability-system.md](../GD-Agentic-Skills/skills/godot-master/references/ability-system.md) + elite: abilities as **data** (`AbilityData` resource) with a network/serializable payload — the intent is an ability id + parameters, not a code path.
- [rpg-stats.md](../GD-Agentic-Skills/skills/godot-master/references/rpg-stats.md): stat block patterns (elite stat patterns file) — one stats resource per unit, signals on change for UI.
- For balancing combat numbers (rank/flank damage curves): [monte-carlo-balancer](../GD-Agentic-Skills/skills/godot-master/references/monte-carlo-balancer.md) — abstract sim must be calibrated against headless Godot.

---

## 4. Many Simultaneous Combats — Sim/Presentation Split & Tab UI

**Primary references:** Part 1 (Layer Cake, Signal Bus) → [ui-containers.md](../GD-Agentic-Skills/skills/godot-master/references/ui-containers.md) + [ui-theming.md](../GD-Agentic-Skills/skills/godot-master/references/ui-theming.md) → [scene-management.md](../GD-Agentic-Skills/skills/godot-master/references/scene-management.md) → [patterns/safe_signal_handler.md](../GD-Agentic-Skills/skills/godot-master/references/patterns/safe_signal_handler.md) → Workflow 11.

### 4.1 Per-combat-event isolation
- Each ongoing combat event = its own **simulation scene/subtree** + its own **scoped CombatBus**. The global bus gets only `match_started` / `match_ended` style events.
- Tabs/windows = **stateless projection layers**. Rule of thumb: a UI node should never hold game state; it subscribes to the combat's bus and re-renders.
- [patterns/safe_signal_handler.md] is **mandatory** here: switching tabs can free/swap a combat view mid-resolution; never keep `Callable` refs to freed nodes, and disconnect in `_exit_tree()`.

### 4.2 UI rules (Workflow 9 + Part 4)
- **F6 Principle:** every UI scene (tab, panel, combat window) must run standalone.
- **Never connect UI buttons to gameplay logic directly.** UI emits a signal; the simulation/controller listens. Prevents crashes when a UI node is deleted.
- UI sends "Signal", `PlayerController`/combat manager listens.
- `MOUSE_FILTER_STOP` only on the background of a panel; `PASS` on children; NEVER leave `STOP` on transparent containers (eats clicks).
- No absolute pixel offsets — container sizing + theme-constant overrides (`add_theme_constant_override("separation", X)`); never deep-nest `MarginContainers`.
- Move UI elements with **Tween**, never `_process()` position writes.
- Never `queue_free()` a node while a Tween is still running on it (kill tweens in `_exit_tree()` or use `get_tree().create_tween()`).
- Dynamic loading: validate paths + allowlisted extensions (`.tres`, `.res`, `.theme`) — Part 11 security notes (adapted for mods, §8).
- **Camera subviewports** (minimap / combat previews): set `render_target_update_mode = UPDATE_WHEN_VISIBLE` (or lower rate) — don't render off-screen combat views at full rate.

### 4.3 Opening/closing combat windows without hitches (Part 6 threading + Workflow 11)
- Build presentation scene **off-tree** on a `WorkerThreadPool` worker (instantiate + add children), attach with `add_child.call_deferred()`.
- Workflow 11 (Builder) for **batch** combat-window/scene scaffolds: design hierarchy on paper → `create_scene.py` → `add_node.py` (set `owner` on every node) → verify with `run_project.py`. Use Builder for *structure*, GDScript for *behavior*.
- Preload effect assets during loading screens to pre-compile the GPU shader pipeline (avoid runtime frame-hitch on first use of a combat VFX).

---

## 5. Isometric Perspective — 2D Assets, Rotatable/Height Camera

**Primary references:** [camera-systems.md](../GD-Agentic-Skills/skills/godot-master/references/camera-systems.md) + [camera-systems-camera-expert-patterns.md] → [adapt-2d-to-3d.md](../GD-Agentic-Skills/skills/godot-master/references/adapt-2d-to-3d.md) (+ its migration notes/recipes) + [3d-world-building.md] (for the world container, not for streaming depth).

### 5.1 Camera (the "2D assets, 3D isometric" case is `adapt-2d-to-3d.md`)
- Use **`Camera3D`** for the isometric world (3D scene, 2D sprite assets, isometric-ish frustum). Smooth follow: `lerp()` or `position_smoothing_enabled = true` — NEVER `global_position = target.global_position` every frame.
- `look_at()` needs an **Up-vector fallback** (targets directly above/below flip the camera) — needed because height/rotation are adjustable.
- If using a spring arm: **collision mask is mandatory** (terrain/environment layer) or it clips.
- **Zoom must be non-linear**: exponential lerp or a `Tween` with `TRANS_CUBIC`. Never linear lerp for zoom (feels dead).
- Screen shake = dedicated **Trauma/Noise** system layered on follow (`camera_shake_trauma_pro.gd` is MANDATORY; the light variant `camera_shake_trauma.gd` too). NEVER `randf()` on `offset` as your whole shake system.
- `offset` is for shake/temporary recoil only; permanent framing goes in `position`.
- NEVER parent the camera to a high-speed physics body — use `RemoteTransform2D/3D` or phantom decoupling (with rotation sync disabled where needed).
- `Camera2D` (if used for any 2D HUD-adjacent views): `limit_smoothed = true` is mandatory; never have two `Camera2D` enabled in the same viewport.
- Minimap / second view: `SubViewport` + `render_target_update_mode = UPDATE_WHEN_VISIBLE` (or a low fixed rate).
- 4.7: check [camera-systems-migration-notes.md](../GD-Agentic-Skills/skills/godot-master/references/camera-systems-migration-notes.md) on the version hop.

### 5.2 Lighting — keep it 2D-cheap
- Never use real-time GI (SDFGI/VoxelGI) for 2D-looking content (Workflow 10 NEVER list). Stick to `DirectionalLight2D` / `CanvasModulate` equivalents and baked-look lighting.
- Keep shadow-casting lights minimal (budget: max 2 shadow-casting directional lights).
- 4.7 note: `AreaLight3D` exists (requires Forward+; project already has Forward Plus) but is almost certainly unnecessary for a 2D-asset game.

---

## 6. Multiplayer — Ranked / Casual / Custom

**Primary references:** [multiplayer-networking.md](../GD-Agentic-Skills/skills/godot-master/references/multiplayer-networking.md) → [server-architecture.md](../GD-Agentic-Skills/skills/godot-master/references/server-architecture.md) → [adapt-single-to-multiplayer.md](../GD-Agentic-Skills/skills/godot-master/references/adapt-single-to-multiplayer.md) + its `authority-and-security` and `prediction-and-reconciliation` companions → Part 2 row "Server-Auth Multi → Deterministic".

### 6.1 Authority model
- **Client sends Input, Server calculates Outcome.** The client NEVER determines damage, position deltas, or inventory changes (Part 4 #17: never trust the client for authoritative state).
- Validate **every** `rpc_id(1, ...)` call — a hacked client can send `damage = 999999`. Use the server-authority validator on every privileged RPC.
- For **simultaneous intents** this is especially clean: each client submits a small set of intents (ability id + params + target ref), the server resolves them all at once, and broadcasts the resolution. Intents are small, discrete, and deterministic — much friendlier to netcode than continuous state.
- Pack with `PackedByteArray` (bit-packing), keep packets small; never JSON/Strings on the wire.

### 6.2 Dedicated / headless host (ranked)
[server-architecture.md] "Host Golden Path" (MANDATORY order):
1. **Headless detect/init** — `server_architecture_headless_init_manager.gd` (`--headless` / `dedicated_server`).
2. **Safe decode** — `server_architecture_safe_packet_decoder.gd` before any untrusted `get_var` (forbids object decoding on untrusted packets — RCE guard).
3. **Host peer** — `server_architecture_enet_optimized_host.gd` (bandwidth/client limits).
4. **DTLS** — `server_architecture_dtls_secure_server.gd` when encrypting UDP.
5. **Authority** — `server_architecture_server_authority_validator.gd` on every privileged RPC.
6. **Ops** — kick manager, health telemetry, matchmaker handoff (`server_matchmaker_client.gd`).

Skill boundary note: `multiplayer-networking` = lobby UI, RPC signatures, MultiplayerSynchronizer, prediction/reconciliation. `server-architecture` = headless boot, ENet/DTLS, safe decode, authority. Load both for ranked; `server-architecture` first.

### 6.3 Client-side
- Client-side prediction + server reconciliation hides ~150ms of latency (mostly cosmetic in a turn-based game — prioritize **intent submission UX** over prediction).
- UDP/ENet, not TCP, for high-frequency traffic; handle drops with interpolation.
- `MultiplayerSpawner` handles replication in Godot 4 — configure **per scene**, not globally.
- Turn-based guard: server-side **turn timeout → default "pass"** (turn-system.md) so a single stalled client can't freeze a ranked match.

### 6.4 Determinism tie-in
Ranked mode = **deterministic resolution** (§3.2) + server-authoritative validation (§6.1). Casual/custom can relax: host-authoritative or lockstep as appropriate; keep the resolution code path identical so "sim" is never forked per mode.

---

## 7. Persistence — Campaign Saves

**Primary references:** Workflow 4 → [save-load-systems.md](../GD-Agentic-Skills/skills/godot-master/references/save-load-systems.md) + [save-load-systems-save-patterns-deep.md].

- **Dictionary-mapped serialization.** Old save files MUST NOT corrupt when new fields appear — always `.get("key", default_value)`. (Also the mod-compat seam: mod-added fields must default sensibly.)
- **Never save whole `Object` or `Node` instances** — they carry transient pointers. Extract data into `Dictionary` / custom `Resource`.
- **Never JSON for strictly-typed data** (`Vector2` etc.) — use `var_to_bytes` or `ConfigFile`.
- **Procedural worlds: save Seed + Delta-List of modifications**, not the map. (100 MB → 50 KB.) If campaign maps are procedural, this is the design.
- **Never block the main thread for auto-saves** — serialize large dicts on a `Thread` / `WorkerThreadPool`.
- **Never save to `res://` in an exported build** — strictly `user://`.

---

## 8. Steam Workshop Mods — SKILL.md GAP (honest note)

**SKILL.md and its 99 blueprints do not cover Steam / Workshop at all.** There is no modding module to "distill". What transfers, and what you must design:

| Concern | Source in SKILL.md | Adaptation needed |
|---------|--------------------|-------------------|
| Mod data as data | Workflow 3 (ONE `ItemData.gd` Resource → 100 `.tres` files) + Part 2 Resource row | **Design all gameplay data as Resources** so mods can be data-only. This is the single biggest architectural bet for Workshop. |
| Safe dynamic loading | Part 11 / Workflow 11 security: validate paths + allowlist extensions | SKILL's rule says "paths must start with `res://`" — that's for *agent* ingestion, NOT your runtime mod policy. For Workshop, allowlist `user://` mod directories, validate manifest + extension, and **never** execute untrusted `.gd` unless you ship an extension sandbox. |
| Save compatibility | Workflow 4 (`.get(key, default)`) | Versioned mod data schemas; default every mod-added field. |
| Exports / addons | [export-builds.md](../GD-Agentic-Skills/skills/godot-master/references/export-builds.md) | Workshop content is not an "addon" in the Project Settings sense; it's runtime-loaded from a user dir. Study export presets + resource paths carefully. |
| Multiplayer safety | server-architecture (safe decode, authority) | Mod-influenced game state must pass the same server-authority validation; a mod that emits bad intent data is an anti-cheat vector. |

**Recommendation:** Phase 1 mods = **data + assets only** (units, abilities, maps, themes — all Resources + textures, loaded from `user://` under a manifest). Code mods are a Phase-2 decision that requires a deliberate security design (GDExtension sandbox / trusted-code signing).

---

## 9. Performance Budgets (Part 5 — desktop targets)

| Metric | Desktop target |
|--------|----------------|
| Script time | < 8 ms/frame (move hot loops to Server APIs) |
| Draw calls | < 500 |
| Triangles visible | < 1M (LOD mandatory above 500K) |
| Texture VRAM | < 2 GB (BPTC compression — never ship raw PNG) |
| Active physics bodies | < 1000 |
| Particles | < 10,000 total |
| Audio buses | < 32 simultaneous |
| Save size | < 50 MB |
| Scene load | < 2 s |

**Workflow 5 — diagnose first, never optimize blindly:**
1. High script time → Profiler; check `_process` on hundreds of nodes → single-manager pattern or Server APIs (Part 6).
2. High draw calls → `MultiMeshInstance`; batch materials (ORM packing).
3. Physics stutter → primitive collision shapes; `_physics_process` not `_process`.
4. VRAM overuse → VRAM compression; never raw PNG.
5. Intermittent frame spikes → GC pass / synchronous `load()` / NavServer rebake → `ResourceLoader.load_threaded_request()`.

**Workflow 5 NEVERs:** no `get_nodes_in_group()` in `_process` (O(n) per frame — cache in `_ready()`); no `Area2D` for 1000+ overlapping objects (O(n²) broadphase — `ShapeCast2D`, `PhysicsDirectSpaceState2D.intersect_shape()`, or Server APIs); no `load()` in hot paths (preload at top, threaded for large); no optimizing before profiling (a 1 ms script is irrelevant against 2000 draw calls).

---

## 10. The NEVER List (trimmed — the items this project must never violate)

From Part 4 (numbered as in the source):
1. **NEVER** `get_tree().root.get_node("...")` absolute paths — use `%UniqueNames`, `@export NodePath`, or signal-based discovery.
2. **NEVER** `load()` in a loop or `_process` — blocks the whole main thread.
3. **NEVER** `queue_free()` while external references exist — clean up refs in `_exit_tree()` and null them first.
4. **NEVER** gameplay logic in `_draw()` — mutates state under the render thread; races `_physics_process`.
5. **NEVER** `Area2D` for 1000+ overlapping objects — O(n²) broadphase.
6. **NEVER** mutate external state from a component — components emit signals; listeners decide. (Your "who owns what" enforcement.)
7. **NEVER** `await` in `_physics_process` — physics steps skip frames.
8. **NEVER** `String` keys in hot-path lookups — `StringName` or ints.
9. **NEVER** store `Callable` refs to freed objects — disconnect in `_exit_tree()` / `CONNECT_ONE_SHOT`.
10. **NEVER** `_process` on 1000+ entities — single manager iterating data structs, or Server APIs.
11. **NEVER** `Tween` on a node that may be freed — kill tweens in `_exit_tree()` or `get_tree().create_tween()`.
12. **NEVER** query `RenderingServer`/`PhysicsServer` getters in `_process` — synchronous pipeline stall.
13. **NEVER** `call_deferred()` as an init-order band-aid — fix the real dependency.
14. **NEVER** circular signal connections — use a mediator (Signal Bus).
15. **NEVER** inheritance > 3 levels — compose instead.
16. **NEVER** `_process` for hit detection/movement in physics-heavy scenes — `_physics_process`.
17. **NEVER** trust the client for authoritative state (health, XP, inventory).
18. **NEVER** standard `String` for high-frequency runtime checks.
19. **NEVER** hand-rolled per-frame RVO avoidance in unit-heavy games — offload to `NavigationAgent` threading.
20. **NEVER** block the main thread for procedural gen / heavy I/O — `WorkerThreadPool`.
21. **NEVER** ignore Local-to-Scene on uniquely-used resources.
22. **NEVER** `float` for currency — integer cents.

Part 8 — Godot 4.x gotchas (all apply, 4.6 and 4.7):
1. **`@export` Resources are shared by default** — #1 reported Godot 4 bug. `duplicate()` in `_ready()` or enable Local-to-Scene.
2. **Godot 3 signal syntax compiles but does nothing** in 4.x — must be `signal_name.connect(callable)`.
3. **`Tween` is no longer a Node** — created via `create_tween()`, dies with its creator; `get_tree().create_tween()` for persistent tweens.
4. **`collision_layer` = what I am; `collision_mask` = what I scan** — same value on both = self-collide / missed hits.
5. **`StringName` (`&"key"`) is O(1) pointer compare; `String` is O(n)** — always `StringName` in `_process`.
6. **`@onready` timing**: runs after `_init()` but during `_ready()`. Constructor-time → `_init()`; tree access → `@onready`/`_ready()`.
7. **Server query stalls** in `_process` (see NEVER #12).
8. **`move_and_slide()`**: returns `bool` (collision occurred); `velocity` is a property set *before* the call.

---

## 11. Part 11 (Unity → Godot) — conditional
Only worth reading if the team has Unity background: nodes-vs-gameobjects, scenes-as-nested-prefabs (every reusable thing is a `.tscn`), signals as first-class observers, typed GDScript for compile-time opcode optimization, refcounting (no GC spikes — but **deterministic-free** also means "ref still held = not freed, period", which bites on freed-node bugs, see NEVER #3/#9), `StringName` for perf.

---

## 12. Module Reading Map — what to load, when (use ONLY what you need)

| Goal in this project | Load (SKILL part / Workflow) | Reference module(s) | Key scripts (`scripts/`) |
|---|---|---|---|
| ECS/entity architecture (with GECS) | Part 2 §1.4, Workflow 2, composition.md | composition.md, patterns/component_registry.md | composition_root_init.gd, health_component.gd, hit_box_component.gd, hurt_box_component.gd, state_component_vsm.gd, status_effect_component.gd |
| Turn/intent system & simultaneous resolution | Part 2 matrix (Sim/RTS, Card/Board), turn-system.md | turn-system.md, turn-system-elite-turn-patterns.md | turn_system_patterns.gd, timeline_turn_manager.gd, turn_predictor.gd, combat_stats_resource.gd |
| Combat / rank / flank damage | combat-system.md + elite | combat-system.md, combat-system-elite-combat-patterns.md | (see combat-system.md script list) |
| Abilities as data | ability-system.md + elite | ability-system.md, ability-system-elite-ability-patterns.md | (see ability-system.md script list) |
| Stats blocks | rpg-stats.md | rpg-stats.md, rpg-stats-elite-stat-patterns.md | (see rpg-stats.md) |
| Multi-combat tab UI | Workflow 9, Part 1 §1.2/§1.3 | ui-containers.md, ui-theming.md, scene-management.md, patterns/safe_signal_handler.md | — |
| Sim/presentation decoupling | Part 1 Layer Cake, Smart Interconnects | signal-architecture.md, autoload-architecture.md | — |
| Isometric camera (2D assets / 3D) | Workflow 11 (n/a), Part 5, camera-systems.md | camera-systems.md, camera-systems-camera-expert-patterns.md, adapt-2d-to-3d.md | camera_shake_trauma_pro.gd, remote_transform_decoupling.gd, phantom_decoupling.gd, spring_lerp_camera_3d.gd, zoom_damping_controller.gd |
| Multiplayer (ranked/casual/custom) | Workflow 8, Part 2 matrix (Server-Auth Multi) | multiplayer-networking.md, server-architecture.md, adapt-single-to-multiplayer.md (+ authority-and-security, +prediction-and-reconciliation) | enet_optimized_host.gd, safe_packet_decoder.gd, headless_init_manager.gd, server_authority_validator.gd, server_matchmaker_client.gd |
| Campaign saves | Workflow 4 | save-load-systems.md, save-load-systems-save-patterns-deep.md | — |
| Performance tuning | Workflow 5, Part 5, Part 6 | performance-optimization.md, performance-optimization-profiler-budgets-and-prewarm.md, server-architecture-rendering-physics-server-cookbook.md | — |
| Scaffolding (feature-first dirs, bus, templates) | Workflow 1 | project-foundations.md, signal-architecture.md, autoload-architecture.md, project-templates.md, gdscript-mastery.md | — |
| Testing (gut is already installed) | — | testing-patterns.md, testing-patterns-manual-testing-checklist.md, testing-patterns-expert-testing-patterns.md | — |
| Combat balance (optional, later) | — | monte-carlo-balancer.md (00..07 chain) | — |

**Skip for this project** (load only if requirements change): mobile/web porting (Workflow 6 mobile rows), procedural-gen depth (Workflow 7 — keep only the Seed+Delta save rule), cinematic lighting/VFX (Workflow 10 — keep only the "no real-time GI for 2D-looking content" rule), and all unrelated genre blueprints (shooter, platformer, horror, stealth, romance, racing, tower defense, battle royale, metroidvania, open-world streaming, etc.), plus the agent-vision modules.

---

## 13. Engine version — 4.6 → 4.7 hop

- `project.godot` is **config_version 5, features "4.6", "Forward Plus"**. SKILL.md targets **4.7+**.
- SKILL.md explicitly says: for **any** engine version upgrade, use the external **[godot-version-migration](https://github.com/thedivergentai/gd-agentic-skills/blob/main/skills/godot-version-migration/SKILL.md)** skill — hop-by-hop, and do NOT treat this hub as a migration changelog.
- Practical note: each module in the catalog ships a `*-migration-notes.md` companion (e.g. `camera-systems-migration-notes.md`, `server-architecture-migration-notes.md`, `turn-system-migration-notes.md`, `project-foundations-migration-notes.md`). On the hop, read the migration notes for every module you're touching, in the same order as the reading map.
- 4.7 cross-cutting items flagged by the hub: **AreaLight3D**/HDR (Forward+ required — we have it, but likely won't need it for 2D assets), **Asset Store** replacing Asset Library (relevant to how we evaluate third-party addons), input device ID constants, Jolt behavior changes.
- The project already ships the **4.7-compatible** input map style and `untyped_declaration=1` warning (Workflow 1 step 3 — keep it on).

---

## 14. Top 10 takeaways (if you read nothing else)

1. **Who owns what, who changes it, who must know** — for every state variable, before writing the system.
2. **Layer Cake:** presentation is a read-only signal listener; sim is the single source of truth.
3. **Scoped Signal Bus per combat event** — that's how N simultaneous combats stay decoupled.
4. **`RefCounted` for logic packets, `Resource` for data, `Node` only for spatial/per-frame.** (And GECS is already your ECS spine.)
5. **Deterministic, integer-safe, server-authoritative intent resolution** — sorted once per round, static tie-breaks, can-perform-then-deduct AP, server turn-timeout → pass. This is what makes ranked multiplayer solvable.
6. **`StringName` everywhere hot; no per-entity `_process` at scale; one manager iterates data; escape to Server APIs (RIDs) when you exceed ~5K nodes** — and never query server getters in `_process`.
7. **Tabs are stateless projections; never connect a button to gameplay; safe-signal-handler on every view that can be freed mid-resolution.**
8. **2D assets → 3D scene → `Camera3D` (non-linear zoom, trauma shake, `look_at` Up fallback, no raw position-set every frame); no real-time GI.**
9. **All gameplay data as Resources** — this is what makes Steam Workshop mods possible (data+assets phase 1).
10. **Hop to 4.7 via godot-version-migration + per-module `*-migration-notes.md`; read migration notes before touching each module on the hop.**
