# 1. Fidelity to the brief

- **Scope**: draft 01 covers only U1Q1 and U1Q5. The owner's *stated priority* — the visual battle-assessment framework and behaviour workshop — plus execution-phase camera/select/tooltip, deployment, Prowess and the whole Overworld section are absent. It defers to "drafts 02/03" without a coverage map. Add a traceability table proving every brief paragraph has an owner draft; right now nothing does.
- **Status line contradicts §5**: "No beads were created" while §5 defines B1–B12. Fix.
- **Over-reach**: §3.2 "Volley phase" and B6 rewrite core lethality/balance. The owner asked to *confirm and clarify* damage output, not retune it. Staggered accumulators change every duel, every golden, every replay. That is an owner decision, not a drafting default.
- **Over-reach**: §3.3/OQ6 declares "**No body blocking**" as a rule. The brief asked to *flesh out* collision and coherency, not delete blocking. Don't foreclose chokepoints/melee lines in a draft.
- **Misread of U1Q5b**: SC2 marines stop **per unit** at their own range. The draft invents a squad-level "fire quorum" plus a 3 m "step-out" patch to approximate it. That is a different, weaker rule and the source of most risks below.
- §3.2's "no order has a hidden damage penalty" is contradicted by its own Move row (accuracy × Instinct). Say "no *unexplained* penalty".

# 2. Design risks

- **Infeasible quorum (§3.2)**: stand-off = max `min_range` of awaited units + 2 m. A mortar (20 m min) + shotgun (15 m max) squad can *never* reach 100% quorum. Result: infinite closing or per-tick oscillation. No fallback rule exists.
- **Quorum feedback**: `shot_share` denominator is living units' standing DPS. Deaths, reloads and unspotting change it every tick → anchor stop/start jitter. No hysteresis/deadband specified anywhere.
- **Step-out (B4)** fights separation (B10) and coherency (B11); it moves units, which moves centroids, which changes the centroid range test that decided to stop. Three coupled feedback loops, no damping. "Re-evaluate every 5 ticks, in row order" also breaks the mirror symmetry that B3/B5/B10 acceptance relies on.
- **B5 gives attack orders a free bonus**: skipping the arrival moving volley removes the cost the trade-off table promises. Slot-based accumulator offsets make *formation slot order* a hidden combat stat and systematically favour low IDs.
- **Fog of war is never mentioned.** Quorum, step-out and "nearest enemy unit" all consume per-unit enemy positions. Forecast ghosts showing the stop point can leak unspotted enemy geometry. Nothing states what is computed in sim vs. shown to the player.
- **Anchor half-speed on any coherency breach (B11)**: one straggler stuck on terrain halves the squad forever; enemy separation pushes become a slow-debuff exploit.
- **Separation push capped at unit speed** grants movement beyond the turn's movement budget and ignores terrain cost.
- **Cluster lead = lowest row** makes row order gameplay-visible.
- **Perf**: B3's `shot_share` is O(units × targets) per tick per squad, paid again per forecast (§1.3 item 8). B3 has no cost acceptance; only B4/B10 do.

# 3. Missing cases

Zero standing DPS (all reloading) → divide-by-zero in `shot_share`; "units with no weapon don't count when nothing can improve them" is undefined. Target dies/unspots mid-close; retarget during closing; turn-end movement budget truncation; run-speed overshoot at 10 tps; multiple engaged squads (whose quorum?); mortar spotter death; step-out into walls/cliffs and the return oscillation; behaviour component conflicts (`advance` + `keep_distance` both move-phase) and precedence; unknown *order* keys vs unknown components; forecast must model B7's run-flag change; **replay/save versioning** — B5 changes spawn state, so old replays desync and no bead bumps a version or migrates. No bead surfaces `CLOSING_IN`/"moving to fire" in the UI, which is the owner's actual clarity ask.

# 4. Bead review

**Swarm beads (Qwen4, alone, <2 h):**
- **B1 — too big and too vague.** 313-line script port + JSON writer + new fixture test + four pinned ratios + README is 1–2 days. "Prints the tables in §1.2" is not a spec. Split: **B1a** port script verbatim to `src/tools/order_dps_lab.gd`, AC = runs, exit 0, <15 s (swarm, ~1 h); **B1b** `tests/sim/test_order_dps.gd` on the fixture with *exact* numbers/tolerances/tick counts (autopilot — needs fixture knowledge); **B1c** README entry (swarm, 15 min). Also drop the two pins that later beads deliberately break (assault ≤0.4×, Hold-duel-one-tick) or mark them `pending_flip` with the flipping bead id.
- **B7 — correct scope and runner.** Sharpen AC to a tick assertion (run byte == 1 at t+1 after Retarget *and* Halt) and add a forecast-parity case. ~1 h.
- **B12 — too cross-cutting for swarm.** Six insertions across three GDD files + decision log + U1Q tag reconciliation with drafts 02/03, gated on an owner review that hasn't happened, and §3.2's text will be falsified by B3/B5/B8. Split per file; give reconciliation to autopilot; move the §2.15 insert *after* B3/B5 land or stamp it "proposed, unimplemented".

**Others:**
- **B2** (autopilot-large): right runner, ~1 day. The 0.2 ms budget is invented — get a target from the owner. Must also profile `shot_share`, not just separation.
- **B3** (autopilot-large): 1–2 days, borderline. AC testable but "rifle/mortar unchanged within 3%" is incompatible with quorum-driven stop distances and with B5. Add infeasible-quorum fallback and a perf AC. Should depend on B2.
- **B4**: **bad acceptance** — R8b (attack-move, 50 m) vs R8 (Hold, 35 m) are different scenarios; the ratio is meaningless. Rebaseline against attack-move-flank pre-change.
- **B5**: wrong runner. Haiku should not rewrite combat math and regenerate all goldens. Move to autopilot-large. "Survivor gap ≤ 3" is arbitrary and possibly unachievable; replace with "no whole-squad wipe on a single tick in the 7 duel rows".
- **B6**: balance change, needs owner sign-off. AC mixes units (Instinct 52-scale vs "Fraying floor 15%") — untestable as written. Renaming the ruleset key breaks existing packages; add migration.
- **B8**: multi-day. Split into schema+validation / compile to `bh_*` / movement reads params / data+docs. "Same hash" is a good AC — keep it on each sub-bead.
- **B9**: "≥0.85× its best order" is unfalsifiable when best = Hold at 12 m. Pin per-template absolute DPS₁ instead.
- **B10**: AC "no enemy units within 1 m" contradicts per-class radii (0.4/0.6/1.2). Assert per-class. Deps should include B3/B4 (pass ordering).
- **B11**: three unrelated features in one bead — split de-dup / coherency slow / cluster routes. Needs a doorway fixture map for its AC.

# 5. Open questions

**Should have asked:** Is U1 allowed to change lethality/balance at all, or clarity only? Is removing body blocking acceptable? Are golden/replay breaks acceptable, and is there a version policy? What is the perf target and reference machine? Per-unit stop (true SC2) vs squad quorum — which does the owner want? Who owns the tooltip/hold-reason/forecast-ghost UI work?

**Could have decided itself:** OQ1 (measure both in B1, pick), OQ2 (ship 15 m as data), OQ4 (already in §2.6), OQ7 (defer, no ask needed), OQ9 (obvious no). OQ3 is two questions and should be a flagged experiment bead, not a blocker on B5.

# 6. Top 5 changes

1. **Replace squad quorum with per-unit stop conditions** (SC2-faithful), keeping a squad anchor leash; delete step-out or make it the fallback only. Kills the infeasible-quorum, jitter and centroid-feedback risks at once.
2. **Carve B5 and B6 out as owner-gated balance proposals**, behind a ruleset flag, with a replay/version bead. U1's default path must be behaviour-only and hash-stable.
3. **Add a fog-of-war and presentation contract** to §2.15: what the sim may know, what the forecast/tooltip may show; add the missing UI bead for hold reasons and the stop ghost.
4. **Re-split the beads**: B1→3, B8→4, B11→3, B12 per-file; move B5 to autopilot-large; fix B4/B9/B10 acceptance to be falsifiable; add perf AC to B3.
5. **Publish a brief-coverage map** across drafts 01–03 and reconcile U1Q tags before B12; the owner's stated priority (visual assessment framework/workshop) must not fall between drafts.
