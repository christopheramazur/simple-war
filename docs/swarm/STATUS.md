# Swarm status

Updated 2026-11-21 09:49 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 25, craft-researcher: 6, games-researcher: 8, lead-designer: 10, orchestrator: 24, tech-lead: 5, ux-art-director: 7 |
| Worker turns / research turns (24 h) | 12 / 8 |
| Workers queued / running / awaiting review | - / sw-0nl / sw-ll4.26.2 |
| Merged / rejected (all time) | 6 / 0 |
| Gateway calls last hour (rate-limited) | 85 (16) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 09:27 UTC **WARN** ([report](audits/20261121-0921.md)) |

## Recently merged
- sw-aty (2026-11-20T13:49)
- sw-ll4.1.1 (2026-11-21T01:07)
- sw-ll4.1.2 (2026-11-21T02:06)
- sw-uyv (2026-11-21T05:27)
- sw-p70 (2026-11-21T05:42)
- sw-ll4.26.1 (2026-11-21T07:07)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 09:27 UTC **WARN** ([report](audits/20261121-0921.md))

WARN (health, compliance clean): 47 gateway calls 08:51-09:21 all nous/qwen4-max (ux-art-director 21, sw-0nl 13, orchestrator 9, craft-researcher 4), 1.48M prompt and 39.1k completion tokens, cost 0 USD, 10 of 47 rate-limited (21 percent), 69 banners all qwen4-max, no delegate or Claude. Last merge sw-ll4.26.1 at 07:07 is 2h14m old with sw-0nl running, past the 2h clause; sw-ll4.26.2 WIP gate returned merge_red this window and the orchestrator turn timed out (rc=-9, 3600s) at 09:11. Work is moving (sw-0nl 19.5k completion tokens, gate was run) so this is a review bottleneck, not a stall: root-cause the red gate before respawn and land a merge.

### 11-21 08:44 UTC **PASS** ([report](audits/20261121-0834.md))

PASS: compliance clean in 08:04-08:34 window — 32 gateway calls all nous/qwen4-max (24 ok, 8 rate-limited = 25%, under the 40% threshold), cost 0 USD, 85 model banners all qwen, no hx delegate or Claude activity, zero turn failures. Health good: sw-ll4.26.2 finished partial in-window and sw-0nl started running, telegraphing-enemy-intent research done, orchestrator active (9 ok calls, main commits 5377732/8a3eade). Last merge sw-ll4.26.1 at 07:07, ~1h27m ago, inside the 2h clause; 6 merges / 0 rejects all time. Recommend prompt review/salvage of the sw-ll4.26.2 partial output; next audit drops to WARN if nothing merged by ~09:07 with workers running.

### 11-21 07:39 UTC **PASS** ([report](audits/20261121-0734.md))

PASS: 07:04-07:34 window, 40 gateway calls all nous/qwen4-max (33 ok, 7 rate-limited 429s = 17.5%), ~1.78M prompt / 35k completion tokens, cost 0 USD; 59 model banners all qwen4-max; no hx delegate, no Claude activity. Health good: sw-ll4.26.1 WIP reviewed and merged 07:07 (merge gap 05:42->07:07 = 1h25m, inside 2h clause), sw-0nl spawned/queued 07:12, research job queued, orchestrator active (8 ok calls), zero turn failures. sw-ll4.26.2 running ~1h49m of its 2h cap, 13 ok calls with 11.3k completion tokens.

### 11-21 06:59 UTC **PASS** ([report](audits/20261121-0655.md))

PASS: 06:25-06:55 window, 43 gateway calls all nous/qwen4-max (orchestrator 14, lead-designer 12, sw-ll4.26.2 10, sw-ll4.26.1 4, games-researcher 3), 1.47M prompt / 33.6k completion tokens, cost 0 USD, 6 rate-limited failures (14 percent), 98 model banners all nous/qwen4-max, no hx delegate and no Claude activity. Zero turn failures. Health good: sw-ll4.26.1 finished attempt 1 (partial) and awaits review, sw-ll4.26.2 running, orchestrator active (13 ok calls, design-triage commit 959e72a). Last merge 05:42, about 73 min ago, inside the 2h clause. Recommend orchestrator review partial sw-ll4.26.1 promptly: merge salvageable work or respawn with root cause, not blind retry.

### 11-21 06:22 UTC **PASS** ([report](audits/20261121-0618.md))

PASS: compliance clean in 05:48-06:18 window - 60 gateway calls all nous/qwen4-max (worker sw-ll4.26.1: 21, orchestrator: 19, lead-designer: 20), 9 rate-limited (15 percent), 1.53M prompt + 34k completion tokens, cost 0 USD, 58 log banners all nous/qwen4-max, no hx delegate, no swarm Claude. Health recovered: sw-uyv merged 05:27 and sw-p70 merged 05:42 ended the ~3h merge drought behind the 05:03 WARN; zero turn failures; sw-ll4.26.1 running attempt 1 (11.4k completion tokens, ~49 min of 2h cap), sw-ll4.26.2 queued; orchestrator active (16.9k completion tokens). User Claude session fdff218d (2 turns opus, 697 out tokens) reported, not counted. Recommend prompt review of sw-ll4.26.1 when it finishes and early commits from it.

