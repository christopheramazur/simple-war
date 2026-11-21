# Swarm status

Updated 2026-11-21 17:52 UTC. Generation 1, audit alert streak 0. Supervisor running.

| | |
|---|---|
| Turns per role | auditor: 37, craft-researcher: 9, games-researcher: 11, lead-designer: 13, orchestrator: 64, tech-lead: 8, ux-art-director: 9 |
| Worker turns / research turns (24 h) | 24 / 9 |
| Workers queued / running / awaiting review | - / - / sw-ll4.27.3, sw-opt |
| Merged / rejected (all time) | 16 / 0 |
| Gateway calls last hour (rate-limited) | 42 (23) |
| Incidents | 0 postmortem(s) |
| Latest audit | 11-21 17:22 UTC **WARN** ([report](audits/20261121-1656.md)) |

## Recently merged
- sw-0nl (2026-11-21T11:43)
- sw-1jy.3 (2026-11-21T12:04)
- sw-1jy.5 (2026-11-21T12:33)
- sw-ll4.27.1 (2026-11-21T13:00)
- sw-ll4.27.4 (2026-11-21T13:19)
- sw-ll4.27.2 (2026-11-21T13:40)
- sw-1jy.4 (2026-11-21T13:50)
- sw-luo (2026-11-21T14:26)

<!-- details: agents see only the summary above -->

## Last audits (newest first)

### 11-21 17:22 UTC **WARN** ([report](audits/20261121-1656.md))

WARN - compliance clean: all 20 gateway calls in the 16:26-16:56 window are nous/qwen4-max (orchestrator 9, lead-designer 11), 23 banners clean, cost 0 USD, no delegate/Claude. Health poor: 13 of 20 calls rate-limited (65 percent; 33 of 40 last hour), zero swarm events, no merge since sw-luo 14:26 (2.5 h, 16 total). sw-ll4.27.3 (att3) and sw-opt (att1, first commit a7bff93 confirmed 14:44) both finished partial and sit awaiting review past the 2 h worker cap. Orchestrator journal ends 14:44Z and no audit file exists after 14:34 even though the 16:26 WARN verdict was recorded: recent turns appear killed before writing outputs, likely 429 retry latency. Orchestrator is alive (5 successful calls) and workers are awaiting review, not idle, so not FAIL. Priority recommendation: next orchestrator turn should review+merge sw-opt and .3 att3 (journal-only conflict, code ff9a7d4 verified) before any other work, and journal early in the turn.

### 11-21 17:05 UTC **WARN** ([report](audits/20261121-1656.md))

WARN - compliance clean: all 20 gateway calls in the 16:26-16:56 window are nous/qwen4-max (orchestrator 9, lead-designer 11), 23 log banners clean, cost 0 USD, no hx delegate and no Claude activity. Health is poor: 13 of 20 calls rate-limited (65 percent, above the ~40 percent threshold; status page shows 33 of 40 in the last hour), zero swarm events in the window (no spawn/merge/reject), and no merge since sw-luo at 14:26 - 2.5 hours ago, 16 total. Workers sw-ll4.27.3 (3 attempts) and sw-opt (1 attempt) have sat partial/awaiting-review since ~14:30, past the 2 h worker cap; .3 has been stuck on a journal-only worker.md conflict since attempt 2. Orchestrator is alive (5 successful calls, ~136k tokens) and turn_failures is empty, so this is not a FAIL. Recommend mechanically resolving the .3 journal conflict (precedent: sw-ijp.5 att3) and reviewing sw-opt now, and pacing calls while Nous throttles. Prior audit 16:26 was WARN; conditions persist.

### 11-21 16:26 UTC **WARN**

auditor recorded no verdict

### 11-21 15:26 UTC **WARN**

auditor recorded no verdict

### 11-21 14:34 UTC **PASS** ([report](audits/20261121-1434.md))

PASS for 14:04-14:34Z: 162 gateway calls, all nous/qwen4-max (orchestrator 71, worker sw-ll4.27.3 39, ux-art-director 16, worker sw-luo 15, craft-researcher 14, worker sw-opt 7 incl 1 failed call that did not fail its turn), ~7.93M prompt + 146k completion tokens, cost 0 USD, 0 rate-limited, 219 model banners all clean, no hx delegate or Claude activity. Health: 1 merge (sw-luo accessibility audit, 16 total), 3 spawns, 3 worker_done, 0 turn failures. sw-ll4.27.3 now at attempt 3 with 0 rejects all-time; checking orchestrator triage before judging it a loop, but spawns and merges show work is moving.

