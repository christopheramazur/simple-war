# Orchestrator journal

## 2026-11-20T13:33Z turn
- did: First turn. Inbox empty (no audit alerts). Spawned 2 workers: sw-aty (harness bug: test_adapter_sends_gateway_key reads real HX_GATEWAY_KEY from env; roster fixture must delenv it — root cause verified, env var is set here) and sw-uyv (game bug: under-strength squads drift sideways; movement uses full-strength sq_members size vs spawn's survivor count; fix = form_size column set at spawn). Both claimed, attempt 1, briefs include exact files/lines and acceptance tests.
- decided: sw-5eq is a duplicate of sw-aty — noted on sw-5eq, will close both when the fix lands on main (never close work not on main). Merge gate runs pytest -q -x for harness changes, so sw-aty unblocks all future harness merges; prioritized it. Skipped epics and the deferred-interview epic (sw-p2q.*).
- next: Review/merge sw-aty and sw-uyv when done (read diffs first). Then fill slots with sw-ll4.1 (P1 test fixture package, well-scoped) and split sw-ll4.26 (P1 playtest grab-bag: theme profiles, menu fit/scroll, hover inspection, playback timing, "Play this map" bug, convoy vanish bug) into child beads; assess sw-ll4.9 remainder (Theme done per notes; translation files + GUIDE keys left). Keep ~70% game work.
- blocked/asked: nothing.

## 2026-11-20T13:58Z turn
- did: Merged sw-aty (pytest -q -x green), closed it and duplicate sw-5eq. Rejected sw-uyv attempt 1 (0 commits: grep failed on empty GD-Agentic-Skills gitlink in worktree, then rate limit); re-spawned attempt 2 with scoped 3-file brief (battle_squads.gd form_size column, battle_setup.gd spawn, movement_system.gd:215) + gitlink workaround. Split sw-ll4.1 into sw-ll4.1.1 (frozen fixture + 4 battle test files; spawned attempt 1) and sw-ll4.1.2 (remaining rule tests; dep-blocked on .1). Slots full: sw-uyv running, sw-ll4.1.1 queued.
- decided: GD-Agentic-Skills is gitlink 160000, empty in every worktree — root cause of sw-uyv failure; workaround in all spawn briefs (read distillation from main checkout, read-only); incident noted on sw-c9l which tracks the real fix. Fixture = frozen snapshot of core (280K/62 files), completeness first; brief warns about absolute res:// art paths in copied defs.
- next: Review/merge sw-uyv and sw-ll4.1.1 when supervisor mails. Then spawn sw-ll4.1.2 (unblocks when .1 closes) and split sw-ll4.26 (theme profiles, menu fit/scroll, hover inspection, playback timing, Play-this-map bug, convoy vanish bug) into children; assess sw-ll4.9 remainder (translation files + GUIDE keys). Consider sw-c9l soon — it taxes every worker turn. Keep ~70% game work.
- blocked/asked: nothing.

## 2026-11-20T21:30Z turn (audit response first)
### Audit response
- Ran `hx swarm selfcheck`: config lists only hx/nous/qwen4-max (config_ok true); non_qwen_swarm_calls_30m = []; 55 log banners all nous/qwen4-max; supervisor alive; alert_streak 0. No delegate/claude/opencode calls made; all delegation stays via hx swarm spawn.
- Alert cause: 6/6 turns hit timeout caps, journal frozen at 13:58, no spawn/merge since ~13:57. Fix this turn: journal early, hard-cut scope to respawning the 2 failed workers (sw-ll4.1.1 with salvage patch, sw-uyv attempt 3). No splitting/research this turn.
