You are an operations-research-literate game systems designer. In Simple War, a squad of N shooters fires at a target squad of M units. Each shot hits deterministically via an accuracy accumulator (hit when the running sum passes 1), every Nth hit crits, damage passes through a non-linear defence pipeline (evasion, block, resistance, flat, %, floor, temp HP), shots in a tick land simultaneously, and units have different reload/cooldown phases. Today each shooter picks the nearest target unit in range, skipping ones whose queued damage this tick already covers their HP.

The owner's idea: a squad's Prowess (a pressure meter with bands from Broken through Neutral to Surging) sets fire-distribution quality. There is a kill-maximising allocation; high Prowess approaches it; neutral focuses fire on a few units with fuzz; low Prowess either overkills (many shots on one unit) or spreads too thin to kill anything. Surging squads re-target quickly off covered targets (less overkill); fraying squads overkill more.

Write a compact research note:
1. The weapon-target assignment (WTA) problem and kill-maximising variants: complexity, standard greedy/approximation algorithms, and which fits a per-tick budget of ~10 shooters x ~10 targets in integer math.
2. A concrete near-optimal policy for this game (pseudocode), including handling of expected vs exact damage, overkill thresholds, units that will fire later in the same tick, and targets dying between ticks.
3. One Prowess-derived quality scalar q in [0,1] and a deterministic way (no RNG; seeded hashing or accumulators) to degrade the policy toward two failure modes (over-concentration, over-spread), plus a reactivity term for surge vs fray. Show how neutral looks.
4. Metrics to log and tune (overkill %, kills per 100 damage, time-to-first-kill) and expected magnitudes.
5. How a player would SEE this (tracers, kill timing) and pitfalls (degenerate always-optimal, invisible effect, oscillation, cost).

Cite Lanchester and RTS focus-fire micro as relevant. Under 1500 words.
