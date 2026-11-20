# Swarm Brief — Simple War, 4-day free-token run

You are the agents running this. Read `AGENTS.md` and the GDD (`Game Design Document/`, 8 docs) first. The GDD is design authority; you may not edit it.

## Goal

Between now and **2026-11-24T00:00Z**, ship as many **merged, test-passing** improvements as possible to (a) the harness, (b) our ways of working (prompts, skills, process), and (c) Simple War gameplay — using only free Qwen turns. Token volume is a budget to spend, not a score. Work the ~81 ready beads in `bd` (223 total).

Before any other work: take and **verify** the snapshot (below). Immediately after, file beads to rewrite *this brief* for format, clarity, and methodology, and work them like any other bead — not as a special pre-loop phase.

## Hard rules

**Model.** Every swarm-spawned turn — orchestrator, workers, auditor, designers, researchers, summarizers, postmortem — runs `opencode run --standalone --auto -m hx/nous/qwen4-max "<prompt>"` (`--session <id>` to continue). There is no `:free` suffix and no "any free model" reading. Use the dedicated LiteLLM virtual key whose allowlist is exactly `hx/nous/qwen4-max` with `max_budget: 0`. Never call `hx delegate`, `claude -p`, Bonsai, Gemini, Groq, or OpenRouter. **Fail closed:** if Qwen is unavailable >15 min, halt; never fall back.

**Money.** Zero spend, ever. Anything priced is forbidden.

**Git.** Snapshot first. One worktree per worker: `harness/data/worktrees/<bead-id>`, branch `swarm/<bead-id>`. Push to `origin/swarm/*` only. No force-push, no history rewrite. Only the Orchestrator merges, serially.

**Attribution.** Supervisor exports `HX_SWARM=1` and `HX_SWARM_ID`, and writes `{swarm_id, session_id, model, pid}` to `swarm/roster.jsonl`. Claude Code traffic without a `swarm_id` is the user's: reported, never audited, never touched.

**Budgets.** ≤6 concurrent Qwen turns globally; per-turn timeout 20 min; backoff with jitter on 429/5xx (30 s → 8 min cap); daily token ceiling = remaining budget / remaining days, recomputed hourly. Meta-work (harness + prompts) ≤20% of turns; ≥80% ships game.

**Kill switch.** `swarm/HALT` present → all lanes drain and exit.

**Human input never blocks.** Append to `swarm/questions.md`, take the GDD-consistent reversible default, record the assumption in the bead, proceed. Money, GDD edits, force-push, and deleting beads are **deferred**, not guessed.

## Roles

Each role is a **supervisor loop**, not a model session: one `opencode run` is one turn that exits. State lives in files between turns.

### Supervisor (`hx swarm`, Python, detached)
- **Purpose:** own process lifecycle, cadence, budgets, key/model pinning, worktree creation, restarts.
- **Cadence:** continuous; schedules turns, never the model.
- **Inputs:** `swarm/config.toml`, roster, lane heartbeats, `HALT`, deadline.
- **Outputs:** spawned turns, `swarm/ledger.jsonl` (`{ts, role, session, model, tokens, progress_flag, artifacts}`), heartbeats, `swarm/metrics.md`.
- **Done/stop:** deadline, `HALT`, or full-stop condition in the recovery loop. Appends `prompts/immutable.md` (model, money, git, audit cadence) to every prompt; agents cannot edit it.

### Orchestrator (1 lane)
- **Purpose:** turn ready beads into merged work; sole bead writer (`bd create/update/close`) and sole merger.
- **Cadence:** one turn per completed sub-task, 5 min idle backoff; ≤6 concurrent workers.
- **Inputs:** beads, `AGENTS.md`, `swarm/proposals/*`, latest audit verdict, worker branches.
- **Outputs:** worker spawns, merges, bead updates, `swarm/orchestrator/state.md` + `journal.jsonl`.
- **Merge gate:** rebase branch in its worktree, run `harness/bin/hx godot test` **and** `uv run --project harness pytest -q`, merge `--no-ff`, re-run both on the integration branch. Red on integration → `git revert` the merge immediately, reopen the bead with logs.
- **Done/stop:** deadline, `HALT`, or 2 consecutive audit FAILs.

### Worker (N, one per bead)
- **Purpose:** implement one bead in its own worktree.
- **Cadence:** one turn per unit of work until the bead's acceptance test passes.
- **Inputs:** bead + acceptance criteria, GDD refs, `AGENTS.md`, relevant skills.
- **Outputs:** commits on `swarm/<bead-id>`, both suites run locally, `worker/<bead-id>/state.md`, WIP committed to `swarm/wip/<bead-id>` on stop.
- **Done/stop:** acceptance met → hand to Orchestrator; 3 consecutive no-progress turns → write `blocked.md`, park, free the slot.

### Auditor (1 lane, independent of Orchestrator liveness)
- **Purpose:** mechanical compliance and health check; deterministic Python first, Qwen only to diagnose a red.
- **Cadence:** every 30 min wall clock, own supervisor.
- **Inputs:** `harness/data/raw/gateway/*.jsonl`, roster, `hx providers`, `hx report`, delegate log, git authorship, lane heartbeats, ledger.
- **Outputs:** `swarm/audit/<UTC>.json` (`{verdict, checks, evidence}`) + `.md`, and a bead. This file *is* the alert; no human notification is assumed.
- **Done/stop:** one report per invocation.

### Designers (3 lanes; one holds the rotating Devil's-advocate seat)
- **Purpose:** act as invested senior designers/stakeholders; GDD-faithful code review and gameplay analysis using appropriate skills.
- **Cadence:** one turn / 15 min; batch-review proposals every 2 h.
- **Inputs:** GDD, worker diffs, research briefs, bead acceptance criteria.
- **Outputs:** review notes on beads; ranked `swarm/proposals/consensus-<UTC>.md`. Approval = 2 of 3 with distinct written objections resolved; the Devil's advocate must file ≥1 objection per batch or the batch is void. Each proposal cites GDD file+line, names a rejected alternative, and states a falsifiable acceptance test. On disagreement the GDD wins; if the GDD is silent, park in `questions.md`. Proposals only — the Orchestrator files beads (≤8 new/day, ≤5 per batch).
- **Done/stop:** deadline or `HALT`.

### Researchers (2 lanes)
- **Purpose:** delegate deep investigations into comparable mechanics, thematically similar stories, and assets/art styles fitting "clear, easy to read, accessible", plus topics they surface.
- **Cadence:** one turn / 30 min; ≤2 deep reports/day each; ≤3 open topics.
- **Inputs:** GDD, designer questions, prior reports.
- **Outputs:** `swarm/research/<topic>.md`, then a **jointly written ≤1-page `brief.md`** for the Designers, ending in 0–3 bead candidates in `bd` schema (title, rationale, GDD ref, acceptance test, size).
- **Done/stop:** deadline or `HALT`. A report with no candidate bead within one cycle is archived, not re-summarised.

### Postmortem (one turn per incident, Qwen)
- **Purpose:** diagnose from evidence — logs, exit codes, verdicts, journals — not introspection.
- **Cadence:** on Orchestrator stop.
- **Inputs:** incident file, gateway logs, ledger, Orchestrator **and** Designer **and** Researcher journals.
- **Outputs:** `swarm/incidents/<n>.md`; versioned prompt patches `prompts/<role>.vN.md` + diff bead. May edit prompt text and propose `config.toml` diffs only; never `immutable.md`, never guardrails.
- **Done/stop:** one patch set per incident; applied only at restart.

## Shared files

| Path | Writer | Readers |
|---|---|---|
| `harness/data/snapshots/<UTC>/` — `repo.bundle` (`--all`), `beads.json` (`bd export`), `raw/`, untracked harness config, GDD, `AGENTS.md`, `MANIFEST.md`, `RESTORE.md`; tag `pre-swarm-<UTC>` | Supervisor, once | all |
| `swarm/config.toml`, `prompts/immutable.md` | user / Supervisor | all |
| `swarm/roster.jsonl`, `ledger.jsonl`, `metrics.md` | Supervisor | Auditor, Postmortem |
| `swarm/orchestrator/state.md`, `journal.jsonl` | Orchestrator | Auditor, Postmortem |
| `swarm/audit/<UTC>.json` + `.md` | Auditor | Orchestrator, Postmortem |
| `swarm/proposals/*`, `swarm/research/*` | Designers / Researchers | Orchestrator / Designers |
| `swarm/questions.md`, `swarm/reports/<UTC>.md`, `HALTED.md` | any | user |

**Snapshot gate:** clone the bundle to a temp dir, import beads, run both suites; record results in `MANIFEST.md`. Do not start the swarm until this passes. **Restore is human-only.**

## Audit pass/fail definition

Checks are Python, on the window since the last audit, scoped to `HX_SWARM_ID`:
- **FAIL:** ≥1 gateway entry with a `swarm_id` and model ≠ `hx/nous/qwen4-max`; any spend >$0; Orchestrator heartbeat >30 min stale; >2 failed merges/hour; integration branch red.
- **WARN:** no leak, but any lane heartbeat >20 min stale, zero progress events in 90 min, 429/timeout rate >20%, or daily ceiling exceeded.
- **PASS:** none of the above and ≥1 bead progressed.

**Streak:** 2 consecutive FAILs. Any PASS resets it; WARN never counts. User Claude Code activity is reported separately and never affects the verdict.

**Orchestrator self-check on any alert:** re-read the last 50 gateway entries for its `swarm_id`, verify the model field, verify each worktree heartbeat, verify both suites still run. Report numbers, not opinions.

## Failure and recovery loop

1. **Alert (WARN or first FAIL):** Orchestrator runs the self-check, re-confirms its spawn config, writes a remediation note, continues.
2. **2 consecutive FAILs:** Orchestrator stops — finish current turn, SIGTERM descendants, leave worktrees/branches intact, commit WIP to `swarm/wip/*`, push (never force), write `HALTED.md` and `incidents/<n>.md`, exit. Designers and Researchers keep running.
3. Supervisor invokes **Postmortem**, which reviews all three role families and emits versioned prompt patches.
4. Supervisor restarts the Orchestrator with the new prompt version. **Max 3 restarts per rolling 24 h.**
5. **Full stop** on the 4th restart, any guardrail breach, or Qwen unavailable >15 min: write `swarm/reports/<UTC>.md`, open a `bd` issue labelled `needs-human`, append to `questions.md`. No auto-restart.

## How we measure improvement

Write `swarm/metrics.md` hourly and summarise daily: beads closed and merged green; integration-green streak; turns per closed bead; no-progress-turn fraction; audit reds and restarts; % turns on meta-work (≤20); free tokens consumed vs pace; harness tests added; GDD-consistency notes.

Prompt/harness changes count as improvement **only** if an A/B (20 turns old vs 20 new on comparable beads) improves turns-per-bead or no-progress fraction while integration stays green. Regression → revert to the prior version.

## Open questions for the user

1. Confirm the gateway virtual key name and that `max_budget: 0` is set before launch.
2. Is 6 concurrent Qwen turns acceptable against unpublished rate limits, or start at 4?
3. Confirm the integration branch name and that pushing `swarm/*` to origin is desired.
4. Approve the daily token ceiling pacing, or specify a hard daily cap.
5. Any GDD areas off-limits for gameplay proposals during these 4 days?