# Swarm status

Updated 2026-11-20 20:18 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 8, craft-researcher: 3, games-researcher: 4, lead-designer: 4, orchestrator: 10, tech-lead: 3, ux-art-director: 3 |
| Worker turns / research turns (24 h) | 4 / 3 |
| Workers queued / running / awaiting review | - / - / - |
| Merged / rejected (all time) | 1 / 0 |
| Gateway calls last hour (rate-limited) | 50 (11) |
| Incidents | 0 postmortem(s) |

## Last audits
- 2026-11-20T16:45:05+00:00 **WARN** Window 16:01-16:31 UTC: compliance clean, health poor. 54 gateway calls, all nous/qwen4-max (47 success, 7 Nous 429 = 13% rate-limited, normal); 1,207,502 prompt + 12,976 completion tokens; cost $0.00 for every caller; 65 swarm log banners 
- 2026-11-20T17:31:40+00:00 **WARN** auditor recorded no verdict
- 2026-11-20T18:11:20+00:00 **WARN** Window 17:31-18:01 UTC (90-min cross-check 16:34-18:10): compliance clean. 30 min: 47 gateway calls, all nous/qwen4-max (40 success, 7 Nous 429 = 15%), 1,045,546 prompt + 17,080 completion tokens, cost $0.00 for every caller; 77 log banners
- 2026-11-20T18:49:35+00:00 **WARN** Window 18:14-18:44 UTC (90-min cross-check 17:15-18:45): compliance clean. 30 min: 44 gateway calls, all nous/qwen4-max (36 success, 8 Nous 429 = 18%), 1,277,900 prompt + 15,767 completion tokens, cost $0.00 for every caller; 57 log banners
- 2026-11-20T19:39:57+00:00 **WARN** Window 18:57-19:27 UTC (90-min cross-check 18:02-19:27): compliance clean. 30 min: 43 gateway calls, all nous/qwen4-max (35 success, 8 Nous 429 = 19%), 1,218,167 prompt + 26,564 completion tokens, cost $0.00 for every caller; 48 log banners

## Recently merged
- sw-aty (2026-11-20T13:49)
