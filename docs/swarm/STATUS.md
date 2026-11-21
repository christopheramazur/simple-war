# Swarm status

Updated 2026-11-21 05:17 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 19, craft-researcher: 6, games-researcher: 7, lead-designer: 9, orchestrator: 18, tech-lead: 5, ux-art-director: 5 |
| Worker turns / research turns (24 h) | 9 / 7 |
| Workers queued / running / awaiting review | - / sw-p70 / sw-uyv |
| Merged / rejected (all time) | 3 / 0 |
| Gateway calls last hour (rate-limited) | 94 (12) |
| Incidents | 0 postmortem(s) |

## Last audits
- 2026-11-21T01:26:46+00:00 **PASS** Window 00:54-01:24 UTC. Compliance clean: 40 swarm gateway calls, all nous/qwen4-max (31 success, 9 Nous 429 = 22%), 1,404,997 prompt + 34,117 completion tokens, $0.00 cost for every caller; 39 swarm log banners all nous/qwen4-max; no swarm
- 2026-11-21T02:03:12+00:00 **PASS** Window 01:30-02:00 UTC: 56 gateway calls, all nous/qwen4-max (48 success, 8 Nous 429 = 14%), 1,516,168 prompt + 31,126 completion tokens, cost $0.00 for every caller; 87 swarm log banners all nous/qwen4-max; no hx delegate or Claude activit
- 2026-11-21T03:51:56+00:00 **PASS** Window 03:17-03:47 UTC: compliance clean - 59 gateway calls all nous/qwen4-max (46 success, 13 Nous 429 = 22%), 1,443,082 prompt + 41,770 completion tokens, cost $0.00 for every caller; 60 swarm log banners all nous/qwen4-max; no hx delegat
- 2026-11-21T04:28:44+00:00 **PASS** Window 03:56-04:26 UTC: compliance clean - 42 gateway calls all nous/qwen4-max (37 success, 5 Nous 429 = 12%), 1,314,770 prompt + 32,601 completion tokens, cost $0.00 every caller; 92 swarm log banners all nous/qwen4-max; no hx delegate or 
- 2026-11-21T05:09:05+00:00 **WARN** Window 04:33-05:03 UTC. Compliance clean: 54 gateway calls all nous/qwen4-max (44 success, 10 Nous 429 = 19%), 1,728,925 prompt + 40,077 completion tokens, /usr/bin/bash.00 cost every caller; 97 swarm log banners all nous/qwen4-max; no hx d

## Recently merged
- sw-aty (2026-11-20T13:49)
- sw-ll4.1.1 (2026-11-21T01:07)
- sw-ll4.1.2 (2026-11-21T02:06)
