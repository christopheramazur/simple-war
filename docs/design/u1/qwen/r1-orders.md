# Research note — attack-move, coherency, collision (Simple War)

## 1. SC2 / Brood War: per-unit attack-move

**The core difference from Simple War: acquisition and stopping are per-unit, not per-squad.** In SC2 each unit runs its own acquire→chase→attack loop; the group's "firing line" is emergent.

- **Acquisition:** each unit has an *acquire radius* (data field, typically ≥ weapon range) and a **Target Sorts** stack (data-driven scorers: distance, attack-priority, "is attacking me", threat, weapon-vs-armor). This is exactly the composable, no-code pattern you want.
- **Attack-move:** a move order with an acquire flag. Unit moves along its path; if a valid target is inside *its own* weapon range it stops and fires; if inside acquire radius but out of range it deviates toward the target, bounded by a **chase/leash distance** anchored to the order position, then resumes the move. (Exact SC2 leash values: unsure; they are per-unit data.)
- **Why it feels good:** the front rank stops at range, the rear ranks keep closing until *they* can shoot, so a blob self-organises into an arc at max range. No unit is idle because a friend found a target.
- **BW clumping:** per OpenBW reverse-engineering, ground collision is only resolved against *non-moving* units — movers pass through each other, so a move-click to one point stacks a "marine ball", which then pushes apart on stop. SC2 uses soft separation with per-unit **separation radius / push priority** in mover data: movers push idlers, idlers don't push movers.
- **Spreading** is manual (split boxes, move-click, hold-position + patrol micro) — the game gives clumping for free and charges APM for spread. For a plan-then-resolve game, invert that: make spread the default, clumping an explicit order.

## 2. Squad games

- **Company of Heroes 1/2/3:** squads of 3–6 entities. Cover is **directional and per-slot** (heavy/light/negative, evaluated against the incoming threat direction). Moving near cover auto-snaps each soldier to a free cover slot within a search radius of the destination — cover seeking is a *slot-assignment* problem, not a steering problem. Cohesion: stragglers speed up / reposition; suppression is applied per-entity but pinning is squad-visible. Infantry collision is soft; vehicles displace infantry. (CoH1 lacked attack-move at launch; CoH2/3 have it — moderately confident.)
- **Dawn of War 1:** squads with independent **stances** (hold/attack-move, ranged/melee, fire-at-will/hold-fire) — a clean precedent for orthogonal stance flags rather than monolithic orders. Members path individually and catch up to the squad anchor; cover is zonal (light/heavy/negative), not per-slot. DoW2 shrinks squads to 1–4 with directional cover. (DoW2 attack-move: unsure.)
- **Total War:** regiment = rigid rank/file formation with spacing; the block moves as one, entities keep slots. Melee uses **matched combat** (entity pairing with synced animations) from Shogun 2 onward; earlier titles use mass-based pushing. Friendly units interpenetrate with a speed penalty; enemies block. **Guard Mode** (Warhammer) = "hold formation, do not pursue" — literally leash = 0, and players read it as a safety toggle.
- **Men of War / Assault Squad:** no formation abstraction; individual soldiers, physical cover and true raycast LOS, stances (stand/kneel/prone), hold-fire/return-fire. Grouping is entirely player-managed. (Fine details: unsure.) Useful lesson: cover as *geometry + LOS*, not as a stat tile.

**Takeaway:** cover-seeking = slot assignment; coherency = anchor + catch-up; collision = soft push with priority; pursuit = an explicit, readable leash.

## 3. Composable behaviour vocabulary (14 components)

Blackboard per squad, evaluated at a fixed 5 Hz decision tick; components are pure functions reading/writing named fields, ordered by a data list. Mods edit weights/params, never code.

| # | Component | In → Out |
|---|---|---|
| C1 | **Sense** | unit sight, grid buckets → candidate enemies + per-unit LOS set |
| C2 | **TargetSort** | candidates, scorer list (dist, threat, armor-fit, assigned-count, order-forced) → ranked targets, per-unit pick |
| C3 | **FireGate** | weapon range band, mag/reload/cooldown, LOS, move-fire mode → per-unit `can_fire_now`, `can_fire_after_move`, `dist_to_solution` |
| C4 | **FirePosSolver** | target pos, range band, move budget left, cost/cover map → desired anchor + per-unit firing slots at `R_stop = 0.9·R_max` |
| C5 | **Advance** | order path, anchor, speed mode → anchor velocity, path progress |
| C6 | **Slots** | formation template (ring/arc/rank/column), count, facing → slot positions + stable assignment |
| C7 | **Leash** | order anchor, chase radius, dwell timer → clamp on desired positions, return intent |
| C8 | **CoverSeek** | cover map, threat bearing, slot candidates → slot re-ranking (bias, never override range) |
| C9 | **Separate** | positions, radii, push priority → integer displacement |
| C10 | **FireControl** | stance flags, C3, duty-cycle params → fire intents / stop-to-fire windows |
| C11 | **Cohesion** | member vs anchor distance → straggler speed scale, anchor wait, catch-up threshold |
| C12 | **FallbackEval** | HP/suppression thresholds, threat proximity → withdraw anchor (hysteretic) |
| C13 | **Contact** | target, contact radius → charge intent, melee pairing |
| C14 | **Arbiter** | all intents + priority weights → one action per unit; ties broken by unit id |

**Archetype × order stacks** (defaults; all overridable in data):

| Archetype | ATTACK_MOVE | HOLD | ATTACK(target) |
|---|---|---|---|
| Rifle | C1,C2,C3,**C4**,C5,C6(ring),C7(6 m),C8(light),C9,C10(move-fire 50%),C11,C14 | drop C4/C5; C7=0 | C7=20 m, C2 forced-target |
| LMG | as rifle, C4 at max band, C6 arc facing threat, C10 setup 1 s / no move-fire, C7=3 m | full DPS, setup once | C7=6 m |
| Mortar | C1 needs spotter LOS; C4 indirect band [min,max]; no advance into LOS; C10 deploy 2 s; C12 auto-fallback inside min range | deploy + fire | same, forced target |
| Sniper | C4 at max range, C8 heavy cover, C10 standing-only long cooldown, C7=0–2 m, C12 on contact threat | full DPS | C7=4 m |
| Melee | C13 replaces C4 (contact 0.8 m), C5 charge, C9 relaxed at contact, C7=20 m | C7=0, counter-charge only | C7=∞ within turn |

The owner's ask is exactly **C4 enabled by default for rifles on ATTACK_MOVE**, with the anchor stopping at the *solved fire position*, not at the first unit's shot.

## 4. Determinism, separation, clustering (1 m grid, ~200 units)

- **Representation:** fixed-point mm (int32), 1 m grid for broadphase only. No floats, no `sqrt` — squared distances + integer isqrt. Fixed 10 Hz sim tick, 5 Hz decisions. All iteration in ascending unit id; pair loops sorted `(id_a,id_b)`.
- **Separation:** 2 relaxation passes max, uniform-grid neighbours (≈O(n·k)). Overlap `d < r_a+r_b` → push each half along the integer normal; rounding remainder always to the lower id (otherwise you get a systematic drift). Cap push at e.g. 0.25 m/tick.
- **Priority:** firing/setup units are anchors (priority 0), movers priority 2, chargers 3. Higher priority displaces lower; equal priority splits. Idle units never push firing units.
- **Jitter fixes:** deadzone (only resolve overlap > 0.10 m); a `settled` flag that suppresses re-push while firing; quantise final positions to 1/16 m so tiny pushes vanish.
- **Deadlock fixes:** deterministic sidestep bias perpendicular to the blocked heading, sign = `id & 1`; after N blocked ticks, allow temporary soft overlap ("ghosting") rather than freezing — cheaper and more readable than a perfect solver.
- **Range-boundary oscillation:** hysteresis — enter fire at `R_max`, resume advance only past `R_max + 1.5 m`; stop target at `0.9·R_max` so drift doesn't break the shot; minimum commitment dwell 0.5 s before any move/fire flip.
- **Ring slots:** for a chosen target, generate slots on an arc at `R_stop` facing the approach, sorted by angle; assign greedily by current angle (stable, O(n log n)), reassign at most every 0.5 s and only if cost improves by > 1 m. This kills slot-swap jitter and produces the SC2 firing arc for free.
- **Cohesion:** anchor waits (speed × 0.5) if any member is > 8 m behind; members > 15 m get +25% speed; never teleport (breaks readability of a replay). Squad-level stop condition: anchor reaches fire position **or** ≥70% of units have a firing solution — not "one unit fires".

## 5. Orders as an explicit damage/safety/speed trade

Every order should publish three numbers in the UI: **DPS factor, exposure, speed**. Damage loss must come from the order, never from pathing accidents.

| Order | DPS factor | Movement | Chase leash | Reads as |
|---|---|---|---|---|
| HOLD | 100% (standing fire) | 0 | 0 | max damage, no repositioning |
| ATTACK_MOVE | 50% move-fire **or** ~55% via stop-to-fire duty cycle (0.6 s stop / 1.2 s cycle) | full | 6 m | advance and shoot, costs ~half your DPS |
| ATTACK(target) | 100% once in range, focus-fire bonus | full | 20 m | tunnel vision: you eat free hits from others |
| RUN | 0% | +40% | 0 | pure tempo, defenceless |
| FALL_BACK | 30% (rear-facing only) | full | 0 | trade damage for distance |
| WITHDRAW | 0% | +25% | 0 | break contact |

Design rules: (a) prefer a **published duty cycle** over a hidden accuracy penalty — players can reason about "half my shots"; (b) since the sim is deterministic, show a **plan preview** with projected shots-per-unit this turn (Frozen Synapse's prime/preview, Combat Mission's WEGO turn planning are the precedents); (c) any residual DPS loss from separation or stragglers should be < 5%, otherwise it's an accident, not a choice.
