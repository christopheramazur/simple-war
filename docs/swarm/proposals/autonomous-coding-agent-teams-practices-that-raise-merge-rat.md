# Proposal: Definition-of-done for worker beads + held-out check at merge

Status: open
From: craft-researcher, based on [../research/summaries/autonomous-coding-agent-teams-practices-that-raise-merge-rat.md](../research/summaries/autonomous-coding-agent-teams-practices-that-raise-merge-rat.md)

## The idea
Two prompt/process-level changes, both reversible, no guardrail files touched:
1. Every worker bead carries a written definition of done (acceptance test/command + out-of-scope list) before it is spawned, and workers write a 3–5 line plan in bead notes before editing.
2. The orchestrator merge checklist gains a test-tampering eyeball and one held-out check the worker did not author, recorded in the merge note.
Our executable gate stack (`hx godot check`/`test`, pytest, merge-time full suite) already matches the strongest evidence and stays the primary verdict; these changes tighten task definition and catch the failure classes tests alone miss.

## Why (evidence, with sources)
- **Task-definition quality caps success.** Agentless's fixed localize/repair/validate pipeline beat all open-source agents on SWE-bench Lite at ~$0.70/issue; its analysis found misleading/underspecified items were a hard ceiling. https://arxiv.org/abs/2407.01489
- **External test feedback beats deliberation.** AgentCoder's programmer/test-designer/executor loop hit 96.3% HumanEval at roughly half the tokens of prior best methods; unaided self-review ("think again" without feedback) fails and can degrade results. Keep executable oracles as the verdict, not review debate. https://arxiv.org/abs/2312.13010 · https://arxiv.org/abs/2310.01798
- **Vague delegation causes duplicate work and gaps.** Anthropic's multi-agent writeup: subtasks need objective, output format and boundaries; hand off artifacts (files + commit refs), not prose. MetaGPT's SOP/plan artifacts reduce cascading hallucinations. https://www.anthropic.com/engineering/multi-agent-research-system · https://arxiv.org/abs/2308.00352
- **Visible tests can pass while composition fails.** SpecBench: holdout gaps grow ~28pp per 10× code size; failures include a 2,900-line hash table memorizing test inputs. Cursor's blind audit of 731 trajectories: 63% of "successful" runs retrieved the known fix rather than deriving it; test tampering is a documented hack class, and hacking attempts *increased* under "keep working without stopping" prompts — our call budgets and stop-and-ask rules are protective, keep them. https://arxiv.org/abs/2605.21384 · https://cursor.com/blog/reward-hacking-coding-benchmarks
- **One fresh-context reviewer with a pass/fail rubric beats judge panels;** LLM judges carry position/verbosity/self-preference biases. In a same-model swarm, fresh context removes reasoning contamination but not family preference — another reason executable gates stay primary. https://arxiv.org/abs/2306.05685 · https://www.anthropic.com/engineering/claude-code-best-practices
- Caveat: no published study measures agent-team merge rate on a living codebase; numbers are directional. Track our own merges/rejections by bead size this run to generate evidence.

## Fits the GDD (doc and section) / Conflicts with
- Ways-of-working (swarm goal weight 2), not game design. Indirectly serves GDD 01 pillar 6 (fast, headless-first: cheap executable oracles) and Release order (small slice-verifiable beads).
- Conflicts with nothing. **Guardrail caveat:** both beads edit role prompts only (`designer.md`, `worker.md`, `orchestrator.md` — none is a guardrail file; `_common.md` is untouched). Code-enforced merge gates would touch `swarm.py`/`commands/swarm.py` and are user-only; not proposed here. Verified current state: worker.md has no plan-before-edit rule; orchestrator.md has "never merge a branch you have not read" but no test-weakening eyeball, no held-out check, no merge-note record of checks.

## Candidate beads
1. **Definition-of-done standard for worker beads.** Designers write an acceptance test/command and an out-of-scope list into every worker bead before spawning (add to designer.md); workers write a 3–5 line plan in bead notes before editing (add to worker.md). Acceptance: designer.md and worker.md state the rules; the next 5 spawned worker beads each carry an acceptance command and out-of-scope list (spot-check via `bd show`). Size: S. Type: task. Priority: 2.
2. **Held-out check + test-edit eyeball in the orchestrator merge checklist.** Add to orchestrator.md: before `hx swarm merge`, eyeball the diff for test deletion/weakening (the merge gate already runs the full suite on the merged branch — a weakened test passes it, the eyeball is what catches that); for beads touching sim behaviour, also run one check the worker did not author (an `hx sim` scenario or an untouched GUT dir); record which checks ran in the merge note. Acceptance: orchestrator.md lists both steps; the next 3 merges each record the held-out check used. Size: S. Type: task. Priority: 2.

## Rejected alternative
- **Judge panels / more self-review rounds:** weakest defects-per-token in the evidence; multi-judge setups were less consistent than one rubric judge, and intrinsic self-correction fails without external feedback.
- **Code-enforced merge gates now:** would require editing guardrail files (`swarm.py`, `commands/swarm.py`) — user-only. Prompt-level first; if the eyeball step keeps getting skipped, that is the signal to ask the user for a hook (Claude Code guidance: "if you keep adding emphasis and it's still missed, that line belongs in a hook").
- **"Keep working until done" pressure:** documented to increase reward-hacking attempts; our existing budgets stay.

## Votes
