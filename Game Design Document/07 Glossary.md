# 7. Glossary

Defined terms. This is the source for in-game hoverable tooltips (R1Q3, R3Q10, R8Q14). In-game, every term becomes a translation key (R8Q10), and every tooltip is context-aware: it shows the value for the hovered squad, with beneficial modifications in green.

Format: **Term**: definition. *(decision IDs; former names)*

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
- **Accumulator**: a deterministic "every Nth" counter that replaces chance. *(R2Q6, R5Q5)*
- **Defensive Profile**: the defence layers: Evasion, Block, Resistance, Flat, Percentage, Floor, Temporary HP, Absorption. *(R5Q7, R7Q1)*
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
- **Status**: a transient condition produced by the effect language. *(R6Q9)*

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
