# Swarm status

Updated 2026-11-21 12:35 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 30, craft-researcher: 8, games-researcher: 9, lead-designer: 11, orchestrator: 42, tech-lead: 6, ux-art-director: 8 |
| Worker turns / research turns (24 h) | 19 / 10 |
| Workers queued / running / awaiting review | sw-ll4.27.4 / sw-ll4.27.1 / - |
| Merged / rejected (all time) | 11 / 1 |
| Gateway calls last hour (rate-limited) | 257 (0) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 12:26 UTC **PASS** ([report](audits/20261121-1225.md)) |

## Recently merged
- sw-uyv (2026-11-21T05:27)
- sw-p70 (2026-11-21T05:42)
- sw-ll4.26.1 (2026-11-21T07:07)
- sw-ll4.26.2 (2026-11-21T10:54)
- sw-ijp.5 (2026-11-21T11:29)
- sw-0nl (2026-11-21T11:43)
- sw-1jy.3 (2026-11-21T12:04)
- sw-1jy.5 (2026-11-21T12:33)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 12:26 UTC **PASS** ([report](audits/20261121-1225.md))

PASS — compliance clean: 139 gateway calls in the 30-min window, all nous/qwen4-max (orchestrator 64, sw-1jy.5 40, sw-1jy.3 13, craft-researcher 12, bench 9, ux-art-director 1), ~9.47M prompt + 127.5k completion tokens, cost 0 USD, 0 rate-limited, 199 model banners all qwen4-max, zero turn failures. Health good: sw-1jy.3 merged 12:04 (10 total), sw-1jy.5 running since 11:45 (58k completion tokens), sw-ll4.27.1 queued 12:18, orchestrator active (journal commit 12:21Z). External non-swarm activity noted, not charged to the swarm: 9 hx delegate calls (all qwen4-max L3) and one Claude Code session (85 turns, 60k output tokens) — user-side; no evidence ties them to the swarm.

### 11-21 11:54 UTC **PASS** ([report](audits/20261121-1153.md))

PASS: window 11:23-11:53 UTC, 69 gateway calls all nous/qwen4-max (orchestrator 34, worker sw-1jy.3 23, ux-art-director 7, sw-0nl 5), 2.37M prompt and 58.8k completion tokens, cost 0 USD, 0 rate-limited, 76/76 banners clean, no delegate or Claude activity. Two merges in window (sw-ijp.5 11:29, sw-0nl 11:43 via att3 mechanical resolution; 9 total), zero turn failures; sw-1jy.3 running since 11:44, sw-1jy.5 queued. Prior merge-drought WARN conditions resolved; compliant and making progress.

### 11-21 11:22 UTC **PASS** ([report](audits/20261121-1120.md))

PASS — 10:50-11:20 window: 163 gateway calls, all nous/qwen4-max (168 log banners clean), ~7.64M tokens, cost 0 USD, 0 rate-limited, no hx delegate or Claude activity, zero turn failures. sw-ll4.26.2 merged 10:54 after the forecast-isolation fix gated green, ending the ~3h47m merge drought that drove three health WARNs. sw-0nl attempt 2 merge conflict was triaged before attempt 3 spawned at 11:01 (journal 3240a73), not a blind respawn; sw-ijp.5 running productively (47k completion tokens). Orchestrator active: 77 calls, 7 turns, 2 spawns, 1 merge, research done. Health recovered; returning to PASS.

### 11-21 10:49 UTC **WARN** ([report](audits/20261121-1049.md))

Audit 10:19-10:49 UTC: compliance clean - 126 gateway calls all nous/qwen4-max (116 success, 10 rate-limited failures, ~8% 429s), 176 log banners all qwen4-max, cost 0 USD, no delegate/Claude activity, zero turn failures. WARN on health: merge gap 07:07->10:49 ~3h42m with workers running exceeds the standing 2h clause; another merge_red this window. Positives: orchestrator root-caused the red gates (journal c213b2f), sw-0nl finished and attempt 2 queued 10:44, research active. Recommend: review/merge sw-0nl attempt-1 output promptly - a merge returns PASS.

### 11-21 10:10 UTC **WARN** ([report](audits/20261121-1002.md))

WARN (health, 2nd consecutive): compliance clean — 36 gateway calls in the 09:32-10:02 window, all nous/qwen4-max (29 success, 7 rate-limited 429s = 19%), cost 0 USD, 67 model banners clean, no delegate or Claude activity, zero turn failures. Health poor: no merge since 07:07 (sw-ll4.26.1), gap now ~2h55m while sw-0nl runs productively (18.0k completion tokens this window), past the standing 2h clause. A second merge_red event landed this window after the 09:21 sw-ll4.26.2 WIP gate failure — orchestrator must root-cause the red gate, not re-run it blindly. Not an idle loop: orchestrator active (7 calls, recovered from its 09:11 timeout), research queued, worker mid-task. Return to PASS once a merge lands and the red gate is triaged.

