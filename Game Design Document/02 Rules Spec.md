# 2. Rules Spec

The simulation's rules. This document is authoritative over the code: if they disagree, either the code is a bug or this document needs a decision-log entry. Numbers given here are **starting defaults held in data**, not constants (R5Q3, R6Q6).

## 2.1 Foundations
- **Determinism** (R1Q7): the same inputs plus the same seed give the same result on every machine. Sim state uses fixed-point integers with **FPDR (Fixed Point Defined Rounding)** (R4Q8). There are no floats in the simulation.
- **No hidden randomness** (R2Q6): chance is replaced by modifiers and deterministic accumulators ("every Nth hit is a crit", R5Q5). Seeds exist only for content generation (map templates).
- **Space** (R2Q5): battles use continuous fixed-point space. The overworld is a hex grid; each hex is a **plot** (R3Q22).
- **Simulation scale** (R1Q9): every model (**Unit**) is simulated. The **Squad** is the command unit. Unit data overrides squad defaults.
- **Transparency** (R1Q3, R3Q10): every calculation exposes its terms for context-aware tooltips. The displayed number is the used number.

## 2.2 The turn and the pulse
### Clock
- By default, the overworld and every battle share one **pulse**: one overworld turn equals one turn in each battle (R2Q3). Independent clocks are a configurable option (R2Q3).
- The turn and timing system is isolated, so the overworld and battles can run separately or together (R2Q1).

### Turn sequence
1. **Planning** (R3Q1, R4Q3): about 60 s by default, with a reserve top-up. Players issue orders in every context they're in.
   - The server forecasts interactions continuously as orders are drafted and keeps a reaction dictionary. Forecasts show *Vacuum* (pending sinks) and intent ghosts (R4Q3, R6Q2).
   - **Parallel-battle bonus** (R4Q2): being in more battles adds planning time, asymptotically: +10 s for the 2nd battle, a little less for each one after, reaching +60 s total at 10 battles, then +1 s per extra battle.
2. **Ready / timeout:** final validation of all orders (R4Q3).
3. **Reveal and reaction window** (R2Q4, R3Q4): the sim pauses after reveal, and players scan all battles and issue reactions.
   - **What a reaction is:** a restricted order, triggered by interactions that the revealed orders create (for example, A and B come into range). It costs the squad and/or the commander.
   - **Limits:** there is one reaction timing and no counter-reactions, except niche abilities.
   - **UI:** a radial popup on reactable squads, plus a scrollable reaction queue.
   - **Timing:** the window doesn't draw on reserve time and can be asymmetric, with more battles giving more time (R3Q1). It is configurable off (R2Q4).
   - **Auto-reactions:** conditional-trigger orders are rejected as too deep; contextual auto-reactions exist only as upgrades or unit abilities (R2Q4).
4. **Execute:** time-sliced simulated resolution (R1Q8). Watching playback isn't timed, and while watching, the overworld is locked. Ranked may skip straight to results (R3Q2).
5. **Turn summary:** a brief per-turn change summary (R3Q2). After Intermission it collapses to a menu icon, and every past summary stays browsable (R4Q1).
6. **Intermission** (R4Q1): its own step, without touching reserve. Capped at 30 s (10 s ranked); when at least 50% of players are ready, it drops to 3 s. Legend consequence choices are offered here (R6Q4).

### Cross-context changes
Cross-context changes (reinforcements, transfers, battle results) apply at fixed pulse points in canonical order (R7Q12, R7Q13).

## 2.3 Commanders, armies and battleforces
- **Commanders** (R3Q3, R1Q10): commanders anchor armies and have abilities, though not every ability category and not all usable on the battlefield. Reactions are tied to the commander. The player has a self-insert commander, but campaigns may cast them as others.
- **Armies grow** across a campaign, and a story may carry an army into the next one (R2Q1).
- **Battleforce** (R2Q1): the share of an army that fights in a given battle. Battleforce caps come from campaign or battle rules. Auto-fill defaults to "strongest until the cap", with archetype presets that sort on squad features, and player presets that persist.
- **Staying or dropping off** (R2Q1, R5Q9):
  - **Staying:** the commander stays in the battle, giving commander bonuses and reinforcements from the rest of the army. The *army's* presence is what enables reinforcements (R3Q3).
  - **Dropping off:** the commander drops the battleforce off and leaves. They can leave at the start of any turn while the commander squad isn't deployed. Leaving frees overworld movement.
  - **Garrisons:** drop-off covers every case where forces are needed but oversight isn't, including neutral garrisons that cause battles (R5Q9).
- **Story-essential commanders** (R2Q13): they revive only on easy; otherwise their death fails the mission.
- **Friendly commanders** sharing a hex trade squads and items freely during planning (R7Q9).
- **Armies in play (sw-o1m.2.1):**
  - **Composition:** an army is the commander's own squad plus the squads it holds, up to its template's `army_cap`. The own squad doesn't count toward the cap and is never traded.
  - **Losses persist:** squads keep their losses between battles until refitted.
  - **Starting armies** come from the commander template's `army`.
  - **Trading:** two of a player's commanders on one hex, neither in a battle, trade squads during planning. A trade takes effect at once, within the receiver's cap. Trading with allies waits for campaigns.
  - **Hidden from enemies:** what a hostile army holds is never shown, even when its commander is in sight (R5Q9). Allies see each other's armies.
- **Battleforces in play (sw-o1m.2.2):**
  - **Caps:** the map's `battleforce` sets the most squads and the most total **strength**. Strength is a squad's Value scaled by its units alive.
  - **Lead:** the commander's own squad leads the battleforce and counts toward the caps, unless the plan keeps it out (the drop-off case).
  - **Auto-fill:** strongest first, adding every squad that still fits, so a weakened squad can still fill the last gap. A wiped-out squad never fights.
  - **Archetype presets** (`battleforce_preset` data) rank squads by the first `prefer` feature they have and never pick an `avoid` one. A squad's features are its legend archetype, doctrine and keywords.
  - **Player presets** are saved by name with the game. A player's own preset wins a name clash with a data preset.
  - **Hand-picking:** a plan may list squads instead of using auto-fill, as long as they fit the caps.
  - **Plans persist** across turns. When a commander is pulled into an engagement, its battleforce is picked from the plan and marked deployed there. Ending the engagement releases it.
  - **Fog:** only the owner (and allies) learn what was deployed.
- **Drop-offs and detachments in play (sw-o1m.2.4):**
  - **Planning:** a commander plans one drop-off a turn: after a route step (or before moving), on that hex or 1 hex off the route. Off the route, it costs that hex's movement cost, and the route's later steps must still fit the budget. Shortening the route past the drop-off cancels it. A battle tile takes no drop-offs.
  - **What drops:** the battleforce as planned, with the commander's own squad kept out. A commander with nothing else to drop can't plan one.
  - **Timing:** the drop-off happens on the movement timeline, and later steps come that much later. A commander pulled into an engagement before then drops nothing.
  - **Detachment:** the dropped squads leave the army and hold the hex without a commander. A second drop-off by the same player there joins the same detachment. A detachment stays put unless rallied as a convoy (§2.9, sw-o1m.2.5).
  - **Garrison:** a detachment never takes features (only commanders flip control, R7Q8). A hostile commander entering its hex stops and engages it first.
  - **Fighting:** a detachment dropped onto guards, or meeting hostile forces, is pulled into the engagement. Its strongest squads fight, within the battleforce caps. The commander that dropped it stays free.
  - **Results:** survivors stay on the hex. A detachment on the losing side of a decided battle scatters, and one with no squads left is gone. Draws leave it.
  - **Pick-up:** during planning, a commander of the same player on the hex takes squads back into its army, within its cap. An emptied detachment is gone.
  - **Fog:** a detachment is a sight source (`detachment_sight`). Enemies in sight see that it is there, but never what it holds.

## 2.4 Battles
### Start and duration
- Battles begin at the start of a turn (R2Q1).
- **Battles from engagements (sw-o1m.2.3):**
  - **Start:** an engagement made during a turn becomes a battle at the start of the next one. Its players plan their battle orders in the same planning phase as the overworld.
  - **Shared pulse:** each turn's Execute runs one battle turn in every battle, applies the battles that ended, then resolves the overworld turn. The reaction window isn't offered in these battles yet.
  - **Battlefield:** the first feature on the hex with a `battlefield`, else the map's `battle_scenario`. Sides take the scenario's two deployment areas in order: players ascending, then neutral guards.
  - **Sides:** every player with squads deployed in the engagement. A hex's neutral guards fight at full strength as a neutral side.
  - **Losses carry:** a squad fights with only the units it has left.
  - **Unopposed:** an engagement with only one side (such as a battle activity on an unguarded hex) is won at once.
  - **Results:** survivors return to their armies with their remaining units; destroyed and scattered squads are gone.
    - **Defeat:** a commander whose own squad is gone is defeated, and the rest of its army scatters.
    - **Guards:** beating a hex's guards clears them for good.
    - **Winners** left on the hex then take its features and caches.
    - **Draws** end the engagement with nothing cleared.
  - **Reinforcements:** a commander staying in its battle (its own squad deployed) can send squads from the rest of its army. They join at its side's deployment area before the next battle turn, while its squads still fighting are under the battleforce squad cap.
  - **Leaving:** a commander whose own squad isn't deployed may leave during planning and move that turn. Its battleforce fights on, and survivors return to its army when the battle ends. If its commander left, they form a convoy rallied to it instead (R8Q3, sw-o1m.2.5).
- A typical battle is about 8 turns:
  - T1: scouting and positioning.
  - T2: first casualties.
  - T3–5: main engagement and reinforcements.
  - T6: the victor emerges.
  - T7+: rout and scoring.
- A hard cap on simultaneous battles is found empirically through performance testing (R2Q1).

### Victory conditions (R7Q6)
These are data. The starting set:
- **Annihilation:** a side has no squads on the field and none in reinforcement.
- **Turn limit:** the scenario sets it (default 10). The primary score decides the winner, and the secondary score breaks ties.
- **Score target:** reaching a set number of Victory Points wins immediately.
- **Withdrawal:** a commander leaves with the whole battleforce.

### End-of-battle hooks (R7Q6, R8Q3)
Data-driven behaviour hooks decide what happens to each side's remaining forces.
- **Losers:** for now, the only hook is **scatter permanently**. Future hooks:
  - become re-recruitable at production features
  - rejoin a re-hired commander
  - become scattered overworld battleforces
- **Winners:** they rejoin their commander's army. A dropped-off battleforce becomes a **convoy** that can be rallied to the commander along with any spoils.

## 2.5 Scoring: Influence and Value (R6Q10, R7Q5)
- **Primary and tiebreaker:** each scenario picks one of two scoring options as primary; the other breaks ties. A weighted combination may come later.
- **Influence:** gained by squads fulfilling objectives, mainly by holding **zones**.
- **Value:** gained by destroying enemy Value.

### Zone resolution (each turn, each zone)
1. **Vacuum:** if the zone's influence is at or above the capture threshold, it sinks by its decay (default 10). Below the threshold there is no vacuum (correction to R7Q5, 2026-11-10). Example: a CR-10 squad contested by a CR-1 squad nets 9 a turn: 9, then 18 (captured), then 18 − 10 + 9 = 17, and so on.
2. **Capture Rate:** each faction's **Capture Rate (CR)** is summed over its squads that *end* the turn in the zone, with squad, faction, zone, commander and tag modifiers applied. Human infantry has CR 10 by default. Some units have CR 0, such as the planetary AI's robots in Angelfall (R7Q7).
3. **Net push:** the strongest faction pushes influence toward itself by its CR minus the strongest opposing CR.
4. **Capture:** a zone is captured when influence reaches the threshold (default 10) for a faction.
5. **Buffer:** the holder's influence can fill above the threshold up to a buffer (default 10). The buffer must be eroded before a contest can flip the zone, so a CR-1 squad can't contest a CR-10 squad forever through the drain.
6. **Scoring:** every captured zone scores Victory Points that turn. You score the turn you capture. A zone stays held after you leave until decay or a rival erodes it.

Decay, threshold and buffer are zone data.

## 2.6 Combat
### Accuracy (R3Q7, R4Q9)
Accuracy is the product of four factors: unit, weapon, activity and enemy state or abilities. Examples:
- Moving full-auto fire lands more hits, at worse accuracy, than stationary aimed bursts.
- A point-blank ambush on an unaware target is best.
- Robotic vector calculators ignore their own movement.
- A Lawbringer in a Ruined zone is unfamiliar with their fallback sidearm.
- Intangible targets ignore mundane bullets.

Crits are deterministic "every Nth hit" accumulators (R5Q5). There are no generic +1 upgrades. Gear is per unit: five plasma rifles from a cache arm five units (R3Q7).

### Weapons (R6Q8)
- Each fire mode has its own stats.
- Reload cycles are modelled.
- Ammunition exists only for consumables.
- Simple drop-in damage and simple area-of-effect, StarCraft II / Warcraft III style (R3Q6).

### Damage and defence order (R7Q1)
Each hit passes through the target's **Defensive Profile** (R5Q7) in this order:
1. **Evasion:** avoid the hit.
2. **Block:** a percentage chance to block a percentage amount, Path of Exile style.
3. **Resistance:** per damage type.
4. **Flat** reduction.
5. **Percentage** reduction.
6. **Floor:** a minimum damage per damage type, as data. It defaults to 0, so immunity is allowed.
7. **Temporary HP:** wards and shields soak first.
8. **Hit Points.**
9. **Absorption:** Diablo 2 style. After taking damage of a type, a flat or percentage amount of it is restored as health.

### Defined conditions
Example: **Bad Hit** = a hit greater than 50% of the unit's HP (R3Q10).
- The tooltip shows "(5 HP)" on a 10 HP unit and "(Any Hit)" on a 1 HP unit.
- A +25% *base* HP buff counts towards the threshold; +25% *temporary* HP does not.
- "Sturdy" doubles the threshold, and the tooltip shows it in green as beneficially modified.

### Other combat rules
- **Terrain, line of sight, cover** (R3Q8): these apply. Movement types use feature cost tables (R6Q8).
- **Readying** (R7Q3): a data-driven behaviour in which a squad needs some time before a separate behaviour becomes available, like a siege-mode transformation or building ammunition. While readying, a squad can create Prowess Vacuum, as data. Interrupting a readying squad floats the interrupter's Prowess.
- **Scavenging** (R3Q7): free for now. Survivors pick up squad upgrades, and limited upgrades are re-equipped up to the maximum on the turn after casualties (R4Q10).

## 2.7 Vision, Detection and Concealment
- **Sight** (R8Q1): every squad has a sight radius, limited by line of sight. Sight reveals normal enemies and lifts the fog of war.
- **Detection and Concealment** (R7Q4) are *abilities* some squads have, natively or through abilities or equipment. They are not universal stats.
  - **Detection:** reveals concealed squads within its radius. Its source defines the radius and how Instinct affects it.
  - **Concealment:** its source defines how terrain traits, activities and Instinct affect it.
  - **Cost:** an active Detection or Concealment sinks Instinct. A source that costs 0 is on by default.
  - **As abilities (E3Q7):** both are toggled abilities whose bundles modify two squad stats, `concealment_pct` and `detection_radius`. Terrain and activity modifiers are effect conditions (on a feature, moving, firing within 2 s). Two engine rules apply: Instinct relative to Neutral shifts concealment by about ±25 points, clamped to 0–95%, and Instinct efficacy scales the detection radius.
  - **Toggling** (R8Q2): toggling is a planning order. It takes effect at execute start and is hidden from opponents, who only see its effects.
  - **Auto-off** (R8Q2): when Instinct reaches Broken, or another data-defined band, the effect breaks. Players can configure auto-off rules, such as "after X turns" or "when Instinct is below X".
- **Ambush:** an attack begun while the target hasn't detected the attacker (R6Q1).
- **Intercept:** a charge against an enemy squad that is itself charging one of yours (R6Q1).
- **Information hiding:** disguise, hallucination and cloak abilities plug into this system (R2Q18).

## 2.8 SIMPL pressure systems
Five squad-level pressure systems (R5Q2, R5Q8):
- **S**tamina (formerly Endurance)
- **I**nstinct (formerly Reflex)
- **M**orale
- **P**rowess
- **L**egend

### The shared contract (R4Q4, R5Q1)
- **Pool:** each system is a pool with a capacity. Its percentage maps to five bands:

| Band | Range |
|---|---|
| Surging | 90–100% |
| Primed | 65–89% |
| Neutral | 40–64% |
| Fraying | 15–39% |
| Broken | below 15% |

- **Verbs** (R6Q2): actions and events **Float** a pool (add pressure) or **Sink** it (create vacuum). A pending sink shown in a forecast is **Vacuum**. Crossing into the top band is a **Surge**; crossing into the bottom band is a **Break**.
- **Drift:** every system starts at Neutral and drifts toward it at its own rate.
- **Parameters:** each squad's pools have a starting value, a neutral value, a drift rate and a sensitivity profile (R5Q8). Everything is parameterised for the Pressure Lab (R5Q3, R6Q6).
- **No direct band multipliers** (R5Q4): effects come from composition. If high Instinct raises a squad's accuracy, that squad's data says so. Sensitivity profiles and band traits are content paths.
- **Leaders** (R5Q2, R6Q5): when a surge benefit needs an individual, the squad's unit tagged `leader` uses it. The tag is validated at squad instantiation. When a squad has no leader, it falls back to the highest-proficiency unit, then the lowest ID.
- **Ledger** (R6Q3): all pressure flows are source-tagged into a per-battle ledger, which consequence selection and analytics read.

### Morale: the governor (R4Q4, R5Q1, R5Q3)
- **Generation:** mainly a base rate. Not every commander feeds Morale. Holding objectives is a source for some squads, not universally.
- **No direct damage link:** Morale isn't tied to damage, losses or being attacked, to avoid perverse incentives. Combat affects it only at second order.
- **The only channel between systems:** on a fixed tick interval during Execute, Morale pays into below-Neutral systems, weighted by capacity × deficit. It leeches from above-Neutral systems.
- **Broken Morale:** it leeches pressure from the other systems, so capability degrades according to each squad's strengths and weaknesses. There are no arbitrary failed charges or ignored orders.
- **Later:** contagion and battle-event inputs (R5Q3).

### Stamina (R3Q7, R4Q5)
- **Sinks:** high exertion such as sprinting, sustained running, climbing, building and digging. Stamina can also take damage directly.
- **Effect:** at Neutral, a squad runs at 100% speed and efficacy. Vacuum proportionally reduces the run bonus and dig, climb and build speeds.
- **Recovery:** below Neutral, Stamina receives proportionally more of Morale's distribution.

### Instinct (R4Q6, R5Q5, R7Q4)
Reaction and precision.
- **Affects:** detection range, damage point, the moving-accuracy penalty, turn radius and speed.
- **Sinks:** shooting on the move, being selected for a reaction, and running Detection or Concealment.
- **Split later?** It stays one stat for now; a Precision split happens only if needed.

### Prowess (R6Q1, R7Q2, R7Q3)
Battlefield presence: a squad's effect on the shape and flow of battle beyond raw combat.
- **Sinks:** using magic, readying special attacks or abilities, and commander duels. General melee is not a sink.
- **Floats:**
  - enemy squads reacting to your orders, such as a revealed charge turning their attack-move into a retreat
  - intercepts
  - ambushes
  - interrupting an enemy's readying
- **Duels:** out of the design space for now (R7Q2).

### Legend (R4Q7, R5Q6, R6Q3, R6Q4)
- **Squad-level, outside Morale governance.** Sensitivity profiles tune what touches Legend and what Legend touches.
- **Archetypal actions only for now:** Legend moves on actions that fit the squad's archetype. Damage dealers dealing damage, tanks tanking, scouts revealing and ambushing, sappers hitting buildings and vehicles.
- **Persistent effects:** holding pressure gives minor in-battle bonuses. Only a Surge or a Break makes a persistent change.
- **Consequences:**
  - **Story categories, not bonus/malus.** Persistent changes feed the squad's story. Example: an honour guard's broken Legend lowers its fire priority for enemy autobattle. That hurts its story but enables a break-away gambit through overwhelming fire.
  - **Choosing:** at Intermission, three options are offered and the player picks one.
  - **Tags:** consequences carry loose associative tags (Reputation, Doctrine, Bond, Kit, Burden), not forced groupings.
  - **Unchosen options:** the two unchosen options are archived and later combined into Angel versions of the squad (§2.11).
  - **Upgrades:** surge upgrades are applied in an Intermission popup when immediate; when a refit is needed, they get a notice line instead (R4Q10).
- **Avoid boring pools:** consequence pools shouldn't produce "the killer kills faster". The pool is influenced by what is boosting Morale.
- **Later:** a deep dive is pending.

## 2.9 Overworld
### Map and features
- **Map** (R3Q22, R4Q12): hex plots carry **features**, which come from map-generation passes, player activity and natural events. Features are not prescriptive terrain types. Maps come from seeded templates (R3Q13).
- **Routes** (R4Q12, R4Q13): a commander's planned hex path.
  - **Quick actions along the route:** drop off a battleforce, including up to 1 hex off the route at a movement cost; pick up caches.
  - **Activities:** refit, recruit, a commander-led battle, converting a resource node. These require ending the route on the hex.
  - **Battle tiles:** routing onto a battle tile ends all movement. To route elsewhere, that segment has to be removed.
- **Interaction timing** (R6Q14):
  - **Uncertain outcomes** (negotiation, battle, interactive events) are presented at the start of a turn in which the player has a commander uncontested on the hex.
  - **Stable outcomes** (production, pickups, setting up supply lines) are handled during planning, when routing through.
- **Control** (R6Q14, R7Q8): only Commanders flip a controllable feature, by passing through it. A garrisoned feature needs an engagement first.
- **In play (sw-o1m.1.3):** a turn resolves as movement, then activities, then production; then uncertain features are offered for the next turn.
  - **Caches** are picked up automatically by any commander passing through or ending on an unguarded hex. Stable outcomes are configured while drafting the route and happen as the commander moves.
  - **Activities** are planned per commander. A commander performs one only if it ends the turn on the planned hex and isn't in a battle; the feature's `activity_cost` in Value is paid then.
    - **Convert** replaces the feature with its `converts_to` feature, owned by the player.
    - **Battle** starts an engagement on the hex.
    - **Recruit** names one of the feature's `recruits`. The squad joins at full strength if the army has room, for `activity_cost` plus the option's cost.
    - **Refit** restores every squad of the army to full strength, for `activity_cost` plus `refit_cost` per unit restored. Planning checks the cost against the army's losses at the time; resolving charges for the losses then.
  - **Production:** every controlled feature pays its owner its `value_per_turn`, including one taken this turn.
  - **Offers:** after a turn resolves, each uncertain feature is offered to the one player whose free commanders stand on its hex. A hex with hostile commanders, or an engaged one, gets no offer. What answering does belongs to the trigger layer (sw-cgl.2).

### Guards and movement
- **Guards** (R4Q14, R5Q9, R6Q11, R6Q12): entering a guarded hex triggers an engagement. What overworld forces will do is never revealed before engagement.
- **Banking movement:** commanders whose plan was cut short bank 50% of their unused movement points, capped at one turn, and it expires after the next turn.
- **Neutrals only:** guard and garrison rules apply only to neutral garrisons and features.
- **Chase and intercept** (R3Q22): commander-vs-commander pursuit needs a chase/intercept handler. This is to be specified.
- **Movement in play (sw-o1m.1.2):**
  - **Simultaneous routes:** every route resolves at once, in movement-point time. A commander enters each hex when it has spent that hex's cumulative cost, so whoever gets there first arrives first. Ties go to the lower commander ID.
  - **Stopping:** a commander stops on entering a battle tile (joining it), a guarded hex (starting a guard engagement), or a hex holding a hostile commander at that moment, including one about to leave it. So two hostile commanders can't swap hexes or pass each other. Everyone on a hex where an engagement starts or is joined stops there.
  - **Banking:** only a commander stopped with route steps left banks. Arriving on the planned last hex, or being found there by an enemy, is not a cut plan.
  - **Control:** a commander that passes through or ends on an unguarded hex takes its controllable features.
  - **Pathfinding** for route drafting is the cheapest path, with ties broken by plot index. It doesn't avoid guards, because the player sees the feature but never what its forces will do, and it never continues through a battle tile.
- **Fog of war** (R8Q4):
  - **Sight sources:** commanders, convoys, controlled features and detachments each have a sight radius in hexes.
  - **Allies:** vision is shared with allies.
  - **Memory:** explored hexes keep their last-seen state.
  - **Battle hexes:** their contents are hidden without sight.
  - **In play (sw-o1m.1.4):**
    - **Radius only:** sight is a radius in hexes; overworld terrain doesn't block it yet. Every source sees its own hex. An owned feature is a source; a neutral one isn't. Detachments are sources too (sw-o1m.2.4).
    - **Memory** records each explored hex's features (and owners) and the turn they were last seen. It's recorded at the start and end of every turn and around every hex a commander enters, so hexes glimpsed on the way are explored too. Commanders are never remembered, only seen.
    - **Battle tiles are public:** every player knows where battles are, because a route onto one ends there. What's in a battle (who and why) needs sight.
    - **Orders use what the player knows.** Pathfinding, route costs and planned activities see unexplored hexes as open ground and explored ones as last seen. Movement uses the truth, so a route into an unseen lake stops at its shore without banking.
    - **Events:** a player sees an event about its own or an allied commander or player, or on a hex it saw during that turn. Other battle starts and ends arrive reduced to where.
    - **Allies** are players on the same team; until campaigns set teams, everyone is hostile.

### Production and logistics (R5Q10, R6Q13)
- **Distributed production:** production is spread across the map, Civilization-like, without tending cities. Features provide production and recruitment activities, like visiting HoMM dwellings and mines.
- **Configuring:** some features let the player select, upgrade or change their output. Most can set up rally routes, or **supply lines**, carried by **convoys**.
- **Convoy merging:** convoys on the same hex along the same supply line merge for interaction, with squads configurable together and items forming one war chest, until they split.
- **Intent:** this design encourages multiple commanders, consolidating battleforces and protecting supply lines.
- **For now:** simple squad, item and resource tiles. Faction or allegiance variants come later.
- **In play (sw-o1m.2.5):**
  - **Production:** a feature's `produces` lists squads it can make. Its owner selects one (the first by default). Each turn it advances one step; on reaching the option's `turns`, the squad is made for the option's `cost` in Value. While the owner can't pay, it waits, ready to go.
  - **No supply line:** produced squads join the owner's detachment holding the feature's hex, which garrisons it until a commander picks them up.
  - **Supply lines:** the owner sends a feature's output to a plot or to one of its commanders. Each squad leaves as a convoy on that line, and changing the line redirects convoys already on it. Capturing the feature resets its output and progress, and its line lapses.
  - **Rallies:** a player sends any of its detachments to a plot or a commander, which makes it a convoy; rallying it nowhere halts it. Survivors of a commander that left its battle rally to it (R8Q3).
  - **Convoy movement:** a convoy is a detachment with a destination. Each turn it walks the cheapest path it knows, around hexes it knows are guarded, for the map's `convoy_movement` points. It moves on the commanders' timeline, after commanders at equal times.
  - **Interception:** like any detachment, a convoy entering a hex with hostile forces or guards, or entered by a hostile commander, is pulled into an engagement and stops. Survivors of a battle it wins carry on.
  - **Arrival:** at its plot, a convoy holds the hex, joining the player's detachment there. At its commander's hex, its squads join the army up to the cap, and the rest halt there. A convoy whose commander is gone halts where it is.
  - **Merging:** after movement, convoys of one player on the same hex and line merge into one.
  - **Fog:** convoys are sight sources like detachments. Enemies in sight see a convoy and where it moves, but not what it holds or where it's going.
  - **Items** produced by features come with the War Chest (sw-o1m.2.6).

### Economy (R2Q15, R5Q11, R6Q15)
- **Value is the sole resource.** It recruits commanders and squads and buys equipment. Supplies, Materiel and Manpower collapse into Value for now.
- **Story experiments:** collectible assets at merchants, trading production for Value, and meta-campaign investments.
- **The real scarcity** is multitasking.
- **Extensibility:** the architecture stays extensible toward deep resource modelling.

### Inventory: the War Chest (R4Q10)
- **The army's inventory:** sortable and filterable, with icons and hover tooltips. A detail view lets you equip valid units.
- **Equipped tab:** organised by squad, for swapping.
- **Availability:** usable anywhere on the overworld outside battle.
- **Refitting** vehicles, monsters and unique units needs special plots.
- **Later:** auto-equip rules.

## 2.10 Magic and Ruin in play (R1Q15, R2Q8, R4Q21)
- **Zones:** plots and battlefield areas carry a magic condition: Law (normal), Ruined or Null.
- **Ruin** is a zone condition. It raises costs, lowers efficacy and restricts types, regardless of how the magic is accessed, like denial-of-service or 500 errors. Ruin effects are ordinary effects in the effect language (§2.13), selected through tags.
- **Null:** no magic works.
- **Raw magic** doesn't become available where the Law fails, except in "wacky" scripted circumstances.

## 2.11 Angels in play (R3Q17, R5Q6, R6Q17)
- **Driven by behaviour data:** Angels are an undirected narrative force (not a player faction), driven by behaviour data through the trigger system.
- **Interference:** they act as filler interference. They give battle in front of resources, eat turn timers with nonsense dialogue, and steal or move overworld items.
- **Inverted auto-resolve:** a commander with no battleforce can temporarily disperse Angels by engaging them. This is required to clear movement-blocking Angels in the Angelfall mission, but it doesn't work in the final key battles.
- **Accumulation:** every Angel not fought becomes one to face later. In the preventable-Angelfall campaign, Angel forces are added or replaced with squads built from the player's unchosen Legend consequences.

## 2.12 Disconnects (multiplayer) (R6Q23, R7Q10, R7Q11)
- **Pause:** the game pauses and gameplay locks. Lobby chat stays available, showing the dropped player's status.
- **Countdown and vote:** after a 30 s reconnect countdown, the remaining players vote:
  - **Drop:** an AI takes over immediately. Not available in ranked.
  - **End:** return to the multiplayer screen.
  - **Return to lobby:** the same players and settings.

  Players may keep waiting. The vote needs majority+1, dropping to a simple majority after another 30 s. End and Return-to-lobby both count toward ending.
- **Host drop:** host migration runs first, then the flow above, authoritative from the new host.
- **Ranked:** a vote-ended match is a forfeit for the disconnected side, and void if everyone dropped. There are no penalties until usage data exists.

## 2.13 The effect language (sw-p2q.1, E1–E4)
One language describes every simulation-side effect: abilities, statuses, equipment, traits and keywords, terrain features, zone conditions (including Ruin), Legend consequences, commander abilities and overworld feature effects. Items, weapons and abilities share effects the way they do in Brotato (E1Q1). The campaign trigger layer (§3.5) stays separate and *invokes* effects.

### Effects and bundles (E1Q2, E2Q13)
- An **effect** is: operation, target, magnitude, condition, duration, stacking, tags, source.
- Abilities, statuses, items and features are named **bundles** of effects. Bundles are package templates: referenced by ID, inheritable, schema-validated.
- The vocabulary (operations, selectors, conditions) is **closed** and engine-provided. Data never holds formulas. New vocabulary arrives with engine updates, and later through opt-in Lua operations (E1Q4).
- **Magnitudes** are a constant, or a constant **per stack**. Stack counts come from auras, selector counts, accumulator values or pool values. There is no separate scaler category (E4Q2).
- **No chance** (E1Q6): accumulators replace it, and their counters are visible.
- **Tags** go on everything: effects, abilities, weapons, damage. Selection, resistances, restrictions, Ruin and Null all work through tags. The tag list is a moddable registry with glossary entries (E1Q7, E2Q10).

### Stats (E1Q3, E3Q1, E3Q2, E3Q4)
- Effects touch **registered stats** only. The registry is derived from the schemas and covers every stat, each with a glossary name, unit, rounding, min/max and scope (unit or squad). A value without a data field gets one, with a sensible default. For example, a reaction's cost is `ability.activation.costs.instinct`.
- Systems read **effective values**, never raw data.
- HP, temporary HP and every pool are fixed-point. One decimal is shown only when the value is fractional. Death is at HP ≤ 0, and thresholds compare exact values.
- **Ratio-keeping:** when a maximum changes, every current/max pair keeps its ratio, unless the effect is flagged *restores*. Example: 17.5/22.5 becomes 11.66/15 when a +50% increased max wears off.

### Modifier order (E2Q1)
PoE-style wording: **"% increased"** values add together; each **"% more"** multiplies separately.

base → flat → summed increased → each more in turn → override → clamp → one rounding.

Every step is recorded in a **trace**, which the inspection window shows. Showing the calculation is the answer to PoE's opacity.

### Applying changes (E2Q2)
Lasting effects change computed values. Damage and other one-off changes are **queued** against their owner, and the owning system applies them; for example, the health system applies damage. All fire in a tick therefore lands simultaneously.

### Selectors, hooks, stacking, durations (E2Q3–E2Q7, E3Q10)
- **Selectors** order results deterministically: distance, then ID. "Within a distance of tagged allies/enemies" is tracked only out to the furthest range any active effect uses.
- **Hooks:** an effect may trigger further effects one level deep (hard chain depth 1), with optional cooldowns. More hooks can be added later, and the depth rule may be relaxed.
- **Stacking:** refresh (the default), stack, independent, or strongest, counted per source or per target.
- **Durations:** time; overworld **distance** (hexes the holder enters by its own movement); and story-campaign **banks** (per profile and namespaced, with cross-campaign reads declared in the manifest; story campaigns only) (E3Q9).
- **No conversion** in v1: only "extra damage as type X" (E2Q8).

### Accumulators (E2Q9)
Fields: starting value, value, step size, counted event (second, attack, hit, health lost, distance, squad casualty, …), threshold and reset condition. Tooltips name the event, e.g. "next in 2 hits", "next after 10 metres", "next after losing 10 hit points".

### Abilities (E2Q10, E3Q6, E3Q7)
- An ability is a bundle plus an **activation**: costs, cooldown, charges, ready time, range, targeting, toggle.
- Abilities are planning orders validated against their activation. Toggles (Detection, Concealment) and reactions are abilities.
- **Readied states:** what the state does, how long it lasts and which conditions lose it are all data.
- **Activation in play (sw-ps1.5):**
  - **Using an ability:** an order's ability entry is checked against cooldown, charges, costs, targeting and range, then applied at execute start. A squad-targeted bundle is held by the target and sourced from the user.
  - **Toggles:** a toggle pays upkeep every tick while on. It switches off when a pool it sinks reaches its auto-off band.
  - **Reactions:** a reaction pays its costs (Instinct, default from the ruleset) when it fires on contact. Its bundle sees the trigger as "other". Reaction bundles use the `order` operation: hold, fall back, or attack the selected squad.
  - **Readying:** readying sinks the squad's Prowess every second (the Vacuum), then applies the bundle as the readied state. Its `lose_on` events (move, attack, damaged, casualty) cancel readying or end the state. An enemy that interrupts readying floats its own Prowess.
  - **Instant bundles:** a bundle with only on-application effects and no duration is released as soon as it has acted.
  - **Stats:** activation numbers are `ability.activation.*` stats, so effects can change them for a whole squad.

### Text and inspection (E1Q5, E2Q3, E2Q11, E2Q12, E3Q8)
- Rules text is generated from data via localised templates with glossary terms and live values. Authors write flavour text only.
- Show calculated numbers, never words like "recently".
- Anything visible is inspectable, except deception-tagged effects, which show their disguise.
- An **inspection window**, available in planning and playback, gives per-unit breakdowns behind tabs or unit cards. Comparison tooltips show how unit and squad stats would change.
- The UI only formats values it receives from the Game API; it never computes them.
- **The inspection call (sw-ps1.6):** `BattleSession.inspect(player, squad)` returns, for one squad:
  - **Strength:** living units against the template's starting count, e.g. "7 / 8 units".
  - **Squad and per-unit stats:** each with base, effective value and the step trace. Trace terms name the bundle each modifier came from, and every fire mode is listed.
  - **Effects held:** stacks, remaining ticks, rules text and accumulator progress, e.g. "Next in 2 hits".
  - **Own squads only:** pools and abilities (state, cooldown, charges, effective costs, rules text).
  - **Visibility:** own squads are always inspectable; enemy squads only while seen. For anyone but the owner, deception-tagged bundles appear as their disguise, in the effects list and in the traces.
