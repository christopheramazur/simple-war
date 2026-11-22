# Proposal: Commander-duel interview prep + champion squads as pure content data

Status: open
From: craft-researcher, based on [summary](../research/summaries/commander-duels-and-champion-fights-inside-tactical-battles-.md)

## The idea
Two beads from the commander-duels report, both respecting R7Q2 (duels stay out of the design space; the user's interview owns the decision):
1. A one-page **options brief for the R7Q2 interview** (prep for sw-p2q.6, same pattern as the accepted Legend-prep bead): five options A–E with trade-offs, four anti-patterns, sources. Prep only — it decides nothing and edits no GDD.
2. A **spike: one champion squad variant authored as pure content-package data** (Battle Brothers pattern). No duel subsystem, no new mechanics — a child archetype with overrides, a marker, and a named item. This is the cheapest reversible way to get miniboss texture into skirmish and to exercise the GDD 03 package format.

## Why (evidence, with sources)
- **Battle Brothers champions** are named elite variants inside normal fights: skull marker, ~1.35–1.82× HP, guaranteed named drop. Pure data, no duel subsystem; readability praised. But exact multipliers were only visible via datamining — a transparency gap pillar 2 must not repeat (our variant's stats must be inspectable in-game). https://battlebrothersgame.com/dev-blog-121-champions/ , https://battlebrothers.fandom.com/wiki/Champions
- **Total War: Three Kingdoms** duels work as *containment* (locking an enemy hero out of the fight) with a visible countdown that makes "survive" a valid goal; the dominant complaint is the AI refusing losing duels for free, which made the feature feel dead. Refusal needs a visible cost; randomness inside a "fair" duel reads as betrayal. https://totalwar.fandom.com/wiki/Duelling_(Total_War:_Three_Kingdoms) , https://steamcommunity.com/app/779340/discussions/0/1642043267236239941/
- **XCOM 2 Chosen**: fixed revealed weaknesses + visible Knowledge doom clock praised; flat Regeneration spikes and toolkit-invalidating strength combos criticised; its pause-the-mission-timer fairness valve is unavailable to a shared-pulse WeGo sim. https://xcom.fandom.com/wiki/The_Chosen , https://vigaroe.com/Analyses/XCOM2/ChosenStrengths
- **Gears Tactics** bosses: good telegraphing (destructible parts, flashing missile zones) but difficulty landed as gear/build checks and unclear dodge windows — boss difficulty should come from readable decisions. https://gamerant.com/gears-tactics-brumak-boss-fight-guide/ , https://steamcommunity.com/app/1184050/discussions/0/4839770694276946630/
- **Dominions 5**: no duel mode; armies rout when all commanders die/rout; pre-battle assassinations with bodyguard odds as counterplay fit the overworld's turn-start timing. https://www.magicgameworld.com/dominions-5-combat/ , https://illwiki.com/dom5/assassin

## Fits the GDD (doc and section) / Conflicts with
- **Fits:** README Open topic 6 (R7Q2) — bead 1 is interview prep, the established pattern (Legend prep accepted). GDD 02 §2.8: commander duels are a Prowess sink, general melee is not; every option in the brief keeps that. GDD 03 §3.1: bead 2 uses parent archetype + overrides flattened at load with provenance — the format's intended mechanism, not a multiplier subsystem. GDD 05 A2Q2: skirmish victory is "every enemy commander defeated", so the brief flags 3K's wound-not-death pattern as an interview option (a duel loss would otherwise be existential).
- **Conflicts with:** nothing, if scoped as written. Bead 2 must not add loot-on-death (the GDD has no loot system; the named item is carried, not dropped) and must not add duel mechanics. Morale has no direct damage link (02 §2.8, R4Q4): any future duel outcome enters via battle-event inputs (deferred R5Q3) or Legend — the brief records this constraint.
- **Dedup:** no existing swarm bead covers champion variants or duel prep (checked tracker). sw-p2q.6 is the interview task itself — bead 1 only prepares it and must not run the interview (deferred-interviews epic needs the user).

## Candidate beads
1. **Commander-duel options brief for the R7Q2 interview (prep for sw-p2q.6)**: consolidate the report's options A–E (champions-only; opt-in pulse duel; emergent duel; overworld assassination; nemesis commander), the four anti-patterns (random duel events, hidden modifiers, refusal without cost, pausing the shared pulse) and sources into a one-page brief under `docs/swarm/`, linked from the research agenda. Acceptance: brief lists five options with trade-offs, four anti-patterns and sources, and explicitly decides nothing; no GDD edits; interview task untouched. Size: S. Type: task. Priority: 2.
2. **Spike: champion squad variant as pure content data**: one named elite variant in a test content package, authored as a child archetype with overrides (GDD 03 §3.1: parent + overrides, flattened at load with provenance), a `champion` tag + name/icon marker, and a named item it carries (GDD 03 items, R3Q7). No new subsystem; loot-on-death explicitly out of scope. Acceptance: package loads headless; marker visible in the battle view; flattened stats deterministic with provenance (GUT test); removing the package removes the champion cleanly. Size: M. Type: feature. Priority: 2.

Note: the 8/day swarm-proposed bead cap was reached 2026-11-21; if still capped, defer creation to the first designer turn on/after 2026-11-22 UTC with the same acceptance criteria (established pattern).

## Rejected alternative
- **Build the opt-in pulse duel (option B) now**: richest WeGo fit, but R7Q2 explicitly defers duels to the user's interview — building it would decide an Open topic. Rejected; the brief prepares the decision instead.
- **Champion stat multipliers as a runtime mechanism** (BB's literal implementation): GDD 03 §3.1 already provides parent + overrides flattened at load; a multiplier subsystem would duplicate it and hide provenance. Rejected in favour of pure archetype overrides.
- **Nemesis commander (option E) as the first step**: post-MVP scope, entangled with Legend consequences (Open topic 5). Kept in the brief as a later layer only.

## Votes
