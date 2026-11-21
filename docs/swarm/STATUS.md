# Swarm status

Updated 2026-11-21 23:24 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 43, craft-researcher: 11, games-researcher: 12, lead-designer: 13, orchestrator: 68, retro: 1, tech-lead: 9, ux-art-director: 10 |
| Worker turns / research turns (24 h) | 23 / 7 |
| Workers queued / running / awaiting review | - / - / sw-ll4.27.3 |
| Merged / rejected (all time) | 17 / 0 |
| Gateway calls last hour (rate-limited) | 40 (26) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 22:58 UTC **WARN** |

## Recently merged
- sw-1jy.3 (2026-11-21T12:04)
- sw-1jy.5 (2026-11-21T12:33)
- sw-ll4.27.1 (2026-11-21T13:00)
- sw-ll4.27.4 (2026-11-21T13:19)
- sw-ll4.27.2 (2026-11-21T13:40)
- sw-1jy.4 (2026-11-21T13:50)
- sw-luo (2026-11-21T14:26)
- sw-opt (2026-11-21T20:42)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 22:58 UTC **WARN**

Compliance clean: 21 gateway calls in window all nous/qwen4-max (craft-researcher 16, worker sw-ll4.27.3 2, auditor/orchestrator/tech-lead 1 each), 40 log banners all nous/qwen4-max, cost 0 USD, no hx delegate, no Claude activity. Health poor: 12/21 calls rate-limited (57 percent), both turns in window failed (orchestrator rc 1 at 1860s, tech-lead killed rc -9 at 3600s), zero merges in window (last merge sw-opt at 20:42, about 2h ago), worker sw-ll4.27.3 partial at attempt 4 since 21:08. Orchestrator is alive (successful call in window) and the worker is active, and a merge landed at 20:42 ending the long drought, so WARN not FAIL. Recommend throttling craft-researcher (10 of its 16 calls were 429s) and merging sw-ll4.27.3 review as the next orchestrator priority.

### 11-21 22:16 UTC **WARN**

auditor recorded no verdict

### 11-21 21:01 UTC **WARN**

WARN (throttle only, recovery underway) 20:26-20:56Z: 21 gateway calls all nous/qwen4-max (orchestrator 10, games-researcher 10, auditor 1), 23 log banners all nous/qwen4-max, cost 0 USD, no delegate or Claude activity, 0 turn failures. 12/21 calls rate-limited = 57% (25/41 = 61% last hour), above the ~40% WARN line; games-researcher took 7 of 10 as 429s. Progress resumed: sw-opt merged 20:42, first merge since 14:26 (17 total); orchestrator alive with 6 successful calls and no killed turn this window. Backlog: sw-ll4.27.3 att3 partial since 14:33, 6+ h awaiting review; no workers running or queued. Recommend: merge .3 att3 next turn, then spawn from ready beads; space out games-researcher calls.

### 11-21 19:58 UTC **WARN** ([report](audits/20261121-1956.md))

WARN — compliance clean: all 21 gateway calls nous/qwen4-max (ux-art-director 14, orchestrator 6, auditor 1), 32 banners clean, cost 0 USD, no delegate/Claude. Health poor: 15/21 calls rate-limited (71%), orchestrator turn killed rc -9 at 3600s, zero spawn/merge/reject events in window, no merge since 14:26 (5.5 h). Workers sw-opt and sw-ll4.27.3 stuck partial/awaiting-review 5+ h past cap. Orchestrator alive (2 successful calls) and workers awaiting review not idle, so WARN not FAIL. Recommend orchestrator merge the two awaiting-review workers before any new spawn, journal early, and diagnose why merges stall under 429 load.

### 11-21 19:22 UTC **WARN**

18:26-18:56 window: compliance clean - 21 gateway calls all nous/qwen4-max (swarm-retro 15, orchestrator 5, auditor 1), 21 log banners clean, cost 0 USD, no delegate or Claude activity, 0 turn failures. But health poor: 62% rate-limited (13/21 calls), zero swarm events, no merge since 14:26 (4.5 h) while both workers sit partial/awaiting-review far past their 2 h caps (sw-opt since 14:27, sw-ll4.27.3 since 14:33, 3 attempts). Orchestrator alive but barely productive (1 success call in window); a retro turn is running. Recommend orchestrator merge sw-opt and .3 att3 before anything else and journal early; WARN not FAIL because orchestrator turns exist and workers are awaiting review, not idle.

