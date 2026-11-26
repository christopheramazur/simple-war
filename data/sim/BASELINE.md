# Sim baseline eras

Results in `harness/data/sim.duckdb` from before the sw-uyv merge (formations sized to
spawned survivors, merged 2026-11-21, commit 15f8d32) are not comparable with later runs.
Compare fitness only within one era.

## Era 2 (post sw-uyv) - baseline commit ff1127a (2026-11-23)
Batch `b20261122-153254`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Earlier post-merge batches that also belong to this era: `b20261122-152015`, `b20261122-133812` (baseline x60).
Batch `b20261122-153132` is 18 failed runs (worktree had no import cache); ignore it.

## Era 3 (coherency radius, sw-txnj.4) - baseline commit 2791748 (2026-11-25)
Batch `b20261125-130349`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Outcomes differ from era 2 on purpose: squads wait for stragglers (anchor at half speed while a unit is out of coherency), so turns and value lost move. Compare fitness only within era 3.

## Era 4 (per-unit firing positions, sw-txnj.5) - baseline commit 1431a0e (2026-11-26)
Batch `b20261125-140516`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Outcomes differ from era 3 on purpose: under attack orders each armed unit walks to its own firing position within coherency, the anchor advances until every armed unit has one, and squads engage unit to unit (a squad engages as its first unit comes into range). Compare fitness only within era 4.

## Era 5 (firing position snap, sw-txnj.16) - baseline commit 74796e2 (2026-11-26)
Batch `b20261125-223050`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Outcomes differ from era 4 on purpose: a unit that reaches its firing position stands on it (it used to stop up to 1/8 m short, which left shotguns out of their 15 m range), so attack from 44 m is 9.13 DPS (was 5.66). Compare fitness only within era 5.

## Era 6 (arrival tick, sw-txnj.6) - baseline commit b654a65 (2026-11-26)
Batch `b20261125-230507`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Outcomes differ from era 5 on purpose: a unit under an attack order that reaches its firing position this tick fires standing, not on the move (the arrival tick, or the tick it comes into range). Attack from 41 m rises 453 -> 462 damage (dps_orders); the 60 m draft 01 duel attack-move vs hold goes 0-5 -> 0-0 (both sides wiped on one tick, lockstep). The dps_orders duty gate for move_then_attack is re-pinned 0.9 -> 0.85 (base duty 0.093 -> 0.097; move_then_attack unchanged). Compare fitness only within era 6.

## Era 7 (archetype behaviours, sw-txnj.11) - baseline commit f9e1a93 (2026-11-26)
Batch `b20261126-001752`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Outcomes equal era 6 in every row (the batch summary matches `b20261125-230507` for all six scenario x variant rows): the mortar stand-off, marksman max band and assault coherency change no sim outcome here. The archetype DPS and stand-off numbers are pinned in the workshop gates instead (`archetype_mortar`, `archetype_marksman`, `archetype_rifle_line`, `table_b_assault`). Compare fitness only within era 7.

## Era 8 (separation between squads, sw-txnj.12) - baseline commit a9bf150 (2026-11-26)
Batch `b20261126-011216`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Outcomes differ from era 7 on purpose: units of different squads are pushed apart to their size-class distance (medium 0.6 m) and walk around each other, so squads that meet or share ground no longer stack. angelfall_spaceport is unchanged; duel_crossroads and hangar_drill shift (baseline p1 win 0.67 -> 0.33 in both; value lost moves both ways). Separation costs 0.16 ms/tick at 208 units. Compare fitness only within era 8.
