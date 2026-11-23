# U1-04 Prowess as fire-distribution quality (long-term)

Traces to the "Longterm SIMPL idea for Prowess" paragraph of `docs/design/u1/brief.md`. This is a **long-term** feature. The first beads add the metrics and the policy seam (an interface that today's nearest-target picker sits behind), so the rest can be slotted in later without touching anything else.

Owner statements from the brief are tagged **U1Q-P1…P6** and treated as settled. The integrator renumbers them into the round's U1Qn sequence. Everything else is *proposed*.

| Tag | Owner statement (brief) |
|---|---|
| U1Q-P1 | For a squad firing at an enemy squad, there is a mathematically optimal way to spread its attacks that kills the most units. |
| U1Q-P2 | Optimal Prowess conditions should make the attacker fire that way. |
| U1Q-P3 | The worse arrangements are overkill (several attacks on one unit) and spreading fire so thin that nothing dies. |
| U1Q-P4 | At Neutral Prowess a squad tries to focus on a few units, with some fuzz. How good it is depends on its base Prowess. High is better, low is worse. |
| U1Q-P5 | Surging squads overkill less because they swap targets faster. Fraying squads overkill more. |
| U1Q-P6 | Hard, but worth it: it creates distinct gameplay modes and feels. |

---

## 1 Findings

### 1.1 Current behaviour (code)
- **Squad-level target** (`src/sim/battle/combat_system.gd:47-93`, `_engage`). The squad takes its ordered attack target if that target is visible and in reach. Otherwise it keeps its previous target (sticky, :60-64). Failing both, it takes the nearest visible enemy squad within its longest weapon range (:65-73).
- **Unit-level victim** (`_fire_squad`, :96-160). Each ready unit, in row order, calls `_nearest_target` (:218-241): the nearest living unit that passes the gate (range, min range, line of fire; `shot_gate` :206-215), preferring units whose queued damage this tick does not already cover their HP.
  - A unit picks its victim *before* the hit roll (:119 vs :137).
  - Within a burst, the unit re-picks before each shot if its victim has become covered (:130-133).
- **The cover check uses raw damage** (`_covered`, :170-173). It compares the pre-defence damage `pending` holds (:163-167) with the victim's HP. The comment says defences "only lower it", so the check overestimates progress against armour: block, resistance, flat reduction and percentage reduction all lower damage (the floor can raise it). Units therefore leave armoured targets they have not actually covered (see the CHI row in §1.3).
- **`pending` is per squad, per tick** (`:104`). Two squads of one side firing at the same enemy squad never see each other's queued damage.
- **Simultaneous fire.** Hits are queued; `HealthSystem` drains them after every squad has fired, in shooter-unit-ID order (`health_system.gd:31-44`).
  - A hit on a unit that is already dead is silently dropped (:52). That is wasted fire, and nothing counts it.
  - The `squad_damaged` event carries damage dealt and kills (:25-28, 96-101), but not raw damage or overkill.
  - **Consequence:** overkill can only arise *within one tick*. Dead units are never chosen again (:227), so on later ticks fire corrects itself.
- **Hit and crit accumulators are deterministic** (`_roll_hit` :244-251; crit every Nth hit :143-149). Every unit's `acc_hit` and `hits` start at 0 (`battle_units.gd:33-36`). Identical units with identical cooldowns therefore fire **lockstep volleys**: every rifleman hits on the same ticks (aimed 0.6 accuracy every 10 ticks lands hits at ticks 10, 30, 40, 60…).
  - The target's evasion and block are per-target accumulators (`damage_pipeline.gd:26-52`). They are deterministic but hidden from the shooter.
- **Prowess today** has no combat effect beyond its floats and sinks:
  - floats: ambush and intercept (`combat_system.gd:86,92`), interrupt (`abilities.gd:211`), reacted-to (`reactions.gd:50`);
  - sink: readying Vacuum (`abilities.gd:235`);
  - the `steady_aim` trait floats Prowess every 3 hits (`data/packages/core/defs/effects.json:59-64`);
  - drift and Morale governance: Prowess is governed (`pools_system.gd:16`). Defaults are capacity 100, neutral 52 and drift 0.5%/s (`ruleset.json:13`).
- **Efficacy** (`pools.gd:61-65`) is value/neutral clamped to [lo, hi], with `hi` defaulting to 1.0. Instinct uses [0.5, 1.0] (`combat_system.gd:127`, `vision_system.gd:100`). A Prowess knob that is *better* above Neutral needs `hi > 1` (up to cap/neutral = 100/52 ≈ 1.92).
- **What this means:** in line-vs-line fights each rifleman's nearest target is "the one opposite me". The current policy therefore spreads one hit per target per volley. That is the **over-spread pole**: every target dies in the same volley (§1.3, first row). Today's default is not neutral in the owner's sense. It is the bad "too distributed" extreme.

### 1.2 The maths: what "optimal" is, and a cheap policy that reaches it
**Problem per squad per tick.** We have:
- ready shooters *S* (units whose reload and cooldown are 0);
- for each shooter, the hits it will land this tick, *h_s*. This is exactly predictable from `acc_hit`, but irrelevant: a miss changes nothing, and `pending` only ever holds hits;
- per-hit damage *d_s*, including the predictable every-Nth crit;
- a reach matrix (`shot_gate`);
- targets *T* with remaining HP *r_t*: HP minus this tick's queued effective damage.

The defence pipeline maps a hit to effective damage *e(d, t)*. The mapping is non-linear (block, resistance, flat, percentage, floor), but deterministic per hit apart from the evasion and block accumulators.

**Objective, lexicographic:**
1. Maximise the number of targets with Σ assigned *e* ≥ *r_t* (kills this tick).
2. Then maximise the damage carried onto the single most-wounded survivor (next tick's kill).
3. Then minimise waste.

That is **bin covering with assignment restrictions**, the dual of bin packing (Assmann et al. 1984). In general it is a generalised weapon-target assignment (WTA) problem and NP-hard (Lloyd & Witsenhausen 1986). It stays tractable here for three reasons:
- **Instances are tiny:** |S|, |T| ≤ ~10.
- **Uniform damage makes greedy exact.** Most squads deal uniform per-hit damage (one weapon type, or the same *e* against identical defences). Then **greedy "fill the lowest-remaining target first" is optimal per tick**. Hits are interchangeable, so covering the cheapest bins first maximises the count (an exchange argument). The leftover hits go onto the next-lowest target, which also satisfies objective 2.
- **Myopic is near-optimal across ticks.** Targets die between ticks and are never shot again. Killing as early as possible also removes return fire earliest (Lanchester square law), so the myopic greedy is near-optimal over the horizon. A search over future ticks buys almost nothing.

**Cases the greedy needs help with:**
- **Mixed damage** (LMG plus rifles, crits): use a best-fit tie-break. Among targets the hit can finish, prefer the one where *e − r_t* is smallest. Otherwise use the lowest *r_t*.
- **AoE** (mortar, rocket): the victim choice decides the splash. Score a victim by the kills in its radius, then the effective damage in its radius. A single-target kill priority makes AoE *worse*: in §1.3 the mortar takes 300 ticks to wipe the squad instead of 120.
- **Defences:** cover must use *expected* effective damage. That means `DamagePipeline` without the evasion and block accumulators, which are the target's hidden state. Then *r_t* is honest.
- **Granularity floor:** a kill costs ⌈r/e⌉·e. The excess over *r* is unavoidable. Rifles (3 damage) against 10 HP troopers waste 2 per kill, which is 14.6% across a rifle squad. Report it separately from "policy overkill".

**What the shooters may know** (proposed: "optimal" means optimal over observable information):
- Only units the side can see. The candidates already come from `seen_by`. Unseen units do not exist to the policy.
- The visible units' current HP and Defensive Profile (both shown in the UI, per the transparency rule §2.1).
- The squad's own queued hits this tick (that is what "coordination" is).
- **Never** the target's evasion or block accumulator state, and never another player's orders.

**Cost.** One candidate pass per shooter: O(|T|) gate checks, the same as `_nearest_target` today. One sort per squad per tick: O(|T| log |T|). O(K) per shot. Total O(|S|·|T| + |T| log |T|) per squad per tick, which is the same order as now. No allocation is needed beyond a reusable PackedInt64Array.

### 1.3 Headless experiment
**Script:** `docs/design/u1/scripts/prowess/fire_policy_exp.gd`, results in `results.txt` beside it. It runs the real `BattleRules` (core package, `duel_crossroads`), the real systems and the real `HealthSystem`. The only change is a `CombatSystem` subclass that overrides `_nearest_target` per squad. `hx godot run` only accepts paths under the repo, so the experiment ran as `Godot_v4.7.2-stable_win64_console.exe --headless --path . -s <script>`.

**Setup:**
- Squads stand on HOLD in line formation, 30 m apart (40 m for the marksman matchup, 36 m for the mortar, inside its 40 m sight).
- Targets are disarmed. They have `no_armour`, so waste = raw − HP removed is exact, except in the CHI row, where waste includes mitigation.
- Time is in ticks (10 per second).

**Policies:**
- **nearest:** today's picker.
- **q,c (the proposed knob, §3):** *q* is focus quality (1 = kill priority, 0 = nearest among all). *c* is the coordination %, the share of volleys in which a shooter sees its squad's queued damage.
- **bad-overkill:** q = 1, c = 0.
- **bad-spread:** always the healthiest target.

**Passive target: first kill, mean kill time, waste and kills per 100 raw damage**

| Matchup | Policy | First kill | Mean kill t | Wipe t | Waste % | Kills/100 |
|---|---|---|---|---|---|---|
| rifle → rifle | nearest (current) | 60 | 60 | 60 | 14.6 | 8.33 |
| | optimal (1, 100) | **10** | **35** | 60 | 14.6 (floor) | 8.33 |
| | neutral (0.6, 70) | 10 | 46 | 80 | 31.7 | 6.67 |
| | fraying (0.3, 35) | 30 | 51 | 80 | 31.7 | 6.67 |
| | broken (0.1, 10) | 40 | 60 | 80 | 31.7 | 6.67 |
| | bad-overkill (1, 0) | 10 | 69 | 130 | **62.6** | 3.65 |
| | bad-spread | 60 | 60 | 60 | 14.6 | 8.33 |
| HWT (2 LMG + 2 rifle) → rifle | nearest | 20 | 68 | 110 | 14.6 | 8.33 |
| | optimal | 10 | 60 | 110 | 14.6 | 8.33 |
| | bad-spread | **90** | 100 | 110 | 14.6 | 8.33 |
| marksman ×2 → scout | nearest / optimal | 25 | 38 | 50 | 0 | 12.5 |
| | fraying | 25 | 50 | 75 | 33.3 | 8.33 |
| | bad-overkill | 25 | 63 | 100 | 60.0 | 5.00 |
| mortar → rifle (AoE 5) | nearest | 120 | 120 | **120** | 36.9 | 6.15 |
| | optimal (single-target priority) | 120 | 143 | **300** | 45.3 | 5.33 |
| rifle → CHI (carapace) | nearest | 30 | 72 | 90 | 56.9* | 4.17 |
| | optimal, raw cover | 40 | 62 | 80 | 48.3* | 5.00 |
| | optimal, defence-aware cover | **10** | **50** | 80 | 48.3* | 5.00 |

\* Includes defence mitigation.

**Duels: rifle squad (policy) against rifle squad (nearest), both armed, 30 m**

| Policy A | Lockstep volleys (today): A alive – B alive | Staggered accumulators: A – B |
|---|---|---|
| nearest | 0 – 0 (draw, mutual wipe at t = 60) | 0 – 1 / 1 – 0 (coin flip by side) |
| optimal | **6 – 0** | **7 – 0** |
| surging (0.9, 100) | 6 – 0 | 7 – 0 |
| neutral (0.6, 70) | 3–4 – 0 | 5 – 0 |
| fraying (0.3, 35) | 3 – 0 | 4–5 – 0 |
| broken (0.1, 10) | 0 – 1 | 1–3 – 0 |
| bad-overkill | **0 – 3** | 5 – 0 |
| bad-spread | 0 – 0 | coin flip |

**Reading:**
1. **Today's picker is the over-spread pole in line fights.** In the rifle row it is identical to bad-spread: first kill only at tick 60, when all 8 targets die together.
2. **Focus fire does not change the total damage against a passive target.** The wipe time is the same, but the mean kill time falls 42% (60 → 35 ticks). Against a target that shoots back, Lanchester makes that decisive: a mirror match goes from mutual annihilation to 6 of 8 survivors.
3. **The proposed knob is monotonic.** optimal ≥ surging > neutral > fraying > broken, and broken loses to today's picker. Neutral beats today's default, so **switching the default is a global balance change** (§4 Q2).
4. **The overkill axis only bites with synchronised volleys.** With lockstep accumulators, bad-overkill loses 0–3. Staggered, it wins 5–0, because few units hit in the same tick and dead units drop out of selection. The coordination term therefore depends on volley sync (§4 Q4).
5. **AoE and armour need their own scoring.** Single-target kill priority makes the mortar 2.5× slower to wipe the squad. Raw cover delays the first kill on CHI from tick 10 to tick 40.

---

## 2 Prior art (short)
- **Weapon-target assignment (WTA).** WTA assigns weapons to targets to maximise expected destroyed value. It is NP-complete in general (Manne 1958, *Operations Research* 6(3); Lloyd & Witsenhausen 1986, Proc. Summer Computer Simulation Conf.). Fast greedy and very-large-neighbourhood heuristics come within a few percent of optimal at sizes far above ours (Ahuja, Kumar, Jha & Orlin 2007, *Operations Research* 55(6):1136-1146). Our deterministic per-hit version is closer to **bin covering** (Assmann, Johnson, Kleitman & Leung 1984, *J. Algorithms* 5(4)), where simple greedy is near-optimal and exact for uniform items.
- **Lanchester's laws.** Under aimed fire, fighting strength scales with the square of numbers (Lanchester 1916, *Aircraft in Warfare*). So killing a unit early, which removes its fire, is worth more than equal damage spread across many units. That is the mechanism behind 0–0 → 6–0.
- **RTS combat AI.** Churchill, Saffidine & Buro, "Fast Heuristic Search for RTS Game Combat Scenarios", AIIDE 2012 ([AAAI](https://ojs.aaai.org/index.php/AIIDE/article/view/12527)), compares scripted policies (attack-closest, attack-weakest, attack-value = highest dpf/hp, and **no-overkill** variants that skip units already assigned lethal damage this frame) as baselines and playout policies. Their attack-value-with-no-overkill script is essentially our "optimal" pole. Attack-closest is our current picker. StarCraft II micro bots routinely implement focus fire plus no-overkill, and the gap between those scripts in the paper is the same order as ours. Secondary summary of the script set: [Gemrot seminar slides](https://cs.cas.cz/seminar-Machine-Learning/gemrot18.pdf).

---

## 3 Proposed GDD text

### 3.1 Rules Spec §2.6: new subsection after "Damage and defence order"
```markdown
### Fire distribution (U1Q-P1, U1Q-P3; proposed)
How a squad's hits are spread across the units of the squad it engages.
- **Two levels:** the squad picks the enemy squad (attack target, else sticky, else nearest in reach); each ready unit then picks a victim within it. The victim rule is a **targeting policy**, data-selected by the ruleset (`fire.policy`).
- **What a shooter knows:** only enemy units its side sees; their current HP and Defensive Profile; and, when coordinated (§2.8 Prowess), the hits its own squad has already queued this tick. Never a target's evasion or block accumulators.
- **Remaining HP:** a unit's HP minus the *expected* effective damage queued on it this tick: each queued hit run through the Defensive Profile without evasion and block. A unit is **covered** when its remaining HP is 0 or less. Covered units are skipped while another victim is in reach.
- **Kill priority:** candidates in reach, lowest remaining HP first, then lowest unit ID. For mixed damage, a hit that can finish a unit prefers the unit it overshoots least.
- **Area of effect:** a fire mode with an area picks the victim whose radius holds the most units its hit would finish, then the most effective damage.
- **Simultaneous fire:** all hits of a tick apply together after fire. A hit on a unit already killed that tick is **wasted**; with the damage beyond the killing hit's need it makes up **overkill**. Damage granularity sets an unavoidable floor (a 3-damage hit needs 12 damage for a 10 HP unit).
- **Shown:** tracers show where a squad's fire goes; the inspection window shows the squad's focus width and coordination and their terms (§2.1 Transparency).
```

### 3.2 Rules Spec §2.8 Prowess: replace the definition line and add a bullet
```markdown
### Prowess (R6Q1, R7Q2, R7Q3, U1Q-P2, U1Q-P4, U1Q-P5)
Battlefield presence: a squad's effect on the shape and flow of battle beyond raw numbers, including how well it distributes its fire (proposed wording).
- **Fire discipline** (proposed; numbers are data):
  - **Efficacy:** Prowess value / Neutral, from 0 up to capacity / Neutral (about 1.9 by default). Unlike Instinct it rises above 1.
  - **Focus quality** q = discipline × efficacy, clamped to 0–1. A unit fires at the nearest of the first K units in kill priority (§2.6), where K = 1 + (1 − q) × (candidates − 1). The fraction of K is carried by a per-unit accumulator, so the fuzz is deterministic (R2Q6). q = 1 is the kill-maximising distribution (U1Q-P1, U1Q-P2); q = 0 is plain nearest-target fire, spread thin (U1Q-P3).
  - **Coordination** c = coordination × efficacy, clamped to 0–100%. Each volley adds c to a per-unit accumulator; when it reaches 100 the unit sees its squad's queued hits this tick and skips covered units. Otherwise it sees only HP already lost and may pile onto a unit that is about to die: overkill (U1Q-P3, U1Q-P5).
  - **By band, with the defaults** (discipline 60%, coordination 70%): Neutral focuses on a few units with some fuzz (q ≈ 0.5–0.7, c ≈ 55–85%) (U1Q-P4); Surging approaches the optimum (q = 1, c = 100%) and swaps off covered units at once (U1Q-P5); Fraying spreads and overkills (q ≈ 0.2–0.45, c ≈ 20–50%); Broken is worse still.
  - **Which way a squad fails is content:** a low-discipline squad (militia) spreads its fire; a high-discipline, low-coordination squad (zealots) piles on; a datalinked squad (CR-0 robots) keeps coordination at 100%.
  - **No direct band multipliers (R5Q4):** discipline and coordination are squad stats that effects can modify; efficacy is continuous.
- **Not a float:** kills and efficient volleys do not float Prowess, which would snowball (proposed; compare Morale's no-damage link).
```
Also amend the Glossary entry: **Prowess**: battlefield presence, including fire discipline. *(R6Q1, U1Q-P2)*

### 3.3 Data Model
- **§3.3 Squad table, new row:**
  `| Fire discipline | `fire.discipline_pct` (default 60) and `fire.coordination_pct` (default 70); squad stats `squad.fire.discipline_pct`, `squad.fire.coordination_pct` (U1Q-P4; proposed) |`
- **Ruleset** (`ruleset.json` `standard`), proposed: `"fire": {"policy": "nearest", "discipline_pct": 60, "coordination_pct": 70}`. The policy ids are `nearest` (today's) and `prowess` (§3.2). Squad templates override the two percentages.
- **Units, runtime only** (not data): accumulators `acc_focus` and `acc_coord` beside `acc_hit`.
- **Glossary terms** (`glossary.json`): Fire discipline, Kill priority, Overkill, Covered.

### 3.4 Harness (GDD 05 §5.2 and §5.3), proposed
- **Battle metrics, per player:**
  - `fire.raw` (queued hit damage on enemies, before defences);
  - `fire.dealt` (to HP plus temporary HP);
  - `fire.mitigated`;
  - `fire.overkill` (wasted plus beyond-need, after defences);
  - `fire.wasted_hits`;
  - `fire.kills`;
  - `fire.first_kill_ticks` (mean ticks from an `engagement` to the first kill on that target);
  - `fire.victims_per_volley` (mean distinct victims per squad volley).
  - Derived in reports: overkill % = overkill / raw; kills per 100 damage.
- **Pressure Lab `fire_distribution`:** described in bead 7.
- **Tropes:**
  - **pile-on:** overkill % ≥ 35;
  - **spray:** kills per 100 damage below the run's granularity floor plus 10%, and first kill ≥ 4 s;
  - **volley wipe:** half of a squad dies in a single tick.

---

## 4 Open questions for the owner

| # | Question | Blocking? | Recommended default |
|---|---|---|---|
| Q1 | Prowess is defined as presence "beyond raw combat". Is fire distribution in scope for Prowess, or should it be its own stat? | Blocks bead 6 | Yes, put it in Prowess. Reword the definition as in §3.2. The brief already names Prowess. |
| Q2 | Switching the default from `nearest` to `prowess` makes Neutral deadlier than today (mirror duel: 0–0 becomes 3–4 survivors; mean kill time −23%). Accept this and rebalance? | Blocks switching the default (bead 6 ships off by default) | Accept. Run the Lab sweep first, then flip `fire.policy` in one commit with a new sim baseline era (BASELINE.md). |
| Q3 | Low Prowess fails toward overkill *or* over-spreading (U1Q-P3). Should each squad's data choose the direction, or should one global rule apply? | No | Per squad: two stats (discipline, coordination). |
| Q4 | Volleys are lockstep today because every `acc_hit` starts at 0. That makes volleys crisp and readable, and it is the only reason the coordination axis matters (bad-overkill 0–3 lockstep vs 5–0 staggered). Keep lockstep? | No | Keep lockstep for now. Add a Lab axis for a deterministic per-slot stagger before deciding. |
| Q5 | May the policy read visible enemy units' exact HP and Defensive Profile? | No | Yes for visible units, since the UI shows them. Never the hidden accumulators. |
| Q6 | Should sides coordinate *across* squads (shared queued damage), for example Surging squads, or squads near a commander? | No | Not now. Note it as a later Prowess or commander hook. |
| Q7 | Should efficient fire or kills float Prowess? And does `steady_aim` (Prowess every 3 hits) become a snowball? | No | No float. Re-tune `steady_aim` once the Lab shows its effect. |
| Q8 | Add a third lever, a re-acquire delay when a victim dies (lost time rather than lost damage)? | No | No. The brief already reports that retargeting seems to cost damage, and this would add more of that loss. |
| Q9 | Should players order fire onto a single unit? | No | No. Orders stay at squad level. Prowess governs everything below that. |

---

## 5 Bead breakdown (ordered)
The first two beads are the measurement and the seam. Nothing after them should change behaviour by default until Q2 is answered.

1. **Fire metrics: overkill, waste and time to first kill**
   - **Type:** task. **Priority:** P2. **Runner:** autopilot.
   - **Why:** the owner can't confirm the damage-output effects. Every later bead needs the numbers.
   - **What:**
     - In `HealthSystem._drain` (`src/sim/battle/health_system.gd:31-101`), count per (attacker, target) pair:
       - raw queued damage;
       - wasted hits and their damage (the victim is already dead at :52);
       - beyond-need damage on killing hits (`res.to_hp` vs the HP before the hit);
       - mitigation.
     - Add these fields to the `squad_damaged` event.
     - In `SimMetrics` (`src/api/sim_metrics.gd`), sum `fire.*` per player and compute `fire.first_kill_ticks` from `engagement` and `unit_killed`. Track `fire.victims_per_volley` via `squad_fired` plus `shot_trace`, or via a new `victims` field on `squad_fired`.
     - Document the metrics in GDD 05 §5.2.
   - **Acceptance:**
     - New GUT test: a rifle squad against a passive `no_armour` rifle squad reports `fire.raw` = 96, dealt = 82 and `first_kill_ticks` = 60 under today's picker.
     - State hash unchanged (`test_determinism`).
     - `hx sim run duel_crossroads` rows include the `fire.*` metrics.
   - **Deps:** none.

2. **Targeting-policy seam: nearest-target behind an interface**
   - **Type:** task. **Priority:** P2. **Runner:** autopilot.
   - **Why:** later policies plug in without editing `CombatSystem`.
   - **What:**
     - Create `src/sim/battle/target_policy.gd` (`class_name TargetPolicy`, RefCounted, static functions only): `begin_volley(state, row, trow)` and `pick(state, urow, targets, w, m, pending) -> int`, dispatching on `state.rules.fire_policy`.
     - Move `_nearest_target` and `_covered` there unchanged (`combat_system.gd:170-173, 218-241`) as the `nearest` policy.
     - Add `fire.policy` to the ruleset schema (`DataSchema`) and `BattleRules`, defaulting to `nearest`.
     - `_fire_squad` calls `TargetPolicy.pick` at :119 and :131.
   - **Acceptance:**
     - All GUT tests pass.
     - Replays and match logs give byte-identical state hashes.
     - `hx godot check` is clean.
     - An unknown policy id fails package validation.
   - **Deps:** none (parallel with 1).

3. **Fire range: a harness case for targeting policies**
   - **Type:** task. **Priority:** P3. **Runner:** swarm.
   - **Why:** a repeatable bench for the "workshop" the brief asks for.
   - **What:** port the U1 experiment to `tests/sim/test_fire_range.gd`:
     - matchups: rifle→rifle, HWT→rifle, marksman→scout, mortar→rifle and rifle→CHI;
     - squads on HOLD, line formation, passive `no_armour` targets;
     - a helper that runs N ticks and returns first kill, mean kill tick, wipe tick and waste.
   - **Acceptance:** under `nearest`, the test pins today's numbers: rifle→rifle first kill 60, mean 60, waste 14.6%; mortar→rifle wipe 120.
   - **Deps:** 2.

4. **Defence-aware cover (expected damage)**
   - **Type:** bug. **Priority:** P3. **Runner:** autopilot.
   - **Why:** `_covered` compares raw damage with HP, so shooters leave armoured units they haven't covered (rifle→CHI first kill: tick 40 with raw cover, tick 10 defence-aware).
   - **What:**
     - Add `DamagePipeline.preview(state, row, damage, dtype) -> int`: pure, no evasion or block, no state writes.
     - Make `pending` hold expected effective damage.
     - Update the §2.6 text.
   - **Acceptance:**
     - Fire-range CHI first kill ≤ 30 under `nearest`.
     - New unit test: `preview` matches `apply` when evasion and block are 0.
     - The determinism test passes.
   - **Deps:** 2, 3. This is a balance change; record it in BASELINE.md.

5. **`focus` policy: kill priority, best fit and AoE scoring**
   - **Type:** feature. **Priority:** P3. **Runner:** autopilot-large.
   - **Why:** the optimal pole (U1Q-P1, U1Q-P2).
   - **What:** in `TargetPolicy`, add:
     - the kill-priority order (remaining HP, then unit ID);
     - the best-fit tie-break for mixed damage;
     - AoE victim scoring (kills in radius, then damage);
     - one reusable buffer per volley; O(|S|·|T|).
     - Not the default.
   - **Acceptance:** in the fire range,
     - rifle→rifle first kill 10 and mean ≤ 36;
     - mortar→rifle wipe ≤ 120 (not worse than `nearest`);
     - rifle mirror duel 6–0 against `nearest`;
     - `perf.combat_usec` within +15% of `nearest` on `duel_crossroads`.
   - **Deps:** 2, 3, 4.

6. **`prowess` policy: discipline, coordination and efficacy above Neutral**
   - **Type:** feature. **Priority:** P3. **Runner:** autopilot-large.
   - **Why:** the quality knob (U1Q-P2, U1Q-P4, U1Q-P5).
   - **What:**
     - squad fields and stats `fire.discipline_pct` and `fire.coordination_pct`, through `DataSchema` and the stat registry;
     - ruleset defaults;
     - `Pools.efficacy(..., hi = cap/neutral)` for Prowess;
     - `BattleUnits` columns `acc_focus` and `acc_coord`, saved with the state;
     - K-width selection over the `focus` ordering, with the coordination accumulator gating whether `pending` is visible.
     - Template overrides: `hf_militia` discipline 30; `cr0_patrol` coordination 100 with no efficacy scaling (or via a bundle).
   - **Acceptance:** in the fire range with `fire.policy = prowess`:
     - Prowess pinned at Surging gives the same results as `focus`;
     - Neutral gives a rifle mirror duel 3–4 survivors against `nearest`;
     - Broken loses to `nearest`;
     - two identical runs give the same hashes;
     - a save mid-battle round-trips.
   - **Deps:** 5. Q1 must be answered before merge; Q2 before the default is switched.

7. **Pressure Lab `fire_distribution` and tropes**
   - **Type:** task. **Priority:** P3. **Runner:** swarm.
   - **What:**
     - Lab file `data/sim/labs/fire_distribution.json`:
       - scenarios `duel_crossroads` and `hangar_drill`, seeds 1;
       - axes `standard.fire.policy` ["nearest", "prowess"], `standard.pool_defaults.prowess.start_pct` [10, 52, 95], `standard.fire.discipline_pct` [30, 60, 90], `standard.fire.coordination_pct` [30, 70, 100];
       - 2 × 3 × 3 × 3 = 54 settings × 2 scenarios = 108 runs. The 27 `nearest` settings vary only Prowess start, which `nearest` ignores, so they double as a noise check.
     - Features `overkill_pct`, `kills_per_100` and `first_kill_s` in `harness/src/hx/lab.py`.
     - Tropes `pile_on`, `spray` and `volley_wipe` in `data/sim/tropes.json`.
     - A GDD 05 §5.3 "Labs shipped" line.
   - **Acceptance:**
     - `hx sim lab fire_distribution` completes.
     - The table shows a monotonic kills-per-100 across `start_pct` for the prowess settings.
     - Harness pytest passes.
   - **Deps:** 1, 6.

8. **Readability: focus readout, tracers and glossary**
   - **Type:** feature. **Priority:** P4. **Runner:** autopilot.
   - **What:**
     - The inspection window and squad card show "Fire discipline: focus K of N, coordination c%" with terms (`src/presentation/war_room/squad_card.gd`, inspection).
     - Glossary terms Fire discipline, Overkill, Kill priority and Covered.
     - Event text for a first-volley kill.
     - Optional: `battle_fx` tints a tracer into an already-doomed unit (overkill).
   - **Acceptance:** a UI mock PNG via `hx godot mock` shows the readout; tooltip values equal the sim values.
   - **Deps:** 6.

9. **Apply U1-04 GDD text after the owner answers**
   - **Type:** task. **Priority:** P2. **Runner:** autopilot.
   - **What:**
     - Insert §3.1–3.4 into Rules Spec §2.6 and §2.8, Data Model §3.3, Glossary and GDD 05.
     - Renumber U1Q-P1…P6 into U1Qn.
     - Record the answers to Q1–Q9 in the decision log.
   - **Acceptance:** the GDD README index is consistent; `hx find "U1Q-P"` returns nothing.
   - **Deps:** owner answers. It can land before 5 and 6 (the text marks them as proposed).

10. **Spike: volley synchronisation (lockstep vs deterministic stagger)**
    - **Type:** task (spike). **Priority:** P4. **Runner:** autopilot-large.
    - **Why:** the coordination axis only matters under lockstep (Q4).
    - **What:**
      - Add a Lab axis `standard.fire.stagger` that initialises `acc_hit` from the formation slot (for example slot × 0.618 mod 1).
      - Compare readability (tracers) against the size of the coordination effect.
      - Write the result into the bead notes.
    - **Acceptance:** a short findings note with numbers, and a recommendation for Q4.
    - **Deps:** 7.
