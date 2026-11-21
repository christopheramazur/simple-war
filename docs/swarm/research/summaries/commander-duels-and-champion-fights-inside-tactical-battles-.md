# Commander duels and champion fights inside tactical battles

Status: draft by games-researcher
Report: [commander-duels](../reports/commander-duels-and-champion-fights-inside-tactical-battles-.md)

Prep for README **Open topic 6 (Commander duels, R7Q2)**. The interview owns the decision; this summary decides nothing.

## What we looked at
How five tactics/wargames stage hero duels, champion elites and boss fights inside battles, how they stay readable and fair, and which balance patterns fit a deterministic WeGo sim where duelling sinks Prowess.

## What we found
1. **Total War: Three Kingdoms** has formal challenge duels: a relative-power meter before consent, a visible countdown, and a weaker duellist who survives to the timer earns a buff and an honourable exit; armies keep fighting around the duel. Players value *containment* (locking an enemy hero out of the fight). The dominant complaint: the AI refuses losing duels, so the feature feels dead — refusal needs a visible cost. Sources: https://totalwar.fandom.com/wiki/Duelling_(Total_War:_Three_Kingdoms) , https://steamcommunity.com/app/779340/discussions/0/1642043267236239941/
2. **Battle Brothers champions** are named elite variants inside normal fights: skull marker, ~1.35–1.82× HP, guaranteed named drop. Pure data, no duel subsystem; readability praised. But exact multipliers were only visible via datamining — a transparency gap pillar 2 should not repeat. Sources: https://battlebrothersgame.com/dev-blog-121-champions/ , https://battlebrothers.fandom.com/wiki/Champions
3. **XCOM 2's Chosen** are persistent nemeses: fixed revealed weaknesses, escalating strengths, a visible Knowledge doom clock; the mission timer pauses while one is on field. Complaints: flat Regeneration spikes and strength combos that invalidate whole toolkits. Sources: https://xcom.fandom.com/wiki/The_Chosen , https://vigaroe.com/Analyses/XCOM2/ChosenStrengths
4. **Gears Tactics bosses** use destructible parts that remove attacks and telegraphed missile zones; the failure mode was gear/build checks and unclear dodge windows, not readable decisions. Sources: https://gamerant.com/gears-tactics-brumak-boss-fight-guide/ , https://steamcommunity.com/app/1184050/discussions/0/4839770694276946630/
5. **Dominions 5** has no duel mode: commanders fight in the battle and armies rout when all commanders die/rout; pre-battle assassinations have bodyguard odds as counterplay. Sources: https://www.magicgameworld.com/dominions-5-combat/ , https://illwiki.com/dom5/assassin

**Recurring patterns:** duel as containment/focus trade; army-wide stakes; a countdown makes "survive" a valid goal; interruption priced, not forbidden; consent needs a refusal cost. **Anti-patterns:** random duel events, hidden modifiers, free refusal, pausing the shared pulse.

## What it means for Simple War
- **Fixed point:** R7Q2 keeps duels deferred; only Prowess involvement is settled — GDD 02 §2.8 lists commander duels as a Prowess sink (general melee is not). All report options keep that.
- **A2Q2 (decision log; GDD 05 §win condition):** skirmish victory is "every enemy commander defeated", so a duel loss is existential — 3K's wound-not-death pattern is worth considering *as an interview option*, not a decision.
- **Morale has no direct damage link (GDD 02 §2.8, R4Q4):** duel outcomes should enter via battle-event inputs (deferred R5Q3) or Legend, never raw damage→morale.
- **WeGo fit:** duels must run on the shared pulse while armies fight (the 3K shape); XCOM's pause-the-timer valve is unavailable to us.
- **Cheapest MVP-safe texture:** Battle Brothers-style champion squads as content-package data (GDD 03), no duel subsystem.

## Candidate beads
1. **Commander-duel options brief for the R7Q2 interview.** Consolidate the report's options A–E (champions-only; opt-in pulse duel; emergent duel; overworld assassination; nemesis commander), the anti-patterns and sources into `Game Design Document/Interview/research-notes.md` or a linked brief. Why: interview prep only; the user decides. GDD: README Open topic 6, 02 §2.8. Acceptance: brief lists five options with trade-offs, four anti-patterns and sources, and explicitly decides nothing. Size: S.
2. **Spike: champion squad variant as pure content data.** One named elite variant in a test content package: token marker, stat multipliers, guaranteed trophy; no new subsystem. Why: the BB pattern is the cheapest miniboss texture for skirmish, reversible, and exercises the GDD 03 package format. GDD: 03 (archetype templates), 02 §2.8. Acceptance: package loads headless; marker visible in the battle view; multipliers deterministic (GUT test); removing the package removes the champion cleanly. Size: M.
