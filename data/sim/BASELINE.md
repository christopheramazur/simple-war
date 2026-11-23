# Sim baseline eras

Results in `harness/data/sim.duckdb` from before the sw-uyv merge (formations sized to
spawned survivors, merged 2026-11-21, commit 15f8d32) are not comparable with later runs.
Compare fitness only within one era.

## Era 2 (post sw-uyv) - baseline commit ff1127a (2026-11-23)
Batch `b20261122-153254`: duel_crossroads, hangar_drill, angelfall_spaceport x baseline, cautious x seeds 1-3 (18 runs, 0 failed).
Earlier post-merge batches that also belong to this era: `b20261122-152015`, `b20261122-133812` (baseline x60).
Batch `b20261122-153132` is 18 failed runs (worktree had no import cache); ignore it.
