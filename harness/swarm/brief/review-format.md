# Review — FORMAT lens

## Problems

1. **No role contracts.** Five actors are described in prose ("orchestration session", "audit sessions", "senior designers", "research sessions", "remediation delegate") with no consistent purpose/inputs/outputs/cadence/stop fields. An implementer cannot tell what a role reads, what file it writes, or when it exits. This is the single biggest structural defect.
2. **"Long-running session" is undefined and, in this environment, impossible as written.** One `opencode run` is one turn that exits. Every "session" here must be specified as *supervisor loop + state file + turn prompt*, or delegates will improvisise five incompatible loop designs.
3. **The failure/remediation clause is repeated three times** with drifting scope (orchestrator only; +designers; +research). Collapse into one numbered protocol referenced by role.
4. **Every threshold is delegated to vibes:** "multiple audits in a row", "auditor's discretion", "obvious improvements". Unspecified thresholds plus a self-modifying prompt loop = unbounded churn. Put numbers in one config file, not in prose.
5. **No shared-artifact contract, and bead write authority is ambiguous.** Designers "find consensus on which tasks to add to the beads" while the orchestrator works the beads — two writers, 223 issues, no lock. Also missing: where audit reports, research reports, proposals, and questions live.
6. **Guardrails are implicit or absent:** model allowlist is an *instruction* rather than an enforced spawn parameter; no worktree rule (env facts say collisions are certain); no-money and no-force-push never stated; no attribution rule so the user's own paid Claude Code sessions will trip the auditor.
7. **No termination, liveness, or human-input channel.** A 4-day detached run needs a deadline, a heartbeat, a kill file, restart idempotency, and a non-blocking place to leave questions for an away user. "Use as much free tokens as we can" is stated as a goal but throughput is a means; success measures are missing.

---

## Rewritten text

### 0. Objective
Over 4 days (deadline `2026-11-24T00:00Z`), maximise **merged, test-passing improvements** to (a) the harness, (b) agent ways-of-working, (c) Simple War gameplay — using only `hx/nous/qwen4-max`. Token volume is a means, not a metric. Report daily: beads closed, PRs merged, harness tests green, GDD deltas.

### 1. Vocabulary
- **Turn** = one `opencode run --standalone --auto -m hx/nous/qwen4-max [--session <id>] "<prompt>"`.
- **Lane** = a Python supervisor loop (`hx swarm lane <name>`) that re-invokes turns, carrying state in `harness/data/swarm/<lane>/state.md`. Lanes are detached; cadence is scheduled by the supervisor, never by the model.

### 2. Guardrails (apply to all lanes)
- **G1** Supervisors pass `-m hx/nous/qwen4-max` explicitly. Lanes must never call `hx delegate`, `claude -p`, or any paid route.
- **G2** No money. No force-push, no history rewrite. Push to `origin/swarm/*` only.
- **G3** One git worktree per worker: `harness/data/worktrees/<bead-id>`, branch `swarm/<bead-id>`. Only the orchestrator merges to the integration branch, serially, gated on `harness/bin/hx godot test` and `uv run --project harness pytest -q`.
- **G4** Every spawn is tagged `swarm_id` in `harness/data/raw/delegate/`. Claude Code activity not carrying `swarm_id` is the user's and is **out of scope for audit**.
- **G5** `harness/data/swarm/HALT` present → all lanes drain and exit.

### 3. Shared artifacts
| Path | Writer | Readers |
|---|---|---|
| `harness/data/snapshots/<UTC>/` (`beads.jsonl`, repo bundle, `raw/`, `RESTORE.md`) | R0 once | all |
| `swarm/config.toml` (thresholds, cadences) | user; remediation may propose diffs | all |
| `swarm/orchestrator/state.md`, `journal.jsonl` | R1 | R2, R5 |
| `swarm/audit/<UTC>.md` + `verdict.json` | R2 | R1, R5 |
| `swarm/proposals/*.md` | R3, R4 | R1 |
| `swarm/research/<topic>.md` + `brief.md` | R4 | R3 |
| `swarm/QUESTIONS.md` (append-only) | any | user |

**Bead writes (`bd create/update/close`) are orchestrator-only.** Others propose.

### 4. Roles

**R0 Snapshot** — once, before anything. `bd export`, `git bundle create --all`, tag `pre-swarm-<UTC>`, copy `raw/`, write `RESTORE.md`; **verify by restoring into a scratch worktree**. Stop: verification passes.

**R1 Orchestrator** — purpose: turn ~81 ready beads into merged work. In: beads, `AGENTS.md`, proposals, latest verdict. Out: worktree spawns, merges, bead updates, journal. Cadence: turn on completion, 60 s idle backoff, max 6 concurrent workers. Stop: HALT, deadline, or F3.

**R2 Auditor** — purpose: verify G1/G2 and lane health. In: `raw/gateway/*.jsonl`, `hx providers`, `hx report`, delegate log, git authorship, journals. Out: `verdict.json` `{alert: bool, reason, evidence}`. Cadence: every 30 min wall clock. Alert if >5 % of swarm-attributed requests in the window are non-allowlisted, any paid spend, any lane heartbeat >20 min stale, or >2 failed merges/hour. Stop: one report per invocation.

**R3 Design council** (2 lanes) — purpose: GDD-faithful senior review. In: GDD (8 docs), diffs, research briefs. Out: code-review and gameplay notes on beads; ranked `proposals/consensus-<UTC>.md`. Cadence: 15 min. Stop: HALT/deadline.

**R4 Research** (2 lanes) — purpose: mechanics/theme/art precedent fitting "clear, easy to read, accessible". Out: full report + jointly written ≤1-page `brief.md` for R3. Cadence: 30 min; ≤3 open topics. Stop: HALT/deadline.

**R5 Remediator** — see §5.

### 5. Failure & remediation protocol (replaces all three repeated clauses)
- **F1** On `alert: true`, R1 re-reads its spawn config, confirms G1, writes a remediation note, continues.
- **F2** Two consecutive alerts → R1 stops, writes `postmortem.md`, exits. Supervisor invokes R5 (one turn, allowlisted) to analyse R1 **and** R3/R4 journals, then apply *bounded* edits: prompt text and `config.toml` only — never guardrails G1–G5.
- **F3** After 3 R1 restarts, or any guardrail breach, the whole swarm halts and writes `swarm/REPORT.md` + `QUESTIONS.md` entry. No auto-restart.

### 6. Human input
Never block. Append the question, record the assumption taken, proceed on the reversible option; irreversible choices (deleting beads, GDD rewrites) wait for the user.

### 7. Prompt-improvement task
File this brief's rewrite as beads *after* R0, worked by R1 like any other task — not as a pre-loop special case.