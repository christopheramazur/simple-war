# Simple War — Design Overview

**Status:** Draft (consolidated)  
**Last Updated:** 2026-10-29  
**Purpose:** The single GDD document for direction on Simple War's design, architecture, and the v1 build (Tight Scope Digital Prototype). Consolidates the source documents listed below into one reference that designers and developers can act from.

**Sources consolidated (superseded by this document, retained for provenance):**
- `Foundation/Foundation.md` (Draft, 2026-03-18)
- `Foundation/Framework-Requirements.md` (Confirmed, 2026-03-18)
- `Foundation/campaign_sector_gecs_architecture.md` (Draft, 2026-03-20)
- `Overview/Main Concepts.md` (Draft, 2026-03-18)

**How to read the GDD as a whole:**

| Document / folder | Role |
|---|---|
| `Overview/Design-Overview.md` (**this doc**) | **Single source of direction.** What the game is, how it's architected, what v1 builds and why. |
| `Gameplay Rules/` | **Formal rules.** Battle Rules (100.x), Entity System Rules (200.x), Movement & Positioning Rules (300.x), Campaign Rules (800.x), Terminology. v1 implements a *subset* of these rules. |
| `docs/godot-skill-distillation.md` | **How to build** engine code here: architecture rules, never-lists, module reading map. |
| `Foundation/` | Source design docs, superseded by this document — kept for history. |
| `About/Introduction.md` | Project framing: pivot to digital-first, simulationist positioning. |

When this document and a rule document disagree, **the rule document is authoritative for the rule**, and this document should be updated (see Maintenance, end of doc). When this document and `Framework-Requirements.md` disagree on v1 scope, this document wins (it was written from the confirmed spec) and both are to be reconciled.

---

## 1. Big Picture

**Simple War** is about Players using **Commanders** to lead **Armies** on a **Campaign**. Campaigns take place across a 2D **Sector Map**. A Campaign has **Activities** — **Armybuilding** to rally forces, **Battle** to establish dominance in a sector, **Travel**, **Trade**, narrative events — and concludes when the Player has achieved its **Objectives** or can no longer participate in any Activities. The Conclusion produces a **Score** that determines the ultimate victor, even if all the Player's Commanders and Armies are lost.

Under the hood, every game object — Campaign, Commander, Army, Squad, Unit, Item, Battlefield, Battle — is an **Entity** in an **Entity–Component–System (ECS)** architecture. Components are what an Entity *is* (data); Systems are what it *does* (logic). All gameplay data is data, not code or scene state.

### What sets Simple War apart

- **Parallel and simultaneous gameplay.** In Heroes of Might and Magic, the overworld and battle are sequential turns. In Total War, the battlefield is simultaneous but battles are still sequential overworld turns. Simple War interweaves them: **battles happen at the same time as other overworld activities**, a Player may run **multiple Battles at once**, and each Battle progresses when all participants have issued their orders — resolved simultaneously. Activities carry **timers** that cost the Player's focus and reward quick play and a real game plan, even though the game is turn-based.
- **Simulation-first combat.** Every attack from every Unit is calculated and resolved in the simulation layer (integer math, deterministic); presentation does its best to display the action.
- **Rosters and limits.** Like Battletech, each Battle imposes restrictions on who and what can participate — deepening the strategic "go wide or go deep" decision.
- **Momentum-heavy, human-squad combat.** Resolution is based on the capabilities of a squad of average human soldiers, so massive aliens and advanced technologies feel devastating — but still vulnerable to heroic pluckiness and the occasional inhaled hand grenade.
- **Morale and identity.** Squads and Commanders can influence each other's morale and temperament, and squads have sensible defaults when not issued orders (autobattler-style).

### Modes and platforming

- **Quickplay** — jump straight into a Battle after an Army Selection step.
- **Skirmish** — a smaller, self-contained Campaign from a list, with Campaign-provided settings (starting Commanders, Faction, Difficulty, Number of Opponents).
- **Story** — the main game: a series of linked Campaigns detailing the narrative through gameplay; **the paid content**.
- **Challenge** — curated Campaign challenges.
- **Multiplayer** — Freeplay (any Campaign/custom content, unranked), Unranked (official campaigns/settings, no rank impact), Ranked (curated competitive campaigns, official squad data only, full rank tracking).
- **Armybuilding** — standalone Army management, outside any Campaign context.
- **Campaign Editor / Squad Editor** — custom content creation and sharing (Freeplay and custom Campaigns accept it; official Campaigns and Ranked use only official data).

The game is free, with a story-driven narrative mode paid for. User activity is captured in **replay files** — hash-chained so they're self-verifying against the game version — used for leaderboards and player stats.

---

## 2. Design Pillars

1. **Simulation is the source of truth.** Fixed-timestep, deterministic simulation. All hot-path math is integer. Same ticks + same inputs → same result. Determinism is a *requirement*, not a feature — ranked multiplayer depends on it.
2. **Data as data.** All gameplay content lives in `data/defaults/*.json`, loaded as `Resource`s at startup. No gameplay data in the scene tree or node properties. This is what makes Workshop-style mods (data + assets) possible.
3. **Presentation is a read-only projection.** UI never holds or mutates game state. UI **emits signals; the sim/controller listens.** Signals travel *up* the stack. Presentation reacts to sim events and never drives the sim.
4. **Parallelism with cost.** Everything advances on timers. Late participants pay into **reserve**; exhausted reserve auto-defaults. The same timer model drives overworld and battle turns.
5. **Modular contracts.** The interfaces and emitted events (`IEngagementResolver`, `IDamageModel`, `move_to`, the event contracts in §9/§10) are stable; v1 bodies are throwaway and are replaced without touching contracts when the full combat model lands.

---

## 3. Architecture

### 3.1 Layers (who owns what)

For **every state variable**, before writing a system, answer: (1) who owns the data, (2) who may change it (owner via a public method only), (3) who must know it changed (signal listener). Signals are the enforcement mechanism — Godot has no access modifiers.

| Layer | Owns | Rules |
|---|---|---|
| **Godot Infrastructure** | Engine services, performance monitoring | Identifies sim vs. presentation bottlenecks. |
| **Meta Layer** | Player profiles, lifetime stats, achievements, unlockables, valid-state notification | Minimal communication with other layers. |
| **Input Layer** | Player↔game interaction interface (GUIDE addon) | Two interfaces: how the *game* accepts input, and how the *player* maps it. All player actions go through named input actions — nothing hardcoded. |
| **Configuration Layer** | Game/player settings (audio, video, gameplay, accessibility) | Source of truth for settings; some settings (difficulty, game speed) may be auditable or constrained by game type (Ranked, campaign rules) and others (brightness, volume) not. Does not *action* settings; conveys them. |
| **Data Layer** | Content: JSON → `Resource`s at load | Manages structured data and sends information up where needed. Content is safe to ingest; mods ship as data + assets. |
| **Simulation Layer** | **The only layer that mutates game state.** ECS entities/components; timers; campaign/battle state; events. | Timers, squad/unit data, campaign state all live here. Mutators created with auditability in mind (metadata + event log → recreates state). |
| &nbsp;&nbsp;&nbsp;&nbsp;Game State Layer *(sub)* | Entity/component store: complete current state | Read access from other layers; independent of audit/validity concerns. |
| &nbsp;&nbsp;&nbsp;&nbsp;System Management Layer *(sub)* | System composers, scheduling, system-to-system bus | The "manager/coordinator" that orchestrates systems; systems **fingerprint mutations to state for audit**. |
| **Presentation Layer** | Everything the player sees/hears: scenes, HUD, UI, VFX, assets | Receives signals; read-only over sim state. Keeps framerate/animation concerns divorced from the sim. Moddable presentation. |
| **Peripheral** (alongside the layers) | GUT (tests), GUIDE (input), Dialogic (JSON dialogue → ECS components), Beehave (AI decision components), addons (`gecs`, `gut`, `guide`, `dialogic`, `custom_graph_editor`, `godot-rts-entity-controller`) | Not part of the data/sim/presentation flow; tests validate the same logic the sim uses. |

**Rule:** unless absolutely necessary, nothing in a layer above tells layers below anything. Nothing above the sim layer owns gameplay state.

**F6 principle:** every scene (entity scene, UI scene, combat window) must run standalone — no scene-external dependencies.

### 3.2 ECS model

- **Entity** — a unique ID. No inherent data or behavior; everything comes from Components.
- **Component** — a data structure attached to an Entity. Holds state (Statline: Endurance, Durability, Morale, Speed, Reflex) or serves as a filter. **Marker Components (Tags)** carry no data and provide keywords for grouping/filtering (`Infantry`, `Vehicle`, `Quickplay`, `Infantry`).
- **System** — logic operating on Entities with specific Components. Systems read Components, compute, write results back. **All game logic lives in Systems.** Where a group of systems needs a manager, that manager is the orchestrator/coordinator (System Management Layer).
- An **archetype** is a common Component combination defining a category of Entity.

Not everything is an Entity. Roster validation, score calculation, and the deployment process itself are structural/bookkeeping objects that carry no Components.

#### Core gameplay archetypes

| Archetype | What it is | Key components (v1 in parentheses) |
|---|---|---|
| **Unit** | An individual figure | Statline, Equipped Items, Destruction State *(v1: Statline, AttackProfile, Size, Position, Order, DestructionState)* |
| **Squad** | A group of Units | Statline, Faction Keywords, Squad Keywords, Composition, Abilities, Value, Zone, Morale State *(v1: Composition, Value, SquadKeywords, Position=center-point, Coherence)* |
| **Item** | Equipment or consumable | Item Type; optionally Attack Profile, Armour |
| **Commander** | A leader of an Army | Statline, Equipment, Abilities, Army Reference *(v1: Statline, Equipment, ArmyRef)* |
| **Army** | All Squads under a Commander | Commander Reference, Squad References, Value |
| **Battleforce** | Squads selected for a Battle | Army Reference, Squad References, Total Value |
| **Battlefield** | Spatial container of a Battle | Battlefield Dimensions, Deployment Zones, Terrain Index |
| **Battle** | A structured conflict | Battle Stage, Phase, Turn Counter, Victory Conditions, Casualty Report, Scoring |
| **Activity** | A Sector Map activity (Armybuilding, Battle, …) | Type, Status, Conditions *(v1: ActivityStatus, Conditions, Type)* |
| **Campaign** | The top-level game structure | Campaign Stage, Sector Map Reference, Objectives, Scoring Rules |

#### Campaign-runtime archetypes (GECS)

| Archetype | Key components |
|---|---|
| **Player Root** | PlayerTag, PlayerProfileRef, PlayerConnected, PlayerSeat (seat swap on reload), PlayerFaction, PlayerState, PlayerFocus |
| **Campaign Root** | CampaignTag, CampaignRef (hashed data source, used for validity), Stage, Turn, GlobalModifier, RosterModifier, EventModifier, Objective |
| **Sector Map** | SectorMapTag, SectorMapRef, PlotIndex, ConnectionIndex |
| **Plot** | PlotTag, Id, DisplayName, ActivityRef, PlotPosition (UI hint), PlotGateRules |
| **Connection** (Path) | ConnectionTag, Id, SourcePlotRef, DestPlotRef, TravelCost, Requirements |
| **Commander (sector)** | CommanderTag, OwnerRef, CurrentPlotRef, Transit, CommanderIntent, CommanderProgressFlags |
| **Activity Instance** | ActivityTag, ActivityType, ActivityStatus, ActivityParticipants, ActivityOutcome |
| **Audit Event** | AuditEventTag, EventSequence, EventType, EventPayload, EventActor, EventTick, EventHash |

#### Systems

*v1 (Tight Scope — only what's needed to play the prototype):*

| System | Role |
|---|---|
| Tick / Turn engine | Fixed-timestep sim clock; drives phases; owns the reserve timers; advances Issue → React → Resolve |
| Order system | Collects player + AI orders into the per-turn buffer; validates |
| Deployment system | Places squads in Deployment Zones (deployment stage) |
| Battle movement system | `move_to` → block-move (v1) → recompute unit positions + squad center-point |
| Coherence (stub) | Computes squad center-point; rule hooks are no-ops in v1 (hook for later morale-break "minders flee / brute charges") |
| Combat system | Orchestrates `IEngagementResolver` + `IDamageModel`; applies damage; emits §10 battle events |
| AI system | Deterministic; issues orders during Issue, reacts instantly at reveal; uses the *same* default-policy code path (just fast) |
| Morale / Ability | **Not built in v1 (reserved)** |

*Campaign-runtime systems (from the GECS campaign/sector design):*

| System | Role |
|---|---|
| CampaignBootstrapSystem / QuickplaySeedSystem | Load Campaign data; create root/sector/plot/connection/commander entities; deterministic initial state |
| CommanderIntentValidationSystem | Validates intents against requirements, ownership, stage constraints |
| SectorTraversalSystem | Resolves legal plot moves and transit updates |
| ActivityLifecycleSystem | Creates/starts/completes activity instances |
| FlowGateSystem | Computes gate results, updates campaign phase |
| SceneRouteSystem | **Single route authority** — exposes one route target; UI follows the route rather than owning transitions |
| EventCaptureSystem | Append-only Audit Event entities for accepted intents and state mutations |
| EventProjectionSystem | Read-units for UI (button enabled state, note text, current route) |
| ReplaySystem / AuditIntegritySystem | Rebuilds state from checkpoint + event tail; validates sequence continuity and hash chain |

### 3.3 Non-negotiables for the v1 build

| Rule | Requirement |
|---|---|
| ECS | Use the **`gecs`** addon (entities, components, systems, archetypes, scheduling). No custom ECS. |
| Simulation layer | **Fixed-timestep deterministic** sim; a sim tick clock drives the game; presentation is read-only over sim state. |
| Determinism | All hot-path math in **integers**. Same ticks + same inputs → same result. |
| Data as data | All gameplay content in `data/defaults/*.json` → `Resource`s at load. **No gameplay data in the scene tree / node properties.** |
| F6 | Every scene runs standalone (no scene-external dependencies). |
| Composition | Compose, don't inherit (refactor if >3 levels). |
| UI contract | UI **emits signals**; the sim/controller listens. UI never holds game state. |
| Scoped signal bus | Per-combat-event bus (global bus only for lifecycle, e.g. `match_started`/`match_ended`). This is how N simultaneous battles stay decoupled. |
| Scope | **Player vs AI only.** No multiplayer, no save/audit, no story, no editors in v1 (deferred items listed in §12). |

---

## 4. Campaigns, Sector Maps, Activities

- A **Campaign** is the top-level Entity organizing all gameplay for a group of Players. It has an **Opening** (terms: activity composition, Objectives), a **Narrative** (Activities), and a **Conclusion** (victor from Objectives + results). The Campaign System manages Sector Map navigation, Activity resolution, and Modifier layering (see Campaign Rules 800.x).
- **Campaign Modifiers** alter how Battles and Sector Maps work by modifying Components on Battle/Sector entities and overriding System parameters — **not** freeform rule text (see Campaign Rules 850.1): e.g. `TurnLimitComponent`, overriding Battlefield Dimensions/Deployment Zones, tightening Roster requirements, modifying Victory Conditions.
- **Sector Map:** Plots (points of interest) connected by **Paths**. Paths may be bidirectional, single-directional, or limited-use. Path navigation never strands a Commander. Default procedural maps avoid one-way/single-use dead-ends. Commanders may move without Paths only via Campaign rules/Abilities, evaluated at permit time.
- **Activities:** Plots host Activities. Almost always accessible: **Armybuilding** and **Battle**; others: Travel, Trade, Narrative Event. Not all Plots are accessible to all Commanders, and not all Commanders are interested in all Plots.
- **Campaign turn (overworld):** each Commander declares an **Intent** per turn — typical: **Travel, Event, Recruit, Battle**. Each Intent has a duration (turns present to realize it) and can be **interrupted** (e.g., an opponent Battles you mid-recruit — losing may prevent realization; if requirements are no longer met, you get less Value). Flat-footed penalties can apply to an un-anticipated Battle. Usually one Intent occupies a Commander's whole turn; abilities may allow multiple Intents by instant-realizing one (teleport). Overworld turns are also **simultaneous**: imperfect information is normal, and some abilities/settings let intent be revealed and reacted to.
- **Battles are not blocking Activities.** A Commander can start a Battle on one Plot and keep acting on the Sector Map (with other Commanders) while it progresses.

### Flow gating and progress (deterministic, component-backed)

| Component | Contents |
|---|---|
| **FlowStateComponent** | `phase: Opening \| SectorTraversal \| BattlePreparation \| BattleActive \| BattleResolved \| CampaignConclusion`; active gate-set id. |
| **GateSetComponent** | List of gate predicates evaluated by `FlowGateSystem`. |
| **GateResultComponent** | Latest per-gate pass/fail + failure reason strings. |
| **CommanderProgressFlagsComponent** | Normalized progress markers **replacing ad-hoc booleans**. Quickplay initial markers: `army_selected`, `moved_to_battle_plot`, `battle_planning_ready`. |
| **CommanderIntentComponent** | Requested action, e.g. `move_to_plot`, `start_activity`. |
| **ActivityOutcomeComponent** | Normalized result of completing an Activity. |

**Rules of flow:** UI never writes campaign progression directly. An intent → `CommanderIntentValidationSystem` (validates) → executing system (`SectorTraversalSystem`, `ActivityLifecycleSystem`) → state mutation is fingerprinted and recorded as an audit event → `FlowGateSystem` recomputes gates → `SceneRouteSystem` updates the single route target → UI reads projections (`EventProjectionSystem`: button state, note text, route) and never sees raw flags.

---

## 5. Armies, Squads, Rosters

- Players build and maintain **Armies** led by **Commanders**. A Commander is how the Player interacts with the Sector Map (moves between Plots, engages Activities); in Battle a Commander may appear as a powerful warrior on the field, a strategist issuing abilities from an interface, or anything between. A Commander can typically lead a **single Army** (Abilities/Campaign modifiers can change this). **A Player's Battleforces must always be led by at least one Commander at the start of a Battle**; a Battle that ends in a dead Commander leaves a disbanded Army — possible for other Commanders (ally or enemy) to recruit or destroy. Commanders are themselves deployable to the Battlefield as their own Squad (generic "slightly better than a regular Squad" Statline for v1).
- **Armies** are composed of **Squads**, composed of **Units** and **Items** (see Terminology). Unlike Heroes of Might and Magic, Units in a Squad are **not uniform** — some carry Abilities, Items, or Characteristics.
- Armies have **no innate limits** on size/composition; the **Campaign** imposes restrictions through **Campaign Modifiers**.
- Armies are organized into **Battleforces**. A Battleforce is the set of Squads a Player commits to a Battle. Squads may sit in multiple Battleforces — Battleforces organize strategic intent. Rules/templates can auto-fill an Army as Squads become available.
- **Value:** each Squad has a Value Component; Army/Battleforce Value is the sum, used for pairing and balancing Battles.
- **Rosters:** a **Roster** is a Zone that organizes Battleforces. The Zone System validates a Battleforce against Roster requirements (total Value, allowed Factions/Squads, …); a Battleforce can be listed in any Roster whose requirements it meets. The **default Roster has no restrictions.** *Theme: Rosters are imposed by The Law and its remnant Enforcers to stop the Galaxy descending into despotism.*
- **v1 needs only:** a way to define and store a small number of Armies per Player, plus a simple validation step — "can this Army be used in this Battle / Campaign?"

---

## 6. Battles

A **Battle** is an Entity of the Battle archetype, fought between two opposing **Battleforces** of similar total **Value** on a **single Battlefield** (Dimensions, Deployment Zones, Terrain Index). It runs until one Battleforce is wiped out or another **VictoryCondition** is met. The Battle System advances its **four Stages** in strict order (Battle Rules 100.2), delegating to specialized Systems within each:

1. **Planning** — Players choose which Commanders/Squads form the Battleforce; the Zone System validates each Battleforce against Roster requirements; pre-Battle information (Faction relationships, etc.) is revealed. v1: select the Commander's existing Army (built at Armybuilding) — that's the whole Planning stage.
2. **Deployment** — Players **simultaneously and hiddenly** arrange Battleforces onto the Battlefield within each side's **Deployment Zone**. Squads not initially deployed are set to **Reserves** (reinforcements), deployed later via other means — ambush, outflanking, teleport — as Commanders, Abilities, and Modifiers allow. v1: drag/multi-select squads wholly into the zone.
3. **Engagement** — repeating cycle of **Turns**, each broken into **Phases** tracked by the Battle's PhaseComponent (full phase list and Order types in Battle Rules 130–133.x; v1 uses the reduced cycle in §7). The Battle System delegates to the Movement, Combat, Morale, Zone, and Ability Systems to resolve Orders and consequences.
4. **Consolidation** — the victor is determined from the VictoryConditions; the Battle's **CasualtyReport** and **Scoring** record outcomes for the Campaign layer. v1: units + squads destroyed per side; **score = value of units destroyed**; victor declared.

**v1 minimum:** a Battlefield Entity where two Battleforces can deploy; a minimal Turn/Phase structure in Engagement; a simple Consolidation that declares a winner and hands high-level results to the Campaign layer.

---

## 7. Turns and the Timer ("Reserve") Model

A **single reusable, simulation-layer-driven timer system** serves **both** overworld and battle turns, with a **separate default config per context**. (The word "reserve" here is the *timer* reserve — distinct from *Reserve* squads/zone in the rules.)

### Model
- Each participant is granted a `turn_time` per turn.
- Execute **within** `turn_time` → `reserve` **untouched**.
- Take **longer** → the **overshoot eats into `reserve`**.
- `reserve == 0` before execute → **auto-execute with defaults**. Per-unit default policy: **in range → attack, else move toward nearest enemy.**
- **No banking:** unused time never adds to `reserve`.
- **Top-up rule:** when `reserve < 60 s`, set `reserve = max(reserve + 30, 60)` **and** `turn_time = 60 s` → the player gets 2 minutes that turn.
- **Sim-owned:** `reserve`/`turn_time` are sim state, decremented by the tick clock during the turn. "Timer hit 0" fires a **deterministic sim event** (apply defaults / execute) — **never a UI callback.**
- **The AI has a timer too** (same model), but its decision algorithm completes well before its clock. No special-casing.

### Default configs (confirmed; configurable, not hard-coded)

| Field | Overworld | Battle |
|---|---|---|
| Initial reserve | 300 s | 180 s |
| Base `turn_time` | 300 s, flat | 180 s, **+60 s/turn** |
| Top-up | yes (reserve<60 → max(reserve+30,60), turn_time=60) | yes (same) |
| Banking | none | none |
| Reaction window | 30 s | 10 s |

### Per-turn battle sequence (v1)

1. **Issue** — each participant works under its turn timer (`turn_time` + `reserve`). May execute anytime: early → reserve untouched; overshoot → eats reserve; reserve 0 → auto-default.
2. **Lock + Reveal** — Issue ends when **all** participants have executed (or defaulted). All orders are revealed.
3. **React** — a single shared, flat window (default **10 s**, sim-driven). Each participant may **re-issue** a unit's order (manual) and/or apply an **auto policy** (default: *"decline all"*). **The AI reacts instantly at reveal.**
4. **Resolve** — **Movement** (apply all move orders as squad block-move) → **Combat** (`CombatSystem` → `IEngagementResolver` → `IDamageModel` → apply damage, emit §10 events).
5. **Next turn** — `turn_no + 1`; timers recompute.

The overworld turn reuses this same shape with its own (more generous) config; in the Tight Scope prototype the overworld is effectively two activities (Armybuilding → Battle), so overworld turning is minimal.

---

## 8. Combat, Coordinates, and Contracts

### Coordinates and positioning
- **Fixed-point integer coordinates**, called simply **"coordinates"** — unitless (100 units per squad ≈ 1 m).
- v1 battlefield: **100 squads tall × 200 squads wide** = **10,000 × 20,000 units**.
- Position struct reserves height: `{ x:int, y:int, z:int (0 = ground) }`. `z` unused in v1 (terrain/height later).
- **Each Unit owns its own absolute position.** Squad position is **derived** = center-point (mean of unit positions), tracked by coherency rules.
- **Coherence (v1 = stub):** `CoherenceSystem` computes the squad center-point and exposes a rule hook; rules are **no-ops** in v1. This is where morale-break "minders flee / brute charges" divergence plugs in later.
- **Movement:** an order is a target; the engine resolves the route via a single **`move_to(squad, target)`** interface. **v1 = block move** (same delta to every unit, relative offsets preserved, direct route). Future: pathfinding (obstacles, height) swaps in behind the same interface.
- **Deployment zones:** enemy = top 20 squads (2,000 units), player = bottom 20 squads (2,000 units). A squad drops **only wholly in-zone**.

### Contracts (v1 — keep stable; only swap bodies)

| Contract | Shape | Notes |
|---|---|---|
| **Order** | `{ type: none \| move_to(pos) \| attack(target) }` | per-unit. `attack` is in the enum but the **UI offers move only** in v1. |
| **Engagement** | `{ attacker_units[], target_unit, combat_type }` | resolver output |
| **DamageResult** | `{ target_unit_id, amount, killed }` | |
| **TurnState** | `{ phase, turn_no, participants[] { reserve, turn_time, executed, orders[] }, reactions { window_remaining, participants[] { policy, manual_orders[] } } }` | |
| **Coherence** | `{ squad_position (center-point), rules: [] (no-op) }` | |
| **IEngagementResolver** | reads the *whole battlefield* → `List<Engagement>` | *Who attacks whom, and how.* Drop-in. |
| **IDamageModel** | `evaluate(engagement, attacker, target) → DamageResult` | *How much damage.* Drop-in. |

### v1 throwaway combat bodies
- **Resolver:** for each surviving unit, nearest enemy within its Attack-Profile range → one engagement; none in range → none.
- **Damage:** `attacker.attack_profile.damage` (int) → subtract from target `durability`; kill at ≤ 0.
- **Explicitly slated to be replaced** when combat becomes the full RTS autobattle simulation (asymmetric events, per-unit positioning, the full order/reaction set from Battle Rules 132–133.x). Keep the **interfaces and emitted events stable**; swap only the bodies.

### Full-combat direction (post-v1)
A\* pathfinding, precomputed paths per movement component, formation selection with sensible defaults, ghost paths for planned movement, run-and-gun vs. dig-in behavior, Reactions distributed either as a timer-based free-for-all or a banked spend. All resolution happens in the simulation layer; presentation displays.

### Readability requirement
Because multiple components can mutate a value, derived values must be displayable **with their calculation**, e.g.
- `Damage: 30 (Base 10, Increase 100%, Multiplier x1.50)`
- or a detailed breakdown: `Damage: 30 (Base 10, Increases: {source: "x", value: y}, Multipliers: {source: "x", value: y})`

---

## 9. Data Model (v1)

All content below is **data, loaded at startup** (`data/defaults/*.json` → `Resource`). **v1 content: one Commander, one unit type, five Riflemen squads (one Militia army), one Battlefield, one Campaign.**

| File | Key fields |
|---|---|
| `commander/generic` | `id, name, statline{ durability, speed }, equipped_items[], squads[]` |
| `unit/rifleman` | `id, name, size{ w, h }, statline{ durability, speed }, attack_profile{ damage, range_band[min,max], damage_type, category }` |
| `squad/riflemen` | `id, name, units[] (10× rifleman), value, default_formation (auto-rectangle)` |
| `battlefield/default` | `id, name, dimensions{ w, h } (100×200 squads), deployment_zones[]{ side, region }, terrain (generic grassland)` |
| `campaign/quickplay` | `id, name (quickplay), marker (quickplay), sector_map_ref, opening, objectives, conclusion{ victor by score }` |
| `sector_map/quickplay` | `plots[] { armybuilding, battle }, paths[] { from, to, requirement: army_built }` |
| `activity/*.json` | `id, type (armybuilding \| battle), plot, requirements[]` |

**Statline note:** Endurance / Morale / Reflex are **present but unused in v1** — placeholders for Morale, hit/miss, and decay systems not yet built. v1 does real work with only `durability`, `speed`, and `attack_profile`.

---

## 10. Events, Audit, and Replay

### Battle event contract
The v1 `CombatSystem` (and turn engine) emit exactly these; presentation (and the future audit system) subscribes to exactly these:

```
turn_started(battle, turn_no)
orders_revealed(battle, side, orders[])
engagement_resolved(battle, engagements[])
unit_damaged(battle, target_unit_id, amount, source_unit_id)
unit_destroyed(battle, target_unit_id, source_unit_id)
turn_resolved(battle, casualties_by_side)
battle_ended(battle, victor_side)
```

### Deterministic event unit (campaign layer)
Every campaign mutation produces one **append-only** Audit Event:

- `seq` — monotonically increasing sequence (total order)
- `type` — namespaced (`campaign.intent.accepted`, `sector.commander.moved`, …)
- `actor_id` — commander/player/system origin
- `payload` — deterministic fields only
- `tick` — campaign tick/round reference
- `prev_hash` + `hash` — tamper-evidence chain

**Required Quickplay events:** `campaign.started`, `armybuilding.selected`, `sector.move.requested`, `sector.commander.moved`, `battleplanning.started`, `battle.started`, `battle.resolved`, `campaign.phase.changed`.

**Replay guarantees:** same event stream + same checkpoint → identical `FlowStateComponent` and route output; **UI-specific artifacts are excluded from payloads**; time/randomness fields are forbidden unless seeded and recorded.

Supporting components: `ReplayCheckpointComponent` (`checkpoint_seq`, `checksum`, `save_path`), `AuditCursorComponent` (last applied sequence, for incremental replay). `AuditIntegritySystem` validates sequence continuity and hash chaining; `EventCaptureSystem` writes the append-only stream; the System Management Layer fingerprints system state mutations.

### Determinism status
Determinism is a requirement and is *already in place* in the v1 sim (integer math, fixed tick, deterministic AI). The event-log + binary save + replay-hash infrastructure is **deferred** to post-v1 — the contracts above are exactly what it hangs on.

---

## 11. User Experience

**Main Menu** options: Quickplay, Skirmish, Story, Multiplayer, Armybuilding, Campaign Editor, Squad Editor, Settings, Exit Game. *(v1: Quickplay + Quit only.)*

**Contextual menu** — at any time, a configurable Hotkey (default **F10**) or the **Menu button** (top-right corner) opens: Main Menu, Settings, Exit Game. Contextual options as appropriate: **Save** (Sector Map, Battle), **Concede** (Campaign or Battle).

**Interaction expectations (Tight Scope):** responsive to standard digital controls — double-click to confirm selection, right-click for context menu, scroll wheel for zoom, pan with WASD or mouse3, drag-click empty space to multi-select, click-and-drag to move.

- **Quickplay** — straight into a Battle (v1 flow is §12). Full: simplified Army Selection for player + computer opponent, Battlefield + Objectives selection, then begin the Battle with the full Armies as Battleforces.
- **Skirmish** — Campaign list (searchable) + details display (configurable options provided by the Campaign — some fixed, some defaulted, some forced); option to load an existing Story save.
- **Story** — linked Campaigns detailing the narrative; choices gate what's available. Option to load a Skirmish save.
- **Multiplayer** — Freeplay (any/custom Campaigns and content), Unranked (official data/settings, no rank impact), Ranked (curated competitive campaigns, official squads, full win/loss/metadata tracking). Saved multiplayer games let players swap seats on load.
- **Armybuilding** — standalone Army management. Army List Panel (search, filters: Faction/Commander/Value, validation status) + Army Editor Panel (Commander, Squads, Units, Items; add/remove/rename; live value total; inline Roster warnings). Armies built here are usable in Quickplay/Skirmish/Story/Multiplayer; changes never affect a live Campaign's snapshot of the Army.
- **Campaign Editor** — Campaign Browser (custom + installed, publication status Draft/Published/Archived); Sector Map Canvas (drag plots, draw connections, assign Activities; connection requirements + visual style); Properties Panel (activity type, Roster restrictions, Objectives, narrative text, AI settings; **Campaign Modifiers as Component modifications + System parameter overrides, not freeform rule text**). Validates the graph is completable (no unreachable Plots, valid Opening→Conclusion path) before publish. Export/shareable.
- **Squad Editor** — Squad Browser (custom + official read-only; duplicate official as a base); Component Editor (Composition, Faction/Squad Keywords, Statline, Abilities, Value; unit slots with Statline/Items/Equipment Costs; Attack Profile inline: category, range brackets, damage, type, modifiers); Validation Panel (live consistency feedback + balance estimate vs. similar official Squads). Enforces structural validity, not balance (that's the Roster's job). Export/shareable.
- **Settings** — Gameplay (timer defaults, autosave, tooltip verbosity, confirmation prompts, AI difficulty), Controls (rebindable hotkeys, mouse sensitivity, scroll speed, camera inversion, drag thresholds), Video (resolution/display, frame cap, VSync, quality presets, shadows/AA/particles/grid-marker toggles), Audio (master/music/SFX/UI/voice, device, spatial), Accessibility (colorblind modes, UI scaling, font size, screen reader, reduced motion). Current value + default shown; Restore Defaults per tab and global.
- **Exit Game** — confirmation listing unsaved contexts (active Campaign, unsaved Army edits, in-progress Battle); Save and Exit / Exit without Saving / Cancel.

---

## 12. Tight Scope Digital Prototype (v1) — the acceptance test

### Deliverable
A **framework** (not merely a prototype) whose correctness is *verified by playing the Tight Scope prototype*. We build the architecture — ECS + deterministic simulation + data model + timer + combat manager — and prove it by reaching the prototype's end-to-end flow:

```
Main Menu → Quickplay → Campaign Planning → Sector Map
  → Armybuilding (select "Militia") → Commander to Battle Plot
  → Battle Planning (select army) → Deployment (drag squads in-zone)
  → Engagement (Issue → React → Resolve, turn-based) → Consolidation (stats)
```

### Prototype UX spec

- **Main Menu** — "Simple War" title; options: **Quick Play** (others: **Quit Game**). A **Menu** button at the top-right of every screen returns to Main Menu or quits at any point.
- **Campaign Planning** — campaign info: *"A single Battle against a single opposing commander, with pre-built armies."* **Back** / **Embark** at bottom-right. "Embark" → Sector Map.
- **Sector Map** — a star chart with two circled plots: **Armybuilding** and **Battle**, connected by a **dotted-line arrow**.
  - Hover/right-click the arrow → *"Requirements for travel: Build an army!"*
  - A small **Commander meeple** on the Armybuilding plot; the Armybuilding plot is **subtly highlighted**; a side note reads: *"We need an army to approach the battle!"*
  - Movement to the Battle plot is **gated** until Armybuilding completes.
  - Start the activity via right-click context menu **"Begin Activity"**, double-click the plot, Enter, or the bottom-right **"Begin Activity"** button.
- **Armybuilding screen** — lists a single **"Militia"** army; highlight and select it (appropriate controls), returning to the Sector Map.
- **Post-activity** — Commander meeple **inherits the highlight**; a small **"army" meeple** attaches next to it; note updates to: *"Move your Commander to the battle!"*
- **Move to Battle plot** — double-click, select + Enter, bottom-right **"Move Here"**, or right-click → **"Move Here"**.
- **At the Battle plot** — note updates to: *"Better them than us!"* Begin the Battle with the same controls used for Armybuilding → Battle Planning screen.
- **Battle Planning** — **"Select Army"** from the Commander's Battleforces (the same army just built — that's all Planning needs for now); **"Deploy"** at bottom-right → Battlefield.
- **Battlefield**
  - **100 squads tall × 200 squads wide**; 1 squad-distance ≈ 1 in-world meter.
  - Generic grassland texture surrounded by grey.
  - **Top 20 squads** tinted **Red** with a dotted line at the 20-squad mark (opponent zone); **bottom 20 squads** tinted **Blue** with a dotted line (player zone).
  - Zoomable; **grid markers** scale with zoom: fully zoomed-in = 1-squad markers; zooming out swaps to 3-squad, then 6-squad markers (and back).
  - Zoom limits: no finer than a 6×6 grid of 1-squad markers; no coarser than seeing the whole battlefield plus 6 squads of grey margin.
  - The selected Army sits in the grey to the side: **5 squads of "Riflemen"**, each 10 circles in a rectangle. Circles keep their rectangle positions for now, but the implementation must leave room for movement, pathfinding, and formation.
  - **Drag / multi-select-and-drag / drop** squads onto the Battlefield — **only wholly within the deployment zone**.
  - Top-middle **"Engage Enemy"** button enables once deployment is done (also: Enter, or right-click battlefield → context menu → "Engage Enemy").
  - Deployment zone indicators go away; **"Engagement Stage: Turn 1"** displays and fades after 3 seconds.
- **Engagement**
  - Click-and-drag movement planning; plans displayed as a **ghost path** — dotted line with a translucent copy of the squad at the end.
  - **"Execute Orders"** at bottom-right. A squad may go without an order, but the player is **prompted to review remaining un-ordered squads**.
  - Basic enemy behaviors: deploy the pre-built army on the line, move it forward, attack the closest enemy in effective range.
- **Consolidation** — when all enemy units are destroyed, move to Consolidation and show statistics: **squads and units destroyed per player; value of squads destroyed as the score**. (A detailed battle **audit system** — needed for player stats and savefiles — should be started early; its contract is §10.)

### Scope IN (v1)
Block movement; auto-attack when in range; per-unit default policy; live React window (default "decline all"); reserve timer; the §9 data set; the §10 battle event contract; Consolidation stats (value of units destroyed per side).

### Scope OUT (deferred — listed so it's not accidentally in)
Reserve/reinforcement squads, morale, hit/miss, abilities, explicit attack targeting, pathfinding/height, coherency rules beyond the stub, **save + audit/replay** (determinism and event contracts stay — the log + save system comes back later), multiplayer, story mode, campaign/squad editors, multiple commanders.

### Build order (each slice ends in something visible)
1. **Core** — `gecs` ECS + JSON→Resource loader + fixed-timestep tick + Main Menu (Quickplay/Quit) + top-right Menu button.
2. **Sector** — 2-plot Sector Map scene (Armybuilding → Battle, dotted-line arrow, travel note) + Armybuilding screen (select Militia) + Commander movement with the path gate.
3. **Battlefield** — 100×200 grid render + zoom (1/3/6-squad markers) + drag/multi-select in-zone deploy + "Engage Enemy".
4. **Turn loop** — Issue orders + ghost paths → Lock/Reveal → React window → Resolve (move + combat) → repeat → Consolidation stats → back to Sector Map.

### Acceptance criteria
The framework is **done** when, **unmodified**, a player can:
1. Launch → Main Menu → **Quickplay**.
2. See the 2-plot Sector Map (Armybuilding + Battle); move the Commander to Armybuilding; select the **Militia** army (Commander + army meeples attach; note updates).
3. Move the Commander to the Battle plot (gated until the army exists).
4. Deploy: drag/multi-select the 5 Riflemen squads into the blue zone (**wholly-in-zone only**) → "Engage Enemy".
5. Run Engagement: issue move orders (ghost path = dotted line + translucent squad at the end) → Execute → AI orders react → resolve (move + combat) → repeat.
6. Reach **Consolidation** when all enemy units are destroyed → show units destroyed + value per side → victor.

### Quality gates (flow/replay)
- **Flow determinism:** same seed + inputs → same event-stream hash chain.
- **Replay fidelity:** replay reaches the same route and gate state as the live run.
- **No direct flow mutation:** UI scripts never write campaign progression state.
- **Gate coverage:** every phase transition has explicit gate predicates and failure reasons.

---

## 13. Migration: Current UI Flow → GECS Flow

The current prototype runs campaign flow on ad-hoc booleans in `GameState`. The migration moves it onto components + audit events, UI becoming a projection:

| Current location | Current behavior | GECS target | Migration step |
|---|---|---|---|
| `game_state.gd` `armybuilding_complete` | Global bool toggled in UI callback | `CommanderProgressFlagsComponent.army_selected` + `armybuilding.selected` event | Add component + event in the Armybuilding completion path, then remove bool reads |
| `game_state.gd` `commander_at_battle` | Global bool toggled by Sector Map button | `CurrentPlotRefComponent` + `sector.commander.moved` event | Replace "Move Here" bool write with move-intent dispatch |
| `game_state.gd` `selected_army_name` | Global string selected in Armybuilding | `ArmySelectionComponent` on Commander + activity outcome event | Move selection into the activity result projection |
| `sector_map.gd` `_refresh_ui` | Button visibility from global flags | `EventProjectionSystem` read unit (`can_begin_activity`, `can_move`, `can_start_battle`) | Query the projection to render controls |
| `sector_map.gd` `_on_move_pressed` | Direct state mutation | Intent → `CommanderIntentValidationSystem` → `SectorTraversalSystem` | Route all actions through the systems |
| `campaign_planning.gd` | Direct scene transition to sector | `SceneRouteSystem` route update after `campaign.started` | Replace direct route logic with route projection |
| `armybuilding.gd` | Direct `GameState` writes and return | `ActivityLifecycleSystem` for the Armybuilding activity | Complete the activity through the system, emit outcome |
| `battle_planning.gd` | Reads global selected army; toggles Deploy | Projection of the activity outcome + gate result | Use read-units for selected force and Deploy-enable |
| `battlefield.gd` `GameState` counters | Writes destroyed counters globally | `battle.resolved` payload + campaign projection update | Keep the battle runtime; project the result into a campaign event |

**Incremental delivery plan:**
1. Introduce a `Campaign Runtime` singleton with entity store + event append API.
2. Mirror the existing quickplay booleans into components, UI behavior unchanged.
3. Switch `sector_map` to projection-backed button state.
4. Route movement and army selection through intent + system execution.
5. Emit + persist the quickplay event stream; add a replay command for deterministic rebuild.
6. Remove obsolete `GameState` flow flags once projections fully cover UI needs.

**Risks and mitigations:**
- **Dual-write drift** (mismatch between `GameState` and components during migration) → assertion checks while dual-write is active.
- **Replay payload bloat** (UI-centric data in payloads) → enforced compact payload schema; UI fields are projection-only.
- **Route thrash** (duplicated transition logic between systems and UI) → `SceneRouteSystem` is the single route authority.

---

## 14. Open / Future (deliberately left)

1. **Full combat resolver** — RTS autobattle with asymmetric events and per-unit positioning; replace the §8 throwaway bodies (interfaces + events stay).
2. **Coherency rules** (non-no-op) + morale-break order conflict (minders flee / brute charges).
3. **Event-log + binary save + replay hash** — determinism already in place; this builds on §10.
4. **Networked multiplayer** (Freeplay/Unranked/Ranked) — the authoritative deterministic sim is already designed for it.
5. **Pathfinding / height** (terrain `z`), full order set (Hold/Advance/Run/Charge/Dig In/Fall Back/Surge), full reaction set (Reposition/Evade/Return Fire) per Battle Rules 132–133.x.
6. Story mode, Campaign/Squad editors, Trade/Event activities — all layered on top of the same architecture.

**Relationship to the rule docs:** the rule documents define the *full* design space (order types, reserve transport, vanguard designations, reaction subtypes, scoring, etc.). v1 implements a deliberately reduced subset — `move_to`-only orders, "decline all" reactions, block movement, value-of-destroyed scoring. Every v1 simplification above has a stable contract so the full rule set can be slotted in without rework.

---

## 15. Maintenance

- **This document is the direction document.** New design decisions, scope additions/removals, or architecture changes get written here first, then propagated to `Gameplay Rules/` (formal rules) and `docs/godot-skill-distillation.md` (implementation rules) where applicable.
- Rule references like "see rule 850.1 in Campaign Rules" must point at a rule that exists in the corresponding rules document; add the rule or drop the reference.
- `Foundation/Foundation.md`, `Foundation/Framework-Requirements.md`, `Foundation/campaign_sector_gecs_architecture.md`, and `Overview/Main Concepts.md` are **sources, superseded by this document** — they are retained for provenance, not for reference.
- The Tight Scope acceptance criteria (§12) are the definition of done for v1; do not expand them without also expanding this document and the build order.
