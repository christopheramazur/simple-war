# 1. Fidelity to the brief

- **U1Q25 "a bit" is not honoured.** §3.1/B1 give caravan sight 1→3 (3×), commanders 3→4, outrider 4→5, *and* features +1, while cutting speed 17–25%. Q9 admits radius 4 = 30% of a 200-hex map. Slower + near-total vision kills scouting and encourages turtling — the opposite of a tuning pass.
- **U1Q24 taxed without asking.** `remote_markup` 25% (§3.1, Q2) is invented; the owner asked for convenience "without a commander present", and §2's HoMM takeaway is used to justify a balance change the owner never requested. Ask, don't ship.
- **U1Q27 under-delivered.** Owner: payload components grant "different behaviours and capabilities". Draft reduces this to two capped integers (`sight`, `movement_points`). No behaviours, no escort/trade/scouting capability. Say so explicitly as a deferral, don't claim the tag is settled.
- **Over-reach:** battle-entry zoom moved 3.0→2.5 (§3.3/B5) and zoom floor 0.5→0.25 — unrequested UX change bundled into a scale bead. `depot` sight 1→2 is invented (owner listed mine/barracks/village/caravan only).
- **Unverified equivalence:** §1.4 asserts self-vision "exists already" because every *owned feature* lights its plot. U1Q26 says *controlled tiles*. If a hex can be controlled without a feature, the requirement is unmet.
- `marksman_team` granting `{"sight":1}` (B3) is flavour nonsense; scouts only.

# 2. Design risks

- **Fog leak via cancellation (§3.1).** "Contested: a hostile garrison or caravan with squads" cancels the buy and "the owner sees the reason as an event". An unseen enemy caravan therefore announces itself on your hex. Cancellation reasons must be derived from the acting player's knowledge, or genericised.
- **Unspecified resolution order.** Value is paid at resolve, validation at plan is "a warning only". Ten features each plan a buy, all pass, three fail. Order (feature ID? player? template?) is never stated. Deterministic-but-arbitrary = unreadable. Needs explicit ordering plus a planning-time budget reservation shown in UI.
- **Permanent-caravan exploit (§3.1 + Q7).** Garrison→caravan on rally; halted caravan stays caravan with sight 3 and is steerable; becomes garrison only "on reaching a plot". Rally one hex out and back, or halt on your own village: you keep sight 3 while sitting on a hex. Does a halted caravan hold/control the hex? Undefined. Make kind derived from state (has destination/route), not a sticky flag.
- **Layout depends on fog (B4).** Inputs are "known road neighbours" and known features, so site positions jump as you scout, moving hit targets under the cursor. Cache invalidation must include fog deltas, not just feature/road changes.
- **Geometry unchecked.** Ring radius 420 + site radius 180 + road shift 300 can push sites outside the hex or into the mover lane (y=620). `at` bounds −700..700 is a *square*, not a hex. No AC asserts containment or site/mover non-overlap.
- **Mirror `at` negation (§3.2, B7)** is a 180° rotation, not necessarily the map's mirror transform on odd-r offset. Likely wrong; verify against `skirmish_mirror`.
- **Right-click collision (B6).** B6 makes right-click set a rally point whenever a producing site is selected; the Battles brief wants right-click comparison/context menus. Cross-draft input conflict, unresolved.
- **Road over lake** becomes paintable in B7's two-layer canvas; impassable + `move_cost −5` interaction undefined.

# 3. Missing cases

- Owner action on a feature that is `cleared`, captured-by-ally, or destroyed mid-turn; per-turn counter reset timing; limit per feature vs per player.
- Buy spawning a garrison on a hex with an enemy → does the spawn itself create an engagement? Cancel check runs *before* spawn.
- Buy output + production output on the same line the same turn: two caravans, merge rules, `purchases_per_turn` vs production loop.
- Squad/item capacity limits; `sells.count` > 1 with partial affordability; chest items excluded from caps (stated) but not from *weight*/movement.
- Old-save band derivation "caravan if it has a destination" (§3.3) vs `dest_plot`/`dest_commander`/`line` — a garrison with a supply line may be mislabelled.
- Selecting the 8th+ site hidden behind "+n" (§3.1); selecting an *enemy* site; `selected_feature` surviving capture/turn end.
- Site vs mover-token hit-test priority; fogged neighbour roads truncating road strips (memory vs live).
- Editor at 2 px zoom (§1.2) has no detail band; HexLayout shared but unusable there.
- No bead re-baselines fitness/AI fixtures after B1's tuning; B10's "no regression" gate is then unachievable.

# 4. Bead review

**Swarm beads:**
- **B1 — too cross-cutting.** "Fix tests that assert old numbers" is unbounded (AI baselines, fitness gates, GDD, two packages, code default). Split: **B1a** data + `DEFAULT_CONVOY_MOVEMENT` + schema default + GDD line (swarm, ~1h, AC = exact value table asserted by one new test); **B1b** repair fallout tests/baselines (autopilot). AC "summary goes in bead notes" is not pass/fail — make it a checked-in fixture.
- **B11 — good swarm bead.** Sharpen: state explicitly *progress held, not reset*; engagement checked at production time; also cover the `_make` battle-hex path B8 will reuse.
- **B12 — too vague for a lone Qwen worker.** "Paste §3 as amended by the owner's answers" across four GDD docs + decision log + glossary + tag renumbering against the battle drafts. Split per document with pre-resolved text and exact anchors (B12a GDD02, B12b GDD03, B12c GDD04+glossary), or run as autopilot. It also blocks the entire chain on owner answers.

**Others:**
- **B2 (autopilot/Haiku) — underscoped runner.** Schema + compile + new column + 7 transition sites + new module + 3 call sites + observe + save compat + 3 GDD docs. Split B2a schema/data/compile, B2b column/transitions/save, B2c `OverworldStats`+call sites+observe; or autopilot-large. **Dep B1 is false** — remove.
- **B3** — right size/runner; AC testable. Drop marksman sight.
- **B4** — right runner; add AC: all points inside hex, no mover overlap, fog-change determinism, and a rendered mock.
- **B5** — right runner; perf AC is unmeasurable as written ("same hexes on screen" changes with scale). Fix camera+map, compare ms/frame. Visual AC needs the brief's bonsai/visual-workshop hook — dependency missing.
- **B6** — split `inspect_feature` (swarm once specified) from selection/hit-test/panel/right-click (autopilot).
- **B7** — canvas one-ground→two-layer is a model change with round-trip/undo fallout; autopilot-large or split canvas vs painter tool.
- **B8** — biggest bead; split B8a schema/state/API/validation, B8b resolver/events/replay tests. **Dep B2 is largely false**; buys can target existing garrison/convoy paths.
- **B9** — fine.
- **B10** — utility-weight tuning plus a win-rate gate is not Haiku work; autopilot-large, and AC must name the gate values.
- **Unfiled:** convoy→caravan rename (Q8 promises it), owner-action ordering/budget, fitness re-baseline.

# 5. Open questions

**Should have asked:** May owner actions be queued during Execution? Does a halted caravan hold/control a hex? Is the purchase limit per feature or per player? May cancellation reasons reveal unseen enemies? Should hex scale change battle-entry zoom? Can roads cross lake? Is remote buying meant to be *free* convenience or priced?

**Could have decided:** Q8 (owner already wrote "caravan"), Q7 (derive kind from state), Q5 (it's a bug — fix it), Q3/Q4 (the brief's list is the closed vocabulary), Q6 (no). Q9 should be answered with `hx sim run` data *before* asking.

# 6. Top 5 changes

1. **Make owner actions fog-safe and ordered:** knowledge-derived cancellation reasons, explicit resolution order, planning-time Value reservation.
2. **Re-scale the tuning to "a bit":** caravan sight 2 (+scouts→3), commanders unchanged, mp −10%; re-baseline fixtures in the same bead.
3. **Close the band loophole:** derive garrison/caravan from state; define whether a halted caravan holds a hex.
4. **Re-cut beads:** split B1/B2/B8/B12, promote B7/B10, delete false deps B1→B2 and B2→B8.
5. **Drop `remote_markup` pending owner answer; fix geometry** (hex containment, `at` bounds, mirror transform) and add payload *behaviours* or an explicit GDD deferral.
