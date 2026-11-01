# harness/ — Simple War agent harness

Client-agnostic tooling for agent work on this repo: telemetry, cheap tools, delegation, benchmarking, reflection.
Design and the reasons behind it: [DESIGN.md](DESIGN.md). Work items: `bd list -l harness`.

## Run
| Shell | Command |
|---|---|
| Git Bash / WSL | `harness/bin/hx <verb>` |
| PowerShell | `harness\bin\hx.ps1 <verb>` |
| cmd | `harness\bin\hx.cmd <verb>` |

The first run creates `harness/.venv` via uv. Every verb takes `--json` (machine-readable) and `-v` (show passing checks too). Exit code is 1 if any check FAILs.

## Verbs
| Verb | Does |
|---|---|
| `status` | Branch, dirty files, last commit, Godot version, autoloads, main-scene sanity, ready/in-progress tasks. `--no-tasks` skips bd. |
| `doctor` | Toolchain (git, uv, bd, rtk, Godot), checks `harness/data/` is git-ignored, scans committable files for API keys. |
| `report` | Spend (API-price estimate), tokens, cache hit, cost per closed task, friction, agent-vs-waiting time, and tables by day, model, task, tool and command. `--since 7d\|24h\|all\|YYYY-MM-DD` (default 7d). `--html` writes `data/reports/report.html`; `--open` also opens it. |
| `bench` | Benchmark ladder (DESIGN.md §8). `bench list`; `bench run --target bonsai [--level L1,L2] [--task 'L1-*-s'] [--context 0,8k,32k] [--repeat N]`; `bench report [--by target,level,size]`. Targets live in `config/bench_targets.toml`. |
| `providers` | The provider roster from `config/providers.toml`: readiness, monthly budget (default $0 with hard stop), free-tier limits, whether the free tier trains on your data. `--checklist` prints setup steps for providers that aren't ready. |
| `secrets` | `secrets set NAME` stores an API key in Windows Credential Manager (hidden prompt; `--file` stores it in `~/.hx/secrets.env`; `--stdin` reads it from a pipe). `secrets list` shows where each key comes from, never the value. `secrets delete NAME`. Lookup order: environment variable, then keyring, then file. |
| `gateway` | Local LiteLLM gateway on `127.0.0.1:4000/v1`.<br>• `start` / `stop` / `status` (usage per provider today, the month's spend, refusals, and whether calls are currently allowed).<br>• `config` regenerates `data/gateway/litellm.yaml` from `config/providers.toml`.<br>• `discover <provider> [--free]` lists a provider's models so you can fill in its `models` entries.<br>Clients authenticate with the `HX_GATEWAY_KEY` stored in the keystore. Models are served as `<provider>/<alias>`, e.g. `bonsai/nothink`. Over-budget or over-quota calls get a 429 with the reason. |
| `bonsai` | Local Bonsai llama-server.<br>• `start [--ctx N]`, `stop`, `status` (VRAM). Flags come from `[provider.bonsai.server]` in `providers.toml`; `--agent` is refused.<br>• `probe [--sizes 200k,…] [--apply]` loads each size, fills about 90% of it, and picks the largest context that keeps at least 95% of peak generation speed. Results go to `data/bonsai/probe-*.json`. |
| `delegate` | Hand a task to the cheapest model `config/routing.toml` trusts with it (DESIGN.md §7).<br>• `delegate --level L1 --class csv_to_json [--size s\|m\|l] [--input FILE] "task"` (or the prompt on stdin).<br>• Lookup order: the exact route; then the same class at a larger size; then any model that is `auto` on every route of the level. The size is guessed from the prompt length when omitted.<br>• Candidates are tried in order. A down local model is started when about 11 GB of VRAM is free; gateway 429s and errors fall through to the next candidate.<br>• Output: the model's text goes to stdout and a status line to stderr. Exit 2 = **escalate** (no trusted model; do it yourself). A `review` route prints `REVIEW IT`.<br>• `--agent` runs headless OpenCode on the first routed model it can drive; it edits the working tree.<br>• Each call is logged without its text to `data/raw/delegate/`. |
| `mcp` | Stdio MCP server exposing the `delegate` tool. Registered for Claude Code in the repo's `.mcp.json`. |
| `worker` | Background job queue (SQLite `data/worker/queue.sqlite`) and Bonsai lifecycle.<br>• `enqueue <kind> [--payload JSON] [--hook]`, `start`, `stop`, `status`, `run [--once]`.<br>• Jobs: `ingest`; `session_end` runs ingest and then any follow-up kinds.<br>• Local jobs start Bonsai only when about 11 GB of VRAM is free. Bonsai is stopped after 10 idle minutes, but only if the worker started it.<br>• `hx delegate` holds a lock that pauses local jobs.<br>• Fed by the Claude Code SessionEnd hook and the OpenCode plugin `.opencode/plugins/hx.js`. |
| `tag` | Session tags (DESIGN.md §3; taxonomy in `config/taxonomy.toml`).<br>• `tag <session_id> [--force]`, `tag --untagged [--limit N]`, `tag --report` (counts, friction by kind, tagger-vs-audit agreement).<br>• The tagger is routed through `hx delegate` (L3/session_kind, so Bonsai). It reads the human prompts, the final reply and ledger stats.<br>• Friction is computed from tool errors, denials, interrupts and compactions.<br>• A deterministic 10% of sessions is re-tagged by Sonnet as an audit.<br>• Rows go to `data/raw/tags/`. The worker tags each finished Claude Code session. |
| `mine` | Repetitive-task mining (DESIGN.md §5).<br>• `mine` lists repeated command shapes (e.g. `git add && git commit && git push`; `cd`, pipes and single read commands are dropped) seen in at least 3 sessions and 5 uses.<br>• `mine --file` files new shapes as bd tasks labelled `mined`, at most 3 per run, with a verb name proposed by the local model.<br>• `mine --report` shows uses and tokens per hx verb, plus each mined shape's baseline cost.<br>• The worker runs it after sessions, at most every 6 h. State is in `data/mining/state.json`. |
| `reflect` | Weekly reflection, proposals only (DESIGN.md §9).<br>• `reflect --evidence` prints the week's evidence pack.<br>• `reflect [--dry-run]` has Sonnet propose at most 5 changes citing that evidence. They are filtered (evidence, area, duplicates, money) and filed as bd tasks labelled `reflection`.<br>• The worker runs it at most every 7 days. Runs are kept in `data/raw/reflection/`. |
| `task` | The tracker interface (DESIGN.md §10), an adapter over bd today.<br>• `ready` (epics hidden), `show <id>`, `claim <id>`, `close <id> [--reason]`, `new "title" [-d] [-p] [-t] [-l] [--parent]`, `note <id> "text"`. |
| `godot` | `check [--no-import]`: headless import plus a GDScript parse of every script under `src/`. Prints errors only, with locations, deduplicated.<br>`test [--dir res://test]`: GUT headless; prints the summary and failures. |
| `ingest` | Copies new Claude Code transcripts and exports changed OpenCode sessions (session tables only) to `data/raw/`, then loads them into the DuckDB ledger (`data/ledger.duckdb`). Incremental. `--rebuild` re-reads all raw copies, e.g. after a schema change. |

## Live monitoring (wired in `.claude/settings.json`)
- **Status line:** `bin/statusline` runs `python -m hx.statusline`, about 210 ms. Example:
  `Opus 5.5 · 5h 42% ↺14:20 · 7d 18% ↺Thu · ctx 34% · sess $1.20 · today $8.45 · $1.12/task`.
  - Quota windows appear only on Pro, Max or Ultra plans, after the session's first response. `⚠ full ~HH:MM` means the current burn rate hits 100% before the window resets.
  - Each refresh appends a quota snapshot to `data/raw/quota/claude-pro.jsonl` (only when the value changed, or every 5 min). `today $` comes from `data/cache/summary.json` and gets a `?` when that cache is older than 6 h.
  - The status line never opens the ledger.
- **Stop hook:** runs `hx ingest` asynchronously after every turn, so the ledger and the summary cache stay current.

## Benchmark suite (`bench/`)
- **Tasks:** `bench/tasks/<level>/*.json` hold suite v1, 20 tasks, generated by `hx.bench.fixtures` from a fixed seed and then frozen.
  - L1: CSV→JSON, JSON→Markdown table, rename/drop keys and filter/sort, each in sizes s, m and l.
  - L2: attack entries filled in to `bench/schemas/attack.schema.json`.
  - L3: Godot log triage, session-kind tagging, and classifying commands as read-only or mutating.
- **Checking:** purely mechanical (exact JSON, table rows, sets, label accuracy, schema plus fields). No LLM judge.
- **Context padding:** `--context` pads the prompt with a frozen GDD copy (`bench/filler/gdd.txt`) up to roughly N tokens.
- **Results:** appended to `data/raw/bench/<run_id>.jsonl`, including the full model output.
- **Report:** pass rate per group, with a routing verdict: `auto` at ≥ 90%, `review` at ≥ 70%, otherwise `no`.
- **Routing:** `hx bench route [--write]` builds `config/routing.toml` from all results for the current suite. Per (task class, size), it picks the cheapest tier whose pass rate is `auto` (local, then free api/client, then subscription); ties go to the higher pass rate, then the faster target. Only ctx-0 runs count toward the rate; context sweeps set `max_ctx_passed`. The file is generated: re-run the ladder and regenerate instead of editing it.
- **Changing the suite:** never edit task files. Bump `SUITE_VERSION` and run `hx bench build --force`; a test fails if the frozen files drift from the generator.
- **Haiku target:** uses the `claude` CLI on your subscription. It needs `claude auth login` once in a terminal.

## Ledger
`data/ledger.duckdb` is derived; the raw copies under `data/raw/<client>/` are the durable record.
Tables:
- `session`
- `call`: one row per model response, deduped by message id, with tokens and `est_usd`
- `tool_use` and `tool_result`
- `event`: prompt, interrupt, api_error, turn, compaction
- `session_task`: linked from `bd update <id> --claim` and `bd close <id>` commands
- `quota_snapshot`
- `import_state`

View: `session_summary`.

Prices live in `config/prices.toml`; every ingest re-prices all calls, so editing prices needs no rebuild. To query the ledger directly: `uv run --project harness python -c "import duckdb; print(duckdb.connect('harness/data/ledger.duckdb', read_only=True).sql('select * from session_summary'))"`.

## Layout
```
bin/            shims (bash, cmd, ps1)
src/hx/cli.py   verb dispatcher; add a verb = add hx/commands/<verb>.py + list it in VERBS
src/hx/output.py Result/Check contract: compact text by default, JSON with --json
tests/          pytest (run: uv run --project harness pytest)
data/           ledger + raw transcripts (git-ignored)
```

## Adding a verb
1. Create `src/hx/commands/<verb>.py` with `HELP`, optional `add_args(parser)`, and `run(args) -> Result`.
2. Add it to `VERBS` in `cli.py`.
3. Add a test in `tests/`.

Keep the default output short: agents pay for every line. Hide passing checks unless `-v` is given.

Mark a known-fake key in a fixture with `hx-allow-secret` on the same line, so the scan skips it.
