# U1 synthesis: the integration plan

Round U1, cross-draft review (2026-11-23). Inputs: `brief.md` (the owner's words) and drafts 01–05. This file is the single plan the orchestrator applies: decision IDs (§1), how the drafts fit together (§2), what to ask the owner (§3), what goes into the GDD and when (§4), which beads to create (§5), and what the drafts got wrong (§6).

Status: review only. Nothing in the GDD, `src/`, `data/`, `tests/` or the tracker was changed.

**In one paragraph:** the five drafts fit together well, with one real disagreement and one shared foundation. The disagreement is the volley phase: 01 wants staggered hit accumulators now, while 04 wants lockstep kept. §2 O5 resolves it: keep lockstep, and ask the owner after a spike. The foundation is a small set of read models that 01, 02, 03 and 04 each want to pull out of `CombatSystem`/`LineOfFire`/the playback re-run on their own. Build those once, first (beads A1, A2 and B7), and the four tracks stop colliding. Six owner questions block beads (§3a). Everything else ships on a recommended default. The first beads to start (§5.9) are C1 (pan, zoom and hover during playback), A1 with A2 (read-model seams), A3 (attack-move closes until the whole squad can fire, the measured 49–77% DPS loss), and B2 then B3 (truth snapshot, then workshop scenarios).

---

## 1 Decision IDs

### 1.1 Owner statements: U1Q1–U1Q27 (settled)

One ID per distinct owner statement in `brief.md`, in brief order. The numbering is chosen so that draft 05's IDs (U1Q20–U1Q27) survive unchanged. The brief's process sentence ("to be picked up by swarm or autopilot", "review delegates to the qwen4 and opus 5.5") is the round's preamble and gets no ID.

| ID | Brief (a few words) | Condensed, for the decision log |
|---|---|---|
| U1Q1 | "unclear whether using attack move, run, or hold affects unit dps" | Whether attack-move, run or hold change damage output is unclear. Anything but walking straight at the enemy seems to lower it sharply. Confirm it. |
| U1Q2 | "Selecting a target and retargeting both seem to diminish damage" | Picking a target and retargeting also seem to lower damage output. Confirm it. |
| U1Q3 | "framework for visually assessing battles at various stages" | A framework for judging battles' visual clarity at several stages is a priority. |
| U1Q4 | "if the local bonsai model can be used for assessing still images" | Use the local Bonsai model to judge stills or short recordings where it can, because there will be a lot of visual work. |
| U1Q5 | "A workshop ... individual components of unit behavior both visually and through api" | A workshop for single components of unit behaviour is wanted, usable both visually and through the API. |
| U1Q6 | "still be able to zoom and move the map" | During execution the player can still zoom and move the map. |
| U1Q7 | "to select squads" | During execution the player can select squads. |
| U1Q8 | "hover-tooltip or right-click comparison ... current and possible interactions" | With one squad selected and another hovered, a tooltip or a right-click comparison menu shows their current and possible interactions (in or out of range, targeting, fleeing), from what is actually going on. |
| U1Q9 | "A start of battle deployment step is still desired" | Battles get a deployment step at the start. |
| U1Q10 | "coherency and collision rules for pathfinding and clustering" | Movement and commands need refining. Flesh out coherency and collision rules for pathfinding and clustering. |
| U1Q11 | "find a position with its remaining movement that it can make attacks from" | An infantry squad on attack-move that sees an enemy it can't yet attack, and has movement left, uses that movement to reach a position it can attack from, like marines on attack-move in StarCraft II. |
| U1Q12 | "Other squads may have other types of default behaviours ... composable" | Other squads may have other default behaviours per command. Build behaviours to be composable where possible. |
| U1Q13 | "nailing the feel here is integral" | Getting U1Q11's feel right comes before building the rest. |
| U1Q14 | "There exists a mathematical optimal distribution of attacks" | For a squad firing at an enemy squad, there is an optimal spread of its attacks that kills the most units. |
| U1Q15 | "Optimal prowess conditions should result in the attacking squad performing this way" | Under optimal Prowess conditions the attacker fires in that optimal way. |
| U1Q16 | "multiple attacks 'overkilling' a single unit, or attacks being too distributed" | The worse arrangements are overkill and fire spread so thin that nothing dies. |
| U1Q17 | "neutral Prowess should generally be attempting to focus their fire on a few units" | At Neutral Prowess a squad focuses on a few units with some fuzz, scaled by its base Prowess: high is better, low is worse. |
| U1Q18 | "surging will overkill less ... fraying will overkill more" | A Surging squad overkills less (it swaps targets faster). A Fraying one overkills more. |
| U1Q19 | "difficult system ... distinct gameplay modes and feels" | Long-term and hard, but worth it for distinct gameplay modes and feel. |
| U1Q20 | "Hex tiles should be much larger ... composable entities" | Hexes are much larger: composable entities that hold and show the feature entities they are made of. |
| U1Q21 | "default method of arranging themselves ... overridden in map creation" | Features have a default arrangement in a hex. Map creation can override it; play cannot. |
| U1Q22 | "If a road is present, sensible offsets" | On a hex with a road, the arrangement keeps its shape, offset out of the road's way by the road's direction. |
| U1Q23 | "Multiple features on a tile should be selectable individually" | Each of several features on a hex is selectable on the map and in the hex's sidebar, and is highlighted in both. |
| U1Q24 | "activated without a commander present ... purchasing items and squads, and updating rally points" | Some owned features can be used without a commander present: buying items and squads, and updating rally points. |
| U1Q25 | "movement speed could come down a bit ... vision could go up a bit" | Overworld movement comes down a bit, caravans especially. Overworld vision goes up a bit. |
| U1Q26 | "Controlled tiles should provide self-vision at least" | Controlled hexes give at least self-vision. Features add more by kind (mine 1, barracks 2, village or caravan 3, more with scouts in a caravan), with sensible configurable defaults per entity. |
| U1Q27 | "a caravan itself should be an entity, and its payload is components" | A caravan is an entity. Its payload is components that systems read to grant behaviours and capabilities. |

**Proposals** keep the label "proposed" and get no ID. An owner answer to a question in §3 is recorded as **U1Q28** onward, in the order answered, with the §3 question label beside it (for example "U1Q28 (OQ-3): deployment shares turn-1 Planning").

### 1.2 Draft-local IDs → final IDs

Rewrite every tag in text inserted from a draft. `hx find "U1Q-P|U1Q[0-9]+[a-d]"` must return nothing in the GDD once the edits are applied.

| Draft | Local tag | Final |
|---|---|---|
| 01 | U1Q1 | U1Q1 (and U1Q2 where it speaks of targeting or retargeting) |
| 01 | U1Q5a | U1Q10 |
| 01 | U1Q5b | U1Q11 |
| 01 | U1Q5c | U1Q12 |
| 01 | U1Q5d | U1Q13 |
| 01 | open questions 1–9 | OQ labels in §3 (01-1 … 01-9) |
| 02 | U1Q2 | U1Q3 (the framework), U1Q4 (Bonsai) |
| 02 | U1Q3 | **U1Q5** (careful: 02's U1Q3 is not 03's U1Q3) |
| 02 | OQ1–OQ10 | 02-OQ1 … 02-OQ10 in §3 |
| 03 | U1Q3a | U1Q6 |
| 03 | U1Q3b | U1Q7 |
| 03 | U1Q3c, U1Q3d | U1Q8 (one statement) |
| 03 | U1Q3 (unsuffixed, for example "(U1Q3)" in the glossary and the war room line) | U1Q6–U1Q8 |
| 03 | U1Q4 | **U1Q9** |
| 03 | Q1–Q11 | 03-Q1 … 03-Q11 in §3 |
| 04 | U1Q-P1 … U1Q-P6 | U1Q14 … U1Q19 |
| 04 | Q1–Q9 | 04-Q1 … 04-Q9 in §3 |
| 05 | U1Q20 … U1Q27 | unchanged |
| 05 | Q1–Q9 | 05-Q1 … 05-Q9 in §3 |

---

## 2 Overlaps and conflicts between drafts

### O1 One battle read model, extracted once, before anyone builds on it
Three drafts each pull a read model out of the same two files:

| Draft | Bead | Wants | From |
|---|---|---|---|
| 01 | B3 | `LineOfFire.shot_share`: per-unit "has a shot", weighted by standing DPS | `line_of_fire.gd`, `movement_system.gd` `_has_shot` |
| 03 | E3 | `CombatSystem.pick_target` (static, pure) | `combat_system.gd` `_engage` |
| 03 | E3 | a per-unit shot-gate summary for the "range" fact | `CombatSystem.shot_gate` |
| 04 | bead 2 | `TargetPolicy`: `_nearest_target` and `_covered` behind an interface | `combat_system.gd` |
| 02 | V2 | the line-of-fire matrix, hold reasons and victims | `LineOfFire`, `BattleActivity` |

**Resolution:** two hash-identical refactor beads come first and run in parallel, since they edit different files:
- **A1:** `combat_system.gd`: static `pick_target` and the `TargetPolicy` seam.
- **A2:** `line_of_fire.gd`: `unit_shot` and `shot_share`.

Then A3 (closing to fire), C3 (`SquadRelation`), B2 (`BattleProbe`) and the D track all *call* these and never re-derive them. 03's E3 loses its extraction step, and 04's bead 2 becomes A1.

### O2 One re-simulation cursor
Three drafts need the state at tick *i* of a turn:
- 02's workshop scene (V7) and capture runner (V8);
- 03's `PlaybackProbe` (E5);
- 02's squad card at a scrubbed tick.

Each proposes a private copy stepped from a snapshot. **Resolution:** one `BattleCursor` in `src/api/battle_cursor.gd` (bead B7): a snapshot plus rules, stepped lazily on a private copy (`IntentForecast._copy` pattern, `rules.forecast_copy()`), restarted on a backward seek, no tick hook. C5, B8 and B9 depend on it. Frame indexes, not playback `t`, so sw-ll4.26.6 doesn't affect it.

### O3 Truth snapshot and pair relations share one fog rule
- 02's `BattleProbe` (a whole-battle snapshot) and 03's `SquadRelation` (pair facts) overlap.
- Both need a fog rule, and both drafts describe the same one: enemy squads are behaviour-only, never hold reasons, orders or reload.

**Resolution:**
- Fog goes through the existing `BattleActivity.squad_seen` and `squad_public`. Neither bead writes new fog code.
- `BattleProbe` ships first (the owner's priority). It gains `SquadRelation` facts per engaged pair in a small follow-up (B15) after C3.

### O4 One scenario format and one place for micro-battles
Four places measure order and targeting behaviour:
- 01 B1: `src/tools/order_dps_lab.gd` plus `tests/sim/test_order_dps.gd`;
- 02 V3/V4: `data/sim/workshop/*.json`, `WorkshopRun` and `tests/sim/test_workshop_scenarios.gd`;
- 04 bead 3: `tests/sim/test_fire_range.gd`;
- 04 bead 7: the Pressure Lab `fire_distribution`.

**Resolution:**
- **Format:** 02's workshop scenario format is the one format.
  - 01 B1 becomes the workshop scenarios in B4: 01's tables A–D, with its ratio pins as `gate` probes on `rules-fixture`.
  - 04 bead 3 becomes the fire-range scenarios in D2 (`victims`, `overkill`, first-kill probes).
  - No `src/tools/order_dps_lab.gd` and no `test_fire_range.gd`: everything gates through `tests/sim/test_workshop_scenarios.gd`.
- **Labs stay separate:** the Pressure Lab (04 bead 7, D6) sweeps ruleset axes over harness runs. That is a different tool and stays.
- **Not blocking the owner's feel priority:** A3 doesn't wait for the workshop. It carries its own GUT test (`tests/sim/test_closing_to_fire.gd`, built like `tests/sim/test_combat_timers.gd`).
  - B4 holds an `attack_move_firing_position` scenario as `pending`, which A3 turns into `gate`.
  - B4 must reproduce 01's table B within 5%, which cross-checks that the runner is faithful.
- **B3's probe kinds:** `duty`, `damage`, `dps` (DPS₁), `victims`, `overkill`, `kills`, `spacing` and `compare` cover 01, 02 and 04. Overkill reads D1's event fields when present, else `hit_trace`.

### O5 Volley phase: 01 and 04 disagree
- **01** (Q3, blocking B5) recommends slot-staggered hit accumulators now, so duels stop being knife-edges.
- **04** (Q4) recommends keeping lockstep: volleys read crisply, and lockstep is what makes the coordination (overkill) axis matter. That is the owner's U1Q18.
- **04's data:** under stagger, `nearest` against `nearest` becomes a coin flip (still a knife-edge), while focus fire wins 7–0 either way.

**Resolution:**
- **Keep lockstep for now.** The knife-edge 01 found comes from nearest-unit pairing in lockstep, and the D track's focus fire breaks it (0–0 becomes 6–0 for the better policy). Staggering now would also weaken the overkill axis the owner asked for.
- **01's other half (no moving volley on arrival) is independent** and ships as A4.
- **A spike decides:** A13 (01 B5 stagger plus 04 bead 10) measures both on workshop scenarios. The owner then answers OQ-1. Only then does A14 (stagger) start, if at all.

### O6 Hold reasons and activities gain values
- A3 adds the activity `CLOSING_IN`, and A7 adds the hold reason "moving to fire".
- Playback frames carry hold reasons and activities as ints, and the squad card, `Glossary.hold_text`, `activity_text`, sw-ll4.27.6's marks, `BattleProbe` and `SquadRelation` read them.

**Resolution:** append new enum values at the end (never renumber). Each bead adds its glossary wording in the same commit.

### O7 Right-click semantics: three drafts touch them
| Context | Right click |
|---|---|
| Battle, Planning | the order button (unchanged) |
| Battle, playback | opens the comparison menu (03) |
| Battle, Planning comparison | GUIDE action `compare_squads`, C / pad (03) |
| Overworld, owned producing site selected | sets its rally point (05 §4.8) |

No conflict, but these are four contexts. **Resolution:** C7 and E6b each add their line to Controls help and to GDD 04 §4.8 in one place (the "What does what" bullet).

### O8 Separation reopens a settled v1 exclusion
- O1Q8 (settled) says "no unit collision ... in v1". 02 §2.14 says the same.
- U1Q10 asks for collision and coherency rules, and 01 proposes separation without body blocking.

**Resolution:** the U1Q10 statement allows the proposal. But the O1Q8 text stays until A11 lands; the proposal goes in beside it, labelled. 01's "Coherency radius" also contradicts §2.14 "There is no separate leash distance". A12b edits that line when it lands, not before.

### O9 Docs beads: five become one
Each draft has its own "apply the GDD text" bead: 01 B12, 02 V14, 03 E0, 04 bead 9 and 05 B12. **Resolution:**
- **Now:** the orchestrator applies the "now" items of §4 itself, in this integration.
- **Per feature:** each feature bead turns its own "proposed" lines into "in play".
- **One gated bead:** X1 records the owner's answers in the decision log and settles the remaining text.

### O10 Balance-changing beads move the harness baselines
These change simulated outcomes:
- A3, A4 and A8;
- D3 and D7;
- E1 (overworld numbers);
- E2, through caravan sight.

The AI issues `attack_move` for almost everything (`src/api/utility_battle.gd:105,123`, `zone_controller.gd:60`, `guard_controller.gd:42`), so A3 shifts every AI battle.

**Resolution:** each of these beads records before and after (`hx sim run duel_crossroads --seeds 3`, or `skirmish_mirror` for the overworld) and adds a `data/sim/BASELINE.md` era line. Don't merge them while an AI factory run is in progress (`hx factory status`).

### O11 Glossary edits break a test unless the data moves with them
- `tests/presentation/test_glossary.gd::test_every_gdd_term_is_data` requires every `- **Term**:` line in GDD 07 to exist in `data/packages/core/defs/glossary.json`, and the reverse.
- Drafts 01 §3.6, 03 §3.7 and 05 B12 add GDD terms without the data.

**Resolution:**
- **Now:** proposed terms go into GDD 07 as a table under "Proposed terms (Round U1)". A table doesn't match the test's regex.
- **Later:** each feature bead moves its terms into the list *and* `glossary.json` together (§4.5 names which bead).

### O12 GDD sections edited by more than one draft
| Section | Drafts | Resolution |
|---|---|---|
| 02 §2.6 "Other combat rules" | 01 (Attack orders bullet), 03 ("Shown" bullet) | Adjacent bullets with no textual overlap. Apply 03's "Shown" now. Keep the in-play Attack orders text and append a pointer to §2.15. Replace it when A3 lands. |
| 02 §2.6 (new subsections) | 04 "Fire distribution" after "Damage and defence order"; 01 §2.15 "Target choice" | 01's "Target choice" line points to §2.6 Fire distribution. 04's text must say `nearest` is what's in play today (see §4.1). |
| 02 §2.8 | 04 (Prowess), 01 B6 (Instinct sinks) | Different subsections. Instinct changes only when A8 lands. |
| 02 §2.2 Turn sequence | 03 only (steps 1, 3, 4) | — |
| 02 §2.14 / new §2.15 | 01 only | §2.15 is free (§2.14 is the last section). |
| 03 §3.3 Squad table | 01 (Formation Profile, Behaviours), 04 (Fire discipline) | Separate rows. |
| 03 §3.5 | 03 (Scenario deployment), 05 (hex feature, band, map template, hex layout) | Different bullets. |
| 04 §4.4 Game API | 03 (relations, deployment), 05 (owner actions, features, bands) | Battle vs overworld bullets. |
| 04 §4.8 | 03 (playback line fixes), 05 (hex view block) | Different bullets. |
| 04 §4.9 | 02 (workshop bullet), 05 (World maps layout) | Different bullets. |
| 05 Harness | 02 (§5.5 amend, new §5.6, §5.7), 04 (§5.2 metrics, §5.3 lab) | No numbering clash. §5.6 and §5.7 are new, after §5.5 (the last). |
| 07 Glossary | 01, 03, 04, 05 | O11. |

### O13 Files touched by several beads: a safe order
The swarm and the autopilot skip a bead whose named paths overlap a busy worker's (`swarm.bead_paths`, regex `(src|harness|data|tests|addons|docs)/…`). That protects against *concurrent* edits only when bead text names its files, so **every bead must name its files by full path**. Logical order is enforced with `bd` deps:

| File | Order (deps) |
|---|---|
| `src/sim/battle/combat_system.gd` | A1 → A4 → A8 → D3 → D4 → D5 → A14. C3 and B2 only read it. |
| `src/sim/battle/line_of_fire.gd` | A2, then read-only (A3, C3, B2) |
| `src/sim/battle/movement_system.gd` | A3 → A7 → A9b → A11 → A12a → A12b → A12c |
| `src/sim/battle/battle_activity.gd` | A3 → A7 (append enum values) |
| `src/sim/battle/battle_setup.gd` | C9 and A14 (never in parallel) |
| `src/sim/battle/effects.gd` | A5 |
| `src/sim/battle/health_system.gd`, `src/api/sim_metrics.gd` | D1 |
| `src/presentation/war_room/war_room.gd` | C1 → C2 → C6b → C7 → C11. sw-ll4.26.6 never in parallel with C1 or C2. |
| `src/presentation/war_room/context_view.gd` | C1 (and sw-ll4.26.6) → C2 → C6b → C11 → E5 → E6b. B6 needs a public camera-transform getter: add it in B6 and nothing else. |
| `src/presentation/contexts/view_contexts.gd` | E5 (zoom constants) → E6b (`selected_feature`) |
| `src/presentation/war_room/squad_card.gd` | sw-ll4.27.7 → D8. C7 only calls `SquadCard.build`. |
| `src/presentation/war_room/command_panel.gd` | E6b → E9 |
| `src/api/overworld_session.gd` | C4/C5 and C10 (battle side) and E2/E6a/E8 (overworld side): C10 and E8 both add logged input kinds, so serialize them |
| `src/api/battle_session.gd` | C4 → C9 → C10 |
| `src/sim/data/data_schema.gd` | A9a, D4, D5, E2, E3, E4, E7, E8, C14: serialize, one schema bead at a time |
| `data/packages/core/defs/*.json` | A8, A10, D4–D5, E1–E4, E8: small, serial merges are fine |
| `harness/config/providers.toml` | B1 only (a protected file, §5.1) |

**Side effect to know about:** if every U1 bead names `docs/design/u1/…`, they all "overlap" through that path, so a swarm worker and the autopilot never run U1 beads at the same time. That is acceptable while the swarm runs (its `end_at` is 2026-11-24 13:00 UTC). To keep the parallelism, refer to "U1 draft 0N §x" without the path.

### O14 A design-script hazard in the Godot project
- `docs/design/u1/scripts/dps/dps_orders.gd` and `scripts/prowess/fire_policy_exp.gd` were committed (b27a920) inside the Godot project: `docs/` has no `.gdignore`.
- `fire_policy_exp.gd` subclasses `CombatSystem` and overrides `_nearest_target` with typed accesses (`state.units.defense`, `r.df_resist`).
- If A1 or D3 changes those signatures, the import pass in `hx godot check` can start reporting script errors from `docs/`, which would fail every runner's merge gate.

**Resolution (integration step, before any U1 code bead):** add an empty `docs/.gdignore`. Nothing under `src/`, `tests/` or `addons/` loads `res://docs`. To rerun a script, copy it to `.godot/u1/` (gitignored), as draft 01 did.

### O15 sw-ll4.27.6 is closed but its feature was never built
- Draft 03 makes E1 and E6 depend on sw-ll4.27.6's "mark at point → tooltip key" lookup.
- The bead was closed at 12:03Z ("merged to main by hx swarm merge"). But its branch held one commit, `00ba3e5 WIP: worker turn ended (rc=-9)`: ten lines of plumbing in `_battle_squads` (`holds`, `reload`, `cooldown`, `own`).
- No hoverable marks, mark lookup or mark tooltips exist (`hx find "tooltip" src/presentation/war_room/context_view.gd` finds nothing).

**Resolution:**
- **Reopen sw-ll4.27.6:** its notes are still the right spec. Note "merged WIP only; hover marks not built".
- **C1** doesn't depend on it.
- **C6b** (the relation tooltip) does, and must reuse its lookup.

---

## 3 Consolidated owner questions

### 3a Blocking: answer before the named beads can start
Each has a decision bead labelled `needs-human` (§5.1). The gated beads depend on it.

| OQ | Question | Recommended default | Blocks | Source |
|---|---|---|---|---|
| **OQ-1** | **Volley phase:** keep lockstep volleys (every unit's hit accumulator starts at 0, so identical units hit on the same ticks), or stagger them by formation slot? | **Keep lockstep for now.** Decide after spike A13 shows both, with focus fire in place. *I disagree with 01's "stagger now": it weakens the overkill axis U1Q18 asks for, and 04 shows stagger alone leaves duels a coin flip.* | A14 | 01-3, 04-Q4 |
| **OQ-2** | **Attack-move feel (U1Q11, U1Q13):** the squad anchor advances until units carrying 100% of its standing DPS each have a shot, then each unit may step up to 3 m off its slot to gain range or a line (01). Or true per-unit stopping, StarCraft II style, where units leave formation into an arc (the Qwen review's view)? | **01's model:** anchor quorum (100% standing DPS) plus a 3 m step-out, with a 15 m leash past an attack-move point. You judge the feel in the workshop scene (B8) once A3 lands. A3 itself proceeds on either answer. | A7, A9a, A9b | 01 §3.2, `qwen/review-01` §6 |
| **OQ-3** | **Deployment model (U1Q9):** deploy in the same Planning that drafts battle turn 1 (no extra pulse), hidden and simultaneous? Turn-1 orders then can't target enemy squads (none are visible). Placements go anywhere in the side's area, and every side's area is shown. | **Yes** (Steel Division's phase 0). A separate deployment pulse can become a clock option later. | C9 → C10–C15 | 03-Q1, 03-Q2 |
| **OQ-4** | **sw-tdz placed squads:** accept that bead's six suggested answers, plus "placed entries are deployment defaults; `locked: true` pins them"? | **Yes to all.** | C14, sw-tdz | 03-Q7 |
| **OQ-5** | **Overworld camera during playback:** R3Q2 says watching execution "locks out overworld view/interaction". U1Q6 says "move the map". May the overworld camera pan and zoom while a turn plays (no selection, no orders)? | **Allow the camera only.** This amends R3Q2, so it is yours to say. Battle playback (C1) is unaffected. | C8 | 03-Q3 |
| **OQ-6** | **Switch the default fire policy** from `nearest` to `prowess`? It is a global balance change: Neutral becomes deadlier (mirror duel 0–0 becomes 3–4 survivors). | **Accept after the Pressure Lab sweep (D6),** in one commit with a new baseline era. Late: nothing before D7 waits on it. | D7 | 04-Q2 |

### 3b Non-blocking: apply the default and record it
Recorded in the decision log's "Proposed (Round U1, awaiting review)" list, and in X1's notes once confirmed. "Agree" means I endorse the draft's default.

| Label | Question (short) | Default applied | Verdict |
|---|---|---|---|
| 01-1 | Fire quorum: count units or standing DPS? | Standing DPS, 100% for infantry, as data | Agree. A3 must add an infeasible-quorum fallback and hysteresis (§5.4). |
| 01-2 | Attack-move leash past its point | 15 m, as data. Attack has none. Hold never moves. | Agree |
| 01-3b | Skip the moving volley on arrival under attack orders | Yes (A4) | Agree. Split from 01-3, which is now OQ-1. |
| 01-4 | Does Move keep firing on the move? | Keep it, and make the trade-off visible in the tooltip | Agree |
| 01-5 | Moving-fire Instinct sink per squad per second instead of per unit volley | Yes, `instinct_fire_moving_per_s` = 2 (A8) | Agree. It is a balance change, so A8 records a baseline era. |
| 01-6 | Body blocking, or separation only? | Separation only. Blocking later. | Agree |
| 01-7 | Cover-seeking behaviour now? | Later, off by default, shown in the forecast | Agree |
| 01-8 | Which unit each shooter picks | Owned by the D track | Agree |
| 01-9 | Hold allows step-out? | No | Agree |
| 02-OQ1 | Bonsai vision doesn't fit free VRAM | (a) a 16k context and the projector on the CPU, with Haiku sampling as the automatic fallback | Agree. B1 measures it. |
| 02-OQ2 | Game screenshots to free cloud tiers that train on data? | No: Bonsai and the Claude subscription only | Agree. It is the conservative default, so it needs no wait. |
| 02-OQ3 | Workshop scenarios in `data/sim/workshop/`: gated ones on `rules-fixture`, feel ones on `core` | Yes | Agree |
| 02-OQ4 | May agents write `pending` scenarios from the brief as the spec you review? | Yes | Agree, but *not blocking* as 02 says: a pending scenario never fails the suite. |
| 02-OQ5 | Golden images committed or local? | Local, git-ignored | Agree |
| 02-OQ6 | May visual reports file beads? | At most 3 a run, labelled `visual`, deduplicated | Agree |
| 02-OQ7 | Debug overlays as a war-room developer toggle? | Later | Agree |
| 02-OQ8 | Frame strips instead of native video | Yes | Agree |
| 02-OQ9 | Verb names | Top-level `hx visual` and `hx workshop` | Agree |
| 02-OQ10 | Stages: deploy, first contact, first blood, mid-fight, rout, end | As listed | Agree |
| 03-Q2 | Enemy deployment areas shown | Yes | Agree (folded into OQ-3) |
| 03-Q4 | How the comparison menu opens | Right click in playback; GUIDE `compare_squads` (C, pad hold-inspect) in every phase | Agree |
| 03-Q5 | May enemy facts use its public weapon range? | Yes, as the range ring already does | Agree |
| 03-Q6 | "Under fire" recency window | 1 s of ticks, as data | Agree |
| 03-Q8 | Placement facing; formation | Any angle in the sim, snapped to 8 in the UI. Formation later. | Agree |
| 03-Q9 | Story / Angelfall battles | `fixed` (no deployment) until the tutorial teaches it | Agree |
| 03-Q10 | Ambush and vanguard deployment | Later | Agree |
| 03-Q11 | Deployment time bonus | 15 s casual, 10 s ranked | Agree |
| 04-Q1 | Is fire distribution in scope for Prowess? | Yes | *Disagree that it blocks:* the brief settles it (U1Q15, "SIMPL idea for Prowess"). Only the definition wording changes. |
| 04-Q3 | Who chooses which way low Prowess fails? | Per squad: two stats, discipline and coordination | Agree |
| 04-Q5 | May the policy read visible units' exact HP and Defensive Profile? | Yes; never the hidden accumulators | Agree |
| 04-Q6 | Coordination across squads | Later (a commander or Prowess hook) | Agree |
| 04-Q7 | Do efficient fire or kills float Prowess? | No. Retune `steady_aim` after the Lab. | Agree |
| 04-Q8 | A re-acquire delay as a third lever | No | Agree |
| 04-Q9 | Unit-level fire orders | No | Agree |
| 05-Q1 | "Much larger": on screen, or world scale? | On screen only (64 px). Revisit after a playtest. | Agree, with a note: "composable entities that hold … features" suggests more sites per hex. Revisit map sizes after E5. |
| 05-Q2 | Remote buy cost | +25% (`remote_markup`, data; 0 disables it), resolved the same turn | Agree, weakly. The brief names no cost; the markup is a proposal. |
| 05-Q3 | Hire as an owner action | No | Agree |
| 05-Q4 | Garrison refit as an owner action | No, for now | Agree |
| 05-Q5 | Production on an engaged hex | It pauses, progress held (E11) | Agree. It is a bug today. |
| 05-Q6 | Scouts raising a commander's sight | Not yet (data-ready) | Agree |
| 05-Q7 | Does a halted caravan stay a caravan? | Yes | Agree |
| 05-Q8 | "Convoy" or "caravan" | "Caravan" in the UI and glossary, "convoy" as an alias | Agree |
| 05-Q9 | Is the tuning too much vision for small maps? | Ship it and measure on `skirmish_mirror` | Agree. 05 said `duel_crossroads`, which is a battle scenario (§6). |

---

## 4 GDD edit plan

Modes:
- **NOW-P:** apply now, labelled **"Proposed (Round U1, awaiting review)"**. Rewrite tags per §1.2.
- **NOW-S:** apply now, as settled: an owner statement U1Qn, or a factual correction.
- **BEAD:** lands with the named bead.
- **ANS:** after the owner answers the named OQ.

Rules:
- A NOW pass never deletes or rewrites settled or in-play text: proposals go beside it.
- Text from a draft is inserted as written, with the §1.2 tag rewrite and the changes noted here.

### 4.1 `02 Rules Spec.md`
1. **§2.2 step 4 (Execute):** NOW-P. Insert 03 §3.1's two sub-bullets under the existing step-4 line, which stays unchanged.
   - Drop "with every input" from the overworld clause.
   - "Watching a battle" is (U1Q6, U1Q7), and "What a squad is doing about another" is (U1Q8).
2. **§2.2 step 1 (Planning):** append 03 §3.4's Deployment bullet. ANS OQ-3.
3. **§2.2 step 3 (Reveal):** append 03 §3.4's "Order at Reveal". ANS OQ-3.
4. **§2.4, new "### Deployment (U1Q9)" after "Start and duration":**
   - NOW-S: the first sentence only ("A battle starts with a deployment step … (U1Q9)"), plus "How it works is proposed; see the U1 synthesis OQ-3".
   - ANS OQ-3: the rest of 03 §3.3, and the Reinforcements and Joining-late sentence edits.
5. **§2.6, new "### Fire distribution (U1Q14, U1Q16)" after "Damage and defence order":** NOW-P, 04 §3.1.
   - Add as its first bullet: "**In play:** each unit fires at the nearest unit it can hit, skipping units its squad's queued damage this tick already covers (`nearest`). Kill priority below is proposed."
6. **§2.6 Other combat rules, Attack orders bullet:**
   - NOW-P: append "Proposed (U1Q11): closing to fire, §2.15."
   - BEAD A3: replace the bullet with 01 §3.1.
7. **§2.6 Other combat rules, Shown bullet:** NOW-P.
   - Keep the in-play sentence and add "(U1Q8; proposed for playback)".
   - Add 03 §3.2's "Pair relations", "Same rules, not a copy" and "Fog" sub-bullets.
8. **§2.8 Prowess:**
   - NOW-S: the definition line becomes 04's ("…beyond raw numbers, including how well it distributes its fire"), tagged (U1Q15).
   - NOW-P: the "Fire discipline" bullet, tagged (U1Q15, U1Q17, U1Q18), and "Not a float".
   - BEAD D5: remove "proposed" from what D5 builds.
9. **§2.8 Instinct, Sinks:** BEAD A8 ("shooting on the move: per squad per second while any unit fires on the move").
10. **§2.9 Map and features:** NOW-P. Insert 05's three bullets: "Hexes are places made of features" (U1Q20), "Arrangement" (U1Q21, U1Q22), "Selecting a feature" (U1Q23).
11. **§2.9 Interaction timing, "Stable outcomes" line:** NOW-S. Replace it with 05's text, tagged (U1Q24). U1Q24 settles it, and the code already allows rally points from anywhere.
12. **§2.9 Turn order and "Owner actions":**
    - NOW-P: insert the "Owner actions" bullet group.
    - BEAD E8: change the Turn order line ("… activities, then owner actions, then production").
13. **§2.9 Production:** BEAD E11 (the engaged-hex pause sentence).
14. **§2.9 Convoy movement:**
    - NOW-P: insert 05's "Caravans" block beside the current bullet.
    - BEAD E2: replace the old bullet.
15. **§2.9 Sight sources:**
    - NOW-S: "A source always sees its own hex, so every controlled hex gives at least self-vision (U1Q26)". It is true today.
    - BEAD E1: the per-kind defaults list.
16. **§2.9 Guards and movement, Speeds line:** BEAD E1.
17. **§2.14, new "### Separation and coherency (U1Q10)" after "Unit movement":**
    - NOW-P: 01 §3.3.
    - BEAD A11 / A12b: edit "What v1 leaves out → Collision" and "Unit movement → Coherency" (O8).
18. **New "## 2.15 Orders and squad behaviours (U1Q1, U1Q2, U1Q10–U1Q13)" after §2.14:** NOW-P, 01 §3.2, with three changes:
    - **Volley phase:** leave out the subsection; add one line, "Volley phase: open question (synthesis OQ-1)".
    - **Target choice:** points to §2.6 Fire distribution.
    - **Measurements:** the "Status" line cites the B4 workshop scenarios once they exist.

### 4.2 `03 Data Model.md`
1. **§3.3 Squad table:** NOW-P. Extend Formation Profile (coherency radius) and add the Behaviours row (01 §3.4). Add the Fire discipline row (04 §3.3).
2. **§3.4, Behaviour template kind (01 §3.5):** NOW-P.
3. **§3.4 or the ruleset bullet, `fire` block (04 §3.3):** NOW-P, stating that the policy is `nearest` today.
4. **§3.5 Scenario, Deployment (03 §3.5):** ANS OQ-3 and OQ-4.
5. **§3.5 Hex feature fields:** NOW-P. Add 05's drawing-only fields, owner actions and the `sight` note.
6. **§3.5 Band kind and Overworld contributions:** NOW-P.
7. **§3.5 Map template:**
   - NOW-P: "Site placement" (`at`).
   - BEAD E2: the "Bands" replacement of "Detachments".
8. **§3.5 Hex layout table (`data/ui/hex_layout.json`):** NOW-P.

### 4.3 `04 Systems Architecture.md`
1. **§4.2, "Relationships and derived stats" (05):** NOW-P.
2. **§4.4 Game API:**
   - NOW-P: Relations (03 §3.6) and the overworld Owner actions, Features and Bands bullets (05).
   - ANS OQ-3: Deployment.
3. **§4.8 Turn playback:** NOW-S (factual).
   - "Space or a click skips it" becomes "Space or Esc skips it; a click inspects the squad under it (sw-ll4.27.4)".
   - In **Not built**, "panning and zooming inside a battle" becomes "mouse panning, zooming and hovering during playback (U1Q6–U1Q8; planning has them)".
4. **§4.8, "Hex view (U1Q20–U1Q23)" block (05):** NOW-P. Its zoom numbers clash with "zooming in to 3x on the overworld enters the battle"; keep that line until E5.
5. **§4.9:** NOW-P. Add the Behaviour workshop bullet (02 §3.2) and the World maps Layout bullet (05).
6. **§4.11:** BEAD. Each feature bead adds its row.

### 4.4 `05 Harness and AI Factory.md`
1. **§5.5 Testing framework, "Feel testing" bullet:** NOW-P. Append "supported by the behaviour workshop (§5.6/§5.7)". A1Q11 stands.
2. **New §5.6 Visual assessment (U1Q3, U1Q4) and §5.7 Behaviour workshop (U1Q5):** NOW-P, 02 §3.1.
   - The §5.7 scenario list names the `victims` and `overkill` probes D2 needs.
   - §5.6's "Not built" line stays until B11.
3. **§5.2 `fire.*` metrics:** BEAD D1.
4. **§5.3 `fire_distribution` lab and tropes:** BEAD D6.

### 4.5 `07 Glossary.md`
- **NOW-P:** one table, "Proposed terms (Round U1, awaiting review)": term, one-line definition, decision ID and owning bead. Not `- **Term**:` lines (O11).

| Term | Moves into the list and `glossary.json` with |
|---|---|
| Fire quorum, Closing to fire | A3 |
| Step out | A7 |
| Behaviour (squad) | A9a |
| Separation, Coherency radius | A11, A12b |
| Relation | C6b |
| Deployment, Deployment area | C11 |
| Fire discipline, Kill priority, Overkill, Covered; the amended Prowess text | D5 |
| Band; Caravan, as the name of the existing `term_detachment_convoy`, with "convoy" as an alias | E2 |
| Owner action | E8 |

### 4.6 `README.md` (GDD)
- **NOW-S:** after the "Ownership review" paragraph, add a short "**Round U1 (2026-11-23)**" paragraph:
  - the owner's brief settled U1Q1–U1Q27 (battle orders and behaviour, battle clarity tooling, execution clarity and deployment, Prowess fire distribution, overworld hexes, features and vision);
  - the proposals are labelled in 02–05 and listed in the decision log;
  - the drafts and this plan are in `docs/design/u1/`.

### 4.7 `Interview/decision-log.md`
- **NOW-S:** append "## Round U1: owner brief (2026-11-23)":
  - the preamble line;
  - "### Settled (Round U1)": U1Q1–U1Q27, from the §1.1 "condensed" column;
  - "### Proposed (Round U1, awaiting review)", with no IDs: the major proposals (closing to fire; separation and coherency; the behaviour vocabulary; visual assessment and the workshop; pair relations and playback relations; the deployment model; fire distribution via discipline and coordination; hex composition and layout; owner actions; bands and caravans; the tuning numbers), and the open questions OQ-1 to OQ-6 by label.
- **ANS:** each answer becomes U1Q28 and onward (X1).

### 4.8 Outside the GDD
- **`harness/README.md` verb rows and the Benchmark suite note (02 §3.3):** BEAD B5 (`workshop`), B11 (`visual`), B10 (vision suite). Don't document verbs before they exist.
- **The `bonsai start --vision` row and `harness/DESIGN.md` §7/§8 (02 §3.4):** BEAD B1, and only on a "go".
- **`AGENTS.md` §7 rows (02 §3.5):** with B5 and B11, as two table rows. Not on the ask-first list, but tell the owner.

---

## 5 Final bead plan

### 5.1 Labels, runners and gating (what the code actually does)
- **The pool:** both runners take from the same `bd ready` pool. "Runner" in a draft is advisory: the swarm's auto-refill and the autopilot both pick by priority, then bugs, then age.
- **Labels each runner skips** (`harness/swarm/swarm.toml` `refill_exclude_labels`; `harness/config/autopilot.toml` `[beads] exclude_labels`):

  | Label | Swarm skips | Autopilot skips |
  |---|---|---|
  | `needs-human` | yes | yes |
  | `swarm-harness` | yes | yes |
  | `autopilot-failed`, `autopilot-blocked`, `autopilot-partial` | no | yes |

  Both also skip epics, parents with open children, children of `sw-p2q`, and titles that start "Design interview".
- **Owner-gated beads:** create one **decision bead** per blocking question:
  - title "U1 decision OQ-n: …", type task, label **`needs-human`**;
  - add `bd dep add <gated> <decision>` for every bead it gates.
  - Gated beads then never appear in `bd ready`, so neither runner can pick them, and they become ready by themselves when the decision bead is closed with the answer.
  - Don't put `needs-human` on the gated beads themselves: someone would have to remember to remove it.
- **`autopilot-large`:** label **`large`**. The autopilot runs those on Opus (`[claude.large] labels`). Descriptions of 2,000 characters or more also go to Opus. So keep Haiku beads' descriptions short and point to "U1 draft 0N §x" rather than pasting.
- **Keeping the swarm off Opus-sized beads:** no label does this today. `swarm-harness` also blocks the autopilot. Recommend adding `no-swarm` to `harness/swarm/swarm.toml` `refill_exclude_labels` (a config edit, not a budget) and labelling every `large` bead `no-swarm`. It is low urgency: the swarm run's `end_at` is 2026-11-24 13:00 UTC, after which everything goes to the autopilot anyway.
- **B1:** it edits the protected `harness/config/providers.toml`. Label it `swarm-harness` (which also stops the autopilot) and run it on purpose: `hx autopilot run --once --bead <id>` (an explicit `--bead` skips the pick filter), or in an interactive session.
- **All U1 beads:** label `u1` plus the area (`u1-orders`, `u1-tooling`, `u1-clarity`, `u1-prowess`, `u1-overworld`).

Epics: **U1-A** Battle orders & behaviour; **U1-B** Battle clarity tooling (visual assessment + workshop); **U1-C** Execution clarity & deployment; **U1-D** Prowess fire distribution; **U1-E** Overworld hexes, features & vision; and **U1-X** (docs plus the six decision beads). Close **sw-o1m** (every child is closed); U1-E is its successor.

Columns below: ID (this plan's), source (draft bead), title, type, P, runner, deps (U1 IDs, existing beads, decision beads).

### 5.2 Integration steps (the orchestrator, now, not beads)
1. Add `docs/.gdignore` (O14).
2. Apply the NOW-P and NOW-S items of §4.
3. Reopen **sw-ll4.27.6** with the note "merged WIP only (00ba3e5); hover marks, mark lookup and tooltips not built" (O15).
4. Create the epics, the decision beads and the beads below.

### 5.3 U1-X: docs and decisions
| ID | Source | Title | Type | P | Runner | Deps |
|---|---|---|---|---|---|---|
| X-OQ1 … X-OQ6 | §3a | U1 decision OQ-n: … (one each) | task | P1 | — (`needs-human`) | — |
| X1 | 01 B12, 02 V14, 03 E0, 04 b9, 05 B12 | Record the U1 owner answers (U1Q28+) and settle the GDD text they decide | task | P2 | autopilot | the decision beads answered so far. Run once per batch of answers. |

### 5.4 U1-A: Battle orders & behaviour (draft 01)
| ID | Source | Title | Type | P | Runner | Deps |
|---|---|---|---|---|---|---|
| A1 | 03 E3 (extraction), 04 b2 | CombatSystem seams: static `pick_target` and `TargetPolicy` (hash-identical) | task | P1 | autopilot | — |
| A2 | 01 B3 (part), 03 E3 (part) | LineOfFire per-unit shot read model: `unit_shot`, `shot_share` (hash-identical) | task | P1 | autopilot | — |
| A3 | 01 B3 | Closing to fire: attack orders close until the fire quorum has a shot | feature | P1 | autopilot-large | A2 |
| A4 | 01 B5 (half) | No moving volley on arrival under attack orders | feature | P2 | autopilot | A3, A1 |
| A5 | 01 B7 | Retarget reaction keeps the run flag | bug | P3 | swarm | — |
| A6 | 01 B2 | Spike: movement and LoF cost per tick, separation prototype | spike | P2 | autopilot-large | — |
| A7 | 01 B4 | Step-out: per-unit firing step once the anchor stands | feature | P2 | autopilot-large | A3, A6, X-OQ2 |
| A8 | 01 B6 | Moving-fire Instinct sink per squad per second | task | P3 | autopilot | A4 |
| A9a | 01 B8 (split) | Behaviour vocabulary: schema, validation, compile to `bh_*` (hash-identical) | feature | P2 | autopilot-large | A3, X-OQ2 |
| A9b | 01 B8 (split) | Movement reads behaviour parameters instead of constants (hash-identical) | feature | P2 | autopilot-large | A9a, A7 |
| A10 | 01 B9 | Archetype behaviours as data: mortar stand-off, assault quorum, marksman max range | feature | P2 | autopilot | A9b, B4 |
| A11 | 01 B10 | Unit separation between squads | feature | P2 | autopilot-large | A6 (go), A3 |
| A12a | 01 B11 (split) | Friendly destination de-duplication (ring placement) | feature | P3 | autopilot | A11 |
| A12b | 01 B11 (split) | Coherency radius and anchor slow-down | feature | P3 | autopilot | A12a |
| A12c | 01 B11 (split) | Order clusters: a shared route plan for multi-select orders | feature | P3 | autopilot-large | A12b |
| A13 | 01 B5 (stagger), 04 b10 | Spike: volley phase, lockstep against slot stagger, on workshop scenarios | spike | P3 | autopilot-large | B3, D1, D4 |
| A14 | 01 B5 (stagger) | Slot-staggered hit accumulators (only if OQ-1 says stagger) | feature | P3 | autopilot-large | A13, X-OQ1 |

Sharpening:
- **A1:**
  - In `src/sim/battle/combat_system.gd`: `static func pick_target(state, row) -> int` holds `_engage`'s choice, and `_engage` calls it.
  - New `src/sim/battle/target_policy.gd`: static `pick(...)` and `covered(...)`, with `_nearest_target` and `_covered` moved there unchanged; `_fire_squad` calls them at both sites. No ruleset field yet; D4 adds `fire.policy`.
  - **Acceptance:** `tests/sim/test_determinism.gd` is unchanged. `hx sim run duel_crossroads --seeds 3` hashes equal main's. A new `tests/sim/test_target_policy.gd` checks that `pick_target` equals the `engaged` that `_engage` sets the next tick, on a three-squad fixture.
- **A2:**
  - `LineOfFire.unit_shot(state, urow, trow) -> int` gives `SHOT`, `BLOCKED`, `OUT_OF_RANGE` or `MIN_RANGE`. It runs `CombatSystem.shot_gate` against the target squad's living units the side sees.
  - `shot_share(state, row, trow) -> int` is the permille of the squad's standing DPS whose units have a shot. It returns 0 with no armed unit, never dividing by zero.
  - No caller changes.
  - **Files:** `src/sim/battle/line_of_fire.gd`, `tests/sim/test_line_of_fire.gd`.
- **A3:** 01 B3, plus what the Qwen review found missing:
  - **Infeasible quorum:** the quorum counts only units that can get a shot at a stand-off of at least every waiting unit's `min_range` + 2 m. With none, it stops at the best achievable share.
  - **Hysteresis:** stop at ≥ quorum; resume only below quorum − 10% for ≥ 1 s.
  - **Fog:** only enemy units the side sees.
  - **Cost:** movement plus combat time on `duel_crossroads` within +10% (`PerfRecorder`).
  - **Activity:** append `BattleActivity` `CLOSING_IN` and its glossary wording.
  - **Test:** `tests/sim/test_closing_to_fire.gd` with 01 table B's squads. Assault Attack-move DPS₁ ≥ 0.9 × Hold-at-12 m, heavy weapons ≥ 0.85×, rifle and mortar within 3% of before, mortar never inside 20 m.
  - **Baseline:** a `data/sim/BASELINE.md` era line (O10).
  - **GDD:** 02 §2.6 Attack orders, per §4.1 item 6.
- **A5:** only the `"attack"` branch of `_order` in `src/sim/battle/effects.gd` passes the squad's current `run`. "Hold" stays 0 and fall-back stays 1. Add a test in `tests/sim/test_abilities.gd`: a running squad that retargets has `squads.run[row] == 1` on the next tick.
- **A7:** acceptance is R8b (attack-move, 45° off) after the change against R8b before it. Not against R8 (Hold, a different scenario). No unit more than 3 m from its slot.
- **A8:** a new ruleset key `instinct_fire_moving_per_s` in `data/packages/core/defs/ruleset.json` and `tests/fixtures/rules/`. Acceptance: Instinct stays at or above the Fraying band's lower bound after 10 s of moving fire by 8 units.
- **A10:** pin per-template absolute DPS₁ in workshop gate probes, not "≥ 0.85 × the best order".
- **A11:** assert the minimum distance per size class (0.4, 0.6 and 1.2 m), not 1 m. Add the `separation_clump` workshop scenario (02 V4).

### 5.5 U1-B: Battle clarity tooling (draft 02)
| ID | Source | Title | Type | P | Runner | Deps |
|---|---|---|---|---|---|---|
| B1 | V1 | Spike: Bonsai vision on battle stills (VRAM, latency, accuracy) | spike | P1 | autopilot-large, **`swarm-harness`**, run with `--bead` | — (cites sw-68h, sw-hbz) |
| B2 | V2 | BattleProbe: one read-only truth snapshot | feature | P1 | autopilot | — |
| B3 | V3 | Workshop scenario format, headless runner, test gate | feature | P1 | autopilot-large | B2 |
| B4 | V4 + 01 B1 | Workshop scenarios for orders and DPS (01's tables A–D; `attack_move_firing_position` pending) | task | P1 | autopilot | B3 |
| B5 | V5 | `hx workshop` verb | task | P2 | swarm | B3 |
| B6 | V6 | Debug frames and overlay layer | feature | P2 | autopilot-large | B3 |
| B7 | 03 E5 (part), 02 V7/V8 (part) | BattleCursor: lazy re-simulation of a battle turn to tick N on a private copy | feature | P1 | autopilot-large | — |
| B8 | V7 | Behaviour workshop F6 scene | feature | P2 | autopilot-large | B6, B7 |
| B9 | V8 | Capture runner: stills and frame strips with truth | feature | P2 | autopilot-large | B2, B6, B7 |
| B10 | V9 | Vision bench suite | task | P2 | autopilot | B1, B9 |
| B11 | V10 | `hx visual capture \| ask \| report` | feature | P2 | autopilot | B9, B10 |
| B12 | V11 | Layout lint (model-free clarity checks) | task | P3 | autopilot | B9 |
| B13 | V12 | Golden-image diff | task | P3 | autopilot (was swarm: "perceptual" is underspecified) | B9 |
| B14 | V13 | Visual proposals and the scheduled sweep | task | P3 | autopilot | B11 |
| B15 | new (O3) | BattleProbe carries SquadRelation facts per engaged pair | task | P3 | swarm | B2, C3 |

Sharpening:
- **B2:** fog through `BattleActivity.squad_seen` and `squad_public` only. The `fire` matrix uses `LineOfFire.check`. Per-unit shots are added through A2's `unit_shot` once A2 lands; this is not a dependency.
- **B3:** includes the shared scenario builder (`_place`, `_target` and `_move_squad` from `tests/sim/test_battle_activity.gd`), and the probe kinds in O4.
- **B4:** cross-check 01's table B within 5%. The bead notes give the DPS-by-order table: the answer to U1Q1 and U1Q2.
- **B5 (for a Qwen worker):**
  - Files: `harness/src/hx/commands/workshop.py`, plus the `VERBS` entry and `harness/tests/test_workshop_cmd.py` with a canned-output fixture.
  - `list` reads `data/sim/workshop/*.json`.
  - `run` calls `hx godot run src/api/workshop/workshop_cli.gd -- --scenario <id>|all --json` and prints one line per scenario, failures first.
  - Add a `harness/README.md` row.
- **B7:**
  - **File:** `src/api/battle_cursor.gd`.
  - **API:** `BattleCursor.new(snapshot, rules)`, `seek(tick) -> BattleState` (read-only use), `state_hash()`.
  - **Acceptance:** stepping to the last frame gives the same `state_hash()` as the real end state. A backward seek restarts. `PerfRecorder` scope `battle_cursor`.
- **B10 on a B1 no-go:** the suite targets Haiku only, and B11's `ask` samples with Haiku or is skipped. B2–B9 never depend on a model.

### 5.6 U1-C: Execution clarity & deployment (draft 03)
| ID | Source | Title | Type | P | Runner | Deps |
|---|---|---|---|---|---|---|
| C1 | E1 | Playback: battle camera and hover pass through the playback blocker | feature | P1 | swarm | — (not sw-ll4.27.6, O15) |
| C2 | E2 | Playback: select squads while watching | feature | P2 | swarm | C1 |
| C3 | E3 | SquadRelation read model (sim) | feature | P1 | autopilot-large | A1, A2 |
| C4 | E4 | Game API: live relation queries | feature | P1 | autopilot | C3, sw-abk |
| C5 | E5 | Playback relations at a frame, through BattleCursor | feature | P1 | autopilot | C3, B7 |
| C6a | E6 (split) | RelationText: relation facts to tooltip lines (pure, static) | task | P2 | swarm | C3 |
| C6b | E6 (split) | Relation tooltip on hover, in Planning and playback | feature | P2 | autopilot | C1, C4, C5, C6a, sw-ll4.27.6 (reopened); related sw-dqj |
| C7 | E7 | Comparison context menu | feature | P2 | autopilot (was swarm: a new window, a GUIDE action, Controls help and the planner) | C6b; related sw-wqc, sw-wut |
| C8 | new (03-Q3) | Overworld camera pans and zooms during playback | feature | P3 | swarm | C1, X-OQ5 |
| C9 | D1 | Sim: deployment step (placements, hidden, applied at Reveal) | feature | P1 | autopilot-large | X-OQ3 |
| C10 | D2 | API, input log, saves and replay for deployment | feature | P1 | autopilot | C9 |
| C11 | D3 | Deployment UI in the battle view | feature | P1 | autopilot | C10, C1, C2 |
| C12 | D4 | Late joiners and reinforcements deploy | feature | P2 | autopilot-large | C10 |
| C13 | D5 | Deployment time bonus | feature | P3 | swarm | C9 |
| C14 | D6 | Scenario deployment switch and placed defaults | feature | P3 | swarm | C9, X-OQ4 (closes sw-tdz) |
| C15 | D7 | AI deployment heuristic | feature | P3 | autopilot-large | C10 |

Sharpening:
- **C1 (for a Qwen worker):** pick 03's first option and name it.
  - **Blocker:** while a battle is focused during playback, `_blocker` (`src/presentation/war_room/war_room.gd`, set up near `_blocker = UiWindow.new()`) covers only the side panels: the stage rect is excluded. Wheel, middle-drag and motion then reach `ContextView`.
  - **Left click** over the map keeps today's inspect semantics.
  - **Hover:** in `src/presentation/war_room/context_view.gd` `_gui_input`, drop the `_play.is_empty()` condition on the `squad_hovered` emit. `WarRoom._on_squad_hovered` refreshes the hover card during playback only when the id or frame changes.
  - **Overworld playback** is unchanged (R3Q2).
  - **Acceptance:** 03 E1's list. The sw-ll4.27.4 tests stay green.
- **C3:** uses A1's `pick_target` and A2's `unit_shot`. Extract `BattleOrders.nearest_visible_enemy` from `fall_back_point` here (`src/sim/battle/battle_orders.gd`).
- **C6a:**
  - **Files:** `src/presentation/war_room/relation_text.gd` and `tests/presentation/test_relation_text.gd`.
  - **Behaviour:** `RelationText.lines(facts) -> PackedStringArray`, at most 3 lines, in priority order targeting/under fire > range > fleeing/moving > contact. Translation keys `relation.<kind>.<value>` with English fallbacks.
  - **Out of scope:** UI wiring and the glossary.

### 5.7 U1-D: Prowess fire distribution (draft 04)
| ID | Source | Title | Type | P | Runner | Deps |
|---|---|---|---|---|---|---|
| D1 | b1 | Fire metrics: overkill, waste, time to first kill | task | P2 | autopilot | — |
| D2 | b3 | Fire-range workshop scenarios (five matchups plus `focus_fire_spread`) | task | P2 | swarm | B3, D1, A1 |
| D3 | b4 | Defence-aware cover (expected damage in `pending`) | bug | P3 | autopilot | A1, A4, D2 |
| D4 | b5 | `focus` policy: kill priority, best fit, AoE scoring (plus ruleset `fire.policy`, default `nearest`) | feature | P3 | autopilot-large | D3 |
| D5 | b6 | `prowess` policy: discipline, coordination, efficacy above Neutral (off by default) | feature | P3 | autopilot-large | D4 |
| D6 | b7 | Pressure Lab `fire_distribution` and tropes | task | P3 | swarm | D1, D5 |
| D7 | new (04-Q2) | Switch the default fire policy to `prowess`, with a new baseline era | task | P3 | autopilot | D6, X-OQ6 |
| D8 | b8 | Readability: focus readout, tracers, glossary | feature | P4 | autopilot | D5, sw-ll4.27.7 |

Sharpening:
- **D2:** gate probes on `rules-fixture` where it has the templates; otherwise status `explore`, with the numbers in the notes. The pins come from 04 §1.3 under `nearest`.
- **D3 and D4:** each changes outcomes, so record a baseline era (O10).
- **D5:** 04's Q1 no longer gates it (§3b).

### 5.8 U1-E: Overworld hexes, features & vision (draft 05)
| ID | Source | Title | Type | P | Runner | Deps |
|---|---|---|---|---|---|---|
| E1 | B1 | Overworld tuning: slower movement, more sight (data) | task | P2 | swarm | — |
| E2 | B2 | Band templates and caravan sight (the caravan entity, step 1) | feature | P2 | autopilot-large (was autopilot: schema, a new column, six transition sites) | E1 |
| E3 | B3 | Payload contributions (scouts raise caravan sight) | feature | P3 | autopilot | E2 |
| E4 | B4 | HexLayout: site slots, road offsets, mover lane | feature | P2 | autopilot-large | — |
| E5 | B5 | War room hex view at the new scale, with detail bands | feature | P2 | autopilot-large | E4; after C2 (file order, O13) |
| E6a | B6 (split) | `OverworldSession.inspect_feature` (`inspect_plot` reuses it) | feature | P2 | autopilot | — |
| E6b | B6 (split) | Per-feature selection on the map and in the hex panel | feature | P2 | autopilot | E5, E6a |
| E7 | B7 | Map editor: site placement override (`at`) and a road layer | feature | P3 | autopilot | E4, sw-7ii, sw-96x, sw-ll4.17 |
| E8 | B8 | Owner actions in the sim: remote buy | feature | P2 | autopilot-large | E2 |
| E9 | B9 | Owner actions UI: buy from the selected feature | feature | P3 | autopilot | E6b, E8 |
| E10 | B10 | AI uses owner actions | task | P3 | autopilot | E8 |
| E11 | B11 | Production pauses on an engaged hex | bug | P3 | swarm | — |

Sharpening:
- **E1 and E10:** measure with `hx sim run skirmish_mirror --variant baseline --seeds 3`, not `duel_crossroads` (§6).
- **E1 files:** `data/packages/core/defs/overworld.json`, `angelfall.json` and `skirmish.json`; `src/sim/overworld/overworld_rules.gd` (`DEFAULT_CONVOY_MOVEMENT`); and tests that assert the old numbers.
- **E7:** it builds on three open, autopilot-partial beads. Expect it to wait.

### 5.9 Start first: highest value for the effort
1. **C1:** pan, zoom and hover during playback (swarm, small, the most visible U1Q6 win; nothing blocks it).
2. **A1 and A2:** the read-model seams (two small hash-identical autopilot beads; they unblock A3, C3 and the D track).
3. **A3:** closing to fire, the attack-move feel (U1Q11, U1Q13), and the measured fix for the 49–77% DPS loss of mixed squads that is most of U1Q1.
4. **B2, then B3:** BattleProbe, then the workshop scenario format, the spine of the visual assessment framework (U1Q3, U1Q5). B4 then turns 01's measurements into gate scenarios.
5. **B1:** the Bonsai vision spike (U1Q4), run on purpose since it is `swarm-harness`. It can run beside everything else: it touches only the harness and the GPU, so not during a Godot capture.

Freebies any idle worker can take: **A5** (retarget keeps run) and **E11** (production pause).

---

## 6 Corrections

1. **03 §1.5 and E1/E6: sw-ll4.27.6 is not "in progress, lease expired".**
   - It is closed, but only a 10-line WIP commit was merged (`00ba3e5`, "worker turn ended (rc=-9)").
   - No hoverable marks, "mark at point → tooltip key" lookup or mark tooltips exist. E1 and E6 depend on something that isn't there (O15).
2. **03 line numbers are stale** after that merge: `context_view.gd:1201` is now `:1209` (the hover emit), and `:720` is now `:728` (`_draw_fire_cues`). Beads should cite symbols.
3. **05 §5 "Related": sw-ll4.17 is not done.** It is open (`autopilot-partial`), and its title, "Map painter: selection, moving stamps, overworld maps", overlaps B7. It is now a dependency of E7.
4. **05: sw-ll4.8 is not a "feature colour from data" bead to fold in.**
   - It is closed: it split `war_room.gd`.
   - Its leftover note concerns battle terrain colours (`context_view.gd`'s `BATTLE_TERRAIN` table).
   - Hex-feature `color` is new work in E4/E5.
5. **05 B1 and B10 measure overworld changes with `hx sim run duel_crossroads`.** That is a battle `scenario`: `sim_runner.gd` runs it as a battle, so overworld tuning wouldn't show. Use an `overworld_map` (`skirmish_mirror` or `test_vale`).
6. **01 B7: "Retarget and Halt keep the run flag".**
   - Halt maps to the hold order, where run means nothing, and fall-back sets run to 1 on purpose.
   - Only the `"attack"` branch (`effects.gd` `_order`, near `:303`) drops run.
7. **01 B4's acceptance compares different scenarios:** R8b (attack-move from 50 m) against R8 (Hold at 35 m). Compare R8b before and after (Qwen review).
8. **01 B10's "no units within 1 m" contradicts its own per-class radii** (0.4, 0.6 and 1.2 m).
9. **01 §1.3 item 3 is incomplete.** `_firing` also holds the squad for `FIRING_HOLD_S` = 2 s after its last shot (`movement_system.gd:146-154`), not only while cooldown or reload runs. The conclusion stands.
10. **04 Q1 is not blocking:** the brief already puts fire distribution in Prowess (U1Q15). And **02 OQ4 is not blocking:** pending scenarios never fail the suite.
11. **01 (§3.6), 03 (§3.7, as `- **Term**:` lines) and 05 (B12) add GDD 07 terms without `glossary.json`.** That fails `tests/presentation/test_glossary.gd::test_every_gdd_term_is_data` (O11). 04 alone mentions `glossary.json`.
12. **01 §1.1 and 04 §1.3 put their experiment scripts in a temporary location.** They are now committed under `docs/design/u1/scripts/`, inside the Godot project (O14).
13. **03 §3.6 replaces the GDD 04 line "Not built: panning and zooming inside a battle" outright.** Planning has keyboard and mouse pan and zoom, but during playback the mouse is still blocked until C1. The replacement should say what is still missing (§4.3 item 3), not delete the line.
14. **02 §1.4 calls sw-68h "decided".** The decision is recorded in DESIGN.md §7, but the bead is open (`autopilot-partial`), waiting on the user to empty `.mcp.json`. No change to the plan.
