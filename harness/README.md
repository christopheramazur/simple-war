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
| `ingest` | Copies new Claude Code transcripts to `data/raw/` and loads them into the DuckDB ledger (`data/ledger.duckdb`). Incremental. `--rebuild` re-reads all raw copies, e.g. after a schema change. |

## Live monitoring (wired in `.claude/settings.json`)
- **Status line:** `bin/statusline` runs `python -m hx.statusline`, about 210 ms. Example:
  `Opus 5.5 · 5h 42% ↺14:20 · 7d 18% ↺Thu · ctx 34% · sess $1.20 · today $8.45 · $1.12/task`.
  - Quota windows appear only on Pro, Max or Ultra plans, after the session's first response. `⚠ full ~HH:MM` means the current burn rate hits 100% before the window resets.
  - Each refresh appends a quota snapshot to `data/raw/quota/claude-pro.jsonl` (only when the value changed, or every 5 min). `today $` comes from `data/cache/summary.json` and gets a `?` when that cache is older than 6 h.
  - The status line never opens the ledger.
- **Stop hook:** runs `hx ingest` asynchronously after every turn, so the ledger and the summary cache stay current.

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
