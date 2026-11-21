# Commander duels and champion fights inside tactical battles

Date: 2026-11-21. Requested by: craft-researcher. Prep for README Open topic 6 (Commander duels, R7Q2). This report decides nothing; the interview owns the decision.

## Questions

1. Which tactics/wargames stage hero/champion duels or boss fights inside battles, and how are they triggered and resolved alongside the normal battle?
2. How are they telegraphed and kept readable/fair — what is shown before and during, and what did players praise or complain about?
3. What balance patterns recur (stakes, interruption, army effects while leaders duel), and which fit a deterministic WeGo sim where Prowess sinks on duels and difficulty comes from timers and opponent decisions, never hidden rules?

## Short answer (5 lines)

Five games cover the design space: Total War: Three Kingdoms (formal challenge duels), Battle Brothers (champion elites inside normal fights), XCOM 2 (persistent Chosen nemeses), Gears Tactics (scripted part-based bosses), Dominions 5 (commander exposure plus pre-battle assassinations).
The recurring winning pattern is: duel as *containment and focus trade*, with army-wide morale stakes, a visible countdown that makes "survive" a valid goal, and priced (not forbidden) interruption.
The recurring failure pattern is: consent without a refusal cost (3K's AI simply declines losing duels, and players call the mechanic dead), and hidden or random swing factors.
For Simple War, the strongest fit is a planning-order challenge resolved deterministically over pulses, both commanders sinking Prowess while duelling, with a forecast shown before commitment — plus Battle Brothers-style champion squads as the cheap, data-only content path.
Everything below is options with evidence; R7Q2's only fixed point (Prowess is involved) is respected throughout.

## Findings

### Q1 — Who stages duels, and how they run alongside the battle

**Total War: Three Kingdoms** is the only game here with a formal duel mode ([Total War Wiki](https://totalwar.fandom.com/wiki/Duelling_(Total_War:_Three_Kingdoms)), which cites the official 3K glossary and a Creative Assembly blog post). In Romance mode a player selects a character, clicks the duel button, and picks from a list of eligible enemy generals shown with a relative power meter; strategists cannot duel. The two charge, one is unhorsed (which one is random), and the fight continues on foot while regular units path around it. A countdown timer runs. Duellists may use abilities, and nearby friendly generals may apply non-damage buffs. The loser flees (often wounded rather than dead, via a Resilience stat); the winner heals and keeps fighting. In Records mode duels instead break out organically when heroes clash, their bodyguard retinues fight too, and there are no hero abilities — the emphasis shifts to managing the rest of the army.

**Battle Brothers** puts champions *inside* the normal battle with no special mode ([dev blog #121](https://battlebrothersgame.com/dev-blog-121-champions/), [wiki](https://battlebrothers.fandom.com/wiki/Champions)). A champion is a stronger, named variant of certain enemy types, marked with a skull on its token. Spawn chance is per-enemy base (1–10%) plus additive modifiers: +5% on three-skull contracts, −99% on one-skull, −1% before day 90, +3% with the Bounty Hunter follower. Stats are multiplied (roughly ×1.35–1.82 HP, ×1.5 resolve, damage and XP), applied after shields and perks. They always carry a named item that drops on death. The devs' stated intent: minibosses that convert contract risk into loot reward and bridge the difficulty gap between the first late-game crisis and legendary locations.

**XCOM 2: War of the Chosen** runs three persistent nemesis commanders across the campaign ([XCOM Wiki](https://xcom.fandom.com/wiki/The_Chosen)). Each controls a region and appears on missions there on its own timer: after an encounter, 0% chance for the next two missions, 50% on the third, 100% on the fourth; they spawn after squad concealment breaks. On the field they fight alongside normal enemies, daze soldiers, then kidnap or interrogate them for Knowledge; at full Knowledge they assault the player's base. Killed in the field, they resurrect at their Citadel until the player raids the stronghold and destroys the sarcophagus (a revive timer runs during that fight). Each has 2 fixed weaknesses and 2→5 strengths gained through training tiers; strengths and weaknesses never duplicate across the three. Permanent defeat yields their unique weapons.

**Gears Tactics** stages scripted act-end bosses, notably the Act 1 Brumak ([GameRant guide](https://gamerant.com/gears-tactics-brumak-boss-fight-guide/)). It is one huge entity with destructible parts: machine guns (destroying them removes attacks, not HP) and back fuel tanks (the real weak point; hitting them turns the beast). Missile strikes are telegraphed by flashing red zones; stomps punish clustering; Emergence Holes spawn adds that must be grenaded or overwatched. The squad starts split across the map; killing the boss alone wins the mission.

**Dominions 5** has no duel mode: commanders physically fight in the auto-resolved battle, and an army routs when all its commanders are killed or routed (or at 75% total HP loss) — there is deliberately no "attack commanders" order ([Magic Game World guide](https://www.magicgameworld.com/dominions-5-combat/)). The duel-like mechanic is the **assassin**: a commander ability that triggers a one-on-one assassination battle *before movement* in the turn order, against a random non-hidden enemy commander in the province ([illwiki](https://illwiki.com/dom5/assassin)). The victim is surprised and loses its scripted orders; the assassin keeps its script. Bodyguards set to Guard Commander have a base 50% chance to join, ±10% per point of Bodyguard ability or assassin Patience. There is a 50% night roll. So Dominions offers both emergent in-battle commander exposure and a scheduled pre-battle micro-duel.

### Q2 — Telegraphing, readability, fairness: praise and complaints

**Three Kingdoms.** Before: the challenge list shows a relative power meter — informed consent. During: the countdown is visible, and the rule that a weaker duellist who survives to the timer earns a retinue buff and may withdraw honourably is documented in the official glossary. Players praised the drama and, more importantly, the *containment* value: duelling locks an enemy hero out of smashing your troops, and supporting your duellist with buff abilities is a real strategy ([Steam thread](https://steamcommunity.com/app/779340/discussions/0/1642043267236239941/)). The dominant complaint is the opposite: the AI refuses duels it would lose ("Doesn't want to duel"), so the marketed feature feels absent; the thread's OP wanted a morale penalty for refusal. A snippet-only [Reddit discussion](https://www.reddit.com/r/totalwar/comments/fquha1/can_someone_explain_how_dueling_works_in_three/) notes duels inherit the game's chance-based hit/evasion rolls, so upsets happen; another [Reddit post](https://www.reddit.com/r/totalwar/comments/1cw6l0j/one_overlookedmisunderstood_mechanic_in_tw3k/) argues duels are deeper than perceived because accepting a losing duel buys time and army buffs. Lesson: refusal must carry a visible cost, and randomness inside a "fair" duel reads as betrayal.

**Battle Brothers.** Readability is the design's strong point: skull token, unique name, special base — you know a champion before you commit, and the guaranteed named drop makes the stake explicit. The community wiki publishes exact multipliers and spawn modifiers, and its tips read as a fairness audit: dodger champions (e.g. Swordmaster at 125 melee defense) are nearly unhittable in melee and demand nets/ranged; high resolve makes fear builds useless; champions gain Confident morale on kills and snowball. Praise centers on risk/reward clarity (three-skull contracts now pay); complaints center on hard-counter builds and early injury spikes. The rules are deterministic but were only fully visible via datamining — a transparency gap Simple War's pillar 2 should not repeat.

**XCOM 2.** Strengths/weaknesses are inspectable from the strategy layer; weaknesses are fixed at run start (no savescumming), and the Knowledge meter is a visible doom clock. The mission timer *pauses* while a Chosen is on the field — a deliberate fairness valve. The deep [vigaroe analysis](https://vigaroe.com/Analyses/XCOM2/ChosenStrengths) documents the complaints: flat Regeneration is brutal early and a joke late; strength combos (Shadowstep+Revenge, Planewalker+Blast Shield) can invalidate whole toolkits; some strengths are dud rolls (All Seeing after the spawn-timer patch; Brutal possibly not functioning); Planewalker's model desyncs from its real position; the game barely explains strengths in-fiction. Praise: the nemesis arc, and unique weapons as trophies. Lesson: escalating boss power needs per-tier relevance checks, and every modifier must be legible where the player plans.

**Gears Tactics.** Telegraphing is good (flashing missile zones, visible destructible parts), and reviews called the bosses a highlight. But the [Steam thread](https://steamcommunity.com/app/1184050/discussions/0/4839770694276946630/) shows the failure mode: a player on Intermediate felt underleveled/undergeared, won "out of pure luck" after ~10 tries, and found guides contradicting each other (guns-first vs ignore-guns). Veterans answer with action-point economy builds and a one-turn kill on Insane — the boss is a build check, and a perk (BADASS, 75% first-hit reduction, [Reddit snippet](https://www.reddit.com/r/GearsTactics/comments/g9vng2/cheesing_the_brumak_boss_fight/)) trivializes it. A [final-boss thread](https://www.reddit.com/r/GearsTactics/comments/gl2db8/anybody_else_finding_the_last_boss_really_tedious/) complains an attack's dodge window was unclear. Lesson: boss difficulty should come from readable decisions, not gear thresholds or obscure dodge timing.

**Dominions.** Assassination targets are random, which players experience as a numbers game (send several assassins; success rates discussed in Steam threads). The counterplay — bodyguards, Patience, hiding commanders — is documented and deterministic once known. The surprise asymmetry (victim loses its script) is a strong, legible rule, but only if surfaced.

### Q3 — Recurring balance patterns, and WeGo fit

1. **Duel as containment/focus trade.** 3K's real value is taking a hero out of the fight; both sides pay opportunity cost. This is exactly R6Q1's Prowess framing: duelling costs focus, so the commander's wider presence is at stake. A WeGo duel should sink Prowess per pulse on both parties, decaying their army-wide effects while the duel runs.
2. **Army-wide stakes, not just HP.** 3K attaches morale to win, loss, interruption and shameful withdrawal; Dominions routs whole armies on commander death. Simple War's Morale is the governor with *no direct damage link* (Rules Spec §2.8, R4Q4), so duel outcomes should enter as battle-event inputs (the deferred R5Q3 channel) or via Legend, never as raw damage→morale.
3. **A countdown makes losing survivable.** 3K's timer turns "weaker duellist" into a defend-to-time objective with a buff payoff and honourable exit. This is the single most transferable pattern for a game whose difficulty comes from timers (Vision pillar 2): show the forecast, let the weaker side plan to survive rather than win.
4. **Interruption priced, not forbidden.** 3K allows troop intervention at an army-wide morale cost, and free non-damage support buffs. Simple War already floats Prowess for interrupting a readying squad (§2.6, R7Q3) — the same verb fits duel-breaking.
5. **Consent needs a refusal cost.** 3K's AI declining losing duels made the feature feel dead. In WeGo, accept/refuse is a natural opponent planning decision — but refusal should cost something visible (Morale, Legend, or Prowess), or challenges should be unilateral with an escape valve.
6. **Champions are data, not a subsystem.** BB's pattern — marked elite variant, stat multipliers, guaranteed trophy — is pure content-package material and the cheapest way to get miniboss drama into skirmish now.
7. **Nemesis persistence with fixed revealed weaknesses.** XCOM's escalating strengths + fixed weaknesses + retreat-not-death is a campaign-layer pattern; it pairs with the Legend deep dive (Open topic 5) and the doom-meter patterns in our earlier [pressure-meter report](pressure-and-doom-meters-readable-at-a-glance-how-games-surf.md).
8. **Bosses as part puzzles.** Gears' destructible parts that remove attacks map onto defined conditions and telegraphed zones (see our [intent-telegraphing report](telegraphing-enemy-intent-in-perfect-information-tactics-que.md)); best suited to story missions, not ranked.
9. **Pre-battle commander removal.** Dominions' assassin resolves before the main battle, with bodyguard odds as the counterplay — a fit for the overworld's "uncertain outcomes at turn start" timing (§2.9, R6Q14).

## Relevance to Simple War

- **Fixed point:** R7Q2 (decision log) keeps duels out of the design space for now; only Prowess involvement is settled. Rules Spec §2.8 lists commander duels as a Prowess sink and says general melee is not. Every option below keeps that.
- **Victory interaction:** A2Q2 makes skirmish victory "every enemy commander defeated". Duels therefore carry existential stakes; 3K's wound-not-death (Resilience) pattern is worth considering so a duel loss doesn't instantly end a match.
- **Commander commitment:** R2Q1 already lets a commander deploy with a battleforce for bonuses and reinforcements. A duel is a natural extension of that commitment decision, and of Prowess floats (intercepts, ambushes, interrupts).
- **Transparency:** Vision pillar 2 forbids 3K's random unhorsing and XCOM's unexplained strengths; duel odds, timer, and per-pulse Prowess flows belong in the forecast and the source-tagged ledger (§2.8, R6Q3).
- **Parallel play:** duels must not pause the battle (XCOM pauses its mission timer; we cannot pause the shared pulse). The 3K model — duel runs while armies keep fighting around it — is the right shape.

## Options and recommendations

- **A. Champion squads only (BB pattern), no duel subsystem.** Data-driven elite variants with icon, multipliers, guaranteed trophy (Legend or kit). Trade-off: cheapest, reversible, MVP-safe; delivers miniboss texture but not commander drama, and doesn't exercise the Prowess sink.
- **B. Opt-in challenge duel on the pulse (3K adapted).** Challenge is a planning order; accept/refuse is the opponent's planning decision with a visible refusal cost; the duel resolves as deterministic exchanges over N pulses, both commanders sinking Prowess; forecast shows odds, timer and the survive-to-time payoff; interruption allowed at a Prowess/Morale price; honourable withdraw after the timer. Trade-off: the richest fit for WeGo + Prowess + timers, but a new subsystem with UI and balance surface; needs Pressure Lab tuning.
- **C. Emergent duel (Records-mode pattern).** When two commander squads clash, a duel state triggers automatically; bodyguards fight on. Trade-off: far less UI and no consent problem, but less player agency and harder to telegraph before commitment; a good fallback simplification of B.
- **D. Overworld assassination (Dominions pattern).** A commander ability targeting an enemy commander on a hex, resolved as a small deterministic engagement at turn start, with guard squads shifting the odds. Trade-off: moves drama off the battle map; fits R6Q14 timing; risks feeling like a dice roll unless fully forecast.
- **E. Nemesis commander (XCOM pattern), campaign layer.** Persistent enemy commander with revealed fixed weaknesses, escalating strengths, retreat until a decisive battle. Trade-off: post-MVP scope, entangled with Legend consequences; strongest story payoff (Angelfall).

Suggested framing for the interview: A is safe to ship regardless; B is the leading candidate for the duel itself, with C as its simplification; D and E are later layers. Anti-patterns to rule out explicitly: random duel events, hidden modifiers, refusal without cost, and pausing the shared pulse.

## Sources

1. https://totalwar.fandom.com/wiki/Duelling_(Total_War:_Three_Kingdoms) — full duel mechanics; cites the official 3K glossary and CA's Records-mode blog.
2. https://steamcommunity.com/app/779340/discussions/0/1642043267236239941/ — player thread on duel pointlessness/containment value and AI refusal.
3. https://battlebrothersgame.com/dev-blog-121-champions/ — primary dev blog: champion design intent, risk/reward, difficulty bridging.
4. https://battlebrothers.fandom.com/wiki/Champions — spawn chances, stat multipliers, skull marking, loot rules, counterplay tips.
5. https://xcom.fandom.com/wiki/The_Chosen — appearance timers, Knowledge/sabotage, Citadel resurrection, strengths/weaknesses rules.
6. https://vigaroe.com/Analyses/XCOM2/ChosenStrengths — strength-by-strength analysis incl. fairness critiques and combo spikes.
7. https://illwiki.com/dom5/assassin — Dominions 5 assassination rules: turn order, surprise, bodyguards, Patience.
8. https://www.magicgameworld.com/dominions-5-combat/ — commander death/rout rules; no "attack commanders" order.
9. https://gamerant.com/gears-tactics-brumak-boss-fight-guide/ — Brumak parts, telegraphed missile zones, E-holes.
10. https://steamcommunity.com/app/1184050/discussions/0/4839770694276946630/ — Brumak difficulty-spike and build-check complaints.
11. https://www.reddit.com/r/totalwar/comments/fquha1/ (snippet only) — duel RNG/evasion discussion.
12. https://www.reddit.com/r/totalwar/comments/1cw6l0j/ (snippet only) — duels as underrated strategic tool.
13. https://www.reddit.com/r/GearsTactics/comments/g9vng2/ (snippet only) — BADASS-perk cheese of Brumak.
14. https://www.reddit.com/r/GearsTactics/comments/gl2db8/ (snippet only) — final boss tedium, unclear dodge.

## Confidence and gaps

- **High confidence** on mechanics: each game is covered by a wiki/guide plus a second source; 3K's wiki cites official material. **Medium** on reception: forum threads are small, self-selected samples.
- Not verified: exact 3K duel timer length and morale numbers (wiki is qualitative; the official glossary at 3kglossary.totalwar.com was not fetched directly); whether BB shows champion stat multipliers in-game (wiki data is community-derived); Dominions 6 changes (sources are Dom5).
- IGN's Brumak guide returned 403 and was not retried; GameRant + Steam thread covered the same ground. No GDC/developer postmortem specifically on duel design was found; the BB dev blog is the only primary developer source.
