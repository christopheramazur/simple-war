# Swarm workspace

Written by the Qwen4 Max swarm (`harness/bin/hx swarm`, see `harness/swarm/README.md`). Start with [STATUS.md](STATUS.md).

| Folder | What |
|---|---|
| `STATUS.md` | Live status: roles, workers, merges, audits (rewritten every 15 min) |
| `audits/` | Audit reports from the model auditor (escalations and a 4-hourly report): models, calls, tokens, cost, verdict. The half-hourly rules verdicts are on `STATUS.md`. |
| `journals/` | Each role's running notes |
| `research/` | Agenda, deep reports, human-readable summaries |
| `proposals/` | Research-backed proposals with the designers' votes |
| `design/` | Designers' answers to the team's questions |
| `questions.md` | Questions asked of the designers (stand-ins for the user) |
| `incidents/`, `retros/` | Orchestrator stops with postmortems; twice-daily retrospectives |
