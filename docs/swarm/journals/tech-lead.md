# Tech-lead journal

## 2026-11-20T21:35Z turn (journal FIRST — auditor found turns die at cap before journaling)
- did: oriented (hx status, workers -v, STATUS, auditor/orchestrator journals). Inbox empty, no proposals. Reviewed sw-aty merge c913c80: correct 1-line fixture fix (delenv HX_GATEWAY_KEY), matches bead. sw-j4u (7b1f126) is pre-swarm work, not a swarm merge.
- discovered: stall root cause per auditor = turns killed rc -9 before journaling; orchestrator repeats selfcheck→salvage discovery each turn; workers sw-uyv (x2) and sw-ll4.1.1 failed with 0 commits; salvage exists at 1c07e3e. sw-c9l (orphan GD-Agentic-Skills gitlink) taxes every worker.
- next: inspect worker failure logs + swarm.toml timeouts; file swarm-harness beads for concrete fixes; verify harness pytest green.
- blocked/asked: none yet.

## 2026-11-21T10:24Z turn
- did: Verified guardrail-file edits (36643f1, f5b037a, cf6a6ae) are the USER's intervention (Opus 5.5 co-author trailer; orchestrator+auditor already cleared them) — no swarm violation. Reviewed all 5 merges since last turn: sw-ll4.1.1/.2 frozen-rules fixture (right exclusions: angelfall content + package-loader tests stay on core); sw-p70 CWD-first paths + conftest sys.path pin (cache_clear hook sound: @cache sits on _toplevel, repo_root uncached); sw-uyv SoaTable.restore missing-column default fill + old-save regression test; sw-ll4.26.1 play-this-map regression test verified red-without-fix. No review beads needed. Harness pytest 217/217 green.
- decided: APPROVE both open SIMPL-readability proposals (code claims verified vs battle_state.gd:85, overworld_session.gd:795, battle_session.gd:231/314). Conditions noted in votes: read-only fog-safe ledger API, band tests call the sim's mapping (displayed=used), sequence squad_card.gd work across the two proposals. Daily cap 5/8 used; 6 candidate beads -> second approver creates at most 3 today, p1 first.
- next: create beads when consensus lands (within cap); review sw-0nl (mirror-duel seat bias) and sw-ll4.26.2 (convoy vanish) when they merge. Last turn's harness concerns closed: user fixed the gate, sw-7vh (needs-human) tracks the guardrail env fix, conftest pin fixes worktree pytest.
- blocked/asked: none.
