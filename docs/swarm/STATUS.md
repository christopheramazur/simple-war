# Swarm status

Updated 2026-11-22 06:44 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 48, craft-researcher: 12, games-researcher: 13, lead-designer: 14, orchestrator: 72, retro: 1, tech-lead: 9, ux-art-director: 11 |
| Worker turns / research turns (24 h) | 18 / 4 |
| Workers queued / running / awaiting review | sw-vld / sw-ll4.27.6 / - |
| Merged / rejected (all time) | 18 / 0 |
| Gateway calls last hour (rate-limited) | 37 (28) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-22 06:29 UTC **WARN** (rules) |

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

### 11-22 06:29 UTC **WARN** (rules)

20 swarm calls (16 rate-limited), all nous/qwen4-max, cost 0 USD | health: 16/20 calls rate-limited (80%)

### 11-22 05:59 UTC **WARN** (rules)

20 swarm calls (13 rate-limited), all nous/qwen4-max, cost 0 USD | health: 13/20 calls rate-limited (65%)

### 11-22 05:29 UTC **WARN** (rules)

27 swarm calls (19 rate-limited), all nous/qwen4-max, cost 0 USD | health: 19/27 calls rate-limited (70%)

### 11-22 02:49 UTC **WARN** (auditor)

Compliance clean: 21 gateway calls all nous/qwen4-max (orchestrator 10, craft-researcher 8, ux-art-director 2, auditor 1), 45/45 model banners clean, cost 0 USD, no hx delegate or Claude activity. But 52% of calls rate-limited (11/21; orchestrator 7/10 were 429s) and the ux-art-director turn was killed rc -9 at 3600s. Orchestrator alive and effective: 2 spawns at 02:41 (sw-ll4.27.6 running, sw-vld queued) after sw-ll4.27.3 merged 01:18 (~85 min ago), ending the long merge stall. WARN for 429 pressure plus worker timeout, not FAIL: work is moving again. Recommend throttling research roles to cut 429s and letting sw-ll4.27.6 finish.

### 11-22 01:49 UTC **WARN** (auditor)

WARN - compliance clean: 21 gateway calls in the 01:13-01:43 window all nous/qwen4-max (ux-art-director 14, games-researcher 4, orchestrator 2, auditor 1), 48/48 log banners clean, cost 0 USD, no hx delegate, no Claude Code. Progress: sw-ll4.27.3 merged 01:18 (18 total), ending the 4.5 h merge drought since 20:42. Health poor: 57% rate-limited (12/21; last hour 24/40 = 60%), both turns that ended in the window were killed rc -9 at 3600s (games-researcher 01:18, orchestrator 01:20 two minutes after its merge), and the worker pipeline is now empty (none queued/running/awaiting review). Orchestrator is alive (2 calls after the kill, status page fresh 01:39). Not FAIL: a merge landed and the orchestrator is running. Recommend: spawn the next worker immediately, pause or throttle research roles (ux-art-director burned 9 of 14 calls on 429s) to free gateway capacity, and journal early each turn.

