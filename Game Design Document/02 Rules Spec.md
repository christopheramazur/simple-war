# 2. Rules Spec

The simulation's rules. This document is authoritative over the code: if they disagree, either the code is a bug or this document needs a decision-log entry. Numbers given here are **starting defaults held in data**, not constants (R5Q3, R6Q6).

## 2.1 Foundations
- **Determinism** (R1Q7): the same inputs plus the same seed give the same result on every machine. Sim state uses fixed-point integers with **FPDR (Fixed Point Defined Rounding)** (R4Q8). There are no floats in the simulation.
- **No hidden randomness** (R2Q6): chance is replaced by modifiers and deterministic accumulators ("every Nth hit is a crit", R5Q5). Seeds exist only for content generation (map templates).
- **Space** (R2Q5): battles use continuous fixed-point space. The overworld is a hex grid; each hex is a **plot** (R3Q22).
- **Simulation scale** (R1Q9): every model (**Unit**) is simulated. The **Squad** is how units are organized for command. Individual Unit data overrides squad defaults.
- **Transparency** (R1Q3, R3Q10): every calculation exposes its terms for context-aware tooltips. The displayed number is the used number.

## 2.2 The turn and the pulse
### Clock
- By default, the overworld and every battle share one **pulse**: one overworld turn equals one turn in each battle (R2Q3). Independent clocks are a configurable option (R2Q3).
- The turn and timing system is isolated, so the overworld and battles can run separately or together (R2Q1).

### Turn sequence
1. **Planning** (R3Q1, R4Q3): about 60 s by default, with a reserve top-up system. Players issue orders in every context they're in.
   - The server forecasts interactions continuously as orders are drafted and keeps a reaction dictionary. Forecasts show *Vacuum* (pending sinks) and intent ghosts (R4Q3, R6Q2).
   - **Forecast:** `IntentForecast` runs the coming turn on a scratch copy with the player's drafted orders.
     - **Output:** each own squad's path as ghosts, plus the contacts it would make, with the reactions it could use.
     - **Fog:** enemies the player can't see yet are taken out of the copy, so the forecast never reveals them. Other players' drafts stay secret, so their squads keep their current orders.
     - **Not yet:** *Vacuum* forecasts.
   - **Parallel-battle bonus** (R4Q2): being in more battles adds planning time, asymptotically: +10 s for the 2nd battle, a little less for each one after, reaching +60 s total at 10 battles, then +1 s per extra battle.
	- **Configurable**: Parallel activities and their bonuses are configurable, data-driven values.
   - **Deployment** (U1Q9, U1Q30): a battle planned for the first time is also deployed in this Planning (§2.4 Deployment).
2. **Ready / timeout:** final validation of all orders (R4Q3).
3. **Reveal and reaction window** (R2Q4, R3Q4): the sim pauses after reveal, and players scan all battles and issue reactions.
   - **What a reaction is:** a restricted order, triggered by interactions that the revealed orders create (for example, A and B come into range). It costs the squad and/or the commander.
   - **Limits:** there is one reaction timing and no counter-reactions, except niche abilities.
   - **Only visible triggers:** a squad can react only to an enemy squad its player already sees when orders are revealed. A contact with an enemy still hidden at Reveal is no opportunity, so the window never hints at unseen enemies.
   - **UI:** a radial popup on reactable squads, plus a scrollable reaction queue.
   - **Marks and queue:** reactable squads are marked with "!" (or the queued reaction's glyph). Clicking one opens the radial: each reaction is a glyph plus its name. The side panel lists every opportunity across battles as the queue, and clicking an entry jumps to its battle and squad. A selected reactable squad (clicked, or picked from the queue) shows what it would react to: a dashed line to each triggering enemy, ringed and labelled "trigger".
   - **Timing:** the window doesn't draw on reserve time and can be asymmetric, with more battles giving more time (R3Q1). It is configurable off (R2Q4).
   - **Auto-reactions:** conditional-trigger orders are rejected as too deep; contextual auto-reactions are intended to exist only as upgrades or unit abilities (R2Q4).
   - **Order at Reveal** (proposed): deployments, then vision, then reinforcements, then orders; the reaction window then opens on what is visible.
4. **Execute:** time-sliced simulated resolution (R1Q8). Watching playback isn't timed. Ranked may skip straight to results (R3Q2).
   - **Watching is reading, not acting** (R3Q2 as amended by U1Q32): playback only shows a turn that has already resolved, so watching never changes it. During playback of a battle or of the overworld:
     - **Allowed:** every camera control (pan, zoom, centre, follow) and every information view: hover tooltips, the hex and feature panels, squad cards, inspection windows, battle relations, the glossary, and selecting things to inspect them.
     - **Refused until Planning:** anything that plans or acts: orders, routes, reactions, deployments, purchases, owner actions, rally changes and production choices. Their controls are disabled and say why.
   - **Watching a battle** (U1Q6, U1Q7, U1Q32): the battle camera pans and zooms as in Planning, and the player can hover and select squads. Selection made while watching carries into the next Planning (proposed).
   - **What a squad is doing about another** (U1Q8; proposed): see §2.6 "Pair relations". During playback, the relations are those of the moment being shown.
5. **Turn summary:** a brief per-turn change summary (R3Q2). After Intermission it collapses to a menu icon, and every past summary stays browsable (R4Q1).
6. **Intermission** (R4Q1): its own step, without touching reserve. Configured for 30 s (10 s ranked) by default; when at least 50% of players are ready, it drops to 3 s if not already under 3 s. Legend consequence choices are offered here (R6Q4).

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
- **Armies:**
  - **Composition:** an army is the commander's own squad plus the squads it holds, up to its template's `army_cap`. The own squad doesn't count toward the cap and is never traded.
  - **Losses persist:** squads keep their losses between battles until refitted.
  - **Starting armies** come from the commander template's `army`.
  - **Trading:** two of a player's commanders on one hex, neither in a battle, trade squads during planning. A trade takes effect at once, within the receiver's cap. Trading with allies waits for campaigns.
  - **Hidden from enemies:** what a hostile army holds is never shown, even when its commander is in sight (R5Q9). Allies see each other's armies.
- **Battleforces:**
  - **Caps:** the map's `battleforce` sets the most squads and the most total **strength**. Strength is a squad's Value scaled by its units alive.
  - **Lead:** the commander's own squad leads the battleforce and counts toward the caps, unless the plan keeps it out (the drop-off case).
  - **Auto-fill:** strongest first, adding every squad that still fits, so a weakened squad can still fill the last gap. A wiped-out squad never fights.
  - **Archetype presets** (`battleforce_preset` data) rank squads by the first `prefer` feature they have and never pick an `avoid` one. A squad's features are its legend archetype, doctrine and keywords.
  - **Player presets** are saved by name with the game. A player's own preset wins a name clash with a data preset.
  - **Hand-picking:** a plan may list squads instead of using auto-fill, as long as they fit the caps.
  - **Plans persist** across turns. When a commander is pulled into an engagement, its battleforce is picked from the plan and marked deployed there. Ending the engagement releases it.
  - **Fog:** only the owner (and allies) learn what was deployed.
- **Drop-offs and detachments:**
  - **Planning:** a commander plans one drop-off a turn: after a route step (or before moving), on that hex or 1 hex off the route. Off the route, it costs that hex's movement cost, and the route's later steps must still fit the budget. Shortening the route past the drop-off cancels it. A battle tile takes no drop-offs.
  - **What drops:** the battleforce as planned, with the commander's own squad kept out. A commander with nothing else to drop can't plan one.
  - **Timing:** the drop-off happens on the movement timeline, and later steps come that much later. A commander pulled into an engagement before then drops nothing.
  - **Detachment:** the dropped squads leave the army and hold the hex without a commander. A second drop-off by the same player there joins the same detachment. A detachment stays put unless rallied or steered as a convoy (§2.9).
  - **Garrison:** a detachment never takes features (only commanders flip control, R7Q8). A hostile commander entering its hex stops and engages it first.
  - **Fighting:** a detachment dropped onto guards, or meeting hostile forces, is pulled into the engagement. Its strongest squads fight, within the battleforce caps. The commander that dropped it stays free.
  - **Results:** survivors stay on the hex. A detachment on the losing side of a decided battle scatters, and one with no squads left is gone. Draws leave it.
  - **Pick-up:** during planning, a commander of the same player on the hex takes squads back into its army, within its cap. An emptied detachment is gone.
  - **Fog:** a detachment is a sight source: a garrison sees 1 hex, a caravan 3 (its band kind, U1Q27). Enemies in sight see that it is there, but never what it holds.

## 2.4 Battles
### Start and duration
- Battles begin at the start of a turn (R2Q1).
- **Battles from engagements:**
  - **Start:** an engagement made during a turn becomes a battle at the start of the next one. Its players plan their battle orders in the same planning phase as the overworld.
  - **Shared pulse:** each turn's Execute runs one battle turn in every battle, applies the battles that ended, then resolves the overworld turn. On turns with battles, the reaction window opens after Reveal: reinforcements and every battle's orders apply at Reveal, each battle's coming turn is forecast, and players react across all their battles. A player with nothing to react to is ready at once, and turns without battles skip the window. Each player's battle count sets its bonus planning and reaction time.
  - **Battlefield:** the first feature on the hex with a `battlefield`, else the map's `battle_scenario`. Sides take the scenario's two deployment areas in order: players ascending, then neutral guards.
  - **Sides:** every player with squads deployed in the engagement. A hex's neutral guards fight at full strength as a neutral side.
  - **Losses carry:** a squad fights with only the units it has left.
  - **Unopposed:** an engagement with only one side (such as a battle activity on an unguarded hex) is won at once.
  - **Results:** survivors return to their armies with their remaining units; destroyed and scattered squads are gone.
    - **Defeat:** a commander whose own squad is gone is defeated, and the rest of its army scatters.
    - **Guards:** beating a hex's guards clears them for good.
    - **Winners** left on the hex then take its features and caches.
    - **Draws** end the engagement with nothing cleared.
  - **Reinforcements:** a commander staying in its battle (its own squad deployed) can send squads from the rest of its army. They join at its side's deployment area before the next battle turn, where the player placed them or at its centre (Deployment, below), while its squads still fighting are under the battleforce squad cap. Nothing joins by itself: the player sends each squad during Planning, from the reserves list beside the battle's orders, and the battle menu says when reserves can join.
  - **Joining late:** a player who enters a battle tile after the battle began becomes a new side before the next battle turn.
    - **Where:** it arrives at whichever of these is farthest from every squad already fighting, the first on a tie: the scenario's deployment areas, then a strip of the same size along the middle of the top edge, then the bottom edge. It places its squads there itself (Deployment, below); squads it doesn't place spread along the area and face the middle of the field.
    - **The clock doesn't restart:** the battle's turn limit and scores carry on, so a side that joins late has fewer turns.
    - **Everyone is hostile:** a battle has no teams yet, so allies who join the same battle would fight each other.
  - **Leaving:** a commander whose own squad isn't deployed may leave during planning and move that turn. Its battleforce fights on, and survivors return to its army when the battle ends. If its commander left, they form a convoy rallied to it instead (R8Q3).
- A typical battle is about 8 turns:
  - T1: scouting and positioning.
  - T2: first casualties.
  - T3–5: main engagement and reinforcements.
  - T6: the victor emerges.
  - T7+: rout and scoring.
- A hard cap on simultaneous battles is found empirically through performance testing (R2Q1).

### Deployment (U1Q9, U1Q30, U1Q31)
A battle starts with a deployment step: each side places its squads inside its deployment area before battle turn 1 (U1Q9).
- **When** (U1Q30): in the Planning phase in which the battle is first planned (the one after the engagement became a battle). It is not an extra turn: the same Planning also drafts battle turn 1's orders, as in Steel Division's phase 0. The battle's turn limit is unchanged.
- **Hidden and simultaneous** (U1Q30): both sides place at once. While a battle is deploying, a player sees their own squads, every side's deployment area, the terrain and the zones, but no enemy squad, even one that would be in sight. Placements are secret like orders. Battle turn 1's orders therefore can't target an enemy squad (none is visible); move, attack-move, hold and the other orders work.
- **What is placed:** each squad's position (its formation anchor) and its facing, anywhere in the side's deployment area (U1Q30). The anchor snaps to the nearest cell the squad can enter (§2.14). Squads may share ground, since nothing blocks (§2.14). The sim takes any facing and the UI snaps it to 8 directions; formation shape is the squad template's until squads have formations of their own (proposed).
- **Defaults** (U1Q31): every squad starts at its automatic place: the scenario's `placed` position if it has one (its cell, or the nearest one it can enter), else the even deal over the rest of the area, as today. Placed entries are defaults the player may move, unless `locked: true` pins them. Battles started from the overworld ignore `placed` (Data Model §3.5). A squad the player doesn't move stays there, and a timeout keeps whatever has been placed. AI controllers and neutral guards use the automatic places unless their controller places them (proposed).
- **Reveal** (proposed): placements apply first, in canonical order (players ascending, then squad ID), then vision is computed, then reinforcements and orders apply as usual. The reaction window that follows sees the revealed deployment. An enemy seen at Reveal is a valid trigger (§2.2 "Only visible triggers").
- **Joining late** (proposed): a player who becomes a new side (Joining late, above) deploys the same way into its arrival area in the Planning before it arrives. The arrival area is chosen when that Planning starts (squads don't move between Execute and Reveal) and shown to that player only. When two sides join in the same Reveal, they are resolved in ascending player order: each later joiner treats the areas of those before it as occupied, so they do not land on each other.
- **Reinforcements** (proposed): a squad sent as a reinforcement may be given a place (and facing) inside its side's deployment area when it is sent. Otherwise it arrives at the area's centre as today. It appears at Reveal.
- **Scenario switch** (proposed): a scenario's `deployment` is `open` (default) or `fixed` (no step: squads start at their automatic places, for scripted and tutorial battles; Story battles stay `fixed` until the tutorial teaches deployment). An ambush start that skips deployment is a later option.
- **Determinism** (proposed): placements are inputs like orders (validated by the sim, logged, saved with the battle and replayed). Automatic places are exactly today's deployment, so a battle with no placement input runs as before.
- **Time** (proposed): deployment uses the Planning timer. A player gets `deployment_bonus` extra seconds (clock config; default 15 s, 10 s ranked) for each battle they deploy in that Planning, on top of the parallel-battle bonus.

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

### Fire distribution (U1Q14, U1Q16)
How a squad's hits are spread across the units of the squad it engages.
- **In play:** each unit fires at the nearest unit it can hit, skipping units its squad's queued damage this tick already covers (`nearest`). Kill priority below is proposed.
- **Default policy** (U1Q33): `nearest` stays the default until the Pressure Lab sweep of fire distribution (D6). Then the default switches to `prowess` (§2.8 Prowess) in one commit with a new baseline era (D7).
- **Proposed (Round U1, awaiting review):**
  - **Two levels:** the squad picks the enemy squad (attack target, else sticky, else nearest in reach); each ready unit then picks a victim within it. The victim rule is a **targeting policy**, data-selected by the ruleset (`fire.policy`).
  - **What a shooter knows:** only enemy units its side sees; their current HP and Defensive Profile; and, when coordinated (§2.8 Prowess), the hits its own squad has already queued this tick. Never a target's evasion or block accumulators.
  - **Remaining HP:** a unit's HP minus the *expected* effective damage queued on it this tick: each queued hit run through the Defensive Profile without evasion and block. A unit is **covered** when its remaining HP is 0 or less. Covered units are skipped while another victim is in reach.
  - **Kill priority:** candidates in reach, lowest remaining HP first, then lowest unit ID. For mixed damage, a hit that can finish a unit prefers the unit it overshoots least.
  - **Area of effect:** a fire mode with an area picks the victim whose radius holds the most units its hit would finish, then the most effective damage.
  - **Simultaneous fire:** all hits of a tick apply together after fire. A hit on a unit already killed that tick is **wasted**; with the damage beyond the killing hit's need it makes up **overkill**. Damage granularity sets an unavoidable floor (a 3-damage hit needs 12 damage for a 10 HP unit).
  - **Shown:** tracers show where a squad's fire goes; the inspection window shows the squad's focus width and coordination and their terms (§2.1 Transparency).

### Defined conditions
Example: **Bad Hit** = a hit greater than 50% of the unit's HP (R3Q10).
- The tooltip shows "(5 HP)" on a 10 HP unit and "(Any Hit)" on a 1 HP unit.
- A +25% *base* HP buff counts towards the threshold; +25% *temporary* HP does not.
- "Sturdy" doubles the threshold, and the tooltip shows it in green as beneficially modified.

### Other combat rules
- **Terrain, line of sight, cover** (R3Q8): these apply. Movement types use feature cost tables (R6Q8).
- **Range and vision** (2026-11-17): a squad engages enemies its *side* can see (shared spotting), within its weapon range. In range means unit to unit (U1Q28, sw-txnj.5): some armed unit of the squad has some living unit of the enemy squad within its own weapon's range, so a squad engages as its first unit comes into range, not when the squads' centres are a weapon range apart.
  - **Direct fire:** each shooter also needs its own line of sight to the unit it hits.
  - **Indirect fire:** a fire mode flagged `indirect` (the mortar) needs no line of sight. A spotted target in range is enough, so spotters matter to artillery.
  - **Attack orders** (U1Q11, U1Q28, U1Q29; details proposed): see §2.15 Closing to fire. Each armed unit of an attacking squad walks to its own firing position, within the squad's coherency radius, and opens fire there on its own as soon as it can. A unit has a shot when its own weapon reaches a living unit of the engaged squad (outside its minimum range) and it has a line to that unit, or the weapon is indirect. The anchor advances until every armed unit has a firing position. Squads built around one long weapon still stop at that weapon's range; mixed squads walk their short weapons in.
    - **In play until it is built:** an attacking squad stops to fight once it has a shot (target in reach, and an indirect weapon or a unit with a clear line). It keeps standing while its weapons reload or cool down. It closes in only when no unit has a shot, so slow weapons that can't fire on the move don't walk into the enemy.
  - **Shown:** with one squad selected, each visible enemy is marked "in range" (it has a shot), "no line of fire" (in reach, but no unit has a line), and "spotted" when only allies see it. The marks come from the same rule (LineOfFire) the attack orders use. They show in Planning, and during playback (U1Q8; proposed for playback).
  - **Pair relations** (U1Q8; proposed, Round U1, awaiting review): with a squad selected (or inspected) and another hovered, a tooltip lists what each is doing about the other; the right-click comparison menu lists all of it. Each line is one *relation fact*, and each fact names the rule it comes from:
    - **Range** (§2.6 Range and vision): in range, no line of fire, too close (inside a fire mode's minimum range), or out of range with the gap in metres; with how many of the selected squad's units have a shot. From the per-unit shot gate the fire pass uses.
    - **Sight** (§2.7): sees it with its own eyes, or only through allies' spotting.
    - **Targeting** (§2.6 Attack orders): firing at it, or aiming at it but not firing, with the hold-fire reason (reloading, cooling down, no line of fire, ...); or ordered to attack it and closing in; or, with no attack order, it is the enemy the squad would engage next (the same nearest-visible-in-reach rule the sim uses).
    - **Under fire** (§2.6): the hovered squad fired at the selected one recently.
    - **Fleeing** (§2.6, fall back): falling back or withdrawing away from it, when it is the enemy the fall-back runs from.
    - **Moving toward / away** (behaviour only): which way it is moving relative to the other squad.
    - **Coming contact** (§2.2 Forecast, Planning only): the forecast contact between the two, its time and outcome summary, with the forecast caveat beside it.
    - **Reaction** (§2.2 reaction window only): the hovered enemy triggers a reaction of the selected squad, or a queued reaction targets it.
  - **Same rules, not a copy** (U1Q8): relation facts are computed by the functions the simulation runs (shot gate, target pick, fall-back threat, LineOfFire, the forecast), never by a parallel formula. During playback they are computed on the battle state at the moment shown (proposed).
  - **Fog** (proposed): relations exist only between squads the viewer can see. About an enemy squad, only what its behaviour shows: whether it fired at a squad, whether it is moving, which way, and what its public weapon range reaches. Never its orders, its chosen target before it fires, its hold-fire reasons or its reload. This is the rule `BattleActivity.squad_seen` already applies to activity.
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

### Prowess (R6Q1, R7Q2, R7Q3, U1Q15)
Battlefield presence: a squad's effect on the shape and flow of battle beyond raw numbers, including how well it distributes its fire (U1Q15).
- **Fire discipline** (U1Q15, U1Q17, U1Q18; proposed, Round U1, awaiting review; numbers are data):
  - **Efficacy:** Prowess value / Neutral, from 0 up to capacity / Neutral (about 1.9 by default). Unlike Instinct it rises above 1.
  - **Focus quality** q = discipline × efficacy, clamped to 0–1. A unit fires at the nearest of the first K units in kill priority (§2.6 Fire distribution), where K = 1 + (1 − q) × (candidates − 1). The fraction of K is carried by a per-unit accumulator, so the fuzz is deterministic (R2Q6). q = 1 is the kill-maximising distribution (U1Q14, U1Q15); q = 0 is plain nearest-target fire, spread thin (U1Q16).
  - **Coordination** c = coordination × efficacy, clamped to 0–100%. Each volley adds c to a per-unit accumulator; when it reaches 100 the unit sees its squad's queued hits this tick and skips covered units. Otherwise it sees only HP already lost and may pile onto a unit that is about to die: overkill (U1Q16, U1Q18).
  - **Arithmetic:** q, K and c are integer permille with defined rounding, like all sim maths (§2.1).
  - **By band, with the defaults** (discipline 60%, coordination 70%): Neutral focuses on a few units with some fuzz (q ≈ 0.5–0.7, c ≈ 55–85%) (U1Q17); Surging approaches the optimum (q = 1, c = 100%) and swaps off covered units at once (U1Q18); Fraying spreads and overkills (q ≈ 0.2–0.45, c ≈ 20–50%); Broken is worse still.
  - **Which way a squad fails is content:** a low-discipline squad (militia) spreads its fire; a high-discipline, low-coordination squad (zealots) piles on; a datalinked squad (CR-0 robots) keeps coordination at 100%.
  - **No direct band multipliers (R5Q4):** discipline and coordination are squad stats that effects can modify; efficacy is continuous.
  - **When it applies** (U1Q33): fire discipline is the `prowess` policy. It becomes the default after the Pressure Lab sweep (D7); until then the default is `nearest` (§2.6 Fire distribution).
- **Not a float** (proposed): kills and efficient volleys do not float Prowess, which would snowball (compare Morale's no-damage link).
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
  - **Stable outcomes** (pickups, captures) happen as a commander routes through. Settings an owner keeps on its features (production output, rally points) and owner actions are made during planning from anywhere, with no commander (U1Q24).
- **Control** (R6Q14, R7Q8): only Commanders flip a controllable feature, by passing through it. A garrisoned feature needs an engagement first.
- **Turn order:** a turn resolves as movement, then activities, then production; then uncertain features are offered for the next turn.
  - **Caches** are picked up automatically by any commander passing through or ending on an unguarded hex. Stable outcomes are configured while drafting the route and happen as the commander moves.
  - **Activities** are planned per commander. A commander performs one only if it ends the turn on the planned hex and isn't in a battle; the feature's `activity_cost` in Value is paid then.
    - **Convert** replaces the feature with its `converts_to` feature, owned by the player.
    - **Battle** starts an engagement on the hex.
    - **Recruit** names one of the feature's `recruits`. The squad joins at full strength if the army has room, for `activity_cost` plus the option's cost.
    - **Refit** restores every squad of the army to full strength, for `activity_cost` plus `refit_cost` per unit restored. Planning checks the cost against the army's losses at the time; resolving charges for the losses then.
  - **Owner actions** (U1Q24; proposed, Round U1, awaiting review): a feature's owner may use it without a commander. Actions are planned during Planning and resolved after activities. A feature lists which ones it allows in `owner_actions`; the vocabulary is closed:
    - **Buy:** one option of its `recruits` (a squad) or its `sells` (items, `count` per purchase). It costs the option's cost plus the feature's `remote_markup` percent (default 25, rounded up). Buying in person stays the commander's `recruit` activity, at the plain price, straight into the army.
    - **Rally point:** set or clear where the feature's output goes (its supply line; see Production and logistics). Already an owner setting; listed here so the UI offers it per feature.
    - **Output:** choose which `produces` option it makes.
    - **Limits:** each feature takes `purchases_per_turn` buys a turn (default 1). The Value is paid when the action resolves, not when planned.
    - **Where a bought squad or item goes:** like produced output. Without a rally point it joins the owner's garrison on the feature's hex (a new garrison if none). With one, it leaves next turn as a caravan on that line. Items go into that garrison's or caravan's War Chest.
    - **Cancelled, with nothing paid, when:** the feature is no longer the player's (captured during movement this turn); the hex is engaged (a battle is there); the hex is contested (a hostile commander, or a hostile garrison or caravan with squads, is on it when the action resolves); or the player lacks the Value. The owner sees the reason as an event.
    - **Fog:** an owned feature always sees its own hex, so planning never acts blind. Enemies see a bought squad or item appear as a garrison or caravan, never what it holds.
    - **Not remote:** hire, refit, convert, battle and answering offers still need a commander on the hex (U1 synthesis defaults 05-Q3, 05-Q4).
  - **Production:** every controlled feature pays its owner its `value_per_turn`, including one taken this turn.
  - **Offers:** after a turn resolves, each uncertain feature is offered to the one player whose free commanders stand on its hex. A hex with hostile commanders, or an engaged one, gets no offer. The player answers during planning with one of the feature's `choices`, once per offer; the map's triggers decide what the answer does.
- **Hexes are places made of features** (U1Q20; proposed, Round U1, awaiting review): a hex shows the features it holds as separate things, not as one terrain colour. Each feature has a drawing `layer`:
  - **Ground** (plains, forest, hills, lake): the hex's surface. The ground with the highest `draw_order` is drawn as the hex's tile.
  - **Path** (roads): drawn as a strip from the hex centre to each side whose neighbour holds a feature it `connects` with.
  - **Site** (village, mine, barracks, depot, caches, camps, shrines): an object drawn in a slot of the hex, selectable on its own.
  - The layer and layout are drawing only: the rules never read them. Movement cost, sight, control and activities are unchanged.
- **Arrangement** (U1Q21, U1Q22; proposed numbers): sites take slots from a fixed table by how many sites the hex has (1–7). They are ordered by `layout_priority` (higher first), then template ID. An eighth or later site shares the last slot with a "+n" badge.
  - **Roads:** on a hex with a path, the arrangement keeps its shape and moves as a group out of the road's way, towards the middle of the widest gap between road directions, and shrinks slightly to fit. Any site still on the road is pushed off it.
  - **Map overrides:** a map may place any site at an exact point in its hex (`at` on its `place` pass). Play never changes the arrangement.
- **Selecting a feature** (U1Q23; proposed): any known site can be selected by itself, on the map or in the hex's panel; both highlight it. Selecting a feature also selects its hex. What the player can do with it depends on owning it (Owner actions).

### Guards and movement
- **Guards** (R4Q14, R5Q9, R6Q11, R6Q12): entering a guarded hex triggers an engagement. What overworld forces will do is never revealed before engagement.
- **Banking movement:** commanders whose plan was cut short bank 50% of their unused movement points, capped at one turn, and it expires after the next turn.
- **Neutrals only:** guard and garrison rules apply only to neutral garrisons and features.
- **Chase and intercept** (R3Q22): commander-vs-commander pursuit needs a chase/intercept handler. This is to be specified.
- **Movement:**
  - **Simultaneous routes:** every route resolves at once, in movement-point time. A commander enters each hex when it has spent that hex's cumulative cost, so whoever gets there first arrives first. Ties go to the lower commander ID.
  - **Stopping:** a commander stops on entering a battle tile (joining it), a guarded hex (starting a guard engagement), or a hex holding a hostile commander at that moment, including one about to leave it. So two hostile commanders can't swap hexes or pass each other. Everyone on a hex where an engagement starts or is joined stops there.
  - **Banking:** only a commander stopped with route steps left banks. Arriving on the planned last hex, or being found there by an enemy, is not a cut plan.
  - **Control:** a commander that passes through or ends on an unguarded hex takes its controllable features.
  - **Pathfinding** for route drafting is the cheapest path, with ties broken by plot index. It doesn't avoid guards, because the player sees the feature but never what its forces will do, and it never continues through a battle tile.
- **Fog of war** (R8Q4):
  - **Sight sources:** commanders, controlled features, garrisons and caravans each have a sight radius in hexes (their effective sight, `OverworldStats`). A source always sees its own hex, so every controlled hex gives at least self-vision (U1Q26).
  - **Allies:** vision is shared with allies.
  - **Memory:** explored hexes keep their last-seen state.
  - **Battle hexes:** their contents are hidden without sight.
  - **Sight:**
    - **Radius only:** sight is a radius in hexes; overworld terrain doesn't block it yet. Every source sees its own hex. An owned feature is a source; a neutral one isn't. Garrisons and caravans are sources too.
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
- **Production and convoys:**
  - **Production:** a feature's `produces` lists squads it can make. Its owner selects one (the first by default). Each turn it advances one step; on reaching the option's `turns`, the squad is made for the option's `cost` in Value. While the owner can't pay, it waits, ready to go.
  - **No supply line:** produced squads join the owner's detachment holding the feature's hex, which garrisons it until a commander picks them up.
  - **Supply lines:** the owner sends a feature's output to a plot or to one of its commanders. Each squad leaves as a convoy on that line, and changing the line redirects convoys already on it. Capturing the feature resets its output and progress, and its line lapses.
  - **Rallies:** a player sends any of its detachments to a plot or a commander, which makes it a convoy; rallying it nowhere halts it. Survivors of a commander that left its battle rally to it (R8Q3).
  - **Steering:** a player selects any of its garrisons or convoys and moves it like a commander. It follows a route of hexes, through waypoints, at its movement points as a caravan. Steering makes it a caravan. A route may take several turns, and it is used up as the convoy walks. A steered convoy takes the player's way, guards and all. Right-clicking one of the player's commanders sends the convoy to join its army.
  - **What convoys can't do:** convoys and garrisons never take controllable features, pick up caches or perform hex activities (recruit, hire, refit, convert, battle). Only commanders do. A convoy still fights what it meets.
  - **Caravans** (U1Q27; band kinds and sight landed with sw-63wt.2, payload with sw-63wt.3): a squad group without a commander is a **band**. A band is either a **garrison** (holding a hex) or a **caravan** (made to travel; "convoy" is an alias). The kind is data (`band` templates) and gives the band its base sight and movement points.
    - **Becoming a caravan:** a garrison sent somewhere (rally, steering, a supply line) becomes a caravan. A caravan that halts stays a caravan: it keeps its sight and can be steered again.
    - **Holding a hex:** a halted caravan holds its hex like any detachment: it fights what enters, and a commander there picks squads up from it. It is not the hex's garrison, though: drop-offs, production and arriving caravans join the garrison (or form one beside it), never a halted caravan.
    - **Becoming a garrison:** a caravan that reaches its plot joins the player's garrison there, or becomes that garrison if there is none.
    - **Walking:** each turn a caravan walks the cheapest path it knows, around hexes it knows are guarded, for its movement points. It moves on the commanders' timeline, after commanders at equal times.
    - **Payload:** what a band carries are components: its squads, their equipped items, and its War Chest. Each squad (and each item it equips) may add to the band's overworld stats (`overworld` contributions). A scout team adds 1 sight to a caravan, up to the band kind's cap.
    - **Effective stats:** systems read a band's effective sight and movement (base + payload, capped), never the raw data. Its tooltip shows each term.
  - **Meeting a commander:** a convoy sent to a commander walks to where that commander's planned route ends this turn, not to where it stood. A commander that enters the hex of a convoy sent to it picks the convoy up there and carries on.
  - **Interception:** like any detachment, a convoy entering a hex with hostile forces or guards, or entered by a hostile commander, is pulled into an engagement and stops. Survivors of a battle it wins carry on.
  - **Arrival:** at its plot, a convoy becomes a garrison, joining the player's garrison there. At its commander's hex, its squads join the army up to the cap, and the rest halt there. A convoy whose commander is gone halts where it is.
  - **Merging:** after movement, convoys of one player on the same hex and line merge into one.
  - **Fog:** caravans are sight sources (3 hexes by default, the `band_caravan` kind). Enemies in sight see a convoy and where it moves, but not what it holds or where it's going.
  - **Items:** an option may produce items instead of a squad (`count` per batch). They go into the War Chest of the receiving detachment or convoy, and travel the same supply lines.

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
- **Items and chests:**
  - **Items are per-unit gear** (R3Q7): one item equips one unit and fills one of its three slots. A weapon item replaces the unit's weapon, a defense item its defense, and a kit adds its bundles. An item's `fits` limits which units may carry it (by unit ID, unit tag or squad faction).
  - **Chests:** every commander, detachment and convoy has a War Chest. Identical items in one place stack. Equipped items belong to their squad and travel with it, through trades, drop-offs and convoys.
  - **Equipping:** a commander outside battle equips items from its chest to squads of its army that aren't in a battle, and unequips them back. A squad takes as many as it has units that fit with the slot free, at full strength. The army view lists each squad's items (the equipped tab), and the chest view lists, per stack, the squads with room for it (the detail view).
  - **Casualties:** a squad keeps its items. In battle they go to its first surviving members that fit, leaders first. A refitted squad carries them all again. A destroyed squad's items are scavenged into its commander's or detachment's chest.
  - **Trading:** friendly commanders sharing a hex hand items over during planning (R7Q9). A commander takes the whole chest of its player's detachment on its hex; one left with nothing is disbanded. A convoy reaching its commander hands over its chest; merging convoys merge chests (R6Q13).
  - **Pickups:** a feature with `items` is a cache: the first commander through takes them into its chest and the feature is removed. The pickup event lists what it found, for the UI to offer equipping.
  - **Unguarded chests:** a detachment or convoy with no squads can't fight. A hostile commander on its hex, or else a hostile detachment with squads, seizes its chest; guards destroy it.
  - **Lost:** a defeated commander's chest, and a destroyed or defeated detachment's, are lost with them.
  - **Fog:** allies see chests and equipped items; enemies never do.

## 2.10 Magic and Ruin in play (R1Q15, R2Q8, R4Q21)
- **Zones:** plots and battlefield areas carry a magic condition: Law (normal), Ruined or Null.
- **Ruin** is a zone condition. It raises costs, lowers efficacy and restricts types, regardless of how the magic is accessed, like denial-of-service or 500 errors. Ruin effects are ordinary effects in the effect language (§2.13), selected through tags.
- **Null:** no magic works.
- **Raw magic** doesn't become available where the Law fails, except in "wacky" scripted circumstances.

## 2.11 Angels in play (R3Q17, R5Q6, R6Q17)
- **Driven by behaviour data:** Angels are an undirected narrative force (not a player faction), driven by behaviour data through the trigger system.
  - **Angels in the overworld:** triggers place and remove features, so Angels can appear as guarded `hex_angel_host` features in front of resources. Its guard is a placeholder until the Angel roster. Stealing items and the inverted auto-resolve still need their own actions.
- **Interference:** they act as filler interference. They give battle in front of resources, eat turn timers with nonsense dialogue, and steal or move overworld items.
- **Inverted auto-resolve:** a commander with no battleforce can temporarily disperse Angels by engaging them. This is required to clear movement-blocking Angels in the Angelfall mission, but it doesn't work in the final key battles.
  - **Engaging with no battleforce:** a commander engages with no battleforce by planning the built-in `none` preset without its own squad (`lead` off).
    - **Dispersible guards:** if every guard on the hex has `dispersal_turns`, they are dispersed (`guard_dispersed`, for triggers to count) and come back after that many full turns (`guard_returned`). The commander takes the hex.
    - **Any other guard holds:** the engagement ends with no battle. Before this rule, a commander with no squads cleared any guard.
- **Guards in battle:** the neutral side's squads take orders from `GuardController` at each Reveal, deterministically from their own observation.
  - **Every guard** attacks the nearest enemy squad it sees.
  - **Hunters** (keyword `hunter`, the Angels) go for squads with the `civilian` keyword first, and when they see nobody they sweep to the nearest zone they don't hold.
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

## 2.13 The effect language (E1–E4)
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
- **Activation:**
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
- **The inspection call:** `BattleSession.inspect(player, squad)` returns, for one squad:
  - **Strength:** living units against the template's starting count, e.g. "7 / 8 units".
  - **Squad and per-unit stats:** each with base, effective value and the step trace. Trace terms name the bundle each modifier came from, and every fire mode is listed.
  - **Effects held:** stacks, remaining ticks, rules text and accumulator progress, e.g. "Next in 2 hits".
  - **Own squads only:** pools and abilities (state, cooldown, charges, effective costs, rules text).
  - **Visibility:** own squads are always inspectable; enemy squads only while seen. For anyone but the owner, deception-tagged bundles appear as their disguise, in the effects list and in the traces.

## 2.14 Battle space (O1Q8, O1Q9)
**Status:** the grid, passability and routing are specified here; the owner said to build them on 2026-11-16. Deployment: a squad's anchor and each of its units start on the nearest cell the squad can enter, so a deployment area painted over a wall or water still fields the side. Charges are not built. It fills the gap behind §2.6's "terrain, line of sight and cover apply".

### The grid
- **Cells:** a battlefield is a grid of 1-metre cells. Each cell holds one terrain feature. Positions stay continuous fixed-point; the grid is what terrain, cover, line of sight and routing read.
- **Authored maps:** a battlefield's cells come from a painted map (Data Model §3.5).

### Passability
- **Per movement type:** each movement profile has a cost per terrain feature (R6Q8). A cost of 0 means that movement type can't enter the feature. So a lake stops infantry and not flyers, with no separate rule.
- **Deployment and orders:** a squad can't deploy on, or be ordered to, a cell its slowest member can't enter. An order to such a point is moved to the nearest cell it can reach.

### Routing
- **Squads route, units follow.** When an order is applied, the squad plans a route for its formation anchor: the cheapest path for its slowest member's movement type, around impassable terrain and preferring cheaper ground. Units keep steering to their formation slots.
- **Deterministic:** integer costs only; equal-cost routes are broken by cell index.
- **Moving targets:** a squad attacking another squad re-plans when its target has moved more than a set distance (data; default 8 m) from where the route was planned to.
- **Forecasts:** the planning forecast runs the same movement, so its ghosts show the route the squad will take.
- **Fog:** a route is planned on the true terrain. Battle terrain is never hidden, only squads are.
- **Routing:** `BattleRoute` plans on the 1-metre cells, one straight leg at a time.
  - **Legs:** the squad walks straight to a waypoint and plans the next leg when it gets there. A leg is the farthest point on the cheapest cell path that it can walk straight to at no more cost. On open ground that is the destination itself, so squads move as they did before.
  - **Costs:** entering a cell costs 10, or 14 diagonally, times the cell's cost for the squad. A squad pays what its slowest member pays, and can't enter what any member can't. Diagonal steps never cut a corner.
  - **Unreachable points:** the squad goes to the nearest cell it can reach: the closest ring of cells around the point that has one, then the least straight distance, then the lowest cell index.
  - **A squad standing on an impassable cell** steps out to the nearest passable one first.
  - **Impassable features:** a feature marked `impassable` costs 0 for every movement type that doesn't list its own cost for it. The core data has `wall` and `water`.
  - **Not state:** a leg depends only on the map, the squad's costs and the two cells, so plans are cached with the rules and never saved or hashed. The squad's current leg is state.
  - **Measured** (200 × 100 map, one plan): about 17 ms across open ground with forests, about 48 ms through a comb of walls, 2 µs when cached. A plan happens once per leg, not per tick.

### What v1 leaves out
- **Collision between units and squads:** units and squads don't block each other. Two squads may stand in the same place. This is revisited only if playtests show it reads badly.
- **Elevation:** there is no height. The map format reserves an elevation layer (Data Model §3.5) so it can be added without a format change. Adding it is a rules decision, not a presentation one.
- **Formation width:** a route is planned for the anchor point, so a wide formation may reach past impassable cells at its edges. Units handle that themselves (next section).

### Unit movement (sw-ll4.16)
- **Terrain collision:** a unit can't enter a cell its own movement type can't (cost 0). If its step would, it slides along the wall on one axis (x first) when that is open, else it stands still for the tick. A unit already on an impassable cell (deployed or displaced there) may leave it.
- **Coherency:** a unit whose formation slot lies on a cell it can't enter heads for the squad's anchor instead, which routes keep on passable ground. There is no separate leash distance: slots are at most a formation's width from the anchor.
- **Not built:** unit-vs-unit collision, and unit pathfinding. A unit stuck in a concave wall pocket waits until the anchor moves on. Revisit if playtests show it reads badly.

### Separation and coherency (U1Q10)
**Proposed (Round U1, awaiting review).** "What v1 leaves out → Collision" (O1Q8) and "Unit movement → Coherency" above stay in play until this lands. The coherency radius is a prerequisite of closing to fire (U1Q29, §2.15) and lands before it; separation, footprints and clusters are later refinements.
- **No body blocking.** Units and squads never block movement or routes. Routes stay static and cached (§2.14 Routing).
- **Separation:** after units steer to their slots, a unit closer than its separation radius (by size class: small 0.4 m, medium 0.6 m, large 1.2 m) to a unit of *another* squad is pushed apart along the line between them.
  - **Pushes:** computed from start-of-tick positions, summed per unit, capped at the unit's speed, and applied together, so row order doesn't matter. Integer math.
  - **Walls:** a push never enters a cell the unit can't (the terrain-collision slide rule applies).
  - **Tie-breaks:** units on the same point push along the lower unit ID's facing.
- **Squad footprints:** two friendly squads ordered to the same point are given points one footprint apart: the nearest free ring position, then the lowest cell index. A footprint is the formation's width.
- **Coherency radius** (U1Q10, U1Q29; data per formation; default proposed: the formation's half-width + 4 m): how far a unit may be from its squad's anchor. Under attack orders, units seek their firing positions inside it (§2.15 Closing to fire).
- **Coherency:** a unit more than its squad's coherency radius from the anchor heads straight for the anchor (this exists, §2.14 Unit movement). The anchor also slows to half speed while any unit is out of coherency, so squads don't string out around corners.
- **Clusters:** squads given one shared order (a multi-select move) share one route plan and keep their offsets from the cluster's lead squad, which is the lowest row. A cluster's leg is the lead squad's leg.
- **Budget:** separation uses a uniform 2 m spatial hash rebuilt each tick, at about one bucket pass per unit. The target is ≤ 0.2 ms per tick at 200 units on desktop, measured before the rule ships, so a 100-tick forecast stays ≤ 20 ms on top of today's.

### Charges
A **charge** is an Attack order while the squad is still closing on its target. This is the meaning Intercept (§2.7) already uses. Melee has no rules of its own in v1: a short-range weapon is a weapon with a short range.

## 2.15 Orders and squad behaviours (U1Q1, U1Q2, U1Q10–U1Q13)
**Status:** U1Q11–U1Q13 settled the intent, and U1Q28 and U1Q29 settled how attack orders close and open fire: per-unit firing positions within coherency, each unit firing as it comes into range. Details not tagged with an owner decision are proposed (Round U1, awaiting review). Measurements: `docs/design/u1/01-battle-orders-and-behaviour.md` §1, until the U1 workshop scenarios for orders and damage output replace them. Owner answers: `docs/design/u1/answers.md`.

### Orders and their trade-offs (proposed)
Every order is a promise about movement. Damage output follows from it; no order has a hidden damage penalty.

| Order | Moves | Fires | Trade-off (intended) |
|---|---|---|---|
| **Hold** | Never. Units may turn. | At anything in reach, standing modes. | Best accuracy and first volley; does nothing out of range. |
| **Move** | To the point, ignoring enemies. | On the move at anything in reach, with moving modes only. Weapons without one stay silent. | Fastest arrival; accuracy × Instinct efficacy, and it sinks Instinct. |
| **Attack-move** | Toward the point; its units take firing positions to fight (Closing to fire, below). | Each unit with standing modes once at its firing position. No moving volley on arrival. | Gives up ground for damage. Stops chasing past its leash. |
| **Attack** | Follows the target squad; its units take firing positions against it (Closing to fire). | The target first. Other enemies only while the target is out of reach. | Focus over efficiency. |
| **Run** (a modifier of Move, Attack-move, Attack) | At run speed scaled by Stamina (R4Q5). | As its order; moving modes while running. | Speed for Stamina. Attack-move and Attack still stop to fight. |
| **Fall back / Withdraw** | Away / off the edge. | Never. | Survival. |

- **Reactions keep the modifier:** a Retarget reaction keeps the squad's run flag (U1Q2). Halt is a hold, where running means nothing, and fall back always runs.

### Closing to fire (U1Q11, U1Q29)
The default for Attack-move and Attack. A squad with an engaged enemy and time left in the turn keeps advancing until each of its armed units can use its firepower. This is the marine arc of U1Q11.
- **Firing positions** (U1Q29): each armed unit seeks its own **firing position**: the nearest point it can reach, within the squad's coherency radius (§2.14) of the anchor, from which it has a shot at a unit of the engaged squad. A shot is the per-unit shot gate: range, minimum range, and a line of fire or an indirect mode. The unit walks there and opens fire on arrival (Volley phase, below). A unit that has a shot from where it stands stays.
- **Anchor** (U1Q29): the anchor advances along its route while any armed unit has no firing position inside the coherency radius. It stops once every armed unit has one, or already has a shot.
- **Hysteresis** (U1Q29): once stopped, the anchor moves again only after a unit has lacked a firing position for at least 1 s.
- **No achievable position** (U1Q29): a unit that can't get a shot from anywhere inside coherency (a minimum range it can't clear, say) doesn't hold the anchor. Units with no weapon never do.
- **Losing the shot** (U1Q29): a unit whose shot is gone (its target moved, its line blocked) seeks a new firing position within coherency. It returns to its slot when the squad's order no longer engages.
- **Search** (U1Q29): deterministic and cheap. Candidate points lie on rings around the unit's slot, toward the target, inside coherency and enterable for its movement type; the first with a shot wins, by ring and then angle index. Its cost is measured with the movement work and must fit that budget.
- **Leash** (U1Q29): attack-move never closes more than its **chase leash** (ruleset `chase_leash_m`; default 15 m) past its point: engaged and closing, its anchor heads for the engaged squad, at most the leash from the point. Attack has no leash. Hold never moves units off their slots.
- **Stand-off** (proposed): a firing position respects the fire mode's minimum range through the shot gate, plus the behaviour's stand-off margin. Squads that keep enemies at a distance (mortars, marksmen) do it with `keep_distance` (Squad behaviours, below).
- **Fog**: only enemy squads the side sees count (the engaged squad must be seen).
- **Built** (sw-txnj.5): candidates are the unit's own spot, its slot, then rings 2 m apart up to the coherency radius, 7 angles over the forward half circle (0, ±30, ±60, ±90°). A shot from a point is a range and minimum-range test against every living target unit, then one line-of-fire trace to the nearest one (none for an indirect standing mode). A weapon with a minimum range keeps a 5 m stand-off beyond it. Each unit is re-evaluated every 5 ticks (staggered by unit); a unit holding a position re-checks only that point; at most 2 full searches per tick per battle; a unit too far for any ring to reach lacks a position without a search. A unit's position is dropped as soon as the anchor's move leaves it outside coherency. The squad-wide "stand while firing" stop is gone: each unit stays at its firing position while its weapon cycles.
- **Firing on arrival** (proposed): a unit reaching its firing position uses its standing mode on the next tick it can fire. It doesn't spend a moving volley on the arrival tick.
- **Shown** (proposed): the forecast ghost shows where the squad will stop and where its units will stand, and the hold reasons show who is "moving to fire".

### Volley phase (U1Q28)
- **Staggered by movement:** each unit opens fire on its own the first tick it meets the conditions to fire: an enemy unit in range, a line of fire or an indirect mode, a fire mode allowed at its current motion, and its timers ready. It never waits for squad-mates. So a homogeneous squad advancing in formation opens with a ragged, staggered volley as each unit comes into range, and its units' reload and cooldown cycles stay out of phase afterwards.
- **No slot stagger:** hit accumulators are not offset by slot. Stagger comes from movement only. Squads that start the battle already in range (both holding) may still volley together; that is accepted, and revisited only if a playtest shows it reads badly.
- **Fire distribution is measured with it:** fire-distribution numbers (§2.6, §2.8 Prowess) are measured with movement-driven stagger, and coordination must still show an effect there.

### Squad behaviours (U1Q12, U1Q29; vocabulary built, sw-txnj.9)
An order runs a **behaviour**: an ordered list of **components** from a closed, engine-provided vocabulary, each with data parameters. Mods compose components; they never add code (Data Model §3.7). Each squad template names a behaviour per order, falling back to the default (today's closing to fire, the values in brackets below).

| Component | Phase | Parameters [default] | What it does |
|---|---|---|---|
| `firing_position` | unit | `coherency_m` or `extra_m` [the formation's radius], `stand_off_m` [5], `cadence_ticks` [5], `hysteresis_s` [1] | Each armed unit seeks a firing position within coherency of the anchor, at least `stand_off_m` beyond a minimum range, re-evaluated every `cadence_ticks`; the anchor moves while a unit lacks one, and once stopped only after `hysteresis_s` (Closing to fire, above). `coherency_m` replaces the formation's radius, `extra_m` adds to it. |
| `keep_distance` | move | `min_m`, `max_m` [none] | Stands off, or backs away, to keep the engaged squad in a band (mortars, snipers). |
| `leash` | move | `chase_m` [Attack-move: the ruleset's `chase_leash_m`; other orders none] | Limits how far past the order point the squad pursues. |
| `fire_on_move` | fire | `allow` [true] | Whether moving modes may fire under this order. |
| `stand_while` | move | `firing` [true], `reloading` [false] | Units with a shot stand while they fire; the squad also stands while a unit reloads. |
| `separate` | unit | `radius_m` [the size-class radius] | Separation (§2.14). |

- **Built** (sw-txnj.9): the vocabulary, validation and compile to per-template, per-order arrays. The core humanity squads name `line_attack_move` and `line_attack`, which spell out the defaults.
- **Read by movement and fire** (sw-txnj.10; the defaults change no outcome, harness hashes equal): a squad uses the behaviour of its *current* order. `firing_position` sets the coherency radius the squad keeps under that order (anchor wait, unit return, the engagement broadphase too), the stand-off, the re-evaluation cadence and the hysteresis. `leash` applies to Attack-move, the only order with a point to leash to. `keep_distance` measures anchor to engaged squad centroid: closer than `min_m`, the anchor backs straight away to `min_m`; farther than `max_m`, it closes and does not stand for firing positions; outside the band the squad takes no firing positions (it walks in formation, firing on the move) and takes them again inside it. `fire_on_move(false)` gives a unit no fire mode while it moves (the hold reason is "moving to fire"). `stand_while(firing = false)` takes no firing positions at all: the squad keeps walking and fires on the move; `stand_while(reloading)` holds the anchor while any armed unit reloads (not while backing off). `separate` is compiled but not read: separation (§2.14) is not built.
- **Superseded** (U1Q29): `advance(quorum_pct)` and `step_out` are gone; the anchor's hysteresis is a `firing_position` parameter.

Archetype defaults (built, sw-txnj.11):

Archetype behaviours, as built in `humanity.json` (sw-txnj.11; the line keeps `line_attack_move` / `line_attack`):

| Archetype | Attack-move / Attack (built) |
|---|---|
| Infantry (line) | the defaults: `firing_position(stand_off_m 5)`, `fire_on_move(true)`, `stand_while(firing)`; attack-move leash is the ruleset's 15 m |
| Indirect (mortar) | `firing_position(stand_off_m 5)`, `keep_distance(min_m 25)` (min range 20 m + 5), `fire_on_move(false)`, `stand_while(firing, reloading)` |
| Short-range / melee (assault) | the line's components with `firing_position(extra_m 3)`: a 3 m wider coherency radius; leash and stand-off unchanged |
| Marksman | the line's components with `keep_distance(max_m 65)` (range 70 m − 5) |

- **Roles** (U1Q29): the archetypes keep their roles. Mortars keep their distance and stand while reloading, marksmen prefer their maximum range, and assault squads have a larger coherency radius. Workshop gates pin each archetype's DPS (`archetype_mortar`, `archetype_marksman`, `archetype_rifle_line`, `table_b_assault`). The numbers are not yet playtested.

- **Order of evaluation:** components run in vocabulary order in their phase, squads in row order, units in row order. Arithmetic is integer and fixed-point.
- **Forecasts:** they run the same behaviours, so the ghosts show them.
- **Target choice:** which enemy unit each shooter picks is not a behaviour component; it is §2.6 Fire distribution.
