# Methodology review — "Simple War" 4-day free-token swarm

## Problems, most important first

1. **The audit can't fail correctly.** "Auditor discretion" plus a ledger that includes *your own* Claude Code sessions means either constant false alerts (you coding normally) or an auditor that rationalises everything. Attribution must be mechanical: tag every swarm-spawned process with a `swarm_id` and write `swarm_id, session_id, model, pid` to a roster file. Audit = Python diff of gateway `*.jsonl` models against the roster, not an LLM opinion. Non-swarm spend is reported, never alerted.

2. **Prompt-only model pinning will drift.** `hx delegate` routes to Bonsai/Gemini/Groq/OpenRouter/`claude -p`; OpenCode may fall back on 429. Enforce at the gateway: a dedicated LiteLLM virtual key whose `models` allowlist is exactly `hx/nous/qwen4-max`, `max_budget: 0` for anything priced. Every swarm process gets only that key. Fail-closed: if Qwen is unavailable, **halt**, never fall back.

3. **Shared checkout = corrupted main.** Worktree per worker (`swarm/wt/<bead-id>`), branch per bead, and exactly one *merger* role. Merge gate: `harness/bin/hx godot test` **and** `uv run --project harness pytest -q` green on the merged result, not the branch. No force-push, no history rewrite; snapshot first.

4. **No budgets, so day 1 eats days 2–4.** Unpublished rate limits + 5–35 s calls means concurrency is the scarce resource. Cap global in-flight turns (start 6), per-role turn budgets, per-turn wall clock (20 min) and tool-call count, exponential backoff with jitter on 429 (30 s → 8 min, cap), and a daily token ceiling that paces the 96 hours.

5. **Runaway loops with no progress signal.** A supervisor re-invoking turns forever will happily re-read the GDD 400 times. Define progress per turn: a bead state change, a commit, a merged PR, or a filed report. Three consecutive no-progress turns → park that session, write `blocked.md`, free the slot.

6. **Restart loop can itself loop.** "Fail → Qwen diagnoses → new orchestrator" has no ceiling. Cap at 3 restarts per 24 h; on the 4th, stop everything and write one human-readable incident report. Diagnosing a failure with the same model that caused it needs *evidence* (logs, exit codes), not introspection.

7. **Designers who all share one model rubber-stamp.** Consensus among identical Qwen sessions is correlated approval. Require: proposals cite file+line in the GDD, state a rejected alternative, and name a falsifiable acceptance test. Approval needs 2 of 3 *with distinct written objections resolved*; a standing "Devil's advocate" seat must file ≥1 objection per batch or the batch is void.

8. **Research that never becomes beads.** Reports are cheap; tasks are the output. Every report must end with 0–3 candidate beads in `bd` schema (title, rationale, GDD ref, acceptance test, size). Cap intake at 8 new beads/day so the 223-issue backlog doesn't become 900. Research without a bead within one cycle is archived, not re-summarised.

9. **"Self-improving" is unmeasured and can regress the harness.** Prompt edits to a *running* supervisor cause churn. Version prompts (`prompts/orchestrator.vN.md`), apply only at restart, and require an A/B: 20 turns old vs 20 new on comparable beads, judged on merges-green, turns-per-bead, no-progress rate. Regression → revert. Cap meta-work (harness + prompts) at **20% of turns**; the other 80% ships game.

10. **Human input blocks a 4-day unattended run.** No session may wait on you. Async `inbox/` with pre-authorised defaults; anything touching money, GDD scope, force-push, or deleting beads is *deferred*, not guessed.

## Rewritten text

**§0 Snapshot (verify it).**
Create tag `pre-swarm-2026-11-20`, `git bundle create harness/data/snapshots/repo.bundle --all`, `bd export > snapshots/beads.json`, copy `AGENTS.md` + GDD. Then *prove* restore: clone the bundle to a temp dir, import beads, run both test suites. Record results in `snapshots/MANIFEST.md`. Do not start the swarm until this passes.

**§1 Hard constraints (mechanical, not advisory).**
All swarm work uses the LiteLLM key `swarm-free` (allowlist: `hx/nous/qwen4-max` only, zero paid budget). Supervisor `hx swarm` launches every OpenCode turn with that key and env `HX_SWARM_ID`. Concurrency ≤6 turns; per-turn timeout 20 min; backoff on 429/5xx up to 8 min; halt-if-model-unavailable >15 min. Daily token ceiling = remaining_budget / remaining_days, recomputed hourly. No `hx delegate`, no `claude -p`, no network spend.

**§2 Roles (each a supervisor loop with file-carried state).**
1 orchestrator, 3 designer/reviewers, 2 researchers, 1 merger, N bead workers (worktrees). Every turn appends `{ts, role, session, model, tokens, progress_flag, artifacts}` to `swarm/ledger.jsonl`.

**§3 Audit, every 30 min, deterministic first.**
`hx swarm audit` (pure Python) checks: (a) any non-allowlisted model in gateway logs attributable to `HX_SWARM_ID`; (b) spend vs daily ceiling; (c) main's last commit passed both suites; (d) ≥1 progress event per role in 90 min; (e) restart count. Only on a red check does a Qwen turn write a diagnosis. Two consecutive red audits → orchestrator stops, writes `incidents/<n>.md`, and a Qwen delegate proposes a prompt patch. Max 3 restarts/24 h, then full stop + report.

**§4 Merge gate.**
Merger only. Rebase branch on main in its worktree, run `hx godot test` + harness pytest, merge `--no-ff`, re-run both on main. Red on main → `git revert` the merge immediately, reopen bead with logs. Never rewrite history.

**§5 Design/research cadence.**
Researchers: ≤2 deep reports/day each, each ending in ≤3 bead candidates. Designers: batch-review candidates every 2 h; 2-of-3 approval with recorded objections; ≤8 new beads/day. GDD edits require human sign-off — file to `inbox/` instead.

**§6 Success metrics (write hourly to `swarm/metrics.md`).**
Beads closed & merged green; main green streak; turns-per-closed-bead; no-progress-turn fraction; audit reds; restart count; % turns on meta-work (target ≤20); free tokens consumed vs pace; harness tests added. "Self-improvement" counts only if turns-per-bead or no-progress fraction improves in an A/B and main stays green.