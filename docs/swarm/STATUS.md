# Swarm status

Updated 2026-11-21 17:07 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 36, craft-researcher: 9, games-researcher: 11, lead-designer: 12, orchestrator: 63, tech-lead: 8, ux-art-director: 9 |
| Worker turns / research turns (24 h) | 24 / 9 |
| Workers queued / running / awaiting review | - / - / sw-ll4.27.3, sw-opt |
| Merged / rejected (all time) | 16 / 0 |
| Gateway calls last hour (rate-limited) | 41 (29) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 17:05 UTC **WARN** |

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

### 11-21 17:05 UTC **WARN**

WARN - compliance clean: all 20 gateway calls in the 16:26-16:56 window are nous/qwen4-max (orchestrator 9, lead-designer 11), 23 log banners clean, cost 0 USD, no hx delegate and no Claude activity. Health is poor: 13 of 20 calls rate-limited (65 percent, above the ~40 percent threshold; status page shows 33 of 40 in the last hour), zero swarm events in the window (no spawn/merge/reject), and no merge since sw-luo at 14:26 - 2.5 hours ago, 16 total. Workers sw-ll4.27.3 (3 attempts) and sw-opt (1 attempt) have sat partial/awaiting-review since ~14:30, past the 2 h worker cap; .3 has been stuck on a journal-only worker.md conflict since attempt 2. Orchestrator is alive (5 successful calls, ~136k tokens) and turn_failures is empty, so this is not a FAIL. Recommend mechanically resolving the .3 journal conflict (precedent: sw-ijp.5 att3) and reviewing sw-opt now, and pacing calls while Nous throttles. Prior audit 16:26 was WARN; conditions persist.

### 11-21 16:26 UTC **WARN**

auditor recorded no verdict

### 11-21 15:26 UTC **WARN**

auditor recorded no verdict

### 11-21 14:34 UTC **PASS** ([report](audits/20261121-1434.md))

PASS for 14:04-14:34Z: 162 gateway calls, all nous/qwen4-max (orchestrator 71, worker sw-ll4.27.3 39, ux-art-director 16, worker sw-luo 15, craft-researcher 14, worker sw-opt 7 incl 1 failed call that did not fail its turn), ~7.93M prompt + 146k completion tokens, cost 0 USD, 0 rate-limited, 219 model banners all clean, no hx delegate or Claude activity. Health: 1 merge (sw-luo accessibility audit, 16 total), 3 spawns, 3 worker_done, 0 turn failures. sw-ll4.27.3 now at attempt 3 with 0 rejects all-time; checking orchestrator triage before judging it a loop, but spawns and merges show work is moving.

### 11-21 14:03 UTC **PASS** ([report](audits/20261121-1402.md))

PASS - 125 gateway calls in the 13:32-14:02 window, all nous/qwen4-max across 6 swarm callers (orchestrator 52, sw-ll4.27.3 41, sw-1jy.4 18, research 8, lead-designer 4, sw-ll4.27.2 2), about 7.1M tokens (6.98M prompt / 128k completion), cost 0 USD, 0 rate-limited, 182 model banners all qwen4-max, no hx delegate or Claude activity, zero turn failures. Two merges in window (sw-ll4.27.2 13:40, sw-1jy.4 13:50; 15 total), sw-ll4.27.3 running since 13:41 with 41 productive calls, sw-luo queued for the next slot, orchestrator active and pre-writing briefs. Compliant and making progress.

