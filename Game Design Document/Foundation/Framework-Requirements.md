# Framework Requirements
**Purpose:** The concrete requirements for the *basic framework* of Simple War. Its **acceptance test is the Tight Scope Digital Prototype** 
---
## 1. Deliverable
A **framework** (not just a prototype) whose correctness is *verified by playing the Tight Scope prototype*. We build the architecture (ECS + deterministic simulation + data model + timer + combat manager) and prove it by reaching the prototype's end-to-end flow:

```
Main Menu → Quickplay → Campaign Planning → Sector Map
  → Armybuilding (select "Militia") → Commander to Battle Plot
  → Battle Planning (select army) → Deployment (drag squads in-zone)
  → Engagement (Issue → React → Resolve, turn-based) → Consolidation (stats)
```

---

## 2. Non-negotiable architecture
| Rule | Requirement |
|---|---|
| ECS | Use the **`gecs`** addon (entities, components, systems, archetypes, system scheduling). |
| Simulation layer | **Fixed-timestep deterministic** sim. A sim tick clock drives the game; the presentation layer is **read-only** over sim state. |
| Determinism | All hot-path math in **integers**. Same ticks + same inputs → same result. |
| Data as data | All gameplay content lives in `data/defaults/*.json` → `Resource`s at load. **No gameplay data in the scene tree / node properties.** |
| F6 | Every scene runs standalone (no scene-external dependencies). |
| Composition | Compose, don't inherit (consider refactor options when inheritance gets too deep). |
| UI contract | UI **emits signals**; the sim/controller listens. UI never holds game state. |

---

## 3. Coordinates & positioning
- **Fixed-point integer coordinates**, called simply **"coordinates"** (unitless; 100 units per squad ≈ 1 m).
- Battlefield = **100 × 200 squads = 10,000 (tall) × 20,000 (wide) units**.
- **Position struct reserves height**: `{ x:int, y:int, z:int (0 = ground) }`. `z` is unused in v1 (reserved for terrain/height later).
- **Each Unit owns its own absolute position.** Squad position is **derived** = center-point (mean of unit positions), tracked per coherency rules.
- **Coherency (v1 = stub):** `CoherenceSystem` computes the squad center-point and exposes a rule hook; rules are a **no-op** in v1. This is where morale-break "minders flee / brute charges" divergence plugs in later.
- **Movement:** an order is a target; the engine resolves the route via a single `move_to(squad, target)` interface. **v1 = block move** (same delta to every unit in the squad, relative offsets preserved, direct route). **Future:** pathfinding (obstacles, height, adjustments) swaps in behind the same interface.
- **Deployment zones:** enemy = top 20 squads (2,000 units), player = bottom 20 squads (2,000 units). A squad drops only wholly in-zone.

---

## 4. Per-turn sequence (Battle)
The turn is **not** a single pass. Per `Foundation` (React live from day one):

1. **Issue** — each participant is under their turn timer (`reserve` + `turn_time`, §5). May execute anytime.
   - early → reserve untouched · overshoot → eats reserve · reserve 0 → auto-default (per-unit default policy: in-range → attack, else move toward nearest enemy).
2. **Lock + Reveal** — Issue ends when **all** participants have executed (or defaulted). All orders are revealed.
3. **React** — a single shared, flat window (default **10 s**, sim-driven). Each participant may **re-issue** a unit's order (manual) and/or apply an **auto policy** (default: *"decline all"*). The **AI reacts instantly at reveal**.
4. **Resolve** — **Movement** (apply all move orders as squad block-move) → **Combat** (`CombatSystem` → `IEngagementResolver` → `IDamageModel` → apply damage, emit events, §7/8).
5. **Next turn** — `turn_no + 1`; timers recompute.

> The **overworld** turn reuses this same shape with its own defaults (more generous). In the Tight Scope prototype the overworld is effectively 2 activities (Armybuilding → Battle), so overworld turning is minimal.

---

## 5. Timer system (the "reserve" model)
A **single reusable, simulation-layer-driven** timer system, used by both overworld and battle turns, with a **separate default config per context**.

### Model
- Each participant per turn is granted `turn_time`.
- Execute **within** `turn_time` → `reserve` **untouched**.
- Take **longer** than `turn_time` → the **overshoot eats into `reserve`**.
- `reserve == 0` before Execute → **auto-execute with defaults**.
- **No banking:** unused turn-time never adds to `reserve`.
- **Top-up rule:** when `reserve < 60 s`, set `reserve = max(reserve + 30, 60)` **and** `turn_time = 60 s` (→ the player gets 2 min that turn).
- **Sim-owned:** `reserve`/`turn_time` are sim state, decremented by the tick clock during the turn; "timer hit 0" fires a **deterministic sim event** (apply defaults / execute), not a UI callback.
- **The AI also has a timer** (same model) but its decision algorithm completes well before its clock. No special-casing.

### Default configs
| Field | **Overworld** | **Battle** |
|---|---|---|
| initial reserve | 300 s | 180 s |
| base turn_time | 300 s, flat | 180 s, **+60 s/turn** |
| top-up | yes (reserve<60 → max(reserve+30,60), turn_time=60) | yes (same) |
| banking | none | none |
| reaction window | 30 s | 10 s |

*(Values are confirmed defaults — configurable, not hard-coded.)*

---

## 6. Data model (`data/defaults/*.json` → `Resource`s)
All content below is data, loaded at startup. **v1 = one commander, one unit type, one squad, one battlefield, one campaign.**

| File | Key fields |
|---|---|
| `commander/generic` | `id, name, statline{ durability, speed }, equipped_items[], squads[]` |
| `unit/rifleman` | `id, name, size{ w, h }, statline{ durability, speed }, attack_profile{ damage, range_band[min,max], damage_type, category }` |
| `squad/riflemen` | `id, name, units[] (10× rifleman), value, default_formation (auto-rectangle)` |
| `battlefield/default` | `id, name, dimensions{ w, h } (100×200 squads), deployment_zones[]{ side, region }, terrain (generic grassland)` |
| `campaign/quickplay` | `id, name(quickplay), marker(quickplay), sector_map_ref, opening, objectives, conclusion{ victor by score }` |
| `sector_map/quickplay` | `plots[] { armybuilding, battle }, paths[] { from, to, requirement: army_built }` |
| `activity/*.json` | `id, type (armybuilding \| battle), plot, requirements[]` |

> Statline fields **Endurance / Morale / Reflex are present but unused in v1** (placeholders for Morale, hit/miss, and decay systems that aren't built yet). **v1 does real work with only** `durability`, `speed`, and the `attack_profile`.

---

## 7. Contracts
- **`Order`** (per unit): `{ type: none | move_to(pos) | attack(target) }` — attack type present in the enum; **UI offers move only** in v1.
- **`Engagement`** (resolver output): `{ attacker_units[], target_unit, combat_type }`.
- **`DamageResult`**: `{ target_unit_id, amount, killed }`.
- **`TurnState`**: `{ phase, turn_no, participants[] { reserve, turn_time, executed, orders[] }, reactions { window_remaining, participants[] { policy, manual_orders[] } } }`.
- **`Coherence`** (stub): `{ squad_position (center-point), rules: [] (no-op) }`.
- **`IEngagementResolver`** (drop-in): reads the *whole battlefield* → `List<Engagement>` — *who attacks whom, and how*.
- **`IDamageModel`** (drop-in): `evaluate(engagement, attacker, target) → DamageResult` — *how much damage*.

**v1 defaults (throwaway):** resolver = *for each surviving unit, nearest enemy within its Attack-Profile range → one engagement; none in range → none*; damage = `attacker.attack_profile.damage` (int) → target `durability`, kill at ≤ 0. **These v1 bodies are explicitly slated to be replaced** when the combat becomes a full RTS autobattle simulation (asymmetric events, per-unit positioning). Keep the **interfaces and emitted events stable**; swap only the bodies.

---

## 8. Event contract
The v1 `CombatSystem` (and turn engine) emit these; the presentation layer and the *future* audit system subscribe to exactly this:

```
turn_started(battle, turn_no)
orders_revealed(battle, side, orders[])
engagement_resolved(battle, engagements[])
unit_damaged(battle, target_unit_id, amount, source_unit_id)
unit_destroyed(battle, target_unit_id, source_unit_id)
turn_resolved(battle, casualties_by_side)
battle_ended(battle, victor_side)
```

---

## 9. Entities / archetypes (gecs)
| Archetype | v1 key components |
|---|---|
| Unit | Statline, AttackProfile, Size, Position, Order, DestructionState |
| Squad | Composition(units[]), Value, SquadKeywords, Position(center-point), Coherence |
| Commander | Statline, Equipment, ArmyRef |
| Army | CommanderRef, SquadRefs, Value |
| Battlefield | Dimensions, DeploymentZones, TerrainIndex |
| Battle | BattleStage, Phase, TurnCounter, VictoryConditions, CasualtyReport, Scoring |
| Activity | ActivityStatus, Conditions, Type |
| SectorMap | Plots, Paths, Visibility |
| Campaign | CampaignStage, SectorMapRef, Objectives, ScoringRules |

---

## 10. Systems (v1)
| System | Role |
|---|---|
| Tick / Turn engine | Fixed-timestep sim clock; drives Phase; owns the reserve timer; advances Issue→React→Resolve |
| Order system | Collects player + AI orders into the per-turn buffer; validates |
| Deployment system | Places squads in their Deployment Zones (deployment stage) |
| Battle Movement system | `move_to` → block move (v1) → recompute unit positions + squad center-point |
| Coherence (stub) | No-op center-point + rule hook |
| Combat system | Orchestrates `IEngagementResolver` + `IDamageModel`; applies damage; emits §8 events |
| AI system | Deterministic; issues its orders during Issue and reacts instantly at reveal; uses the *same* default-policy code path (fast) |
| Morale / Ability | **Not built in v1** (reserved) |

---

## 11. Scope
**IN (v1):** block movement, auto-attack when in range, per-unit default policy, live React window (default "decline all"), reserve timer, the data set in §6, the event contract in §8, Consolidation stats (value of units destroyed per side).

**OUT (deferred — listed so it's not accidentally in):** reserves, morale, hit/miss, abilities, explicit attack targeting, pathfinding / height, coherency rules beyond the stub, **save + audit/replay** (deterministic sim stays; the event log + save system comes back later), multiplayer, story mode, campaign/squad editors, multiple commanders.

---

## 12. Build order (each slice ends in something visible)
1. **Core** — `gecs` ECS + JSON→Resource loader + fixed-timestep tick + Main Menu (Quickplay/Quit) + top-right Menu button.
2. **Sector** — 2-plot Sector Map scene (Armybuilding → Battle, dotted-line arrow, travel note) + Armybuilding screen (select Militia) + Commander movement with the path gate.
3. **Battlefield** — 100×200 grid render + zoom (1/3/6-squad markers) + drag/multi-select in-zone deploy + "Engage Enemy."
4. **Turn loop** — Issue orders + ghost paths → Lock/Reveal → React window → Resolve (move + combat) → repeat → Consolidation stats → back to Sector Map.

---

## 13. Acceptance criteria (Tight Scope)
The framework is *done* when, unmodified, a player can:
1. Launch → Main Menu → **Quickplay**.
2. See the 2-plot Sector Map (Armybuilding + Battle); move the Commander to Armybuilding; select the **Militia** army (Commander + army meeples attach; note updates).
3. Move the Commander to the Battle plot (gated until the army exists).
4. Deploy: drag/multi-select the 5 Riflemen squads into the blue zone (wholly-in-zone only) → "Engage Enemy."
5. Run Engagement: issue move orders (ghost path = dotted line + translucent squad at the end) → Execute → AI orders react → resolve (move + combat) → repeat.
6. Reach **Consolidation** when all enemy units are destroyed → show units destroyed + value per side → victor.

---

## 14. Open / future (deliberately left)
- Full combat resolver (RTS autobattle, asymmetric events) — replace the §7 throwaway bodies.
- Coherency rules (non-no-op) + morale-break order conflict.
- Event-log + binary save + replay hash (determinism is already in place).
- Networked multiplayer (authoritative deterministic sim is already designed for it).
- Pathfinding / height (terrain `z`).

---
**Bottom line:** build the architecture (ECS + deterministic sim + data + reserve timer + combat manager + events) and *prove* it by playing the Tight Scope prototype. Everything deferred is deferred *on purpose* — the contracts and events above are what the deferred systems will hang on.
