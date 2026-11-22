# Swarm status

Updated 2026-11-22 02:40 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 46, craft-researcher: 11, games-researcher: 13, lead-designer: 14, orchestrator: 70, retro: 1, tech-lead: 9, ux-art-director: 11 |
| Worker turns / research turns (24 h) | 22 / 5 |
| Workers queued / running / awaiting review | - / - / - |
| Merged / rejected (all time) | 18 / 0 |
| Gateway calls last hour (rate-limited) | 41 (26) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-22 01:49 UTC **WARN** |

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

### 11-22 01:49 UTC **WARN**

WARN - compliance clean: 21 gateway calls in the 01:13-01:43 window all nous/qwen4-max (ux-art-director 14, games-researcher 4, orchestrator 2, auditor 1), 48/48 log banners clean, cost 0 USD, no hx delegate, no Claude Code. Progress: sw-ll4.27.3 merged 01:18 (18 total), ending the 4.5 h merge drought since 20:42. Health poor: 57% rate-limited (12/21; last hour 24/40 = 60%), both turns that ended in the window were killed rc -9 at 3600s (games-researcher 01:18, orchestrator 01:20 two minutes after its merge), and the worker pipeline is now empty (none queued/running/awaiting review). Orchestrator is alive (2 calls after the kill, status page fresh 01:39). Not FAIL: a merge landed and the orchestrator is running. Recommend: spawn the next worker immediately, pause or throttle research roles (ux-art-director burned 9 of 14 calls on 429s) to free gateway capacity, and journal early each turn.

### 11-22 01:13 UTC **WARN**

auditor recorded no verdict

### 11-21 23:51 UTC **WARN** ([report](audits/20261121-2346.md))

WARN - compliance clean: 21 gateway calls in 23:16-23:46 window, all nous/qwen4-max (orchestrator 10, lead-designer 8, craft-researcher 2, auditor 1), 48/48 log banners clean, cost 0 USD, no delegate or Claude activity, ~188.7k tokens. Health poor: 13/21 calls rate-limited (62%; last hour 26/41), craft-researcher turn killed rc -9 at 3601s, zero spawn/merge/reject in window, no merge since sw-opt at 20:42 (~3 h). sw-ll4.27.3 partial at attempt 4 since 21:08, the recurring journal-conflict bead, past its 2 h cap. Orchestrator alive (2 successful calls, status page fresh 23:39) and the worker is awaiting review, not idle, so WARN not FAIL. Recommend: resolve the sw-ll4.27.3 worker.md journal conflict by hand and merge it first, one merge per turn, journal immediately; throttle or pause research roles to free gateway capacity. If next window still has zero merges with sw-ll4.27.3 stuck, escalate to FAIL for loop-without-effect.

### 11-21 22:58 UTC **WARN**

Compliance clean: 21 gateway calls in window all nous/qwen4-max (craft-researcher 16, worker sw-ll4.27.3 2, auditor/orchestrator/tech-lead 1 each), 40 log banners all nous/qwen4-max, cost 0 USD, no hx delegate, no Claude activity. Health poor: 12/21 calls rate-limited (57 percent), both turns in window failed (orchestrator rc 1 at 1860s, tech-lead killed rc -9 at 3600s), zero merges in window (last merge sw-opt at 20:42, about 2h ago), worker sw-ll4.27.3 partial at attempt 4 since 21:08. Orchestrator is alive (successful call in window) and the worker is active, and a merge landed at 20:42 ending the long drought, so WARN not FAIL. Recommend throttling craft-researcher (10 of its 16 calls were 429s) and merging sw-ll4.27.3 review as the next orchestrator priority.

### 11-21 22:16 UTC **WARN**

auditor recorded no verdict

