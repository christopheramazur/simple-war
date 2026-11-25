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
