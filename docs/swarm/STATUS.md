# Swarm status

Updated 2026-11-21 13:51 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 32, craft-researcher: 8, games-researcher: 10, lead-designer: 12, orchestrator: 51, tech-lead: 7, ux-art-director: 8 |
| Worker turns / research turns (24 h) | 21 / 11 |
| Workers queued / running / awaiting review | - / sw-ll4.27.3 / - |
| Merged / rejected (all time) | 15 / 0 |
| Gateway calls last hour (rate-limited) | 278 (0) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 13:31 UTC **PASS** ([report](audits/20261121-1330.md)) |

## Recently merged
- sw-ijp.5 (2026-11-21T11:29)
- sw-0nl (2026-11-21T11:43)
- sw-1jy.3 (2026-11-21T12:04)
- sw-1jy.5 (2026-11-21T12:33)
- sw-ll4.27.1 (2026-11-21T13:00)
- sw-ll4.27.4 (2026-11-21T13:19)
- sw-ll4.27.2 (2026-11-21T13:40)
- sw-1jy.4 (2026-11-21T13:50)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 13:31 UTC **PASS** ([report](audits/20261121-1330.md))

PASS 13:00-13:30Z: 140 gateway calls all nous/qwen4-max (orchestrator 67, sw-ll4.27.2 35, sw-ll4.27.4 16, games-researcher 14, lead-designer 8), ~6.92M prompt + 141k completion tokens, cost 0 USD, 0 rate-limited, 181 banners clean, no delegate/Claude activity, zero turn failures. Progress: sw-ll4.27.4 merged 13:19 (13 total), sw-ll4.27.2 running since 13:01 with early commit c3bd324 pre-reviewed green, sw-1jy.4 fresh respawn queued 13:21 as planned (not a blind retry). One recovered gateway call failure on sw-ll4.27.2, no turn impact.

### 11-21 12:59 UTC **PASS** ([report](audits/20261121-1257.md))

PASS — compliance clean: 166 gateway calls in the 12:27-12:57Z window all nous/qwen4-max (orchestrator 76, sw-ll4.27.1 60, tech-lead 14, sw-ll4.27.4 13, sw-1jy.5 3), 217 log banners all qwen4-max, cost 0 USD, 0 rate-limited, no delegate or Claude activity, zero turn failures. Progress: sw-1jy.5 merged 12:33 (11 total), sw-ll4.27.1 done in about 35 min and in orchestrator pre-review, sw-ll4.27.4 running with 10.3k completion tokens; 1 spawn, 1 merge, 2 worker_done in window. No stall, no merge drought.

### 11-21 12:26 UTC **PASS** ([report](audits/20261121-1225.md))

PASS — compliance clean: 139 gateway calls in the 30-min window, all nous/qwen4-max (orchestrator 64, sw-1jy.5 40, sw-1jy.3 13, craft-researcher 12, bench 9, ux-art-director 1), ~9.47M prompt + 127.5k completion tokens, cost 0 USD, 0 rate-limited, 199 model banners all qwen4-max, zero turn failures. Health good: sw-1jy.3 merged 12:04 (10 total), sw-1jy.5 running since 11:45 (58k completion tokens), sw-ll4.27.1 queued 12:18, orchestrator active (journal commit 12:21Z). External non-swarm activity noted, not charged to the swarm: 9 hx delegate calls (all qwen4-max L3) and one Claude Code session (85 turns, 60k output tokens) — user-side; no evidence ties them to the swarm.

### 11-21 11:54 UTC **PASS** ([report](audits/20261121-1153.md))

PASS: window 11:23-11:53 UTC, 69 gateway calls all nous/qwen4-max (orchestrator 34, worker sw-1jy.3 23, ux-art-director 7, sw-0nl 5), 2.37M prompt and 58.8k completion tokens, cost 0 USD, 0 rate-limited, 76/76 banners clean, no delegate or Claude activity. Two merges in window (sw-ijp.5 11:29, sw-0nl 11:43 via att3 mechanical resolution; 9 total), zero turn failures; sw-1jy.3 running since 11:44, sw-1jy.5 queued. Prior merge-drought WARN conditions resolved; compliant and making progress.

### 11-21 11:22 UTC **PASS** ([report](audits/20261121-1120.md))

PASS — 10:50-11:20 window: 163 gateway calls, all nous/qwen4-max (168 log banners clean), ~7.64M tokens, cost 0 USD, 0 rate-limited, no hx delegate or Claude activity, zero turn failures. sw-ll4.26.2 merged 10:54 after the forecast-isolation fix gated green, ending the ~3h47m merge drought that drove three health WARNs. sw-0nl attempt 2 merge conflict was triaged before attempt 3 spawned at 11:01 (journal 3240a73), not a blind respawn; sw-ijp.5 running productively (47k completion tokens). Orchestrator active: 77 calls, 7 turns, 2 spawns, 1 merge, research done. Health recovered; returning to PASS.

