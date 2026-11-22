# Qwen swarm (`hx swarm`)

An autonomous team of Qwen4 Max agents (free on Nous Portal, from 2026-11-20) that works the beads backlog, reviews its own output and researches direction. Brief: [brief/original.md](brief/original.md) (the user's words), [brief/improved.md](brief/improved.md) (Qwen's three-lens rewrite, merged). Live output: [docs/swarm/STATUS.md](../../docs/swarm/STATUS.md).

## How it runs
Claude Code sessions cannot run on Qwen, so every role is a **headless OpenCode turn** (`opencode run --standalone --auto -m hx/nous/qwen4-max`) through the local gateway. A detached Python supervisor (`hx swarm run`, started by `hx swarm start`) re-runs each role on its cadence and carries memory in files.

| Role | Cadence | Prompt | Writes |
|---|---|---|---|
| Orchestrator | continuous (90 s pause) | `roles/orchestrator.md` | spawns workers, merges, closes beads |
| Workers (≤2) | when queued | `roles/worker.md` | commits on `swarm/<bead>` in `../simple-war-worktrees/<bead>` |
| Auditor | the verdict every 30 min by rules (no model); the model only to escalate, confirm a FAIL, or every 4 h, outside the turn slots | `roles/auditor.md` | a PASS/WARN/FAIL verdict; `docs/swarm/audits/` when the model runs |
| Designers ×3 | each ~45 min | `roles/designer.md` + persona | answers, reviews, votes, `swarm-proposed` beads |
| Researchers ×2 | each ~60 min | `roles/researcher.md` + persona | agenda, summaries, proposals |
| Deep research | when queued (≤3) | `roles/deep-researcher.md` | `docs/swarm/research/reports/` |
| Postmortem | after 2 FAILs in a row | `roles/postmortem.md` | incident diagnosis, prompt edits |
| Retro | every 12 h | `roles/retro.md` | `docs/swarm/retros/`, prompt and cadence tweaks |

Every prompt is `roles/_common.md` (hard rules) + the role file + generated context (inbox, journal tail, status). The supervisor saves each turn's exact prompt and output under `harness/data/swarm/logs/<role>/`.

## Qwen-only, enforced three ways
1. `opencode.json` here lists only `hx/nous/qwen4-max` and denies `claude`, `opencode` and `hx delegate` in the shell.
2. The gateway refuses any non-Qwen model for a request whose `x-hx-caller` header starts with `swarm` (OpenCode sends `swarm-<role>`), and logs the caller on every call.
3. `hx delegate` refuses to run when `HX_SWARM` is set (the supervisor sets it for every turn).
The auditor checks the evidence anyway; `hx swarm merge` refuses branches that touch these guardrail files.

## Audit and recovery
**Pipeline steps without a model** (sw-0zi.3): the orchestrator's turns start on new mail (a worker finished, an alert, an answer) or an hourly heartbeat, not on a timer. `hx swarm merge` closes the bead when the merge lands. Once a minute the supervisor spawns the top ready bead if a worker slot sat empty for 10 min (skipping epics, parents with open children, `needs-human`, `swarm-harness` and the design interviews), and merges a `done` worker nobody reviewed within 90 min through the same gate, labelling it `swarm-unreviewed`. Settings in `swarm.toml` `[orchestrator]` and `[workers]`.

**When Nous throttles** (sw-0zi.2): the gateway paces Nous call starts (AIMD, `hx/gateway/pacer.py`) and gives each free start to the waiting call in the best lane: the user's own tools, then workers and postmortems, the orchestrator, deep research, designers, researchers and the retro, then the auditor. A waiting call moves up a lane every 3 min, so nothing starves. While over 40% of the last hour's swarm calls were rate-limited, or fewer than 30 succeeded, the supervisor holds support turns (designers, researchers, research, retro) until the share is under 25% again (`throttle_on` / `throttle_off` events; thresholds in `swarm.toml` `[run]`).

The supervisor computes the verdict every 30 min from counts (`rule_verdict` in `swarm.py`, sw-0zi.4): FAIL = a non-Qwen model or money used by the swarm, or the orchestrator silent or spinning; WARN = something the orchestrator can act on (a finished worker waiting for review, a worker past its limit, repeated `merge_red`) or poor health it can't fix (throttling, failed turns), which is only shown on STATUS.md. FAIL mails the orchestrator, which must run `hx swarm selfcheck` and record an audit response; an actionable WARN mails it the list to act on. The model auditor runs only for a FAIL, to confirm a previous FAIL, for an actionable WARN (at most hourly) or every 4 h; it can raise the verdict, never lower it, and a killed model turn leaves the rules' verdict standing. Two FAILs in a row: the orchestrator pauses, an incident file and a `bd human` bead are written, a Qwen postmortem edits the prompts (orchestrator, designers, researchers), and generation N+1 starts. A fourth postmortem within 24 h stops the swarm for the user.

## Merging
`hx swarm merge <bead>` merges `main` into the worker branch, runs `hx godot test` (and harness pytest when `harness/` changed) in the worktree, and fast-forwards `main` only when green, then pushes. `main` never goes red from the swarm.

## Operate
```bash
harness/bin/hx swarm start      # detached; survives this shell
harness/bin/hx swarm status     # rewrites and prints docs/swarm/STATUS.md
harness/bin/hx swarm stop       # writes STOP; running turns are ended (workers keep WIP and resume on the next start), the supervisor exits, leftovers are killed
```
Cadence and limits: `swarm.toml` (the run ends at `run.end_at`). The running supervisor reloads it on save, with no restart: a `config_reloaded` event lists the changed keys, and a file that does not parse is ignored (`config_error`). Restore point from before the run: `../simple-war-snapshots/2026-11-20-pre-qwen-swarm/RESTORE.md` and the git tag `snapshot/2026-11-20-pre-qwen-swarm`.
