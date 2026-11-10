# Simple War: Game Design Document

This is the authority on game design. It was rewritten after the design interview (bd `sw-d46`). Every rule carries the decision ID that settled it, for example `R7Q4` (round 7, question 4), so you can trace it back to [the decision log](Interview/decision-log.md).

| # | Document | What it holds |
|---|---|---|
| 1 | [Vision and Pillars](01%20Vision%20and%20Pillars.md) | What the game is, who it is for, the pillars, modes, platforms, business model |
| 2 | [Rules Spec](02%20Rules%20Spec.md) | The simulation's rules: turns, battles, combat, SIMPL pressure, overworld, scoring. Authoritative over the code |
| 3 | [Data Model](03%20Data%20Model.md) | Content schemas, archetype templates, unit and squad stat lists, mod packages |
| 4 | [Systems Architecture](04%20Systems%20Architecture.md) | State stores, systems, event queues and the pulse bus, the Game API, networking, saves |
| 5 | [Harness and AI Factory](05%20Harness%20and%20AI%20Factory.md) | Headless runs, metrics, replays, Pressure Lab, controller profiles, evolution |
| 6 | [Narrative Bible](06%20Narrative%20Bible.md) | Setting, magic, factions, the Angelfall tutorial, story scope |
| 7 | [Glossary](07%20Glossary.md) | Defined terms. The source of in-game hoverable term tooltips |
| 8 | [Decision Log](Interview/decision-log.md) | Append-only interview record; [research notes](Interview/research-notes.md) beside it |

## Precedence
1. The decision log records what the designer decided. If a document contradicts it, the document is wrong: fix the document.
2. Documents 1–7 are the readable, consolidated form. Code follows the Rules Spec and Data Model.
3. `History/` holds the pre-interview GDD and the old `data/defaults` JSON. It is reference only. Where it conflicts with the documents above, it is superseded. Known issues in it: the old tabletop framing (statlines, dice, Baseline Competence), the "~50 Ma" Humanity date in the Timeline (R2Q9), the Second Magic and Ruin definitions in the zone table (R1Q15), and many places where "Squad" still stands for what is now a Unit (model).

## Open topics (each gets its own interview, R8Q16)
In order:
1. **Effect language**: a Path of Exile study. Abilities, statuses and Ruin effects all depend on it (R3Q9).
2. **Timeline** grilling (R2Q9).
3. **Narrative pass**, with art direction, audio and UI aesthetics (R4Q22, R8Q11).
4. **AI factory wave**: the rest of the testing framework (R4Q16, R6Q24).
5. **Legend deep dive** (R2Q7, R5Q6).
6. **Commander duels** (R7Q2).

Explicitly later: Morale contagion and battle-event inputs (R5Q3), deeper economy (R5Q11), Lua scripting mods (R6Q25), the in-game player editor (R8Q7), rating models (R7Q10), Dawn of War-style weapon × armour types (R3Q6), wargear logistics (R3Q7).
