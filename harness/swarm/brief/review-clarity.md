# Review — CLARITY lens

## Problems (most important first)

1. **`qwen4-max:free` is not a real model id here.** The gateway exposes `hx/nous/qwen4-max`. An agent may read `:free` as a suffix to pass through (404s), or as "any free-tier model" (Groq/Gemini/Bonsai leak in). Also unclear *who* is bound: only the orchestrator's sub-delegates, or the auditor, prompt-fixer, designers, researchers, and summarizers too?
2. **"Fail an audit" is undefined, and conflated with "alert."** Two readings: (a) any alert = failure, (b) alert is advisory and failure is a separate verdict. "Multiple in a row" has no N, and no definition of what clears the streak.
3. **"Cost" when everything is free.** Could mean USD, subscription-token burn (`hx report`), rate-limit consumption, or wall-clock opportunity cost. Worse: the user's own Claude Code sessions appear in the same ledger, so "non-qwen work being done" is ambiguous between *swarm-caused* and *user-caused*. Without an attribution rule the auditor will alert on the user.
4. **"Long-running session."** One `opencode run` is one turn that exits. Undefined: turn cadence, state carried between turns, max turns, idle behaviour, and what ends the session besides failure.
5. **"User input will sometimes be required" while the user is away 4 days.** Blocking (swarm stalls on day 1) vs non-blocking (agent invents answers). Neither is stated; no default decision policy, no queue.
6. **"Alert" and "report back" — to whom, via what?** No channel, no artifact path, no severity, no acknowledgement semantics. A report written to stdout of a detached process is a report to nobody.
7. **"A few."** 2? 5? Unbounded spawning collides on one checkout and burns unpublished rate limits. Also unstated: how many concurrent Qwen calls the gateway tolerates.
8. **"Consensus."** Unanimity vs majority vs lead-designer decides; what happens on disagreement; who is allowed to run `bd create`; no cap on new issues (223 could become 2000 of unvetted work). Also: may designers override the GDD?
9. **"Check itself that it's still delegating using only qwen… and appropriately running."** Self-attestation is not evidence. Needs mechanical checks against gateway logs and heartbeats, not introspection.
10. **"Every 30 minutes."** Scheduled by whom? An orchestrator mid-turn cannot audit itself; a blocked orchestrator stops auditing exactly when audits matter. Missed windows, and the ~192-audit token bill, are unaddressed.
11. **"Stop."** Stop the current turn, the supervisor, all descendants, all worktrees? Are in-flight edits committed, abandoned, or pushed?
12. **"Begin a new orchestration session."** Unbounded restart loop; and a Qwen delegate editing the orchestrator prompt could relax the model whitelist or the audit rule itself.
13. **"Full snapshot … restore from later."** Scope (beads DB, untracked files, harness data, worktrees?) and who may restore, when.
14. **"Improve this prompt" / "as much as we can."** Which prompt — the brief, or the orchestrator prompt? And is the objective tokens consumed or shipped value? These optimise differently.

## Rewritten text

**Definitions (binding).**
- **Qwen** = exact model string `hx/nous/qwen4-max` via `opencode run --standalone --auto -m hx/nous/qwen4-max`. **Every** swarm-spawned agent turn — orchestrator, sub-delegates, auditor, prompt-fixer, designers, researchers, summarizers — uses it. `hx delegate` and `claude -p` are forbidden inside the swarm; supervisors set an env flag `HX_SWARM=1` and a per-run `swarm_id`, and refuse any other route.
- **Session** = one `hx swarm` supervisor process looping OpenCode turns, state in `harness/data/swarm/<name>/state.json` + `journal.md`, `--session` reused for continuity. Cadence: orchestrator 1 turn per completed sub-task or 5 min idle; designers/researchers 1 turn / 15 min; auditor 1 turn / 30 min wall clock, scheduled by its **own** supervisor, independent of orchestrator liveness. Hard stop: 2026-11-24T00:00Z.
- **Leak** = a gateway log entry with `swarm_id` set and model ≠ Qwen. User-initiated Claude Code traffic is tagged `origin=user` and is never a leak. **Cost** = (a) leak count, (b) paid-token delta from `hx report` attributable to swarm, (c) Qwen 429/timeout rate. Money spend > $0 is an immediate FAIL.
- **Audit verdict**: `PASS` (0 leaks, heartbeat < 10 min, ≥1 bead progressed since last audit); `WARN` (0 leaks but stalled heartbeat or zero progress, or 429 rate > 20%); `FAIL` (≥1 leak, or any spend, or orchestrator heartbeat > 30 min). Written to `harness/data/swarm/audit/<UTC>.json` plus a bead. **Alert** = that file + bead; no human notification is assumed.
- **Fail streak** = 2 consecutive `FAIL` verdicts. Any `PASS` resets it. `WARN` never counts toward the streak.
- **Self-check** = re-read the last 50 gateway entries for its `swarm_id`, verify model field, verify each worktree heartbeat file, verify tests still run. Report the numbers, not an opinion.
- **Stop** = finish the current turn, SIGTERM descendants, leave worktrees and branches intact, commit WIP to `swarm/wip/<worker>`, push (never force), write `HALTED.md`, exit.
- **Restart** = max 3 per rolling 24 h, then stay halted for the human. The prompt-fixer may edit only `harness/prompts/orchestrator.md`; the whitelist, audit cadence, and money ban live in `harness/prompts/immutable.md` and are appended by the supervisor, not editable. Every edit is a versioned file + diff bead.
- **Report back** = write `harness/data/swarm/reports/<UTC>.md`, open a `bd` issue labelled `needs-human`, continue other sessions. Nothing blocks on the user.
- **User input** = append to `harness/data/swarm/questions.md`, take the GDD-consistent default, record the assumption in the bead, proceed. Only money, force-push, history rewrite, and GDD edits are blocked pending human.
- **A few** = exactly 2 designer sessions, 2 researcher sessions, 1 orchestrator, 1 auditor; max 4 concurrent Qwen calls globally; one git worktree per worker under `.worktrees/<swarm_id>/`.
- **Consensus** = both designers approve; on disagreement the GDD wins, and if the GDD is silent the item is parked in `questions.md`, not beads. Researchers produce ≤3 proposals/cycle; designers may create ≤5 beads/cycle, each with acceptance criteria and a `harness/bin/hx godot test` expectation. Designers may not edit the GDD.
- **Snapshot** = `git bundle` of all refs + `bd export` JSON + tar of untracked harness config, into `harness/data/snapshots/<UTC>/`, tagged `pre-swarm`. Restore is human-only.
- **Objective** = merged, test-passing beads. Token usage is a budget to spend, not a score.