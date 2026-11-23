# U1 draft 01: Battle orders, damage output and autobattler behaviour

Traces to `docs/design/u1/brief.md`, Battles, first paragraph (damage output) and fifth paragraph ("Movement and commands").

Status: research draft for the owner. Nothing in the GDD, `src/`, `data/` or `tests/` was changed. No beads were created.

**Tagging.** Owner statements from the brief are tagged `U1Qn`, numbered by their paragraph in the brief, as drafts 02 and 03 do. The numbers are provisional until the decision log records Round U1; the integrator should reconcile them across drafts.
- **U1Q1:** whether attack-move, run or hold affect damage output is unclear. Anything other than walking straight at the enemy seems to lower damage output dramatically. Picking a target and retargeting seem to lower it too.
- **U1Q5a:** movement and commands need refining. Coherency and collision rules for pathfinding and clustering need fleshing out.
- **U1Q5b:** an infantry squad on attack-move, with an enemy visible but not in range or attackable, and movement left, uses its remaining movement to find a position it can attack from, like a group of marines on attack-move in StarCraft II.
- **U1Q5c:** other squads may have other default behaviours for various commands. Behaviours should be composable where possible.
- **U1Q5d:** getting the feel of U1Q5b right is integral to building the rest.

Everything else here is **proposed**.

---

## 1 Findings

### 1.1 Method

The harness is a throwaway headless script: `docs/design/u1/scripts/dps/dps_orders.gd`. The scratchpad can be wiped, so the full script is reproduced in the appendix. Bead B1 adopts it.
- **Data:** the real core package (`data/packages/core`), compiled for `duel_crossroads`. All squads stand on open ground (the lane at y = 80, x 20–135, with no forest or ruin).
- **Placement:** squads are placed by hand with `BattleSetup.spawn_squad`, as `tests/sim/test_combat_timers.gd` does. Orders are set with `BattleOrders.set_order`, the same call the validated API and the Retarget reaction end in. Each run is 300 ticks (3 battle turns) of `BattleSim.runner.step`.
- **Damage:** HP and temporary HP actually removed, from `hit_trace`. Two kinds of run:
  - **Output runs:** the target is a disarmed rifle squad with 1000 HP per unit, standing on Hold, so only the shooter's output is measured.
  - **Duels:** the target is armed and at full strength.
- **Hold reasons:** `BattleActivity.hold` per armed unit-tick. The per-second timeline is `F` when most units fired that second, else the most common reason:
  - `R` reloading, `c` cooldown, `m` no moving fire mode
  - `n` minimum range, `o` out of range, `l` no line of sight
  - `s` not spotted, `t` no target
- **Running it:** copy the script under the repo (for example `.godot/u1_dps/`, which is gitignored), because `hx godot run` only takes repo paths, then run `harness/bin/hx godot run .godot/u1_dps/dps_orders.gd --tail 400`. 63 runs take about 9 s.

Reference rates from the data (`data/packages/core/defs/equipment.json`):
- **Rifle, standing (aimed):** 1 shot × 0.6 × 3 dmg every 1.0 s = 1.8 DPS per unit, about 2.0 with the every-8th-hit crit.
- **Rifle, moving (burst):** 3 shots × 0.3 × 3 dmg every 1.5 s = 1.8 DPS per unit, times Instinct efficacy (0.5–1). It has no crit.
- **Mortar:** standing only, 20–90 m.
- **Shotgun:** 15 m.
- **LMG:** 50 m. The moving hip mode has 0.15 accuracy.

### 1.2 Numbers

**A. Rifle squad (8 rifles) against the disarmed dummy.** DPS₃₀ counts all 30 s. DPS₁ counts from the first shot.

| Run | Order | Start | Damage | DPS₃₀ | DPS₁ | Shots | Hit % | First shot (s) | Fire events moving / standing | Instinct min | Hold profile (unit-ticks) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | Hold, in range | 35 m | 483 | **16.1** | 16.1 | 240 | 60 | 0.0 | 0 / 240 | 52 | F240 c2088 R72 |
| R2 | Hold, out of range | 44 m | 0 | 0 | — | 0 | — | — | — | 52 | t2400 |
| R3 | Move to the enemy's centre | 44 m | 429 | 14.3 | 15.0 | 336 | 38 | 1.4 | 72 / 120 | 39 | — |
| R3b | Move to 20 m short | 44 m | 441 | 14.7 | 15.4 | 288 | 45 | 1.4 | 40 / 168 | 44 | — |
| R4 | Attack-move to the enemy | 44 m | 453 | 15.1 | 15.8 | 240 | 56 | 1.4 | 8 / 216 | 44 | — |
| R5 | Attack (target) | 44 m | 453 | 15.1 | 15.8 | 240 | 56 | 1.4 | 8 / 216 | 44 | identical to R4 |
| R6 | Move, run | 44 m | 441 | 14.7 | 15.1 | 288 | 45 | 0.8 | 40 / 168 | 40 | — |
| R6b/c | Attack-move or Attack, run | 44 m | 453 | 15.1 | 15.5 | 240 | 56 | 0.8 | 8 / 216 | 44 | — |
| R7 | Move, starting unseen | 70 m | 276 | 9.2 | 13.8 | 264 | 32 | 10.0 | 72 / 48 | 39 | — |
| R7b | Attack-move, starting unseen | 70 m | 315 | 10.5 | 15.8 | 176 | 55 | 10.0 | 8 / 152 | 52 | — |
| R8b | Attack-move, enemy 45° off the facing | 50 m | 378 | 12.6 | 14.3 | 226 | 54 | 3.6 | 9 / 199 | 44 | `.`17 t271 |
| R8d | Attack-move against a line side-on (column) | 44 m | 432 | 14.4 | 15.1 | 240 | 56 | 1.4 | 8 / 216 | 44 | — |
| R9 | Two enemies: Attack A | 44 m | 453 | 15.1 | 15.8 | 240 | 56 | 1.4 | 8 / 216 | 44 | — |
| R9c | Attack A, retarget to B at 5 s | 44 m | 438 | 14.6 | 15.3 | 243 | 55 | 1.4 | 11 / 210 | 44 | — |
| R9d | Attack A, retarget to B at 15 s | 44 m | 441 | 14.7 | 15.4 | 243 | 55 | 1.4 | 11 / 210 | 44 | — |
| R10 | A in range at 35 m; Attack a far B at 55 m | 35 m | 441 | 14.7 | 14.7 | 286 | 48 | 0.0 | 35 / 181 | 44 | — |
| R10c | Hold on A, retarget to the far B at 5 s | 35 m | 447 | 14.9 | 14.9 | 286 | 48 | 0.0 | 35 / 181 | 44 | — |
| R11 | Target walks 40 m away; Attack | 38 m | 405 | 13.5 | 13.5 | 324 | 40 | 0.0 | 62 / 138 | 44 | — |
| R11b | Target walks away; Attack-move to its start | 38 m | 213 | **7.1** | 7.1 | 176 | 39 | 0.0 | 36 / 68 | 44 | `.`330 o420 t430 |
| R11c | Target walks away; Hold | 38 m | 72 | 2.4 | 2.4 | 40 | 60 | 0.0 | 0 / 40 | 52 | t1950 |

**B. Mixed-range squads against the dummy.** This is the big one.

| Squad (members) | Hold at 12 m (everyone in range) | Move to the enemy's centre (from 60 m) | Attack-move (from 60 m) | Attack (from 44 m) | Where Attack-move stops |
|---|---|---|---|---|---|
| `assault_squad`: 1 rifle (40 m) and 4 shotguns (15 m) | **6.7** | **8.8** | **2.0** (−70%; shotguns out of range for 900 of 900 unit-ticks after contact) | **2.2** (o1112) | 39.6 m |
| `heavy_weapons_team`: 2 LMG (50 m) and 2 rifles (40 m) | **8.0** | 4.8 (hip fire 0.15) | **4.1** (−49%; rifles idle, o472) | 4.0 (o600) | 44.8 m |
| `rocket_team`: 2 rockets (45 m) and 1 rifle (40 m) | **7.7** | 4.2 | 4.7 (−39%) | 5.8 (−24%, o300) | 44.7 m |

These are DPS₁ figures. Timelines (assault squad): Attack-move `ttttttttoooooooooooooooooooooo`; Move `ttttttttoooooooFFFFFRFFFcFRFFF`.

**C. Mortar team (3 mortars) against the dummy.** A disarmed friendly spotter holds 25 m from the target.

| Run | Damage | DPS₃₀ | DPS₁ | Shots / hits | First shot (s) | Notes |
|---|---|---|---|---|---|---|
| Hold, in range (60 m) | 120 | 4.0 | 4.0 | 15 / 3 | 0.0 | `FRRccc` every 6 s |
| Hold, out of range (100 m) | 0 | 0 | — | 0 | — | t900 |
| Move to the enemy's centre (100 m) | **0** | 0 | — | 0 | — | m900: no moving mode, so it never fires |
| Move to 50 m short | 0 | 0 | — | 6 / 0 | 20.1 | m603 while walking; the accumulator hadn't filled by the end |
| Attack-move (100 m) | 120 | 4.0 | 4.7 | 15 / 3 | 4.3 | stops at 89.5 m: correct |
| Attack (100 m) | 120 | 4.0 | 4.7 | 15 / 3 | 4.3 | same |
| Attack-move, run | 120 | 4.0 | 4.4 | 15 / 3 | 2.8 | — |

**D. Armed rifle duels (8 against 8, 82 HP a side).** Damage dealt is nearly equal in every row; kills are not.

| Attacker order | Defender order | Start | Attacker damage dealt | Survivors (attacker – defender) |
|---|---|---|---|---|
| Hold | Hold | 35 m | 82 | **0 – 0**: all 16 die on the same tick, t = 6.0 s |
| Attack-move | Hold | 44 m | 74 | **0 – 6** |
| Move | Hold | 44 m | 73 | **0 – 7** |
| Attack-move | Attack-move (mirror) | 60 m | 82 | 0 – 0 |
| Hold | Attack-move | 60 m | 82 | **6 – 0** |
| Move | Attack-move | 60 m | 71 | 0 – 6 |
| Move | Move (mirror) | 60 m | 79 | 0 – 1 |

Death trace, Attack-move against Hold:
- **t = 12.2 s:** both sides have 7 units on **1 HP** (`[3,1,1,1,1,1,1,1]` against `[3,1,1,1,1,1,1]`).
- **t = 12.7 s:** the holder's next volley kills 7 attackers at once.

### 1.3 Verdicts on the suspicions and leads

1. **"Anything but walking straight at the enemy lowers damage dramatically" (U1Q1): real for mixed-range squads, false for single-weapon squads.**
   - **Rifle squads:** every order lands within 10% of Hold-in-range once firing starts (table A, DPS₁ 14.3–16.1). Walking straight at the enemy (Move) is actually the *worst* rifle order: R3 is −11%, and it loses every armed duel.
   - **Mixed-range squads:** for the assault squad, Move is the *only* order that brings its shotguns into range. Attack-move and Attack cut its DPS by 70–77% (table B). Heavy weapons and rocket teams lose 24–49%. This matches the owner's experience exactly. The AI issues `attack_move` for almost everything (`src/api/utility_battle.gd:105,123`, `src/api/zone_controller.gd:60`, `src/api/guard_controller.gd:42`), so its mixed squads stall too.
2. **Lead: `CombatSystem._engage` uses squad-centroid distance against the squad's longest reach (`src/sim/battle/combat_system.gd:54-73`; reach = longest member weapon, `src/sim/battle/battle_setup.gd:72-85`). Real.**
   - **Single-weapon squads:** a small effect. At 45° (R8b) the squad loses 10% of DPS₁ to units with no target (t271).
   - **Mixed squads:** this is half of the root cause in item 1.
3. **Lead: `MovementSystem._destination` stops attack-move as soon as one unit has a shot (`src/sim/battle/movement_system.gd:127-130`; Attack at `:135-136`). Real, and the largest effect measured.** Three pieces of code combine:
   - `_has_shot` (`:168-170`) calls `LineOfFire.check` (`src/sim/battle/line_of_fire.gd:12-23`). That returns SHOT as soon as the first armed unit has a line to the target's centre, and the centre is within the *longest* reach.
   - `_firing` (`movement_system.gd:149-159`) then keeps the squad standing while *any* unit's cooldown or reload is running.
   - A sergeant firing once a second therefore pins four shotguns at 40 m for the whole battle. The GDD text behind it (02 §2.6, "Attack orders") is the stated intent, written for mortars (sw-kys.6). It is the opposite of StarCraft II marines and of U1Q5b.
4. **Lead: firing on the move costs accuracy, and Instinct decays. Real but bounded.** The code:
   - `pick_mode` (`src/sim/battle/battle_rules.gd:344-356`) chooses burst on the move.
   - Accuracy is multiplied by Instinct efficacy, `value / neutral` clamped to 0.5–1 (`combat_system.gd:126-128`, `src/sim/battle/pools.gd:61-65`).
   - Each unit's moving volley sinks 1 Instinct (`ruleset.json` `sinks.instinct_fire_moving`), so an 8-unit squad sinks about 5.3/s against a drift of about 1/s.

   The numbers:
   - **Instinct:** it fell 52 → 25–27 within about 8 s of sustained moving fire (duel Move rows). The efficacy floor of 0.5 is reached near 26.
   - **Hit rate on the move:** 20–21%, against 60% aimed.
   - **Moving DPS:** −11% against standing at Neutral Instinct (no crit), and −56% at the floor.
   - **Squad size:** the sink is per unit, so big squads decay fastest.
5. **Lead: Attack re-plans only when the target moves 8 m (`movement_system.gd:52-58`, `route_replan` at `battle_rules.gd:69,588`), with sticky targeting (`combat_system.gd:60-64`). Not a meaningful damage factor.**
   - **A target walking away:** Attack keeps 13.5 DPS (−16% against Hold, nearly all of it from moving fire).
   - **Retargeting:** costs 2–3% (R9c, R9d). Attacking a far target past a near one costs 9% (R10), from walking and moving fire.
   - **What does lose:** Attack-move to the target's *old position* loses 56% (R11b). That is expected of a point order and needs no fix, but it is easy to misread.
6. **New finding: duels are knife-edges because volleys run in lockstep.** Three mechanisms combine:
   - **Accumulators:** hits come from deterministic accumulators (`combat_system.gd:244-251`).
   - **Pairing:** identical units, plus nearest-unit targeting (`_nearest_target`, `:220-241`), make eight parallel 1-v-1 duels that kill on the same tick (table D: all 16 die at t = 6.0).
   - **The first volley:** a squad arriving under *any* movement order fires its first volley on the move, in burst mode. That volley accumulates 3 × 0.3 = 0.9, so it scores zero hits, and its cooldown is 1.5 s instead of 1.0.

   So its volleys stay 0.5 s behind a stationary enemy's. Both sides reach 1 HP on 7 units, and whoever fires next wins 7–0.
   - **What the owner sees:** HP bars falling at the same rate on both sides, then the whole squad dying at once. The order changed only the volley phase. That is very likely the "dramatically lower damage output" (U1Q1).
   - **Spread:** nearest-unit pairing spreads damage perfectly: 74 damage, 90% of the enemy's HP, killed 1–2 units. This is the overkill and distribution problem the brief's Prowess paragraph describes, inverted. See the Prowess draft.
7. **Smaller issues:**
   - **Retarget drops run.** The Retarget reaction's order effect always sets `run = 0` (`src/sim/battle/effects.gd:298-303`), so a running squad slows down when it retargets.
   - **Move never lets a mortar fire.** A mortar under Move does nothing all turn (hold reason `m` in every tick), and Move to a point inside 20 m leaves it unable to fire even after it stops. That is correct by the rules, but the only cue is the hold reason.
8. **Cost reference.** Rough, from the harness wall time: about 0.35 ms per tick with 2–4 squads (about 30 units) and shot tracing on. That is about 9 s for 63 runs × 300 ticks, startup included. A turn forecast reruns 100 ticks on a scratch copy (`src/sim/battle/intent_forecast.gd:68`, `src/sim/battle/reactions.gd:143`), so every per-tick cost here is paid again for each forecast.

---

## 2 Prior art (short)

- **StarCraft II attack-move:** units move to the point and engage what they meet. Each unit acquires the *closest* enemy and walks until **it** is in range. Hold Position never chases, and Move ignores enemies.
  - Sources: [Liquipedia, Micro](https://liquipedia.net/starcraft2/Micro_(StarCraft)); Blizzard, [Basic Unit Controls](https://news.blizzard.com/en-us/article/4552956/game-guide-basic-unit-controls) and [Unit Control](https://news.blizzard.com/en-us/article/4552957/game-guide-unit-control).
  - Lesson: range is a *per-unit* stop condition. The group arrives as a ragged arc, not a parade line.
- **StarCraft II movement stack:** a navmesh A* path with a funnel for unit radius, then layered steering: following, flocking, grouping, separation, avoidance and arrival. Blizzard chose predictability over realism (James Anhalt, GDC 2011, summarised in a [GameDev.net thread](https://gamedev.net/forums/topic/563819-whats-starcraft2s-pathfinding-tech/) and in [Research into Group Movement](https://aitorsimona.github.io/Research_GroupMovement)).
  - Lesson: route once, then resolve crowding with cheap local steering, not with pathfinding.
- **Boids and steering behaviours:** separation, cohesion and alignment from neighbours only (C. Reynolds, [Steering Behaviors for Autonomous Characters](https://www.red3d.com/cwr/steer/gdc99/), GDC 1999).
  - Lesson: separation alone (no alignment or cohesion, which slots already give) is enough to stop stacking.
- **Company of Heroes:** squads seek cover near the ordered point (green, yellow and red markers). Attack-move stops and fires on contact ([Prima eGuide, unit control](https://primagames.com/eguides/company-of-heroes-2-eguide/advanced-tactics/unit-control)). Players complain that auto-cover steals control, delays moves and pulls infantry off capture points ([coh2.org, "Remove Auto-Cover"](https://www.coh2.org/topic/48861/title/post/486670); [squad AI guide](https://coh2.org/topic/63245/squad-ai-a-how-to)).
  - Lesson: any position-seeking behaviour must be bounded, visible in the forecast, and overridable.
- **Leader and follower squads:** followers steer to offsets from a point predicted about 2 s ahead on the leader's path, and their speed scales with their distance from the slot ([Kaos Studios squad movement paper](https://forum.arongranberg.com/uploads/short-url/rWod3K2KhNWcOEdjewnsLXQKU6A.pdf)).
  - Simple War already uses an anchor with slots, so this matches.
- **Coherency (tabletop, which Dawn of War inherits):** a squad's models must stay within a fixed distance of each other ([Goonhammer on 40k coherency](https://goonhammer.com/ruleshammer-page-2-of-the-40k-rules-coherency-and-avoiding-traps)). I found no primary source on Dawn of War's own leash rule.
  - Lesson: coherency is a *distance from the squad* rule, not a formation.

---

## 3 Proposed GDD text

Three edits to `Game Design Document/02 Rules Spec.md`, two to `03 Data Model.md`, one Glossary pass. The text is exact markdown to insert.

### 3.1 `02 Rules Spec.md` §2.6, "Other combat rules": replace the **Attack orders** bullet with this

```markdown
  - **Attack orders** (U1Q5b; details proposed): see §2.15. An attacking squad closes until enough of its own units each have a shot, then stands. A unit has a shot when its own weapon reaches a living unit of the engaged squad and it has a line to that unit (or the weapon is indirect). Squads built around one long weapon still stop at that weapon's range; mixed squads walk their short weapons in.
```

### 3.2 `02 Rules Spec.md`: a new section **§2.15 Orders and squad behaviours**, after §2.14

```markdown
## 2.15 Orders and squad behaviours (U1Q1, U1Q5)
**Status:** U1Q5b–d settled the intent; the rules below are proposed until the owner confirms them. Measurements: `docs/design/u1/01-battle-orders-and-behaviour.md`.

### Orders and their trade-offs (proposed)
Every order is a promise about movement. Damage output follows from it; no order has a hidden damage penalty.

| Order | Moves | Fires | Trade-off (intended) |
|---|---|---|---|
| **Hold** | Never. Units may turn. | At anything in reach, standing modes. | Best accuracy and first volley; does nothing out of range. |
| **Move** | To the point, ignoring enemies. | On the move at anything in reach, with moving modes only. Weapons without one stay silent. | Fastest arrival; accuracy × Instinct efficacy, and it sinks Instinct. |
| **Attack-move** | Toward the point; stops to fight (Closing to fire, below). | Standing modes once stopped. It never opens with a moving volley while it is stopping. | Gives up ground for damage. Stops chasing past its leash. |
| **Attack** | Follows the target squad and stops to fight it (Closing to fire). | The target first. Other enemies only while the target is out of reach. | Focus over efficiency. |
| **Run** (a modifier of Move, Attack-move, Attack) | At run speed scaled by Stamina (R4Q5). | As its order; moving modes while running. | Speed for Stamina. Attack-move and Attack still stop to fight. |
| **Fall back / Withdraw** | Away / off the edge. | Never. | Survival. |

- **Reactions keep the modifier:** a reaction that changes the order (Retarget, Halt) keeps the squad's run flag.

### Closing to fire (U1Q5b; mechanics proposed)
The default for Attack-move and Attack. A squad with an engaged enemy and time left in the turn keeps advancing until it can use its firepower.
- **Quorum:** the anchor stops once units carrying at least the squad's **fire quorum** (data; default 100% of its standing damage per second) each have a shot. Indirect weapons and units with no weapon don't count against the quorum when nothing can improve them.
- **Stand-off:** it never closes nearer than the largest `min_range` among the units it is waiting for, plus 2 m.
- **Leash:** it never closes more than its **chase leash** (data; default 15 m) past an Attack-move point. An Attack order has no leash.
- **Step out:** once the anchor stands, a unit with no shot may step up to its **step-out distance** (data; default 3 m) from its slot toward its nearest target. It does this only to gain range or a line, and returns when its shot is gone. This is the marine arc of U1Q5b; it never moves the anchor.
- **Blocked lines:** if no unit gains a shot by standing, the squad keeps closing, as before (§2.6, LineOfFire).
- **Firing while stopping:** a unit whose squad meets its quorum this tick uses its standing mode on the next tick it can fire. It doesn't spend a moving volley on the arrival tick.
- **Shown:** the forecast ghost shows where the squad will stop, and the hold reasons show who is stepping out ("moving to fire").

### Volley phase (proposed, pending U1 open question 3)
- **Staggered start:** each unit's hit accumulator starts at a fixed fraction set by its slot: slot k of n starts at k/n of a hit. Identical units therefore don't hit or kill on the same tick. Whole-squad deaths stop deciding duels on sub-second timing.
- **Deterministic:** the offset is integer and set at spawn, so the same seed gives the same result.

### Squad behaviours (U1Q5c; vocabulary proposed)
An order runs a **behaviour**: an ordered list of **components** from a closed, engine-provided vocabulary, each with data parameters. Mods compose components; they never add code (Data Model §3.7). Each squad template names a behaviour per order, falling back to its archetype's default.

| Component | Phase | Parameters | What it does |
|---|---|---|---|
| `advance` | move | `quorum_pct`, `margin_m` | Closing to fire (above). |
| `leash` | move | `chase_m` | Limits how far past the order point the squad pursues. |
| `keep_distance` | move | `min_m`, `max_m` | Stands off, or backs away, to keep enemies in a band (mortars, snipers). |
| `step_out` | unit | `max_m` | Per-unit step to gain range or a line. |
| `fire_on_move` | fire | `allow` | Whether moving modes may fire under this order. |
| `stand_while` | move | `firing`, `reloading` | Today's "keep standing while weapons cycle". |
| `separate` | unit | `radius_m` | Separation (§2.14). |

Archetype defaults (proposed):

| Archetype | Attack-move / Attack |
|---|---|
| Infantry (line) | `advance(quorum 100%)`, `leash(15)`, `step_out(3)`, `stand_while(firing)` |
| Indirect (mortar) | `advance(quorum 100%)`, `keep_distance(min_range + 5, —)`, `fire_on_move(false)`, `stand_while(firing, reloading)` |
| Short-range / melee (assault) | `advance(quorum 75%)`, `leash(25)`, `step_out(4)` |
| Marksman | `advance(quorum 100%)`, `keep_distance(—, range − 5)`, `step_out(2)` |

- **Order of evaluation:** components run in vocabulary order in their phase, squads in row order, units in row order. Arithmetic is integer and fixed-point.
- **Forecasts:** they run the same behaviours, so the ghosts show them.
- **Target choice:** which enemy unit to shoot is not a behaviour component yet. It belongs to the Prowess fire-distribution work (brief, Prowess paragraph).
```

### 3.3 `02 Rules Spec.md` §2.14: replace "What v1 leaves out" → **Collision** with this subsection

```markdown
### Separation and coherency (U1Q5a; proposed)
- **No body blocking.** Units and squads never block movement or routes. Routes stay static and cached (§2.14 Routing).
- **Separation:** after units steer to their slots, a unit closer than its separation radius (by size class: small 0.4 m, medium 0.6 m, large 1.2 m) to a unit of *another* squad is pushed apart along the line between them.
  - **Pushes:** computed from start-of-tick positions, summed per unit, capped at the unit's speed, and applied together, so row order doesn't matter. Integer math.
  - **Walls:** a push never enters a cell the unit can't (the terrain-collision slide rule applies).
  - **Tie-breaks:** units on the same point push along the lower unit ID's facing.
- **Squad footprints:** two friendly squads ordered to the same point are given points one footprint apart: the nearest free ring position, then the lowest cell index. A footprint is the formation's width.
- **Coherency:** a unit more than its squad's **coherency radius** (data; default the formation's half-width + 3 m) from the anchor heads straight for the anchor (this exists, §2.14 Unit movement). The anchor also slows to half speed while any unit is out of coherency, so squads don't string out around corners.
- **Clusters:** squads given one shared order (a multi-select move) share one route plan and keep their offsets from the cluster's lead squad, which is the lowest row. A cluster's leg is the lead squad's leg.
- **Budget:** separation uses a uniform 2 m spatial hash rebuilt each tick, at about one bucket pass per unit. The target is ≤ 0.2 ms per tick at 200 units on desktop, measured before the rule ships, so a 100-tick forecast stays ≤ 20 ms on top of today's.
```

### 3.4 `03 Data Model.md` §3.3 Squad: extend the **Formation Profile** row and add a row

```markdown
| Formation Profile | Formation, spacing, coherency radius (default half-width + 3 m), stance or mode |
| Behaviours | Per order: a behaviour ID (Rules Spec §2.15). Unset orders use the archetype default |
```

### 3.5 `03 Data Model.md` §3.4: add a template kind

```markdown
- **Behaviour** (`kind: "behaviour"`, U1Q5c; proposed): `{"components": [{"c": "advance", "quorum_pct": 100, "margin_m": 1}, ...]}`. Components come from the closed vocabulary in Rules Spec §2.15; unknown components or parameters fail validation. They compile to packed per-template arrays with the rules.
```

### 3.6 `07 Glossary.md` (proposed)

Add **Fire quorum**, **Closing to fire**, **Step out**, **Coherency radius**, **Separation** and **Behaviour (squad)**, with the one-line definitions above.

---

## 4 Open questions for the owner

| # | Question | Blocking? | Recommended default |
|---|---|---|---|
| 1 | What should the fire quorum count: units, or standing damage per second? | No | Standing damage per second, 100% for infantry. A squad whose sergeant does 20% of the damage then closes for its shotguns. |
| 2 | Should attack-move chase past its point, and how far? | No | 15 m leash past the point. Attack has no leash. Hold never moves. |
| 3 | Duels are knife-edges (§1.3 item 6). Should accumulators start staggered by slot, and should attack orders skip the moving volley on arrival? | **Yes**, for B5 only | Both. Without them, outcomes flip on 0.5 s timing, and orders look like damage penalties. |
| 4 | Should Move keep firing on the move? StarCraft II's Move ignores enemies. | No | Keep it, as §2.6 already says ("moving full-auto fire…"). Make the trade-off visible: the tooltip shows the moving hit chance and the Instinct sink. |
| 5 | Should the Instinct sink for moving fire be per unit volley (today) or per squad per second? | No | Per squad per second (`instinct_fire_moving_per_s`). Today an 8-unit squad decays 8× faster than a 1-unit team. |
| 6 | Body blocking, or separation only? | No | Separation only. Blocking (chokepoints, melee lines) is a later rules decision. |
| 7 | Cover-seeking (Company of Heroes style) as a behaviour component now? | No | Later, off by default and shown in the forecast. Players resent auto-cover that overrides orders (§2). |
| 8 | Fire distribution (focus against spread): which enemy unit each shooter picks. | No, here | Owned by the Prowess draft. Today's nearest-unit rule spreads damage perfectly: 90% of the enemy's HP for 1–2 kills. |
| 9 | Should Hold allow step-out? | No | No. Hold is a promise to stand; a "hold area" order can come later. |

---

## 5 Bead breakdown (ordered)

**B1. Adopt the order-DPS harness as a permanent lab and regression test**
- **Type / priority / runner:** task · P1 · `swarm`.
- **Why:** U1Q1 asked for confirmation, and nothing in the repo measures damage by order. Every later bead needs a before-and-after number.
- **What:**
  - Turn the appendix script into `src/tools/order_dps_lab.gd`: a SceneTree script run with `hx godot run`. It prints the tables in §1.2 and writes JSON next to `harness/data/`.
  - Add `tests/sim/test_order_dps.gd` on the `tests/fixtures/rules` package, so numbers don't drift with balance. It pins today's *ratios*:
    - rifle Attack-move DPS₁ ≥ 0.9 × Hold-in-range;
    - assault Attack-move DPS₁ ≤ 0.4 × Move (the bug, marked as expected-to-flip in B3);
    - mortar Move = 0;
    - the Hold-against-Hold duel ends on one tick.
- **Acceptance:**
  - The lab runs in under 15 s.
  - The test passes in `hx godot test --file tests/sim/test_order_dps.gd`.
  - The lab is documented in `harness/README.md` under labs.
- **Deps:** none.

**B2. Spike: movement-phase cost and a separation prototype**
- **Type / priority / runner:** spike · P1 · `autopilot-large`.
- **Why:** collision is the risky area (forecasts rerun every tick).
- **What:**
  - Measure the per-tick cost of `MovementSystem` and `CombatSystem` and one `IntentForecast` at 4, 20 and 40 squads (about 200 units) on Crossroads.
  - Prototype the §3.3 spatial-hash separation in a scratch branch and time it.
  - Record the numbers in the bead notes and in Rules Spec §2.14 "Measured".
- **Acceptance:** a table of ms per tick and ms per forecast, a go or no-go against the 0.2 ms per tick budget, and a determinism check (same hash twice).
- **Deps:** none.

**B3. Closing to fire: attack orders close until the fire quorum has a shot**
- **Type / priority / runner:** feature · P1 · `autopilot-large`.
- **Why:** this is the measured 49–77% loss for mixed squads and the core of U1Q5b.
- **What:**
  - Add `LineOfFire.shot_share(state, row, trow)`: the standing damage per second of the units with a per-unit shot over the total.
  - In `MovementSystem._destination`, stop Attack-move and Attack only when the share ≥ quorum (default 100%), with the min-range stand-off and the 15 m Attack-move leash.
  - Keep `_firing` only for units waiting on reload or cooldown *that already count toward the quorum*.
  - Update `BattleActivity` (a CLOSING_IN reason) and 02 §2.6 "Attack orders".
- **Files:** `src/sim/battle/movement_system.gd`, `src/sim/battle/line_of_fire.gd`, `src/sim/battle/battle_activity.gd`, tests.
- **Acceptance:**
  - B1 lab: assault Attack-move DPS₁ ≥ 0.9 × Hold-at-12 m.
  - Heavy weapons ≥ 0.85×.
  - Rifle and mortar are unchanged within 3%.
  - The mortar still never enters 20 m.
  - Determinism and mirror-duel tests pass, and forecast ghosts match execution.
- **Deps:** B1. Open question 1 can default.

**B4. Step-out: per-unit firing step once the anchor stands**
- **Type / priority / runner:** feature · P2 · `autopilot-large`.
- **Why:** this is the marine arc (U1Q5b) for flank and oblique contacts (R8b lost 10%).
- **What:** in `MovementSystem._move_units`, a unit of a standing squad under an attack order with no shot targets its slot plus up to 3 m toward its nearest enemy unit. Re-evaluate every 5 ticks per unit, in row order. Add the hold reason "moving to fire".
- **Acceptance:**
  - R8b DPS₁ ≥ 0.97 × R8 (Hold flank).
  - No unit ends more than 3 m from its slot.
  - Cost: ≤ 0.05 ms per tick at 200 units (B2 method).
- **Deps:** B3, B2.

**B5. Volley phase: staggered accumulators and no moving volley on arrival**
- **Type / priority / runner:** feature · P2 · `autopilot`.
- **Why:** this is the knife-edge in §1.3 item 6, where orders look like damage penalties.
- **What:**
  - Initialise the `acc_hit` column at spawn to `slot * ONE / form_size` (`src/sim/battle/battle_setup.gd`).
  - In `CombatSystem._fire_squad`, a unit whose squad is under an attack order and has met its quorum this tick skips the moving mode.
- **Acceptance:** B1 duels: Attack-move against Hold ends with neither side wiped in one tick, and the survivor gap is ≤ 3. Determinism tests pass. Goldens (replays, `tests/sim` hashes) are regenerated in one commit.
- **Deps:** B3, **owner answer to open question 3**.

**B6. The moving-fire Instinct sink per squad per second**
- **Type / priority / runner:** task · P3 · `autopilot`.
- **Why:** big squads decay 8× faster (§1.3 item 4).
- **What:** replace the per-volley sink in `combat_system.gd:128` with a per-squad per-tick accrual while any unit fires on the move (`instinct_fire_moving_per_s`, default 2), in `data/packages/core/defs/ruleset.json` and the fixture.
- **Acceptance:** an 8-unit squad's Instinct stays ≥ the Fraying floor (15%) after 10 s of moving fire. The Pressure Lab `morale_drift` sweep is unchanged in its other pools.
- **Deps:** B1, open question 5.

**B7. Retarget and Halt reactions keep the run flag**
- **Type / priority / runner:** bug · P3 · `swarm`.
- **What:** `src/sim/battle/effects.gd` `_order` passes the squad's current `run` byte instead of 0, plus one test in `tests/sim/test_abilities.gd`.
- **Acceptance:** a running squad that retargets keeps running.
- **Deps:** none.

**B8. Behaviour vocabulary: schema, compile, and defaults that reproduce B3 and B4**
- **Type / priority / runner:** feature · P2 · `autopilot-large`.
- **Why:** U1Q5c, composable data-driven behaviours.
- **What:**
  - Add a `behaviour` template kind to `src/sim/data/data_schema.gd`, with the closed component list.
  - Compile it in `BattleRules` to packed `bh_*` arrays indexed by squad template × order.
  - Movement reads its parameters from those arrays instead of constants.
  - Add the archetype defaults to `data/packages/core/defs/humanity.json` (a `behaviours` map on `humanity_squad`) and to the fixture.
  - Write Data Model §3.3 and §3.4.
- **Acceptance:** no change to B1 numbers (a pure refactor). A malformed behaviour fails validation with a message. Same hash as before for the determinism suite.
- **Deps:** B3, B4.

**B9. Archetype behaviours: mortar stand-off, assault quorum, marksman max range**
- **Type / priority / runner:** feature · P2 · `autopilot`.
- **What:** data-only behaviours per §3.2's archetype table, plus lab rows for each squad template.
- **Acceptance:**
  - B1 lab: every core squad's Attack-move DPS₁ ≥ 0.85 × its best order.
  - Mortars never enter `min_range + 5`.
  - Marksmen stop within 5 m of their range.
- **Deps:** B8.

**B10. Unit separation between squads**
- **Type / priority / runner:** feature · P2 · `autopilot-large`.
- **Why:** U1Q5a. Today stacked squads read as one blob.
- **What:** the §3.3 separation pass in `MovementSystem` after `_move_units`, using a spatial hash. Separation radius by size class in `equipment.json` or `humanity.json`. Write §2.14 "Separation and coherency".
- **Acceptance:**
  - Two squads ordered onto one point end with no units from different squads within 1 m.
  - Within B2's cost budget.
  - Determinism, mirror-duel and forecast-matches-execution tests pass.
- **Deps:** B2 (go).

**B11. Squad footprints, coherency slow-down and order clusters**
- **Type / priority / runner:** feature · P3 · `autopilot-large`.
- **What:**
  - Friendly destination de-duplication (ring placement).
  - The anchor slows to half speed while any unit is out of coherency.
  - A multi-select order shares one route plan with offsets, applied in `BattleOrders.apply` and `MovementSystem._plan_routes`.
- **Acceptance:** three squads ordered to one point stand one footprint apart, and a column through a doorway arrives without a straggler beyond its coherency radius.
- **Deps:** B10.

**B12. GDD: record the U1 orders and behaviour rules**
- **Type / priority / runner:** docs · P1 · `swarm`.
- **What:** insert §3.1–3.6 of this draft into the GDD as the owner amends them, and add Round U1 entries to the decision log.
- **Acceptance:** the GDD links render, and every proposed line carries a U1 tag or "proposed".
- **Deps:** owner review of this draft. B3 onward cite it.

---

## Appendix: the harness script (`dps_orders.gd`, as run for §1.2)

<details><summary>dps_orders.gd (313 lines)</summary>

```gdscript
extends SceneTree
## U1 DPS-by-order harness (throwaway; a bead may adopt it as a sim lab).
## One attacker squad vs a target under each battle order, real core data
## (data/packages/core), open ground on the Crossroads map (lane y = 80).
## Measures damage dealt (HP + temp HP actually applied), shots, hits,
## unit-ticks moving vs firing, fire mode (moving/standing), Instinct, and
## BattleActivity hold reasons per unit-tick and per second.
##
## Run: harness/bin/hx godot run <this file> --tail 400

const ONE := Fixed.ONE
const TICKS := 300  # 3 battle turns at 10 tps
const LANE_Y := 80
const AX := 20

var rules: BattleRules
const HOLD_LETTERS := {
	BattleActivity.Hold.NONE: ".", BattleActivity.Hold.UNARMED: "u", BattleActivity.Hold.FALLING_BACK: "f",
	BattleActivity.Hold.RELOADING: "R", BattleActivity.Hold.COOLDOWN: "c", BattleActivity.Hold.NO_MOVING_FIRE: "m",
	BattleActivity.Hold.MIN_RANGE: "n", BattleActivity.Hold.OUT_OF_RANGE: "o", BattleActivity.Hold.NO_LOS: "l",
	BattleActivity.Hold.NOT_SPOTTED: "s", BattleActivity.Hold.NO_TARGET: "t",
}


func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	print("legend: per-second timeline char = F if most armed units fired that second, else the dominant hold reason;")
	print("  . none  R reload  c cooldown  m no moving fire  n min range  o out of range  l no LOS  s not spotted  t no target")
	print("cols: scenario | dmg | DPS(300t) | DPS from 1st shot | shots | hits | hit% | 1st shot s | unit-ticks moving | unit fire events moving/standing | instinct end/min | end centroid dist m | holds (unit-ticks)")
	var rifle := [
		# name, order, dist, extra
		["R1 HOLD in range 35m", "hold", 35, {}],
		["R2 HOLD out of range 44m", "hold", 44, {}],
		["R3 MOVE to enemy centre 44m", "move", 44, {}],
		["R3b MOVE to 20m short of enemy", "move", 44, {"move_short": 20}],
		["R4 ATTACK_MOVE to enemy 44m", "attack_move", 44, {}],
		["R5 ATTACK target 44m", "attack", 44, {}],
		["R6 MOVE run 44m", "move", 44, {"run": true}],
		["R6b ATTACK_MOVE run 44m", "attack_move", 44, {"run": true}],
		["R6c ATTACK run 44m", "attack", 44, {"run": true}],
		["R7 MOVE 70m (unseen start)", "move", 70, {}],
		["R7b ATTACK_MOVE 70m", "attack_move", 70, {}],
		["R8 HOLD flank 35m @45deg", "hold", 35, {"flank": true}],
		["R8b ATTACK_MOVE flank 50m @45deg", "attack_move", 50, {"flank": true}],
		["R8c ATTACK flank 44m @45deg", "attack", 44, {"flank": true}],
		["R8d ATTACK_MOVE vs column 44m", "attack_move", 44, {"enemy_facing_south": true}],
		["R9 2 enemies: ATTACK A only", "attack", 44, {"second": true}],
		["R9b 2 enemies: ATTACK B only", "attack", 44, {"second": true, "target_b": true}],
		["R9c 2 enemies: ATTACK A, retarget B @t50", "attack", 44, {"second": true, "retarget_at": 50}],
		["R9d 2 enemies: ATTACK A, retarget B @t150", "attack", 44, {"second": true, "retarget_at": 150}],
		["R9e 2 enemies: ATTACK_MOVE", "attack_move", 44, {"second": true}],
	]
	print("\n== Rifle squad (8 x rifle: aimed 1x0.6x3/1.0s standing; burst 3x0.3x3/1.5s moving) vs disarmed 1000-HP rifle squad on HOLD ==")
	for s in rifle:
		_run("rifle_squad", s[0], s[1], s[2], s[3])
	print("\n== Rifle squad vs ARMED rifle squad on HOLD (real duel, 300 ticks) ==")
	for s in rifle.slice(0, 11):
		var ex: Dictionary = s[3].duplicate()
		ex["armed"] = true
		_run("rifle_squad", s[0] + " [armed]", s[1], s[2], ex)
	print("\n== Mortar team (3 x mortar: 1x0.35x10 AoE5 / max(reload 30, cd 60) = 6 s, range 20-90, standing only) vs disarmed target; a disarmed friendly spotter holds 25 m from the target ==")
	var mortar := [
		["M1 HOLD in range 60m", "hold", 60, {}],
		["M2 HOLD out of range 100m", "hold", 100, {}],
		["M3 MOVE to enemy centre 100m", "move", 100, {}],
		["M3b MOVE to 50m short", "move", 100, {"move_short": 50}],
		["M4 ATTACK_MOVE to enemy 100m", "attack_move", 100, {}],
		["M5 ATTACK target 100m", "attack", 100, {}],
		["M5b ATTACK target 60m (in range)", "attack", 60, {}],
		["M6 ATTACK_MOVE run 100m", "attack_move", 100, {"run": true}],
	]
	for s in mortar:
		var ex: Dictionary = s[3].duplicate()
		ex["spotter"] = true
		_run("mortar_team", s[0], s[1], s[2], ex)
	print("
== Mixed-range squads vs disarmed target (does the squad stop where only its longest weapon reaches?) ==")
	for sq in [["assault_squad", "1 sgt rifle 40m + 4 breacher shotgun 15m"], ["heavy_weapons_team", "2 lmg 50m + 2 rifle 40m"], ["rocket_team", "2 rocket 45m + 1 rifle 40m"]]:
		print("-- %s (%s)" % sq)
		for s in [["HOLD at 12m (all in range)", "hold", 12, {}], ["MOVE to enemy centre 60m", "move", 60, {}],
				["ATTACK_MOVE to enemy 60m", "attack_move", 60, {}], ["ATTACK target 44m", "attack", 44, {}]]:
			_run(sq[0], "  " + s[0], s[1], s[2], s[3])
	print("
== Far second target and moving targets (rifle vs disarmed) ==")
	for s in [["R10 A at 35m in range; ATTACK far B (55m, spotted)", "attack", 35, {"far_b": true, "target_b": true}],
			["R10b A at 35m; HOLD (fires at A)", "hold", 35, {"far_b": true}],
			["R10c HOLD on A, retarget far B @t50", "hold", 35, {"far_b": true, "retarget_at": 50}],
			["R11 target walks north 40m: ATTACK", "attack", 38, {"foe_walk": true}],
			["R11b target walks north 40m: ATTACK_MOVE to its start", "attack_move", 38, {"foe_walk": true}],
			["R11c target walks north 40m: HOLD", "hold", 38, {"foe_walk": true}]]:
		_run("rifle_squad", s[0], s[1], s[2], s[3])
	print("
== Armed rifle duels, both sides acting (attacker order vs defender order), start 60 m (out of sight) ==")
	for s in [["A: ATTACK_MOVE vs D: ATTACK_MOVE (mirror)", "attack_move", 60, {"armed": true, "foe_order": "attack_move"}],
			["A: HOLD vs D: ATTACK_MOVE", "hold", 60, {"armed": true, "foe_order": "attack_move"}],
			["A: MOVE vs D: ATTACK_MOVE", "move", 60, {"armed": true, "foe_order": "attack_move"}],
			["A: MOVE vs D: MOVE (mirror)", "move", 60, {"armed": true, "foe_order": "move"}],
			["A: ATTACK_MOVE vs D: HOLD", "attack_move", 60, {"armed": true}],
			["A: ATTACK_MOVE vs D: HOLD (deaths traced)", "attack_move", 60, {"armed": true, "trace_deaths": true}],
			["A: HOLD 35m vs D: HOLD (deaths traced)", "hold", 35, {"armed": true, "trace_deaths": true}]]:
		_run("rifle_squad", s[0], s[1], s[2], s[3])
	quit(0)


func _place(s: BattleState, player: int, squad: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, rules.squad_index(squad), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid


func _disarm(s: BattleState, sid: int) -> void:
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)


func _toughen(s: BattleState, sid: int) -> void:
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"hp", 1000 * ONE)
		s.units.set_value(s.units.id_at(urow), &"hp_max", 1000 * ONE)


func _order(s: BattleState, sid: int, kind: String, x: int, y: int, target: int, run: bool) -> void:
	var row := s.squads.row_of(sid)
	var t: int = BattleOrders.TYPES[kind]
	var tx := x
	var ty := y
	if kind == "hold":
		tx = s.squads.cx[row]
		ty = s.squads.cy[row]
	BattleOrders.set_order(s, row, t, tx, ty, target, 1 if run else 0)


func _run(squad: String, name: String, order: String, dist: int, ex: Dictionary) -> void:
	var s := BattleState.new(1, rules, 1)
	s.trace_shots = true
	var armed: bool = ex.get("armed", false)
	var ex_x := AX + dist
	var ex_y := LANE_Y
	var enemy_facing := Fixed.ANGLE_HALF
	if ex.get("flank", false):
		# 45 degrees off the attacker's facing (east), to the north.
		var d := Fixed.mul(dist * ONE, Fixed.fcos(Fixed.ANGLE_QUARTER / 2))
		ex_x = AX + Fixed.to_int_round(d)
		ex_y = LANE_Y - Fixed.to_int_round(d)
	if ex.get("enemy_facing_south", false):
		enemy_facing = Fixed.ANGLE_QUARTER
	var me := _place(s, 1, squad, AX, LANE_Y, 0)
	var foe := _place(s, 2, "rifle_squad", ex_x, ex_y, enemy_facing)
	var foe_b := -1
	if ex.get("second", false):
		foe_b = _place(s, 2, "rifle_squad", AX + dist - 4, LANE_Y - 18, Fixed.ANGLE_HALF)
	if ex.get("far_b", false):
		foe_b = _place(s, 2, "rifle_squad", AX + 45, LANE_Y - 32, Fixed.ANGLE_HALF)
		var spb := _place(s, 1, "rifle_squad", AX + 45, LANE_Y - 55, 0)
		_disarm(s, spb)
	if not armed:
		for f in [foe, foe_b]:
			if f >= 0:
				_disarm(s, f)
				_toughen(s, f)
	if ex.get("spotter", false):
		var sp := _place(s, 1, "rifle_squad", ex_x - 25, ex_y + 5, 0)
		_disarm(s, sp)
	if ex.get("foe_walk", false):
		var frow0 := s.squads.row_of(foe)
		BattleOrders.set_order(s, frow0, BattleSquads.Order.MOVE, s.squads.cx[frow0], s.squads.cy[frow0] - 40 * ONE, -1, 0)
	if ex.has("foe_order"):
		var mrow := s.squads.row_of(me)
		_order(s, foe, ex["foe_order"], s.squads.cx[mrow], s.squads.cy[mrow], -1, false)
	var target := foe_b if ex.get("target_b", false) else foe
	var trow := s.squads.row_of(target)
	var tx := s.squads.cx[trow]
	var ty := s.squads.cy[trow]
	var short: int = ex.get("move_short", 0)
	if short > 0:
		tx -= short * ONE
	_order(s, me, order, tx, ty, target if order == "attack" else -1, ex.get("run", false))
	var my_units := {}
	for urow in Centroids.units_of(s, s.squads.row_of(me)):
		my_units[s.units.id_at(urow)] = true
	var sim := BattleSim.new()
	var holds := {}
	var timeline := ""
	var sec_counts := {}
	var sec_fired := 0
	var sec_armed := 0
	var moving_ticks := 0
	var fire_moving := 0
	var fire_standing := 0
	var inst_min := 1 << 62
	var first_shot := -1
	var death_me := "-"
	var death_foe := "-"
	var me0: int = s.squads.alive[s.squads.row_of(me)]
	var foe0: int = s.squads.alive[s.squads.row_of(foe)]
	for t in TICKS:
		if ex.has("retarget_at") and t == ex["retarget_at"]:
			# What the Retarget reaction's order effect does (effects.gd _order "attack").
			var brow := s.squads.row_of(foe_b)
			BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK, s.squads.cx[brow], s.squads.cy[brow], foe_b, 0)
		sim.runner.step(s)
		if ex.get("trace_deaths", false):
			var cm := 0
			var cf := 0
			var hm := PackedStringArray()
			var hf := PackedStringArray()
			for ur in s.units.count():
				if s.units.hp[ur] <= 0:
					continue
				if s.units.squad[ur] == me:
					cm += 1
					hm.append("%.0f" % (float(s.units.hp[ur]) / ONE))
				elif s.units.squad[ur] == foe:
					cf += 1
					hf.append("%.0f" % (float(s.units.hp[ur]) / ONE))
			if cm != int(ex.get("_cm", me0)) or cf != int(ex.get("_cf", foe0)):
				print("      t=%.1f alive me %d foe %d  my hp [%s]  foe hp [%s]" % [t / 10.0, cm, cf, ",".join(hm), ",".join(hf)])
				ex["_cm"] = cm
				ex["_cf"] = cf
		var row := s.squads.row_of(me)
		if row < 0:
			break
		var frw := s.squads.row_of(foe)
		if death_me == "-" and s.squads.alive[row] < me0:
			death_me = "%.1f" % (t / 10.0)
		if death_foe == "-" and (frw < 0 or s.squads.alive[frw] < foe0):
			death_foe = "%.1f" % (t / 10.0)
		var ivalue := Pools.value(s, row, BattleSquads.INSTINCT)
		inst_min = mini(inst_min, ivalue)
		for urow in Centroids.units_of(s, row):
			if s.units.hp[urow] <= 0:
				continue
			if s.units.moving[urow] == 1:
				moving_ticks += 1
			if s.units.weapon[urow] < 0:
				continue
			sec_armed += 1
			if s.units.fired_tick[urow] == s.tick - 1:
				sec_fired += 1
				if first_shot < 0:
					first_shot = s.tick - 1
				if s.units.moving[urow] == 1:
					fire_moving += 1
				else:
					fire_standing += 1
				holds["F"] = int(holds.get("F", 0)) + 1
				continue
			var h: String = HOLD_LETTERS[BattleActivity.hold(s, urow)]
			holds[h] = int(holds.get(h, 0)) + 1
			sec_counts[h] = int(sec_counts.get(h, 0)) + 1
		if (t + 1) % rules.tps == 0:
			# A rifle fires about once a second, so "most fired" = fired events >= half the armed units.
			var units_alive: int = maxi(sec_armed / rules.tps, 1)
			if sec_fired * 2 >= units_alive:
				timeline += "F"
			else:
				var best := "."
				var bn := -1
				for k: String in sec_counts:
					if sec_counts[k] > bn:
						bn = sec_counts[k]
						best = k
				timeline += best
			sec_counts = {}
			sec_fired = 0
			sec_armed = 0
	var shots := 0
	var hits := 0
	for o in range(0, s.shot_trace.size(), BattleState.SHOT_STRIDE):
		if my_units.has(s.shot_trace[o + 1]):
			shots += 1
			hits += s.shot_trace[o + 3]
	var dmg := 0
	for o in range(0, s.hit_trace.size(), BattleState.HIT_STRIDE):
		if my_units.has(s.hit_trace[o + 3]):
			dmg += s.hit_trace[o + 2]
	var foe_dmg := 0
	for o in range(0, s.hit_trace.size(), BattleState.HIT_STRIDE):
		if not my_units.has(s.hit_trace[o + 3]):
			foe_dmg += s.hit_trace[o + 2]
	var row := s.squads.row_of(me)
	var end_d := -1.0
	var inst_end := -1.0
	var alive := 0
	if row >= 0:
		var frow := s.squads.row_of(target)
		if frow >= 0:
			end_d = float(Fixed.distance(s.squads.cx[row], s.squads.cy[row], s.squads.cx[frow], s.squads.cy[frow])) / ONE
		inst_end = float(Pools.value(s, row, BattleSquads.INSTINCT)) / ONE
		alive = s.squads.alive[row]
	var dmgf := float(dmg) / ONE
	var secs := float(TICKS) / rules.tps
	var after := (float(TICKS - first_shot) / rules.tps) if first_shot >= 0 else 0.0
	var extra := ""
	if armed:
		var frow2 := s.squads.row_of(foe)
		extra = " | my alive %d | foe alive %d | foe dmg %.0f | first foe death s %s, first own death s %s" % [alive, s.squads.alive[frow2] if frow2 >= 0 else 0, float(foe_dmg) / ONE, death_foe, death_me]
	print("%-44s | %6.1f | %5.2f | %5.2f | %4d | %4d | %3d%% | %5s | %4d | %d/%d | %.0f/%.0f | %5.1f | %s%s" % [
		name, dmgf, dmgf / secs, (dmgf / after) if after > 0 else 0.0, shots, hits,
		(100 * hits / shots) if shots > 0 else 0, ("%.1f" % (first_shot / float(rules.tps))) if first_shot >= 0 else "-",
		moving_ticks, fire_moving, fire_standing, inst_end, float(inst_min) / ONE, end_d, _fmt_holds(holds), extra])
	print("    " + timeline)


func _fmt_holds(h: Dictionary) -> String:
	var keys := h.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s:%d" % [k, h[k]])
	return " ".join(parts)
```

</details>
