# Swarm status

Updated 2026-11-21 11:20 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 27, craft-researcher: 7, games-researcher: 9, lead-designer: 11, orchestrator: 33, tech-lead: 6, ux-art-director: 7 |
| Worker turns / research turns (24 h) | 15 / 9 |
| Workers queued / running / awaiting review | sw-0nl / sw-ijp.5 / - |
| Merged / rejected (all time) | 7 / 0 |
| Gateway calls last hour (rate-limited) | 288 (10) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 10:49 UTC **WARN** ([report](audits/20261121-1049.md)) |

## Recently merged
- sw-aty (2026-11-20T13:49)
- sw-ll4.1.1 (2026-11-21T01:07)
- sw-ll4.1.2 (2026-11-21T02:06)
- sw-uyv (2026-11-21T05:27)
- sw-p70 (2026-11-21T05:42)
- sw-ll4.26.1 (2026-11-21T07:07)
- sw-ll4.26.2 (2026-11-21T10:54)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 10:49 UTC **WARN** ([report](audits/20261121-1049.md))

Audit 10:19-10:49 UTC: compliance clean - 126 gateway calls all nous/qwen4-max (116 success, 10 rate-limited failures, ~8% 429s), 176 log banners all qwen4-max, cost 0 USD, no delegate/Claude activity, zero turn failures. WARN on health: merge gap 07:07->10:49 ~3h42m with workers running exceeds the standing 2h clause; another merge_red this window. Positives: orchestrator root-caused the red gates (journal c213b2f), sw-0nl finished and attempt 2 queued 10:44, research active. Recommend: review/merge sw-0nl attempt-1 output promptly - a merge returns PASS.

### 11-21 10:10 UTC **WARN** ([report](audits/20261121-1002.md))

WARN (health, 2nd consecutive): compliance clean — 36 gateway calls in the 09:32-10:02 window, all nous/qwen4-max (29 success, 7 rate-limited 429s = 19%), cost 0 USD, 67 model banners clean, no delegate or Claude activity, zero turn failures. Health poor: no merge since 07:07 (sw-ll4.26.1), gap now ~2h55m while sw-0nl runs productively (18.0k completion tokens this window), past the standing 2h clause. A second merge_red event landed this window after the 09:21 sw-ll4.26.2 WIP gate failure — orchestrator must root-cause the red gate, not re-run it blindly. Not an idle loop: orchestrator active (7 calls, recovered from its 09:11 timeout), research queued, worker mid-task. Return to PASS once a merge lands and the red gate is triaged.

### 11-21 09:27 UTC **WARN** ([report](audits/20261121-0921.md))

WARN (health, compliance clean): 47 gateway calls 08:51-09:21 all nous/qwen4-max (ux-art-director 21, sw-0nl 13, orchestrator 9, craft-researcher 4), 1.48M prompt and 39.1k completion tokens, cost 0 USD, 10 of 47 rate-limited (21 percent), 69 banners all qwen4-max, no delegate or Claude. Last merge sw-ll4.26.1 at 07:07 is 2h14m old with sw-0nl running, past the 2h clause; sw-ll4.26.2 WIP gate returned merge_red this window and the orchestrator turn timed out (rc=-9, 3600s) at 09:11. Work is moving (sw-0nl 19.5k completion tokens, gate was run) so this is a review bottleneck, not a stall: root-cause the red gate before respawn and land a merge.

### 11-21 08:44 UTC **PASS** ([report](audits/20261121-0834.md))

PASS: compliance clean in 08:04-08:34 window — 32 gateway calls all nous/qwen4-max (24 ok, 8 rate-limited = 25%, under the 40% threshold), cost 0 USD, 85 model banners all qwen, no hx delegate or Claude activity, zero turn failures. Health good: sw-ll4.26.2 finished partial in-window and sw-0nl started running, telegraphing-enemy-intent research done, orchestrator active (9 ok calls, main commits 5377732/8a3eade). Last merge sw-ll4.26.1 at 07:07, ~1h27m ago, inside the 2h clause; 6 merges / 0 rejects all time. Recommend prompt review/salvage of the sw-ll4.26.2 partial output; next audit drops to WARN if nothing merged by ~09:07 with workers running.

### 11-21 07:39 UTC **PASS** ([report](audits/20261121-0734.md))

PASS: 07:04-07:34 window, 40 gateway calls all nous/qwen4-max (33 ok, 7 rate-limited 429s = 17.5%), ~1.78M prompt / 35k completion tokens, cost 0 USD; 59 model banners all qwen4-max; no hx delegate, no Claude activity. Health good: sw-ll4.26.1 WIP reviewed and merged 07:07 (merge gap 05:42->07:07 = 1h25m, inside 2h clause), sw-0nl spawned/queued 07:12, research job queued, orchestrator active (8 ok calls), zero turn failures. sw-ll4.26.2 running ~1h49m of its 2h cap, 13 ok calls with 11.3k completion tokens.

