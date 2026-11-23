# 1. Fidelity to the brief

- **Scope inflation.** The owner tags Prowess "**Longterm** SIMPL idea". The draft ships 10 beads including UI readouts, tracers, a 108-run lab and a default-flip plan (§5, Q2). Only beads 1–2 (metrics + seam) are clearly U1-sized; the rest should be explicitly parked behind a "long-term" gate.
- **Bead 1's "Why" over-claims.** "The owner can't confirm the damage-output effects" refers to *attack-move/run/hold and retargeting* DPS. `fire.*` metrics measure none of that. Either add command-mode/retarget counters or stop claiming the brief's headline complaint is addressed.
- **U1Q-P5 is misread.** Owner: surging = "more reactive target swapping". Draft models low coordination as *blindness to your own squad's queued hits* (§3.2). That's an information handicap, not reaction speed, and it is invisible to the player. It also contradicts Q8's (correct) refusal to add re-acquire delay — the draft rejects the mechanism the owner actually described and substitutes a stranger one.
- **Nothing says what makes a squad Surge or Fray.** §1.1 lists drift 0.5%/s toward 52 and `steady_aim`. With no battle driver, Prowess is a static template stat and the owner's "distinct gameplay modes and feels" never occurs. This is the largest fidelity gap and it isn't even an open question.

# 2. Design risks

- **Efficacy `hi` change is a silent global buff (bead 6).** §1.1 lists Prowess efficacy feeding ambush, intercept, interrupt, reactions and Vacuum. Raising `hi` to ~1.92 nearly doubles all of them. The draft never mentions this. Scope the new clamp to fire only, or rebalance those sinks in the same bead.
- **Per-squad coordination doesn't scale.** §1.1 admits `pending` is per squad; Q6 defers cross-squad. With 3 squads on one target, "optimal" still overkills badly. The 6–0 duel result (§1.3) will not generalise, and the lab will show `pile_on` on good policies.
- **Order bias masquerading as Prowess.** Hits drain in shooter-unit-ID order and volleys are lockstep (§1.1). "optimal 6–0" is partly an artifact of ID ordering + synchronisation, not discipline. Bead 10 can invalidate beads 5/6's pinned outcomes.
- **Metrics conflate mitigation with bad policy.** `overkill_pct = overkill/raw` (§3.4) puts post-defence numerator over pre-defence denominator; the CHI row shows 48–56% "waste" that is mostly armour. Trope `pile_on ≥ 35` will fire on every armoured matchup regardless of policy. Subtract mitigation and the granularity floor before judging policy.
- **Fixed-point violations.** `q = discipline × efficacy`, `K = 1 + (1−q)(candidates−1)`, and bead 10's `slot × 0.618 mod 1` are float maths in an integer sim. Specify permille integers and rounding, or hashes drift.
- **K depends on candidate count**, which changes with range/visibility each tick. Same Prowess, different behaviour, no player-visible cause. "Nearest of the top-K kill-priority" is also a hybrid the owner never asked for and is hard to explain in a tooltip.
- **Fog:** Q5 assumes per-unit enemy HP and Defensive Profile are UI-visible. Verify; if the UI shows squad aggregates, the policy is reading information the player doesn't have.

# 3. Missing cases

- All reachable victims covered → hold fire or shoot anyway? Unspecified (§3.1). This directly changes DPS and is exactly the owner's complaint.
- Target squad wiped mid-volley; sticky-target re-acquire within the same tick; engagement restart and how `fire.first_kill_ticks` resets.
- Temporary HP/shields, mid-tick heals, damage floor *raising* damage (noted in §1.1, absent from `preview` spec in bead 4).
- AoE: friendly fire in radius, per-unit defence differences inside splash, min-range/LoF gates interacting with kill-priority.
- Moving squads: every experiment is HOLD in line formation. Attack-move (the brief's core case) changes the reach set per tick.
- |S|,|T| ≤ 10 is assumed, not verified against content.
- Bead 2 adds a ruleset field — does the package/ruleset hash change? "Byte-identical state hashes" needs to say which hash.

# 4. Bead review

1. **autopilot, ~1 day, borderline.** Core `HealthSystem` + events + metrics + GDD is a lot for Haiku. Acceptance is testable but `dealt = 82` doesn't reconcile with 8×10 = 80 HP; derive numbers from the fixture, don't transcribe. Split: 1a drain counters + event fields; 1b SimMetrics/GDD.
2. **autopilot, right-sized, deps none — good.** Best bead in the set. Add "which hash" and a policy-id validation test.
3. **swarm — too big as written.** Five matchups + fixture helper + pinned ticks in <2h is optimistic, and the dep on 2 is artificial (the bench can run against today's picker). Split: **3a** helper + rifle→rifle only (swarm, no deps); **3b** remaining four matchups (swarm, deps 3a). Don't pin CHI numbers here — bead 4 changes them.
4. **autopilot, ~1 day, deps 2/3 right.** Testable. Add: `preview` must not touch evasion/block accumulators, must include the floor, and must be covered by a purity test.
5. **autopilot-large, right runner, ~1 day tight.** AoE scoring alone is half a day. Split AoE out (5b). Replace "mirror duel 6–0" with an order-symmetric assertion (run both ID assignments) or it will break at bead 10.
6. **autopilot-large, too big.** Schema + stat registry + ruleset + two SoA columns + save + efficacy clamp + K/c maths + two templates is 2–3 days. Split: **6a** data/stat/column plumbing with inert policy (autopilot); **6b** K-width + coordination maths (large); **6c** efficacy clamp scoping + regression tests for ambush/intercept/interrupt/Vacuum (autopilot). "Neutral gives 3–4 survivors" is not a testable criterion in a deterministic sim — pin one number with a named fixture.
7. **swarm — too cross-cutting.** GDScript-adjacent JSON + Python harness features + tropes + GDD, 108 runs. Split: **7a** lab JSON (swarm, deps 6); **7b** `lab.py` features + pytest (autopilot); **7c** tropes + GDD line (swarm). **Acceptance is falsified by the draft's own data**: §1.3 shows kills/100 = 6.67 for neutral, fraying *and* broken. Monotonicity must be asserted on mean-kill-tick or survivors, not kills/100.
8. **autopilot, ~1 day if "optional" tracer tint is dropped.** Four surfaces. Split glossary/event text to swarm. "Tooltip values equal sim values" needs a named API field; otherwise presentation will recompute K and diverge — specify the read-only query.
9. **autopilot, fine.** But `hx find "U1Q-P"` returns nothing is self-defeating: this design doc is full of those tags. Scope the grep to `docs/gdd/` or renumber the doc too.
10. **autopilot-large, wrong position.** Deps 7 means it lands after the policy it can invalidate. Move it before 5/6, or make 5/6 acceptance stagger-agnostic. Use integer stagger.

# 5. Open questions

**Should have asked:** What drives Prowess up/down during a battle (surge/fray triggers)? What effect size does the owner want — is 0–0 → 6–0 acceptable, or should Prowess be a ±15% nudge? Is per-unit enemy HP legitimately player-visible? Does "longterm" mean U1 ships only the seam?

**Could have decided:** Q1 (the brief names Prowess — decided), Q3 (per-squad content, obviously), Q5 (read the UI/fog code), Q8 and Q9 (both already answered by the brief). Q4 is an experiment, not a question — bead 10 answers it. That leaves Q2 and the surge/fray driver as the only genuine owner blockers.

# 6. Top 5 changes

1. **Define what moves Prowess in battle**, or explicitly descope surging/fraying and say so in §3.2. Without it the feature is inert.
2. **Scope the efficacy `hi` change to fire** and add regression tests for ambush/intercept/interrupt/reactions/Vacuum (bead 6c).
3. **Fix the overkill metric** (exclude mitigation + granularity floor) and rewrite bead 7's monotonicity acceptance, which the draft's own table contradicts.
4. **Reorder: spike 10 before 5/6**; make 5/6 acceptance order- and stagger-robust; split 6 into three beads and 7 into three.
5. **Re-model coordination as reaction latency, not blindness** — or drop the c axis for U1 and ship q only, with an honest note that the owner's "reactive swapping" is unimplemented.
