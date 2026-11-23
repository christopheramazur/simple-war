# Angelfall tutorial pacing gaps (sw-136.3)

Status: options only. No fix is chosen; the rework decision belongs to release step 2 and the user's narrative-pass interview (README Open topic 3). No GDD, code or data edits.

Compared: shipped slice (GDD 06 §6.9; `data/packages/core/defs/angelfall.json`, triggers `af_*`; `src/presentation/angelfall/angelfall.tscn` = war room on `angelfall_frontier`, seed 7) against the SC2 Mar Sara and Halo: Reach New Alexandria patterns in `docs/swarm/research/summaries/angelfall-story-kin-themes-and-tutorial-framing-for-the-team.md` (findings 3 and "What it means").

## Teaching order as shipped
1. Overworld turn 1: `af_intro` (message only) states the whole goal: "Get everyone to the spaceport." Player routes Jeff, sets battleforce, sends town civilians along supply lines, ends turn (GDD 06 §6.9 "Overworld controls").
2. Overworld, any turn: the Angel blockade at (7,3) is the only gap in the cliffs, so the player must learn "No battleforce disperses Angels" (`dispersal_turns: 3`, `af_dispersed`).
3. Overworld turn 4+: `af_angels_hunt` adds a second blockade at (5,5) near the hill town.
4. Spaceport battle: planning UI, then the control console (`control` zone) to unlock the hangars (`af_ai_console`), then civilians holding a hangar for shuttles (`af_shuttle`), with `score_target` 12 (two hangars at 3 VP) and `turn_limit` 12.

## Gap 1: stakes escalation is flat, then arrives all at once
Evidence: `af_intro` names the final goal on turn 1. The only mid-campaign escalation is `af_angels_hunt` on turn 4 (a time trigger, not tied to anything the player did), and its text ("going for the town in the hills") names no consequence: the town is not lost and nothing is counted. The first time anything is *at risk* is the spaceport battle, whose Angels are undispersable. Mar Sara teaches on small local stakes and then recontextualises; here there is no small-stakes phase and no later reveal.
- OPTION A: open on a small local problem (Jeff's town, one civilian group, one blockade) and gate the spaceport and its message behind it, so the evacuation scope is revealed after the player knows the verbs. Adds triggers and a staged map; closest to the report's recommended spine.
- OPTION B: keep one map but make `af_angels_hunt` consequential (a town stops producing civilians, or the civilians en route are lost) so turn 4 reads as an escalation. Smaller change, but it adds a failure state a tutorial may not want.
GDD: 06 §6.9 ("Triggers", "Enemy"); 01 Release order (step 2); README Open topic 3.

## Gap 2: objective ordering is implicit, and the order in the battle is a hidden dependency
Evidence: the overworld has no objective message beyond the turn-1 line, and nothing tells the player the blockade must be dispersed before the road opens (the cliffs only imply it). In the battle, the hangars start `locked: True` and the console zone (x 45, near the deployment edge) must be held first; the only prompt is `af_ai_hint` on turn 2 when `hangar_a` is still locked. A player who heads straight for hangars (as the intro suggests) spends turn 1 on zones that score nothing. New Alexandria lets objectives run in any order and each completes independently, so a player never waits on an unstated prerequisite.
- OPTION A: keep the console-first dependency but surface it on turn 1 (move the AI line to battle start, or add an objective list entry), so the order is taught rather than discovered.
- OPTION B: drop the dependency for the first run (hangars start open, console becomes an optional accelerator) and introduce locked objectives in a later mission, matching New Alexandria's any-order shape.
GDD: 06 §6.9 ("Objective", "Battle `angelfall_spaceport`"); 03 Data Model (zone `locked`, `unlock_zone`).

## Gap 3: first shuttle lift-off comes last, after nearly every mechanic is already taught
Evidence: `af_shuttle` can only fire in `angelfall_spaceport`, after the console and a hangar hold. By then the player has used routing, battleforce choice, supply lines, dispersal, the planning UI and zone capture. The headline payoff (the shuttle leaving, the thing that makes the CR-0 / Capture Rate 0 rule matter) therefore has no earlier preview; the robots' inability to board is never exercised before it decides the battle. New Alexandria shows shuttles lifting early and repeatedly as the feedback loop for clearing turrets.
- OPTION A: add an early, small lift-off (for example a town's own landing pad on the overworld, or a scripted first shuttle after the first blockade is dispersed) so the player sees the reward and the CR-0 rule before the finale.
- OPTION B: keep the single finale lift-off but add a CR-0 demonstration earlier (a robot patrol that visibly cannot board or hold a zone in the first battle) so the rule is taught before it is scored.
GDD: 06 §6.9 ("Allies", "Evacuating"); 01 Release order (step 2).

## Gap 4 (smaller): the first battle is also the finale
Evidence: the slice has one battle, `angelfall_spaceport`, 160x100 with 12 turns and two undispersable Angel squads against Jeff's squad, two civilian groups and a CR-0 patrol. The planning UI, zone capture and the Angel `GuardController` behaviour (hunt civilians first) are all met for the first time under the win condition. The overworld battleforce choice also has no consequence visible before this battle, since the blockade is dispersed by going alone.
- OPTION A: add a short pre-spaceport battle (the blockade, fought rather than dispersed) as a tutorial-scale encounter.
- OPTION B: leave one battle and tune its first turns (a start with no Angels in sight, an AI hint at turn 1) as a guided opening.
GDD: 06 §6.9 ("Battles", "Proven headless"); 06 §6.10 (open narrative pass).

## Not covered
No balance sims or numbers were run (designer closed sw-f75; escort screen endorsed). Numbers in the slice are first-pass per GDD 06 §6.9. Tutorial turn counts above come from the data, not from a playtest.
