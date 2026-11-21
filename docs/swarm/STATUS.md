# Swarm status

Updated 2026-11-21 06:33 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 21, craft-researcher: 6, games-researcher: 7, lead-designer: 9, orchestrator: 20, tech-lead: 5, ux-art-director: 6 |
| Worker turns / research turns (24 h) | 11 / 7 |
| Workers queued / running / awaiting review | - / sw-ll4.26.2 / sw-ll4.26.1 |
| Merged / rejected (all time) | 5 / 0 |
| Gateway calls last hour (rate-limited) | 107 (15) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 06:22 UTC **PASS** ([report](audits/20261121-0618.md)) |

## Recently merged
- sw-aty (2026-11-20T13:49)
- sw-ll4.1.1 (2026-11-21T01:07)
- sw-ll4.1.2 (2026-11-21T02:06)
- sw-uyv (2026-11-21T05:27)
- sw-p70 (2026-11-21T05:42)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 06:22 UTC **PASS** ([report](audits/20261121-0618.md))

PASS: compliance clean in 05:48-06:18 window - 60 gateway calls all nous/qwen4-max (worker sw-ll4.26.1: 21, orchestrator: 19, lead-designer: 20), 9 rate-limited (15 percent), 1.53M prompt + 34k completion tokens, cost 0 USD, 58 log banners all nous/qwen4-max, no hx delegate, no swarm Claude. Health recovered: sw-uyv merged 05:27 and sw-p70 merged 05:42 ended the ~3h merge drought behind the 05:03 WARN; zero turn failures; sw-ll4.26.1 running attempt 1 (11.4k completion tokens, ~49 min of 2h cap), sw-ll4.26.2 queued; orchestrator active (16.9k completion tokens). User Claude session fdff218d (2 turns opus, 697 out tokens) reported, not counted. Recommend prompt review of sw-ll4.26.1 when it finishes and early commits from it.

### 11-21 05:09 UTC **WARN** ([report](audits/20261121-0503.md))

Window 04:33-05:03 UTC. Compliance clean: 54 gateway calls all nous/qwen4-max (44 success, 10 Nous 429 = 19%), 1,728,925 prompt + 40,077 completion tokens, /usr/bin/bash.00 cost every caller; 97 swarm log banners all nous/qwen4-max; no hx delegate or Claude activity; zero turn failures. Health WARN: last merge sw-ll4.1.2 at 02:06, ~2h57m ago, while workers run - sw-uyv attempt 4 active (15 calls, 16.7k completion tokens), sw-p70 attempt 2 queued since 04:16 after merge_red with no visible root-cause. Work is moving (orchestrator commits ad1995d/66d8941, research queued) so not an idle loop, but the 2h+ no-merge-while-workers-run clause is met, as flagged in the 04:26 audit. Recommend: root-cause sw-p70 merge_red before attempt 2 gets a slot; review/merge sw-uyv promptly when attempt 4 finishes (~06:0x), triage rather than respawn if it fails again.

### 11-21 04:28 UTC **PASS** ([report](audits/20261121-0426.md))

Window 03:56-04:26 UTC: compliance clean - 42 gateway calls all nous/qwen4-max (37 success, 5 Nous 429 = 12%), 1,314,770 prompt + 32,601 completion tokens, cost $0.00 every caller; 92 swarm log banners all nous/qwen4-max; no hx delegate or Claude activity. Zero turn failures. Work moves: sw-p70 attempt 1 ended and was respawned as attempt 2 (queued 04:16) after 1 merge_red, sw-uyv attempt 4 running (12 successful calls), orchestrator and lead-designer active with commits. Watch item: last merge 02:06 (~2h20m ago) - at the WARN threshold, but the gap is one long worker task that hit the gate and was immediately respawned, not a stall; PASS on judgement. Recommend orchestrator root-cause the sw-p70 merge_red before attempt 2 finishes.

### 11-21 03:51 UTC **PASS** ([report](audits/20261121-0347.md))

Window 03:17-03:47 UTC: compliance clean - 59 gateway calls all nous/qwen4-max (46 success, 13 Nous 429 = 22%), 1,443,082 prompt + 41,770 completion tokens, cost $0.00 for every caller; 60 swarm log banners all nous/qwen4-max; no hx delegate or Claude activity. Health good: zero turn failures; worker sw-p70 actively working (15 successful calls, 24k completion tokens); orchestrator active (17 successful calls, commits d882e49/483d4a9, status page updated 03:32); last merge sw-ll4.1.2 at 02:06 (~1h41m ago, 3 merges all-time). No events this window but a worker is mid-task, not an idle loop. Watch: sw-p70 nearing its 2h cap (~04:07); sw-uyv queued at attempt 4 after 3 failures - triage if it fails again.

### 11-21 02:03 UTC **PASS** ([report](audits/20261121-0200.md))

Window 01:30-02:00 UTC: 56 gateway calls, all nous/qwen4-max (48 success, 8 Nous 429 = 14%), 1,516,168 prompt + 31,126 completion tokens, cost $0.00 for every caller; 87 swarm log banners all nous/qwen4-max; no hx delegate or Claude activity. Health good: zero turn failures, sw-uyv respawned (attempt 4 running), sw-ll4.1.2 finished attempt 1 (worker_done), orchestrator active (16 successful calls). Last merge sw-ll4.1.1 at 01:07 (~53 min ago); main commits since are docs/status only. Compliant and moving.

