# 7. Glossary

Defined terms. This is the source for in-game hoverable tooltips (R1Q3, R3Q10, R8Q14). In-game, every term becomes a translation key (R8Q10), and every tooltip is context-aware: it shows the value for the hovered squad, with beneficial modifications in green.

Format: **Term**: definition. *(decision IDs; former names)*

**In play (sw-ip8.4):**
- **Terms are data:** each term below is a `term` template in `data/packages/core/defs/glossary.json`, so mods add their own. A test fails if a term here is missing there, or the reverse: add new terms in both places.
- **Translation keys:** `term.<id>.name` and `term.<id>.text`, plus `glossary.*` for value phrases. The English is the fallback.
- **Linking:** `Glossary` links terms in any text by name, plural or alias, matching whole words only and longest match first. `GlossaryLabel` underlines them, and hovering shows `GlossaryTooltip`.
- **Live values:** a term's `context` gives the value for the hovered squad or unit: a stat, a SIMPL pool, every band, the Bad Hit threshold, or units alive.
- **Better or worse:** a value modified for the better shows green with ▲, and for the worse red with ▼, never colour alone.
- **Mock:** `Mocks/glossary.png`.

## Time and turns
- **Pulse**: one shared clock step. By default, one overworld turn plus one turn in every battle. *(R2Q3)*
- **Planning**: the step in which orders are drafted and forecast. About 60 s plus reserve. *(R3Q1)*
- **Reserve**: banked planning time that tops up the per-turn budget. *(R3Q1)*
- **Reveal**: the moment all orders become visible, before the reaction window. *(R2Q4)*
- **Reaction**: a restricted order triggered by an interaction that revealed orders create. *(R3Q4)*
- **Reaction window**: the pause after Reveal in which reactions are issued. *(R2Q4)*
- **Execute**: time-sliced simulated resolution of the turn. *(R1Q8)*
- **Intermission**: the step between turns. It holds summaries and Legend choices; 30 s cap, 10 s ranked. *(R4Q1)*
- **Intent ghost**: the preview of a planned order's path or effect. *(R4Q3)*

## Forces
- **Unit**: one simulated model. *(R1Q9)*
- **Squad**: the command unit, a group of Units. *(R1Q9)*
- **Leader**: the Unit tagged `leader` that uses a squad's individual surge benefits. *(R5Q2, R6Q5)*
- **Commander**: the hero-like unit that anchors an army and owns reactions. *(R3Q3)*
- **Army**: everything a Commander leads on the overworld. *(R2Q1)*
- **Battleforce**: the part of an army committed to one battle. *(R2Q1)*
- **Drop-off**: committing a battleforce without the Commander staying. *(R2Q1, R5Q9)*
- **Detachment / Convoy**: forces or items moving on the overworld without a Commander. Convoys on the same hex and supply line merge. *(R6Q13, R8Q3)*
- **War Chest**: an army's item inventory. *(R4Q10)*
- **Archetype**: a content template (parent plus overrides, at most 3 deep), flattened at load. *(R6Q18)*

## SIMPL pressure
- **SIMPL**: Stamina, Instinct, Morale, Prowess, Legend: the five squad-level pressure systems. *(R5Q8)*
- **Stamina**: exertion capacity. *(R4Q5; formerly Endurance)*
- **Instinct**: reaction and precision. It pays for Detection and Concealment. *(R4Q6, R7Q4; formerly Reflex)*
- **Morale**: the governor. The only channel between the other systems. *(R4Q4)*
- **Prowess**: battlefield presence. *(R6Q1)*
- **Legend**: a squad's story pressure. Its Surges and Breaks leave persistent consequences. *(R5Q6; formerly Mythos)*
- **Float / Sink**: add pressure to, or remove pressure from, a pool. *(R6Q2)*
- **Vacuum**: a pending sink, shown in forecasts. Also a zone's influence decay. *(R6Q2, R6Q10)*
- **Bands**: Surging 90–100%, Primed 65–89%, Neutral 40–64%, Fraying 15–39%, Broken below 15%. *(R4Q4)*
- **Surge / Break**: crossing into Surging, or into Broken. *(R6Q2)*
- **Drift**: a pool's movement toward Neutral each tick. *(R5Q1)*
- **Sensitivity profile**: data saying what moves a squad's pool and what the pool affects. *(R5Q4)*
- **Pressure ledger**: the per-battle, source-tagged record of every pressure flow. *(R6Q3)*

## Combat
- **FPDR**: Fixed Point Defined Rounding, the deterministic arithmetic rule. *(R4Q8)*
- **Accumulator**: a deterministic counter that replaces chance: it counts an event (seconds, hits, distance, health lost, ...) and fires at a threshold. *(R2Q6, R5Q5, E2Q9)*
- **Defensive Profile**: the defence layers: Evasion, Block, Resistance, Flat, Percentage, Floor, Temporary HP, Absorption. *(R5Q7, R7Q1)*
- **Contact forecast**: the planning preview of a coming engagement: who comes out ahead, and at higher verbosity the exact damage dealt and taken. Computed by the same combat code the turn runs, and it assumes the enemy keeps its current orders and shows nothing the player can't see. *(R1Q3, R4Q3, R6Q2)*
- **Evasion**: avoids a hit entirely. *(R7Q1)*
- **Block**: a percentage chance to block a percentage of a hit. *(R6Q7)*
- **Floor**: the minimum damage a hit can deal after reductions, per damage type. 0 means immunity is possible. *(R7Q1)*
- **Temporary HP**: wards and shields that soak damage before Hit Points. They don't count toward HP-based thresholds. *(R3Q10, R7Q1)*
- **Absorption**: after taking damage of a type, a portion of it is restored as health. *(R6Q7)*
- **Bad Hit**: a hit greater than 50% of a unit's base HP. *(R3Q10)*
- **Readying**: time spent before a separate behaviour becomes available. *(R7Q3)*
- **Sight**: a universal radius, limited by line of sight, that lifts fog. *(R8Q1)*
- **Detection**: an ability that reveals concealed squads within its radius. *(R7Q4)*
- **Concealment**: an ability that hides a squad from enemies without Detection. *(R7Q4)*
- **Ambush**: an attack begun while the target hasn't detected the attacker. *(R6Q1)*
- **Intercept**: a charge against an enemy squad that is itself charging one of yours. *(R6Q1)*
- **Keyword**: a static squad property. *(R6Q9)*
- **Status**: a transient bundle of effects on a unit or squad. *(R6Q9, E1Q2)*

## Effects
- **Effect**: one change described in the effect language: operation, target, magnitude, condition, duration, stacking, tags, source. *(E1Q2)*
- **Bundle**: a named group of effects. Abilities, statuses, items and features are bundles. *(E1Q2, E2Q13)*
- **Stat**: a registered value effects can change. Systems read its effective value. *(E1Q3, E3Q4)*
- **Increased**: a percentage modifier summed with every other "increased" on the same stat before it applies. *(E2Q1)*
- **More**: a percentage modifier that multiplies on its own, after all "increased" modifiers. *(E2Q1)*
- **Trace**: the step-by-step calculation of an effective value, shown in the inspection window. *(E2Q1, E2Q3)*
- **Stack**: one count of a stacking effect; "per stack" magnitudes multiply by it. *(E2Q6, E4Q2)*
- **Selector**: picks an effect's targets, ordered by distance then ID. *(E2Q4)*
- **Hook**: an effect that fires when an event happens, one level deep. *(E2Q5)*
- **Tag**: a registered label on effects, abilities, weapons and damage, used for selection, resistance, restriction, Ruin and Null. *(E1Q7)*
- **Restores**: an effect flag that refills current value when a maximum rises, instead of keeping the ratio. *(E3Q2)*
- **Bank**: story-campaign data carried between campaigns. *(E2Q7, E3Q9)*
- **Ability**: a bundle plus an activation (costs, cooldown, charges, ready time, range, targeting, toggle). *(E2Q10)*
- **Inspection window**: the per-unit breakdown screen, available in planning and playback. *(E2Q3, E3Q8)*

## Objectives and scoring
- **Zone**: an area that accrues Influence for whoever holds it. *(R6Q10)*
- **Capture Rate (CR)**: how strongly a squad pushes a zone's influence. Human infantry has 10. *(R6Q10)*
- **Influence**: zone progress, and one of the two scoring modes. *(R6Q10)*
- **Buffer**: stored influence above the capture threshold that must be eroded before a zone can flip. *(R6Q10, R7Q5)*
- **Value**: the economic and scoring worth of forces. The sole resource. *(R5Q11, R6Q15)*
- **Victory Points (VP)**: score from captured zones. *(R6Q10)*
- **End-of-battle hook**: data deciding what happens to remaining forces when a battle ends. *(R7Q6, R8Q3)*

## Overworld
- **Plot**: one hex. *(R3Q22)*
- **Feature**: what a plot offers: production, recruitment, resources, events, garrisons. *(R4Q12)*
- **Route**: a Commander's planned hex path. *(R4Q12)*
- **Quick action**: something done while passing along a route. *(R4Q12)*
- **Activity**: something that requires ending the route on the hex. *(R4Q12)*
- **Supply line**: a production rally route carried by convoys. *(R5Q10)*
- **Movement bank**: 50% of unused movement kept when a plan is cut short. *(R6Q11)*

## Setting
- **The Law**: First Magic. A magic operating system with a registry and audits. *(R1Q15)*
- **Raw magic**: the primal narrative force. *(R1Q15)*
- **Second Magic**: illicit access to Law endpoints. *(R1Q15)*
- **Ruin / Ruined**: Law scoured beyond function. A zone condition. *(R1Q15, R4Q21)*
- **Null**: no magic at all. *(R3Q19)*
- **Legivore**: the magic-killer. *(R3Q19)*
- **Angel**: a lensed counterfactual, a "messenger from nonsense". *(R2Q10)*
- **Angelfall**: the planetary collapse Angels bring. *(R2Q10)*
- **Lawbringer**: an agent of the organisation sustaining the Law. *(R3Q16)*
- **EoAT**: The End of All Things, the era of the story. *(R1Q13)*

## Proposed terms (Round U1, awaiting review)
Not yet terms: each moves into the lists above, and into `glossary.json`, with the U1 task named here (U1 synthesis §4.5), so the glossary test keeps passing.

| Term | Definition | Decisions | Moves in with |
|---|---|---|---|
| Firing position | The nearest point within its squad's coherency radius from which a unit has a shot; under attack orders each armed unit walks to its own and fires on arrival. | U1Q29 | A3 |
| Closing to fire | The default for Attack-move and Attack: the anchor advances until every armed unit has a firing position, and each unit opens fire on its own as it comes into range. | U1Q1, U1Q11, U1Q28, U1Q29 | A3 |
| Behaviour (squad) | What an order runs: an ordered list of components from a closed vocabulary, each with data parameters. | U1Q12 | A9a |
| Separation | The push that keeps units of different squads from standing in one another, without blocking movement. | U1Q10 | A11 |
| Coherency radius | How far a unit may stray from its squad's anchor before it heads back and the anchor slows; it bounds firing positions. Data per formation. | U1Q10, U1Q29 | A12b |
| Relation | One fact about what a squad is doing about another (in range, targeting, under fire, fleeing...), shown on hover and in the comparison menu. | U1Q8 | C6b |
| Deployment | The step before a battle's first turn where each side places its squads, hidden, inside its deployment area. | U1Q9, U1Q30 | C11 |
| Deployment area | The part of a battlefield where a side places its squads and where its reinforcements arrive. | U1Q9 | C11 |
| Fire discipline | How well a squad focuses its fire (discipline) and avoids piling onto units already covered (coordination), scaled by Prowess. | U1Q15, U1Q17, U1Q18 | D5 |
| Kill priority | The order a shooter considers enemy units in: lowest remaining HP first, then lowest unit ID. | U1Q14 | D5 |
| Overkill | Damage spent on a unit beyond what killed it, including hits on a unit already killed that tick. | U1Q16 | D5 |
| Covered | A unit whose queued damage this tick already kills it; coordinated shooters skip it. | U1Q16 | D5 |
| Prowess (amended) | Battlefield presence, including fire discipline. | R6Q1, U1Q15 | D5 |
| Band | A squad group on the overworld without a commander: a garrison or a caravan. | U1Q27 | E2 |
| Caravan | A band made to travel, with its own sight and movement; the name for today's convoy, with "convoy" as an alias. | U1Q27 | E2 |
| Owner action | Something a feature's owner does with it without a commander: buy, set its rally point, choose its output. | U1Q24 | E8 |
