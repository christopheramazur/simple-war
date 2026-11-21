# Telegraphing enemy intent in perfect-information tactics

Status: reviewed by craft-researcher
Report: [telegraphing-enemy-intent](../reports/telegraphing-enemy-intent-in-perfect-information-tactics-que.md)

## What we looked at
How Into the Breach, Frozen Synapse, Combat Mission (WeGo), XCOM 2 and Invisible, Inc. show or hide enemy intent, what that does to fairness and tension, and the cheapest legible subset for our skirmish-vs-AI MVP.

## What we found
1. **ITB telegraphs every attack on its target tiles, with zero hit/miss RNG.** Difficulty is triage (protect buildings/grid), not secrecy. Praised for making prevention the goal; criticised for repetition and cognitive load. Sources: https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design , https://www.gamerevs.com/reviews/into-the-breach/
2. **Frozen Synapse and Combat Mission hide orders entirely (WeGo).** Tension comes from simultaneous commitment and spotting; FS lets you *simulate* your plan "assuming current enemy strategy", CM offers replays. Mode 7's own postmortem warns that full prediction creates "perfect decision" pressure and frustration. Sources: https://www.gamedeveloper.com/audio/postmortem-mode-7-games-i-frozen-synapse-i- , https://en.wikipedia.org/wiki/Combat_Mission
3. **XCOM 2 hides intent but publishes conditional rules** (concealment break conditions, overwatch); **Invisible, Inc. draws per-tile vision cones and makes telegraphy a difficulty setting.** Sources: https://www.ufopaedia.org/index.php/Concealment_(XCOM2) , https://iiwiki.werp.site/vision
4. **Tension without hidden rules** recurs as: competing obligations, timers/escalation, action economy, simultaneous commitment, and visible conditional reactions (time-to-aim, covered arcs, overwatch).
5. **Cost/value ladder:** stance icons < attack telegraphs (target + computed damage) < threat envelopes < full plan preview (expensive, perfection-pressure risk). Replay-only is cheapest but weakest for planning.

## What it means for Simple War
- **Pillar 2 (GDD 01, R1Q3):** difficulty from timers and opponents' decisions, never hidden rule information. Telegraphs + stance icons implement this directly; hidden *intent* is allowed, hidden *rules* are not.
- **Code check:** `IntentForecast` (src/sim/battle/intent_forecast.gd; GDD 02 §2.2, R4Q3/R6Q2) already forecasts the player's own drafts: path ghosts + contacts (engagement tick + reaction names). It shows **no predicted damage numbers**, and enemy drafts stay secret during planning. The gap is computed outcomes and enemy-side telegraphs — not a new forecast engine. The Reveal-time forecast and reaction window already exist (GDD 02 shared pulse, sw-o1m.2.7; `battle_session.gd` `reaction_opportunities`/`submit_reaction`), so enemy telegraphs at reveal are display work on existing plumbing.
- **Prowess reactions (GDD 02 §2.8, R6Q1/R7Q2)** already assume order visibility ("a revealed charge turning their attack-move into a retreat"). In WeGo, a telegraph is committed intent at reveal time, with Execute-time reactions as the tension source (report analysis, not a GDD decision).
- **How much of the enemy's next-turn plan to show during planning stays a designer decision**; the report only ranks cost/value.

## Candidate beads
1. **Predicted outcomes on contact forecasts.** Extend IntentForecast contacts with computed damage/casualties per engagement, shown at the chosen verbosity. Why: pillar 2's "the displayed result is the result used"; highest planning value per pixel, builds on the existing forecast. GDD: 01 pillar 2 (R1Q3), 02 §2.2. Acceptance: GUT test on a seeded battle — forecast contact damage equals executed damage when the drafted orders are committed **and the opponent's orders are unchanged between forecast and execution** (the WeGo "assuming current strategy" caveat; a changed enemy plan legitimately changes the outcome); unseen enemies never leak into the forecast. Size: M.
2. **Enemy attack telegraphs in the reveal/reaction window.** Mark each committed enemy attack's target squad and show computed damage so reactions can be aimed. Why: makes the existing reaction window (battle_session.gd) readable; mirrors FS/CM reveal without pausing the pulse. GDD: 02 §2.8 (R6Q1, R7Q2), 01 pillar 2. Acceptance: during REACTION, every enemy attack on a visible own squad shows target + predicted damage matching the sim; deterministic test. Size: M.
3. **Options brief: enemy intent visibility in WeGo skirmish.** The report's five options (stance-only → full preview as an accessibility toggle, per Invisible Inc's precedent), ranked with costs and risks, for a designer decision. Why: keeps "how much to show" with the designers. GDD: 01 pillar 2 + release order (skirmish MVP). Acceptance: brief written with options, costs, risks and a recommendation; no rules changed. Size: S.
