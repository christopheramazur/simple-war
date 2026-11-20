# Orchestrator journal

## 2026-11-20T13:33Z turn
- did: First turn. Inbox empty (no audit alerts). Spawned 2 workers: sw-aty (harness bug: test_adapter_sends_gateway_key reads real HX_GATEWAY_KEY from env; roster fixture must delenv it — root cause verified, env var is set here) and sw-uyv (game bug: under-strength squads drift sideways; movement uses full-strength sq_members size vs spawn's survivor count; fix = form_size column set at spawn). Both claimed, attempt 1, briefs include exact files/lines and acceptance tests.
- decided: sw-5eq is a duplicate of sw-aty — noted on sw-5eq, will close both when the fix lands on main (never close work not on main). Merge gate runs pytest -q -x for harness changes, so sw-aty unblocks all future harness merges; prioritized it. Skipped epics and the deferred-interview epic (sw-p2q.*).
- next: Review/merge sw-aty and sw-uyv when done (read diffs first). Then fill slots with sw-ll4.1 (P1 test fixture package, well-scoped) and split sw-ll4.26 (P1 playtest grab-bag: theme profiles, menu fit/scroll, hover inspection, playback timing, "Play this map" bug, convoy vanish bug) into child beads; assess sw-ll4.9 remainder (Theme done per notes; translation files + GUIDE keys left). Keep ~70% game work.
- blocked/asked: nothing.
