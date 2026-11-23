# Research Note: Prowess-Modulated Fire Distribution in *Simple War*

## 1. WTA: what we are actually solving

**Static WTA** (assign *N* weapons to *M* targets, maximise expected damage-to-value) is NP-complete (Lloyd & Witsenhausen 1986); the dynamic/stochastic version is harder still. Two objective families matter:

- **Value-attrition WTA**: maximise Σ vⱼ·(1 − Πᵢ(1−pᵢⱼ)). Separable, monotone, **submodular** in the assignment set → marginal-gain greedy is (1−1/e)-approximate (Nemhauser et al. 1978); for homogeneous weapons the marginal-return algorithm is *exact* (denBroeder et al. 1959; Manne 1961).
- **Kill-maximising WTA** (our case): damage is worthless until it crosses HP. With deterministic damage this is **bin covering / dual bin packing** (Csirik–Johnson–Kenyon 2001): maximise the number of bins filled to threshold. Greedy "cheapest bin first" is ½-approximate in general.

**Key structural result for us:** if shots are interchangeable and each target *j* has a well-defined integer cost sⱼ = shots-to-kill, then *maximise kill count subject to Σsⱼ ≤ N* is solved **exactly** by sorting sⱼ ascending and filling greedily (exchange argument: any optimal solution can be swapped to the cheapest prefix). No DP needed. Heterogeneity (range, per-shooter damage, crit phase) breaks interchangeability → GAP; then use greedy + one local repair, and keep an O(N·2^M) ≈ 10·1024-state bitmask DP as an **offline oracle**, not runtime.

**Budget verdict (10×10, integer):** cost table O(N·M) = 100 pipeline evals, sort O(M log M), allocation O(N·M) = 100. ~300 integer ops/squad/tick. Exact DP (~10⁵) is affordable only for a handful of squads; don't.

**Why focus fire is the right default:** Lanchester's square law (1916) — under aimed fire, concentration makes strength scale as N², so removing one enemy shooter early compounds. RTS micro literature and practice (Churchill & Buro 2013; Ontañón et al. 2013; StarCraft focus-fire) identifies **overkill** as the dominant waste term, exactly our failure mode.

## 2. Near-optimal policy

**Exact vs expected.** The accuracy accumulator is deterministic, so *never* average. Simulate: `a += acc; if a > 1 { a -= 1; hits++; crit = (hits % C == 0) }`, then run the defence pipeline per shot. Non-linearity (block, floor, temp HP) makes E[dmg] ≠ dmg(E): sub-block shots collapse to floor, so "spread" is catastrophically worse than average-damage math predicts. Use **exact** damage for own ready shooters; **expected × confidence** only for foreign/in-flight/pending damage whose phase or arrival is unknown.

```
plan(S, t):                                  # re-planned every tick; plans are ephemeral
  T = live targets in range(S)               # re-read HP: dead-between-ticks dropped here
  for j in T: need[j] = hp[j] + temp[j] + inbound[j]     # inbound: other squads' queued dmg
  R = shooters ready at t ; P = shooters firing later in t
  for i in P:                                # reserve, don't double-tap
      need[nearest(i)] -= rho * exact_dmg(i, nearest(i), phase(i))    # rho = reactivity
  clamp need >= 0 ; drop need == 0
  R.sort(-max_dmg)                           # heavy hitters place first (fewer, bigger bins)
  for j in T: s[j] = shots_to_cover(j, R)    # phase-aware simulation
  order = T.sort(s[j], -threat[j], dist[j], id[j])       # stable tiebreak = no thrash
  focus = order[0]
  for j in order:
    while need[j] > 0 and R not empty:
      if defect(OVER): j' = focus            # ignore "covered": dump on one unit
      elif defect(SPREAD): j' = rr_next()    # ignore "finish": one shot each
      else: j' = j
      i = argmax_{i in R} exact_dmg(i, j', phase(i))
      d = exact_dmg(i, j', phase(i))
      if d - need[j'] > theta * hpmax[j'] and exists killable j2 != j': break   # surge only
      queued[j'] += d ; need[j'] -= d ; advance(phase(i)) ; R.remove(i)
      if need[j'] <= 0: break
  for i in R: assign to argmin need[j] > 0   # leftovers chip; never idle
defect(mode): e[mode] += r[mode]; if e[mode] >= 1 { e[mode] -= 1; return true }; return false
```

Notes: **later-in-tick shooters** are handled by the reservation pass (confidence ρ), not by allocating them — they keep their own nearest-target rule. **Between-tick deaths** need no special case: `need[]` is rebuilt from live state each tick and only *queued* damage persists. **Overkill threshold θ** is a *defection* rule, not a cap: overshoot is accepted if no other target is finishable (a kill now beats a chip).

## 3. One scalar, two failure modes

**q** from Prowess *P* ∈ [−100, 100], piecewise-linear through band anchors: Broken 0.0, Fraying 0.25, Neutral 0.5, Pressing 0.75, Surging 1.0. Low-pass it: `q_eff += (q − q_eff) >> 3` (integer EMA) with band hysteresis ±5 P.

Per-squad **tilt** τ ∈ [0,1] fixed by archetype (mobs τ≈0.8 → concentrate; militia τ≈0.2 → spread). Defect rates, quadratic so neutral stays competent:

```
r_over   = ((1-q)^2 * tau)      >> fixed-point
r_spread = ((1-q)^2 * (1-tau))
```

Both are **Bresenham accumulators** — same idiom as the accuracy accumulator, no RNG, replay-safe, state saved. Rate is deterministic; *which* target the spread defect lands on uses `hash(squad_id, tick, decision_idx) % |T|` for variety without noise.

**Reactivity** ρ = q, feeding three places:
- reservation confidence ρ (surging trusts pending shots → no double-tap; fraying ignores them → overkill),
- overshoot tolerance θ = θ_max·(1−q) (surging θ≈0.1, fraying θ≈1.0 = accepts any overshoot),
- staleness L = floor(2·(1−q)) ticks before `need[]` is refreshed mid-fight (surging re-evaluates after *every* assignment).

**Neutral (q=0.5, τ=0.5):** r_over = r_spread = 0.125 → ~25% of decisions deviate, evenly split. Behaviour: correct cheapest-bin focus fire, producing **2–3 concurrent focus clusters**, an occasional stray shot, an occasional extra round into a covered unit. Reads as "competent, slightly sloppy".

**Invariant to assert in tests:** total damage *output* is independent of q. Prowess redistributes, never nerfs DPS.

## 4. Metrics

| Metric | Definition | Surging | Neutral | Fraying | Broken |
|---|---|---|---|---|---|
| Overkill % | damage past lethal on killed units / total damage | 3–8% | 12–20% | 30–45% | 45–60% |
| Kills / 100 dmg | raw, HP=100, shot=25 (ideal 1.0) | 0.90–1.00 | 0.70–0.85 | 0.40–0.60 | 0.20–0.40 |
| Kill efficiency | kills / oracle-DP kills | 0.95–1.0 | 0.75–0.85 | 0.4–0.6 | 0.25–0.4 |
| TTFK (ticks) | vs ideal ⌈HP/(N·dmg)⌉ | ×1.0–1.1 | ×1.3–1.6 | ×2–3 | ×3+ / never |

Log both overkill **and** efficiency: over-spread has *low* overkill (<5%) and *terrible* efficiency — one metric alone misdiagnoses it. Also log: shot-distribution Herfindahl index (focus concentration), retarget latency (ticks from covered → next shot elsewhere; target 0 / 1 / 2–3), stray-shot rate, shots wasted on already-dead units, greedy/oracle gap (offline), and µs per squad-tick. Tune so q→efficiency is roughly linear with a knee near q=0.3, and Broken floors at ~0.25 (never zero kills — unrecoverable feels broken, not frayed).

## 5. What the player sees, and how it breaks

**Tracers.** Surging: a tight bundle converging on one unit, then a clean *snap* to the next; kills arrive as a crisp staircase, one per ⌈HP/squad DPS⌉ ticks. Over-concentrated fray: ten tracers into a corpse, a visible wasted volley, then a long silence. Over-spread: a fan across the whole enemy line — everyone at 30% HP, nobody dead. Neutral: two clusters plus strays. **Kill timing is the true signal**, because Lanchester compounding means the first kill removes enemy DPS for the whole remaining fight; surface a first-blood timer and the enemy-DPS curve.

**Pitfalls.**
- *Degenerate always-optimal*: q only bites when shots-to-kill ≈ 2–6 and N ≈ M. One-shot kills or HP sponges make all policies identical. Tune HP/damage so TTK spans 3–8 ticks.
- *Invisible effect*: same cause. Add a prowess band icon and tracer tint so the redistribution is legible even when the outcome is close.
- *Oscillation*: prowess ← kills ← prowess is positive feedback. Clamp ΔP per tick, hysteresis on bands, EMA on q_eff, stable id tiebreaks plus a stickiness bonus for the current focus target.
- *Cost*: never run the DP at runtime; cache damage tables keyed by (shooter archetype, target archetype, crit phase); recompute `need[]` only on change; amortise re-planning across ticks for large armies.
- *Determinism*: all degradation from integer accumulators and `hash(squad_id, tick)`; no floats, no frame time; accumulator state must be in the save.
- *Feel*: players read over-spread as "my troops are stupid", not "my squad is fraying". Pair it with a visible cause (suppression, casualties, morale shock) and a visible recovery path.
