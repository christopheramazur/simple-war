# Swarm status

Updated 2026-11-21 15:06 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 34, craft-researcher: 9, games-researcher: 10, lead-designer: 12, orchestrator: 61, tech-lead: 7, ux-art-director: 9 |
| Worker turns / research turns (24 h) | 24 / 10 |
| Workers queued / running / awaiting review | - / sw-ll4.27.3 / sw-opt |
| Merged / rejected (all time) | 16 / 0 |
| Gateway calls last hour (rate-limited) | 224 (15) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 14:34 UTC **PASS** ([report](audits/20261121-1434.md)) |

## Recently merged
- sw-0nl (2026-11-21T11:43)
- sw-1jy.3 (2026-11-21T12:04)
- sw-1jy.5 (2026-11-21T12:33)
- sw-ll4.27.1 (2026-11-21T13:00)
- sw-ll4.27.4 (2026-11-21T13:19)
- sw-ll4.27.2 (2026-11-21T13:40)
- sw-1jy.4 (2026-11-21T13:50)
- sw-luo (2026-11-21T14:26)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 14:34 UTC **PASS** ([report](audits/20261121-1434.md))

PASS for 14:04-14:34Z: 162 gateway calls, all nous/qwen4-max (orchestrator 71, worker sw-ll4.27.3 39, ux-art-director 16, worker sw-luo 15, craft-researcher 14, worker sw-opt 7 incl 1 failed call that did not fail its turn), ~7.93M prompt + 146k completion tokens, cost 0 USD, 0 rate-limited, 219 model banners all clean, no hx delegate or Claude activity. Health: 1 merge (sw-luo accessibility audit, 16 total), 3 spawns, 3 worker_done, 0 turn failures. sw-ll4.27.3 now at attempt 3 with 0 rejects all-time; checking orchestrator triage before judging it a loop, but spawns and merges show work is moving.

### 11-21 14:03 UTC **PASS** ([report](audits/20261121-1402.md))

PASS - 125 gateway calls in the 13:32-14:02 window, all nous/qwen4-max across 6 swarm callers (orchestrator 52, sw-ll4.27.3 41, sw-1jy.4 18, research 8, lead-designer 4, sw-ll4.27.2 2), about 7.1M tokens (6.98M prompt / 128k completion), cost 0 USD, 0 rate-limited, 182 model banners all qwen4-max, no hx delegate or Claude activity, zero turn failures. Two merges in window (sw-ll4.27.2 13:40, sw-1jy.4 13:50; 15 total), sw-ll4.27.3 running since 13:41 with 41 productive calls, sw-luo queued for the next slot, orchestrator active and pre-writing briefs. Compliant and making progress.

### 11-21 13:31 UTC **PASS** ([report](audits/20261121-1330.md))

PASS 13:00-13:30Z: 140 gateway calls all nous/qwen4-max (orchestrator 67, sw-ll4.27.2 35, sw-ll4.27.4 16, games-researcher 14, lead-designer 8), ~6.92M prompt + 141k completion tokens, cost 0 USD, 0 rate-limited, 181 banners clean, no delegate/Claude activity, zero turn failures. Progress: sw-ll4.27.4 merged 13:19 (13 total), sw-ll4.27.2 running since 13:01 with early commit c3bd324 pre-reviewed green, sw-1jy.4 fresh respawn queued 13:21 as planned (not a blind retry). One recovered gateway call failure on sw-ll4.27.2, no turn impact.

### 11-21 12:59 UTC **PASS** ([report](audits/20261121-1257.md))

PASS — compliance clean: 166 gateway calls in the 12:27-12:57Z window all nous/qwen4-max (orchestrator 76, sw-ll4.27.1 60, tech-lead 14, sw-ll4.27.4 13, sw-1jy.5 3), 217 log banners all qwen4-max, cost 0 USD, 0 rate-limited, no delegate or Claude activity, zero turn failures. Progress: sw-1jy.5 merged 12:33 (11 total), sw-ll4.27.1 done in about 35 min and in orchestrator pre-review, sw-ll4.27.4 running with 10.3k completion tokens; 1 spawn, 1 merge, 2 worker_done in window. No stall, no merge drought.

### 11-21 12:26 UTC **PASS** ([report](audits/20261121-1225.md))

PASS — compliance clean: 139 gateway calls in the 30-min window, all nous/qwen4-max (orchestrator 64, sw-1jy.5 40, sw-1jy.3 13, craft-researcher 12, bench 9, ux-art-director 1), ~9.47M prompt + 127.5k completion tokens, cost 0 USD, 0 rate-limited, 199 model banners all qwen4-max, zero turn failures. Health good: sw-1jy.3 merged 12:04 (10 total), sw-1jy.5 running since 11:45 (58k completion tokens), sw-ll4.27.1 queued 12:18, orchestrator active (journal commit 12:21Z). External non-swarm activity noted, not charged to the swarm: 9 hx delegate calls (all qwen4-max L3) and one Claude Code session (85 turns, 60k output tokens) — user-side; no evidence ties them to the swarm.

