# Retro journal

## 2026-11-21T18:57Z turn
- did: first retro. Measured 12 h (06:26–18:26Z): 11 merges all before 14:26, zero since; 19% turn failures concentrated after 15:00; 429 share 56% last hour / 65–82% audit windows; sw-opt + sw-ll4.27.3 att3 finished but unmerged 3+ h; orchestrator = 40% of gateway calls.
- did: 3 changes, committed+pushed: worker.md → per-bead journals worker-<bead>.md (kills the shared-worker.md conflict loop that burned .3 att2–3); orchestrator.md → throttle playbook (journal early, merge-before-spawn, lean re-review of conflict-only continuations); swarm.toml → pause_s 240, designers/researchers every_s 14400, audit timeout 2700. Slots unchanged. Report: docs/swarm/retros/20261121-1857.md.
- decided: pipeline is merge-starved, not design-starved (deep brief queue), so cut support/polling demand instead of adding slots. TOML parse verified; most toml values apply after supervisor restart.
- next: retro ~06:57Z — verify sw-opt/.3 merged, worker_done→merge lag, zero journal conflicts, 429 share, no-verdict WARNs gone, designer ask latency. Revert every_s to 7200 if asks block workers.
- blocked/asked: none. Noted on sw-2sq that per-bead journals supersede its shared-file workarounds (README doc still fine to land).
