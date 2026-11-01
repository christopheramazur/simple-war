# Simple War Agent Harness — Design Record

Settled 2026-10-31 in a design-tree interview (Q1–Q44). This file is the record of *what was decided and why*.
Change it by proposal (reflection loop or human), not silently.

## 0. Goals
1. Track task, duration, model, token spend (and further metrics as they surface).
2. Turn repetitive tasks into cheap tool calls.
3. Reduce tokens via output encoding/compression.
4. Benchmark local Bonsai 2 27B as a subagent — *what complexity of task can be handed off*, not speed.
5. Model/provider-agnostic continual harness improvement (reflection loop).

Order of work (Q5): telemetry → seed tools → gateway/providers → encoding A/B → Bonsai ladder → worker/tagging → reflection → AGENTS.md rewrite.
Scope (Q7/Q17): a thin slice of every goal first, then back to game work; the harness improves in the background.

## 1. Shape
| Decision | Choice | Ref |
|---|---|---|
| Clients | Client-agnostic: Claude Code, OpenCode, Codex, Antigravity CLI, any OpenAI-compatible endpoint. Thin adapter per client. | Q1 |
| Location | Top-level `harness/`, self-contained, extractable to its own repo. Game-specific helpers stay in `scripts/`. | Q2 |
| Language | Python via `uv` (PEP 723 inline deps), thin `.ps1`/`.cmd` shims. Go only if hook latency is measured as a problem. | Q12 |
| Entry point | One CLI: `hx <verb>`. Compact output by default, `--json` on every verb. | Q12, Q40 |
| Host | Windows-native. Agents use Git Bash. WSL/Docker only for sandboxes (L5 bench) and optional services (Phoenix). | Q27, Q32 |
| Tests | pytest for `hx` (importers, budgets, adapter contracts); runs before every auto-merge. | Q41 |

## 2. Telemetry
- **Ledger (Q11):** append-only DuckDB at `harness/data/ledger.duckdb`, plus raw source copies in `harness/data/raw/` (gitignored). Importers are re-runnable; the schema can evolve.
  Core tables: `session`, `call`, `tool_use`, `task_tag`, `quota_snapshot`, `job`.
- **Sources:**
  - Claude Code transcript JSONL importer + backfill of all existing history (Q20a); dedupe by `message.id`.
  - Claude Code OpenTelemetry → small Python OTLP receiver in `hx` (Q20b), right after the importer. No double counting.
  - OpenCode session importer (Q37).
  - LiteLLM gateway logs (Q19).
- **Retention (Q44):** keep everything indefinitely. User-level `cleanupPeriodDays` = 3650. The importer copies raw transcripts on import.
- **Unit of work (Q3):** a tracker task (`bead_id`). Untagged sessions are still aggregated and auto-tagged (Q13).
- **Spend (Q4):** tokens (input/output/cache read/cache write) plus an API-price USD estimate from a local price table. Local runs record wall time.
- **Metrics (Q39):** cache hit rate; tool-output size per tool/command; friction (retries, tool errors, denials, interrupts, compactions); human-wait vs agent-work time; outcome rate and cost per completed task; delegation acceptance rate; quota burn projection.
- **Views (Q21):** `hx report` (CLI) and `hx report --html` (static dashboard, no server). Phoenix (WSL/Docker) later, if trace drill-down is needed.
- **Status line:** Claude Pro 5-hour and weekly usage (`rate_limits.*`), cost per completed task, quota burn, unpushed auto-merges, advisory model hint (Q42).
- **Reports use local time (UTC+10).**

- *OpenCode importer (sw-lbm.7):* OpenCode 2.x keeps sessions in SQLite (`~/.local/share/opencode/opencode.db`; override with `HX_OPENCODE_DB`).
  - `hx ingest` exports each changed session (only `session_v2` and `session_message`; the DB also holds account tokens and credentials) to `data/raw/opencode/<id>.jsonl`, then parses it into the same ledger tables.
  - Calls OpenCode sent through our gateway get `source = 'opencode-gateway'`. The gateway logs them too (client `gateway`), so totals count them twice until the report dedupes (sw-lbm.23).
  - Tagging and mining read OpenCode sessions as well.

## 3. Session tagging (Q13)
Taxonomy, versioned in `harness/config/taxonomy.toml`:
- **kind**: feature / bugfix / refactor / content-data / research / harness / ops / chat
- **area**: free text, mapped to GDD systems where possible
- **complexity**: 1–5
- **outcome**: completed / partial / abandoned / blocked
- **friction**: computed, not judged

Tagged after each session by Bonsai, with confidence. *Built (sw-lbm.17):*
- The worker's `tag_session` job runs after every `session_end`.
- The digest holds up to 6 human prompts (600 characters each), the end of the final reply, and ledger stats.
- Friction is the share of tool calls that errored or were denied, plus 0.1 per interrupt and 0.05 per API error or compaction.
- The audit uses `claude-sonnet-5-5`, picked by a hash of the session id. Tags are raw rows in `data/raw/tags/`; join them to the ledger on session_id.
- First backfill: 18 sessions, 0 invalid. On the 2 audit pairs, kind and complexity agree but outcome does not: on one-word smoke sessions Bonsai says `abandoned` where Sonnet says `completed` or `blocked`.
 A random 10% is re-tagged by a stronger model to measure tagger accuracy (this doubles as a benchmark task). The reflection loop may propose new tags.

## 4. Gateway, providers, budgets
- **Hybrid capture (Q19):** Claude Code on the Pro subscription talks to Anthropic directly; Anthropic's terms allow a proxy only for your own Claude Code traffic, so we keep it out. Everything else goes through a native LiteLLM gateway (uv, no Docker, no Postgres), which logs into the ledger via OTel or a custom-logger callback.
- **Client-only free models (Q37):** OpenCode Zen free models (and possibly Antigravity CLI) can't be reached through the gateway. They are delegation targets run via headless OpenCode, tracked from imported data rather than enforced up front.
- **Config (Q30):** `harness/config/providers.toml`, one entry per provider:
  - `monthly_budget_usd`: default 0
  - `hard_stop`: default true
  - `billing`: default `"unknown"`. LiteLLM prices free-tier calls at list price, so on 2026-11-01 one Gemini call was recorded as $0.0025 and tripped the $0 hard stop. Only an account with no payment method (`billing = "none"`, set by the user) records that price as `list_usd` instead of spend.
  - `enabled`: false keeps a provider on the roster but skips it everywhere. Mistral is disabled because Experiment-tier keys are no longer issued.
  - `alert_at`: e.g. 50/80/100%
  - free-tier RPM/RPD/TPD limits and reset timezone
  - `trains_on_data` flag
  The gateway enforces these before each call: an over-budget or over-quota provider gets an HTTP 429 that names the limit.
  - *Built (sw-lbm.10):* fallback is done by the **caller** (`hx delegate`), not LiteLLM. LiteLLM's pre-call hook only sees the first model of a fallback chain, so per-provider enforcement would be bypassed.
  - The caller moves to the next ladder-passing model on a 429.
  - LiteLLM 1.106.6 is pinned, run via `uvx` on Python 3.14 with no database.
  - Calls are logged raw to `data/raw/gateway/`.
  - Port 4000 requires a locally generated `HX_GATEWAY_KEY`.
- **Roster (Q24/Q37):**
  | Provider | Notes |
  |---|---|
  | Claude Pro | Tracked, not enforced |
  | Bonsai (local) | |
  | OpenRouter | Free models; one-time $10 for 1,000 requests/day. The unlock counts lifetime purchases. |
  | Gemini API free tier | |
  | Groq | |
  | Mistral | Experiment plan |
  | Cloudflare Workers AI | |
  | OpenCode Zen free models | |
  | Antigravity CLI | Quota to be checked |
  Dropped: GitHub Models (retired), Cerebras (trial only), Qwen Code (free tier reportedly shut down). NVIDIA NIM is unclear.
- **Policy (Q16):** one account per provider; stay within published limits; back off on 429; no key rotation to dodge limits.
- **Secrets (Q31):** Windows Credential Manager via `keyring`; fallback `%USERPROFILE%\.hx\secrets.env` for WSL and containers. Never in the repo; `hx doctor` scans for committed keys. The user creates accounts and pastes keys (checklist provided).

## 5. Repetitive tasks → tools
- **Seed verbs (Q40):** `hx status`, `hx godot check`, `hx godot test`, `hx task`, `hx report`, `hx delegate`, `hx bench`, `hx worker`, `hx doctor`.
- **Mining (Q26):** transcripts from all projects plus OpenCode history, mined frequently by the local model as a post-session worker job (not monthly). Candidates are filed as tasks; use and tokens saved are measured per verb.
  - *Built (sw-lbm.18):* `hx mine` groups ledger shell commands into shapes. Wrappers are read through (`uv run pytest`). The verbs come from the ledger, so all Claude Code projects are covered; OpenCode follows with sw-lbm.7.
  - Thresholds: at least 3 sessions and 5 uses. Filing: at most 3 per run, at most every 6 h, deduplicated by shape.
  - Savings: each filed shape keeps its tokens per use as a baseline, to compare with the verb's tokens per use in `hx mine --report`.
  - First run (2026-11-01): no shape yet meets the 3-session bar. Only 2 sessions have real shell activity, and the top shape is `uv run pytest` with 17 uses in 1 session.

## 6. Encoding (Q27)
- **rtk** command-line tool only (Apache-2.0; not the BUSL proxy). Hook for Claude Code and OpenCode.
- rtk only rewrites the Bash tool, so agents use Git Bash by default; PowerShell only for Windows-only operations wrapped by `hx`.
- **A/B:** compression on/off randomized per session, recorded in the ledger. Keep if it saves ≥20% of tool-output tokens without more retries.

## 7. Local model and delegation
- **Bonsai 2 27B** (PQ2_0 ternary, llama.cpp PrismML CUDA build, `:8080`) on an RTX 3060 12 GB.
- **Agent loop (Q23):** OpenCode drives Bonsai's tool use (`--jinja` tool calls). llama-server `--agent` is off for benchmark and delegate runs; fine for web-UI chat.
- **Delegation:** `hx delegate --level Ln --task …`, as a CLI and an MCP tool, routed through the gateway.
  - *Built (sw-lbm.15):* reads `config/routing.toml`. Lookup goes exact route → same class at a larger size → targets `auto` on every route of the level.
  - Candidates go through the gateway; the Claude subscription goes through `claude -p`. Fallback to the next candidate happens on a local model that can't start, a 429, or an error.
  - Nothing usable gives exit code 2 (escalate). A `review` verdict flags the output for checking.
  - `--agent` uses headless OpenCode, limited to models in `opencode.json`. The MCP tool is the stdlib `hx mcp` server (`.mcp.json`).
  - Raw call records without prompt or output go to `data/raw/delegate/`; ledger ingest is not done yet.
- **Lifecycle (Q33):** `hx worker` starts Bonsai on demand when about 11 GB of VRAM is free and stops it after 10 idle minutes. Jobs are queued in the ledger from client hooks (Claude Code SessionEnd/Stop, an OpenCode plugin). `hx delegate` calls jump the queue.
- *Worker as built (sw-lbm.16):*
  - The queue is SQLite (`data/worker/queue.sqlite`), not the ledger: DuckDB locks its file across processes.
  - Jobs retry 3 times. Jobs left running by a killed worker are recovered, and pending jobs are deduplicated per session.
  - Bonsai is stopped on idle only if the worker started it. `hx delegate` holds `data/worker/delegate.lock` so local jobs wait.
  - Hook enqueue costs about 480 ms, mostly hx startup (`uv run python` alone is 170 ms). The hook is async, so it's acceptable.
- *OpenCode 2.2 findings:*
  - Plugins are `export default { id, setup(api) }`. `api.event.subscribe({})` is an async iterable; its `types` filter delivered nothing.
  - A turn ends with `session.execution.succeeded`/`failed`.
  - `opencode run` attaches to the desktop app's background service by default, which uses that service's environment and working directory. `hx delegate --agent` uses `--standalone` and passes `HX_GATEWAY_KEY`.
  - The desktop app itself can't use the `hx` provider until `HX_GATEWAY_KEY` is in its environment.
- **Context (Q18c):** 200k may not fit (estimated 10.4 GiB). The benchmark finds the best context size for the VRAM that's free.
  - *Measured (sw-lbm.12, `hx bonsai probe`):* every size up to 200k loads and fills on the RTX 3060.
  - Short-prompt generation speed is 34.5 t/s up to 128k, then 31.1 at 160k and 25.2 at 200k. Generation on a short prompt shouldn't depend on context size, so the drop means the driver is spilling into shared memory.
  - Chosen: **128k**. It runs at full speed, uses 10.4 GB with others' usage included, and leaves about 1.8 GB of headroom.
  - `hx bonsai start` launches llama-server directly from `providers.toml`, never with `--agent`.
- **OpenCode:** the desktop app's bundled CLI is v2.2.0. The project `opencode.json` routes OpenCode through the gateway as provider `hx`, with models `hx/bonsai/nothink` and `hx/bonsai/think`. The key comes from `HX_GATEWAY_KEY`, and force-push and history rewrites are denied. Verified end to end: a headless `opencode run --auto` created a file through a tool call, with every model call logged by the gateway.

## 8. Benchmark ladder (Q9/Q15/Q25/Q34)
| Level | Class | Checker |
|---|---|---|
| L1 | Reformat / transform | Exact diff |
| L2 | Schema data-fill (GDD-derived models) | Schema validation + rules |
| L3 | Summarize / classify / tag | Agreement with strong-model labels |
| L4 | GDScript from spec / template | `--check-only` + GUT |
| L5 | Multi-step repo edit with tools | Tests pass + diff stays in scope (sandboxed) |

- Each level runs across output sizes and context sizes (8k / 32k / 128k / max-fit), with thinking on and off, against Haiku as baseline.
- **Every roster model** runs the same ladder.
- **Routing table:** for each task class, the cheapest model that passes. Order: local → free → subscription, with quota headroom as the tie-break. ≥90% pass = automatic handoff; 70–90% = draft plus review by a stronger model. Time and VRAM are logged, not decisive.
- **First ladder (2026-11-01, suite v1, sw-lbm.14):** Haiku passes 20/20. Bonsai no-think (3 runs) is `auto` on 17 of 20 and holds through 96k of context padding on every small task.
  - Bonsai fails: filter_sort m (0/3; it miscounts) and l, and json_to_table l (scores 0.994, one row off).
  - Thinking mode is worse on large outputs: it runs into the 16k output cap on csv_to_json l and rename_drop m/l, and on command_mutates. It rescues only filter_sort m (n=1).
  - So `config/routing.toml` sends 18 routes to Bonsai (17 no-think, 1 think) and filter_sort l and json_to_table l to Haiku. Only 4 targets are tested so far; free-tier APIs are untested until their keys exist (sw-lbm.21).
- **Free-tier ladder (2026-11-01):**
  - OpenRouter `nemotron-3-ultra-550b:free` passes 19/20. It solves filter_sort m and l, which Bonsai fails, and misses only json_to_table l (149/161 rows). L1 large outputs are slow, about 3–4 min.
  - filter_sort l now routes to OpenRouter; only json_to_table l still goes to Haiku.
  - After the user confirmed no card on Gemini, Groq or Cloudflare (`billing = "none"`), full ladders ran. Pass rates exclude gate refusals:
    - Cloudflare gpt-oss-120b: 21/21
    - Gemini 3.5 Flash: 19/20
    - Groq gpt-oss-120b: 17/18, with output capped at 6k by its 8k TPM free tier, so the large tasks can't fit
  - Every route now has a free model; Haiku remains a fallback candidate only. filter_sort l and json_to_table l go to Gemini.
  - Bench calls retry upstream 429s that carry a "try again in Xs" hint.
  - Routing ignores gate refusals and connection errors: they say nothing about the model.
- **Fixtures:** frozen in `harness/bench/`, sourced from:
  - GD-Agentic-Skills `.gd` files (held-out functions, L4)
  - GDD plus schemas (L2)
  - ledger transcripts (L3)
  - synthetic repos (L5)
- **Model advice (Q42):** the routing table also suggests which Claude model the main session should use. Advisory only.

## 9. Reflection and autonomy
- **Engine (Q29):** our own continual loop modelled on harness2's propose → probe → compose. It reads the ledger and transcripts, finds friction, and proposes changes. The thin slice is proposals only, filed as tasks, weekly.
- *Built (sw-lbm.19):* `hx reflect`, plus a worker job that runs at most every 7 days.
  - **Evidence** is mechanical: spend by client and provider with billing status, failing tools and command shapes, events, sessions by kind, high-friction sessions, tag-audit agreement, delegate fallbacks, gateway failures, unfiled mining shapes.
  - **Propose:** Sonnet, through `claude -p`, gives at most 5 proposals, each citing evidence keys.
  - **Probe** rejects a proposal that cites no evidence, falls outside the allowed areas, duplicates an open task (title word overlap ≥ 0.6), or asks for money or deletion. Negated mentions are allowed.
  - **Compose:** bd tasks labelled `reflection`. The full run is kept in `data/raw/reflection/`.
  - First run (2026-11-01) filed 4 tasks: PowerShell-safe verbs (OpenCode's shell tool failed 79/403), skipping Bonsai early when VRAM is short, compaction checkpoints, and failing fast on web tools.
- **Auto-apply (Q8/Q14), once the eval set exists:**
  1. Change made on an `auto/*` branch.
  2. pytest plus the ladder must pass with no score drop, within the change's token budget.
  3. Auto-merge, with a daily summary to the user.
  4. Auto-revert if live metrics regress over the next N sessions.
- **Agent freedom (Q35/Q38):** agents are broadly free to change things; push to `origin` is allowed; no force-push or history rewrite. Restrictions get added later only if needed.
- **Always needs user approval (Q38):**
  - raising any budget above its cap or otherwise spending money
  - deleting ledger or tracker history
  - publishing or posting externally
  - the loop editing this approval list

## 10. Task tracking (Q10/Q22)
- **beads** (`bd`, target ≥1.3.2), fresh database, embedded mode. Accessed only via `hx task ready|show|claim|close|new`, so the tracker can be swapped (td, Backlog.md) by replacing one adapter.
- Switch to beads' server mode only if parallel agents actually hit write contention.

## 11. Repo housekeeping
- AGENTS.md is canonical and was rewritten once monitoring was live (sw-lbm.20); `CLAUDE.md` is just `@AGENTS.md` (Q28). The bd-generated blocks keep their markers so `bd setup` can maintain them.
- The Godot-rules distillation now lives at `GD-Agentic-Skills/godot-skill-distillation.md` (restored by the user). Its integration is a deferred game-side task.
- Godot binary is 4.7.2; docs should match.
- `project.godot` main scene points at the removed `src/ui/main_menu.tscn`; that's a game-side task.

## 12. Open facts to verify during build
- Antigravity CLI free quota.
- Groq free-tier limits and training policy.
- Whether LiteLLM's custom-logger callback is in the open-source edition (OTel callback is a known-good fallback).
- Python hook latency on Windows (decides whether hooks are written in Go).
- Bonsai's best context size on 12 GB.
