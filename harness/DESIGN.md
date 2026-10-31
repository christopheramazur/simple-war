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

## 3. Session tagging (Q13)
Taxonomy, versioned in `harness/config/taxonomy.toml`:
- **kind**: feature / bugfix / refactor / content-data / research / harness / ops / chat
- **area**: free text, mapped to GDD systems where possible
- **complexity**: 1–5
- **outcome**: completed / partial / abandoned / blocked
- **friction**: computed, not judged

Tagged after each session by Bonsai, with confidence. A random 10% is re-tagged by a stronger model to measure tagger accuracy (this doubles as a benchmark task). The reflection loop may propose new tags.

## 4. Gateway, providers, budgets
- **Hybrid capture (Q19):** Claude Code on the Pro subscription talks to Anthropic directly; Anthropic's terms allow a proxy only for your own Claude Code traffic, so we keep it out. Everything else goes through a native LiteLLM gateway (uv, no Docker, no Postgres), which logs into the ledger via OTel or a custom-logger callback.
- **Client-only free models (Q37):** OpenCode Zen free models (and possibly Antigravity CLI) can't be reached through the gateway. They are delegation targets run via headless OpenCode, tracked from imported data rather than enforced up front.
- **Config (Q30):** `harness/config/providers.toml`, one entry per provider:
  - `monthly_budget_usd`: default 0
  - `hard_stop`: default true
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

## 6. Encoding (Q27)
- **rtk** command-line tool only (Apache-2.0; not the BUSL proxy). Hook for Claude Code and OpenCode.
- rtk only rewrites the Bash tool, so agents use Git Bash by default; PowerShell only for Windows-only operations wrapped by `hx`.
- **A/B:** compression on/off randomized per session, recorded in the ledger. Keep if it saves ≥20% of tool-output tokens without more retries.

## 7. Local model and delegation
- **Bonsai 2 27B** (PQ2_0 ternary, llama.cpp PrismML CUDA build, `:8080`) on an RTX 3060 12 GB.
- **Agent loop (Q23):** OpenCode drives Bonsai's tool use (`--jinja` tool calls). llama-server `--agent` is off for benchmark and delegate runs; fine for web-UI chat.
- **Delegation:** `hx delegate --level Ln --task …`, as a CLI and an MCP tool, routed through the gateway.
- **Lifecycle (Q33):** `hx worker` starts Bonsai on demand when about 11 GB of VRAM is free and stops it after 10 idle minutes. Jobs are queued in the ledger from client hooks (Claude Code SessionEnd/Stop, an OpenCode plugin). `hx delegate` calls jump the queue.
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
- **Fixtures:** frozen in `harness/bench/`, sourced from:
  - GD-Agentic-Skills `.gd` files (held-out functions, L4)
  - GDD plus schemas (L2)
  - ledger transcripts (L3)
  - synthetic repos (L5)
- **Model advice (Q42):** the routing table also suggests which Claude model the main session should use. Advisory only.

## 9. Reflection and autonomy
- **Engine (Q29):** our own continual loop modelled on harness2's propose → probe → compose. It reads the ledger and transcripts, finds friction, and proposes changes. The thin slice is proposals only, filed as tasks, weekly.
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
