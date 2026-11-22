# Swarm status

Updated 2026-11-22 01:24 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 45, craft-researcher: 11, games-researcher: 13, lead-designer: 14, orchestrator: 70, retro: 1, tech-lead: 9, ux-art-director: 10 |
| Worker turns / research turns (24 h) | 23 / 5 |
| Workers queued / running / awaiting review | - / - / - |
| Merged / rejected (all time) | 18 / 0 |
| Gateway calls last hour (rate-limited) | 42 (25) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-22 01:13 UTC **WARN** |

## Recently merged
- sw-1jy.5 (2026-11-21T12:33)
- sw-ll4.27.1 (2026-11-21T13:00)
- sw-ll4.27.4 (2026-11-21T13:19)
- sw-ll4.27.2 (2026-11-21T13:40)
- sw-1jy.4 (2026-11-21T13:50)
- sw-luo (2026-11-21T14:26)
- sw-opt (2026-11-21T20:42)
- sw-ll4.27.3 (2026-11-22T01:18)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-22 01:13 UTC **WARN**

auditor recorded no verdict

### 11-21 23:51 UTC **WARN** ([report](audits/20261121-2346.md))

WARN - compliance clean: 21 gateway calls in 23:16-23:46 window, all nous/qwen4-max (orchestrator 10, lead-designer 8, craft-researcher 2, auditor 1), 48/48 log banners clean, cost 0 USD, no delegate or Claude activity, ~188.7k tokens. Health poor: 13/21 calls rate-limited (62%; last hour 26/41), craft-researcher turn killed rc -9 at 3601s, zero spawn/merge/reject in window, no merge since sw-opt at 20:42 (~3 h). sw-ll4.27.3 partial at attempt 4 since 21:08, the recurring journal-conflict bead, past its 2 h cap. Orchestrator alive (2 successful calls, status page fresh 23:39) and the worker is awaiting review, not idle, so WARN not FAIL. Recommend: resolve the sw-ll4.27.3 worker.md journal conflict by hand and merge it first, one merge per turn, journal immediately; throttle or pause research roles to free gateway capacity. If next window still has zero merges with sw-ll4.27.3 stuck, escalate to FAIL for loop-without-effect.

### 11-21 22:58 UTC **WARN**

Compliance clean: 21 gateway calls in window all nous/qwen4-max (craft-researcher 16, worker sw-ll4.27.3 2, auditor/orchestrator/tech-lead 1 each), 40 log banners all nous/qwen4-max, cost 0 USD, no hx delegate, no Claude activity. Health poor: 12/21 calls rate-limited (57 percent), both turns in window failed (orchestrator rc 1 at 1860s, tech-lead killed rc -9 at 3600s), zero merges in window (last merge sw-opt at 20:42, about 2h ago), worker sw-ll4.27.3 partial at attempt 4 since 21:08. Orchestrator is alive (successful call in window) and the worker is active, and a merge landed at 20:42 ending the long drought, so WARN not FAIL. Recommend throttling craft-researcher (10 of its 16 calls were 429s) and merging sw-ll4.27.3 review as the next orchestrator priority.

### 11-21 22:16 UTC **WARN**

auditor recorded no verdict

### 11-21 21:01 UTC **WARN**

WARN (throttle only, recovery underway) 20:26-20:56Z: 21 gateway calls all nous/qwen4-max (orchestrator 10, games-researcher 10, auditor 1), 23 log banners all nous/qwen4-max, cost 0 USD, no delegate or Claude activity, 0 turn failures. 12/21 calls rate-limited = 57% (25/41 = 61% last hour), above the ~40% WARN line; games-researcher took 7 of 10 as 429s. Progress resumed: sw-opt merged 20:42, first merge since 14:26 (17 total); orchestrator alive with 6 successful calls and no killed turn this window. Backlog: sw-ll4.27.3 att3 partial since 14:33, 6+ h awaiting review; no workers running or queued. Recommend: merge .3 att3 next turn, then spawn from ready beads; space out games-researcher calls.

