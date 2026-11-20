# Proposal: Angelfall rework prep — tutorial pacing gap note and glossary-tooltip audit

Status: open
From: games-researcher, based on [../research/summaries/angelfall-story-kin-themes-and-tutorial-framing-for-the-team.md](../research/summaries/angelfall-story-kin-themes-and-tutorial-framing-for-the-team.md)

## The idea
Turn the story-kin research into two small, finished prep artifacts for the Angelfall rework (Vision release step 2) and the narrative-pass interview (README Open topic 3). Neither changes the GDD or the slice; both give the designers and the user concrete options instead of vibes:
1. A **tutorial pacing gap note** comparing the shipped Angelfall slice against the two best-shipped evacuation tutorials (StarCraft II's Mar Sara arc, Halo: Reach's *New Alexandria*).
2. A **glossary-tooltip coverage audit** of the slice UI, checking pillar 3's promise of hoverable defined terms.

## Why (evidence, with sources)
- The report's strongest finding: the best tutorials build competence on small local stakes, then let the evacuation recontextualise everything (SC2 Mar Sara: bar → small raid → planetary evacuation; https://en.wikipedia.org/wiki/StarCraft_II:_Wings_of_Liberty). Reach's *New Alexandria* is the direct mechanical ancestor of our hangar escort — clear turrets so civilian shuttles lift off, objectives in any order (https://www.halopedia.org/Reach:New_Alexandria). The slice already has this shape (GDD 06 §6.9 "In play"), but nobody has compared its actual pacing, triggers and message flow against these models; the rework should start from that comparison.
- Lore depth works through optional channels, never mandatory lore dumps: Dark Souls' NPC lines, item descriptions and world placement (https://www.gamedeveloper.com/design/narrative-design-in-dark-souls). Simple War's native channel is pillar 3's hoverable glossary terms (GDD 01, doc 07) — but we don't know which defined terms the slice actually surfaces, or whether hovering shows their glossary text. An audit turns that promise into a checklist.
- Theme-through-systems, not speeches: Frostpunk's irreversible Book of Laws and unscored closing report (https://gamedesignthinking.com/frostpunk-players-decisions/); the cautionary tale is Mass Effect 3's late exposition-heavy ending (https://en.wikipedia.org/wiki/Reapers_(Mass_Effect)). This is narrative-pass territory — options for the user's interview, not work to do now.

## Fits the GDD / Conflicts with
- Fits: GDD 01 pillar 3 (hoverable defined terms) and Release order step 2 (Angelfall reworked with editor tools and skirmish playtest lessons); GDD 06 §6.8 (Jeff), §6.9 (tutorial, "In play" and playable slice); GDD 07 (glossary as tooltip source); README Open topic 3 (narrative pass).
- Conflicts: none. Both beads produce notes only — no GDD edits, no slice changes, no narrative decisions. The report's campaign-architecture and theme-delivery recommendations stay as prepared options for the user's interviews.

## Candidate beads
1. **Angelfall rework prep: tutorial pacing gap note.** Write `docs/swarm/research/notes/angelfall-tutorial-pacing-gaps.md` comparing the shipped slice (read GDD 06 §6.9, `data/packages/core/defs/angelfall.json`, and the slice's trigger/message flow in `src/presentation/angelfall/`) against the Mar Sara and New Alexandria patterns from the report. Acceptance: the note lists ≥3 concrete gaps (e.g. stakes escalation, objective ordering, when the first shuttle lifts off relative to taught mechanics), each with 1–2 options and a GDD reference; no GDD edits, no code changes. Size: S. Type: task. Priority: 2.
2. **Audit glossary-tooltip coverage in the Angelfall slice.** List every defined term surfaced in the slice UI (overworld, commander panel, planning UI, messages — e.g. Angel, Ruin, Capture Rate, Influence) and whether hovering it shows its GDD 07 glossary text. Acceptance: an audit note in `docs/swarm/research/notes/` with a term-by-term table (term, where shown, tooltip present yes/no, glossary entry exists yes/no); missing coverage written up as candidate follow-ups for the designers, not fixed in this bead. Size: S. Type: task. Priority: 2.

## Rejected alternative
- **Rework the tutorial spine now** (open on Jeff's small local problem, then widen to the spaceport): rejected because release order says the rework follows the skirmish MVP and its editor tools, and the narrative pass is the user's interview topic. The gap note prepares that decision without making it.
- **Add lore dialogue or cutscenes to the slice:** rejected — pillar 3's tooltips are the native lore channel, and the Dark Souls evidence says opt-in depth beats forced exposition. The audit comes first.

## Votes
