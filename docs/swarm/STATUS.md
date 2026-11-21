# Swarm status

Updated 2026-11-21 07:49 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 22, craft-researcher: 6, games-researcher: 8, lead-designer: 10, orchestrator: 22, tech-lead: 5, ux-art-director: 6 |
| Worker turns / research turns (24 h) | 11 / 7 |
| Workers queued / running / awaiting review | sw-0nl / sw-ll4.26.2 / - |
| Merged / rejected (all time) | 6 / 0 |
| Gateway calls last hour (rate-limited) | 70 (11) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 07:39 UTC **PASS** ([report](audits/20261121-0655.md)) |

## Recently merged
- sw-aty (2026-11-20T13:49)
- sw-ll4.1.1 (2026-11-21T01:07)
- sw-ll4.1.2 (2026-11-21T02:06)
- sw-uyv (2026-11-21T05:27)
- sw-p70 (2026-11-21T05:42)
- sw-ll4.26.1 (2026-11-21T07:07)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 07:39 UTC **PASS** ([report](audits/20261121-0655.md))

PASS: 07:04-07:34 window, 40 gateway calls all nous/qwen4-max (33 ok, 7 rate-limited 429s = 17.5%), ~1.78M prompt / 35k completion tokens, cost 0 USD; 59 model banners all qwen4-max; no hx delegate, no Claude activity. Health good: sw-ll4.26.1 WIP reviewed and merged 07:07 (merge gap 05:42->07:07 = 1h25m, inside 2h clause), sw-0nl spawned/queued 07:12, research job queued, orchestrator active (8 ok calls), zero turn failures. sw-ll4.26.2 running ~1h49m of its 2h cap, 13 ok calls with 11.3k completion tokens.

### 11-21 06:59 UTC **PASS** ([report](audits/20261121-0655.md))

PASS: 06:25-06:55 window, 43 gateway calls all nous/qwen4-max (orchestrator 14, lead-designer 12, sw-ll4.26.2 10, sw-ll4.26.1 4, games-researcher 3), 1.47M prompt / 33.6k completion tokens, cost 0 USD, 6 rate-limited failures (14 percent), 98 model banners all nous/qwen4-max, no hx delegate and no Claude activity. Zero turn failures. Health good: sw-ll4.26.1 finished attempt 1 (partial) and awaits review, sw-ll4.26.2 running, orchestrator active (13 ok calls, design-triage commit 959e72a). Last merge 05:42, about 73 min ago, inside the 2h clause. Recommend orchestrator review partial sw-ll4.26.1 promptly: merge salvageable work or respawn with root cause, not blind retry.

### 11-21 06:22 UTC **PASS** ([report](audits/20261121-0618.md))

PASS: compliance clean in 05:48-06:18 window - 60 gateway calls all nous/qwen4-max (worker sw-ll4.26.1: 21, orchestrator: 19, lead-designer: 20), 9 rate-limited (15 percent), 1.53M prompt + 34k completion tokens, cost 0 USD, 58 log banners all nous/qwen4-max, no hx delegate, no swarm Claude. Health recovered: sw-uyv merged 05:27 and sw-p70 merged 05:42 ended the ~3h merge drought behind the 05:03 WARN; zero turn failures; sw-ll4.26.1 running attempt 1 (11.4k completion tokens, ~49 min of 2h cap), sw-ll4.26.2 queued; orchestrator active (16.9k completion tokens). User Claude session fdff218d (2 turns opus, 697 out tokens) reported, not counted. Recommend prompt review of sw-ll4.26.1 when it finishes and early commits from it.

### 11-21 05:09 UTC **WARN** ([report](audits/20261121-0503.md))

Window 04:33-05:03 UTC. Compliance clean: 54 gateway calls all nous/qwen4-max (44 success, 10 Nous 429 = 19%), 1,728,925 prompt + 40,077 completion tokens, /usr/bin/bash.00 cost every caller; 97 swarm log banners all nous/qwen4-max; no hx delegate or Claude activity; zero turn failures. Health WARN: last merge sw-ll4.1.2 at 02:06, ~2h57m ago, while workers run - sw-uyv attempt 4 active (15 calls, 16.7k completion tokens), sw-p70 attempt 2 queued since 04:16 after merge_red with no visible root-cause. Work is moving (orchestrator commits ad1995d/66d8941, research queued) so not an idle loop, but the 2h+ no-merge-while-workers-run clause is met, as flagged in the 04:26 audit. Recommend: root-cause sw-p70 merge_red before attempt 2 gets a slot; review/merge sw-uyv promptly when attempt 4 finishes (~06:0x), triage rather than respawn if it fails again.

### 11-21 04:28 UTC **PASS** ([report](audits/20261121-0426.md))

Window 03:56-04:26 UTC: compliance clean - 42 gateway calls all nous/qwen4-max (37 success, 5 Nous 429 = 12%), 1,314,770 prompt + 32,601 completion tokens, cost $0.00 every caller; 92 swarm log banners all nous/qwen4-max; no hx delegate or Claude activity. Zero turn failures. Work moves: sw-p70 attempt 1 ended and was respawned as attempt 2 (queued 04:16) after 1 merge_red, sw-uyv attempt 4 running (12 successful calls), orchestrator and lead-designer active with commits. Watch item: last merge 02:06 (~2h20m ago) - at the WARN threshold, but the gap is one long worker task that hit the gate and was immediately respawned, not a stall; PASS on judgement. Recommend orchestrator root-cause the sw-p70 merge_red before attempt 2 finishes.

