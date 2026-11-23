# U1 draft 03: execution-phase clarity and start-of-battle deployment

Round U1, topic 3. Source: `docs/design/u1/brief.md`, the third and fourth paragraphs of **Battles**.
Status: draft for owner review. Nothing here has been applied to the GDD, code or tracker.

**Decision tags.** The brief's owner statements are tagged by the paragraph they come from: **U1Q3** for the third Battles paragraph (execution-phase clarity) and **U1Q4** for the fourth (deployment). Sub-points are U1Q3a, U1Q3b and so on. These are settled. Everything else is *proposed*. The numbers are provisional, and the orchestrator may renumber them when it merges the U1 drafts.

- **U1Q3a:** during the execution phase the player can still zoom and move the map.
- **U1Q3b:** the player can select squads during execution.
- **U1Q3c:** with one squad selected and another hovered, a hover tooltip, or a right-click context menu that compares the two, shows their current and possible interactions. Examples: "in / out of range", "targeting with attacks", "fleeing from".
- **U1Q3d:** these interactions reflect "what's actually going on", that is, the simulation's own state.
- **U1Q4:** a start-of-battle deployment step is wanted.

---

## 1 Findings

### 1.1 Playback today: what works, what is blocked

Execution is presentation-only playback of a turn that has already resolved. `war_room.gd:25-30` says so: "The game itself has already resolved: playback only delays what is drawn".

| Capability during playback | State | Where |
|---|---|---|
| **Mouse wheel zoom and middle-drag pan in a battle** | **Blocked.** `_blocker` is a full-screen `UiWindow` on the BLOCKER layer with `MOUSE_FILTER_STOP`, opened in the `"playback"` context. It eats every mouse event before `ContextView._gui_input` sees it. Wheel zoom (`context_view.gd:1215-1218`) and middle-drag pan (`:1211-1214`) never fire. | `war_room.gd:463-471`, `:527` |
| **Keyboard / stick pan and zoom** | **Works.** The blocker is not MODAL, so `UiRoot.top()` returns null (`ui_root.gd:90-95`), `_keys_free()` is true, and the GUIDE actions `pan_*`, `zoom_in` and `zoom_out` run. `_show_play` re-applies `contexts.zoom` and `battle_centre` every frame (`war_room.gd:2026`). | `war_room.gd:1520-1537`, `:1573-1575` |
| **Hover a squad** | **Blocked twice.** The blocker eats mouse motion, and `ContextView` only emits `squad_hovered` while `_play.is_empty()` (`context_view.gd:1201`). `show_playback` also clears hover (`:204`). `WarRoom._on_squad_hovered` does not refresh the card during playback (`war_room.gd:848-851`). | as cited |
| **Left click on a squad** | **Inspects only** (sw-ll4.27.4). `_on_playback_clicked` maps the click through the blocker to `squad_at` and sets `_inspected`. The card then follows the shown moment (`SquadCard.moment`, sw-ll4.27.3). | `war_room.gd:2050-2060`, `:817-819` |
| **Select squads (planner selection)** | **No.** Clicks never reach `_on_battle_pressed`, and if they did, it returns after inspection while `_play` is set (`war_room.gd:1239-1240`). `_cycle_squad` only inspects during playback (`:1593`). `show_playback` doesn't draw selection or orders (`context_view.gd:186-190`). | as cited |
| **Fire cues ("in range", "no line of fire", "spotted")** | **Planning only.** `_draw_fire_cues` returns early during playback (`context_view.gd:720`). It reads the observation's `fire` and `sees` per own squad, which `BattleSession.observe_state` builds from `LineOfFire.check` and `LineOfFire.own_sight` (`battle_session.gd:304-324`). | as cited |
| **Right click** | Does nothing during playback (`_on_playback_clicked` ignores it). In Planning, right click is the order button: move, or attack the enemy under the cursor (GDD 01 Input and UI). No context menu exists anywhere in the war room (`PopupMenu` appears only in `ui_theme.gd` styling). | — |
| **Overworld during playback** | Locked by design: R3Q2, "Watching real-time execution locks out overworld view/interaction". The blocker returns early on the overworld (`war_room.gd:2054`). | decision log R3Q2 |

**Conclusion:** the order gate already lives in `_on_battle_pressed` (`war_room.gd:1239`). For the battle view, the blocker is redundant: it only adds the mouse block that U1Q3a and U1Q3b forbid. Its real job is to keep the side panels' buttons from acting mid-turn.

**GDD drift (fix with the text in §3):**
- GDD 04 line 114 says "Space or a click skips it". Since sw-ll4.27.4, a click inspects and only Space or Esc skip.
- GDD 04 line 117 lists "panning and zooming inside a battle" as not built. Planning has both, via `ContextView.zoom_camera` / `pan_camera` (`context_view.gd:1111-1133`).

### 1.2 Sim read models available for "relation" facts

| Read model | What it answers | Fog | Where |
|---|---|---|---|
| `LineOfFire.check(state, row, trow)` | `SHOT` / `BLOCKED` / `OUT_OF_RANGE` for squad → squad (centroid in reach, plus any living armed unit that is indirect or has a line). The same rule drives attack-order standing (`movement_system.gd:168-170`) and the planning marks. It ignores minimum range. | none (caller filters) | `line_of_fire.gd:12-23` |
| `LineOfFire.own_sight` | The squad sees the target with its own eyes, as opposed to the side's shared spotting (`seen_by`). | none | `line_of_fire.gd:29-33` |
| `CombatSystem.shot_gate(state, urow, t, w, m, d)` | Per unit → unit gate: OK / MIN_RANGE / NO_LOS / out of range. This is the authority for whether a unit can fire. | none | `combat_system.gd:206` |
| `CombatSystem._engage` | Picks the target: the ordered ATTACK target if valid, else sticky keeps the previous one, else the nearest seen enemy within reach. It is an **instance method that writes state**, so nothing can ask "whom would it pick" without duplicating it. | — | `combat_system.gd:47-73` |
| `BattleActivity.squad` / `.hold` / `.victim` / `.unit_report` | The squad's activity code. Per unit: the hold-fire reason (RELOADING, COOLDOWN, MIN_RANGE, NO_LOS, NOT_SPOTTED, ...) and the current victim. **Not fog-filtered.** | owner-only by API convention | `battle_activity.gd:23-148` |
| `BattleActivity.squad_seen` / `.squad_public` | What an enemy's behaviour alone reveals: fired on the last tick, moving, or idle. This is the precedent for the fog rule in §3. | yes | `battle_activity.gd:44-63` |
| `BattleOrders.fall_back_point` | Fall back runs 20 m directly away from the **nearest enemy the player sees**. The enemy it flees is computed at apply time and **not stored** (`target` stays -1). | — | `battle_orders.gd:96-100`, `:122-` |
| `IntentForecast.run` | Planning only. Own ghosts, plus contacts `{squad, target, tick, reactions, dealt, taken, kills_*}` from a scratch run of the real systems, fog-safe (unseen enemies are removed). sw-abk (in progress) added the damage numbers and the caveat text (`Telegraph.CAVEAT`). | yes | `intent_forecast.gd:16-136` |
| `Inspection.squad(state, id, viewer)` | The card's data: activity behaviour-only for non-owners, `target` (= `engaged`) owner-only. | yes | `inspection.gd:41-69` |

**No read model answers the pair question** "what is A doing about B, and B about A". Today, presentation gets close only through `observe.fire` / `observe.sees` (own squad × visible enemy, planning only).

### 1.3 What playback frames carry

`OverworldSession._record_turn` keeps one frame per tick (`overworld_session.gd:729-764`), 16 ints per unit (`_frame`, `:771-783`): id, squad, player, x, y, squad facing, `seen_by`, template, hp, hp_max, ACT bits, hold reason, raw squad activity, reload, cooldown, ammo. It also keeps `shots`, `volleys` and `hits` traces. `playback(player)` (`:800-862`) filters each frame by `seen_by`, strips enemy holds and timers, and sanitises enemy activity through `squad_public`.

**Not in frames:** the squad's order, order target, engaged target, reach, and each unit's actual weapon (War Chest gear can override the template weapon, `battle_setup.gd:84-90`). So from frames alone, the war room **cannot** say "targeting B" between volleys, "ordered to attack B", or compute LineOfFire faithfully. Two ways to close the gap:

- **(a) Widen frames:** add a per-squad record per tick.
- **(b) Shadow re-simulation:** the battle is deterministic, so a scratch copy of the turn-start state, stepped to frame *i*, *is* the state at frame *i*. Every live read model then applies unchanged. `IntentForecast._copy` (`intent_forecast.gd:47-52`) already shows how to make a private copy that never touches the real battle's caches.

§3.2 proposes (b).

### 1.4 How battles start today (deployment)

- **Built at the end of Execute.** `OverworldSession._pump` runs battles, resolves the overworld, then `_start_battles` (`overworld_session.gd:658-667`, `:867-882`). The following Planning is therefore the new battle's first planning. Its turn-1 orders are drafted then and applied at Reveal (`_reveal_battles`, `:679-690`).
- **Placement:** `OverworldBattles.build` (`overworld_battles.gd:42-95`) gives sides the scenario's areas in order (players ascending, then neutral guards). `BattleSetup.deploy_side` deals each side's squads evenly down the area's vertical midline (`battle_setup.gd:22-41`), snapped to an enterable cell (`open_point`, `:117-148`). Facing is the side's facing.
- **Vision runs immediately at build** (`overworld_battles.gd:92`; `BattleSession._setup` does the same at `battle_session.gd:72`). So in that first Planning, an enemy already within sight is **visible at its auto-deployed position**. Any hidden deployment must stop this.
- **Reinforcements** spawn at Reveal, at the centre of their side's area (`reinforce`, `overworld_battles.gd:118-161`), *before* orders apply. Because they don't exist when orders are drafted, they hold for their first turn.
- **Late joiners:** `_join` (`:165-193`) chooses the arrival area farthest from every fighting squad, among the scenario areas plus top-edge and bottom-edge strips, at Reveal. Squads don't move between the end of Execute and Reveal, so **the same choice can be computed at the start of Planning**.
- **Deployment areas:** scenario `sides[].deploy {x, y, w, h}` plus `facing` (`data/packages/core/defs/scenarios.json:12-15`), compiled to fixed-point rectangles (`battle_rules.gd:805-813`). Pre-placed `placed` squads are only proposed (GDD 03 §3.5 l.89; GDD 04 l.159 "Not built"). **sw-tdz** holds six open questions on them (storage, area containment, mixing with the even deal, overworld battles, planner, duplicates) and is blocked on the owner.
- **Formation** is a squad-template property (`sq_shape`, `Formation.offset`); there is no per-squad formation state. The planner's "new formation" only spreads move targets (`battle_planner.gd:159-177`). So "placeable formation" has nothing to place yet.
- **Saves and replays:** pending battle orders are saved (`OverworldBattles.to_dict` includes `orders`, `overworld_battles.gd:349-354`), and every input is logged and replayed (`overworld_session.gd:1259`). A deployment input can ride the same two paths.

### 1.5 Related beads (read)

| Bead | State | Bearing on this topic |
|---|---|---|
| sw-ll4.27 (epic: "squad activity and reasoning unreadable") | open | Parent context. Children .1–.5 closed. |
| sw-ll4.27.6 hoverable status marks | in progress, lease expired | **Owns `context_view.gd` hover and mark lookup.** The relation tooltip must reuse its "mark at point → tooltip key" function, not fork it. Its notes fix the fog rule: enemy marks are behaviour-only, never hold reasons. |
| sw-ll4.27.7 squad card fixes | in progress | Card only. No overlap beyond "don't fork the card". |
| sw-abk IntentForecast contact outcomes | in progress (autopilot-failed label, work done) | Source of the "possible interactions" fact in Planning (contact tick, dealt/taken summary, caveat). |
| sw-ll4.26.6 playback pacing | open, swarm | Changes how `t` maps to frames. The relation probe must index by **frame**, not `t`, so it is unaffected. |
| sw-dqq gamepad bindings | open (work merged: `_cycle_squad`, pad zoom/pan) | Pad users can already cycle and inspect during playback. A context menu needs a pad binding. |
| sw-wut virtual cursor | open, blocked on sw-dqq | Pad hover depends on this. |
| sw-tdz placed squads | open, needs-design | The deployment defaults build on its answers. §4 Q7 proposes them. |
| sw-dqj / sw-wqc glossary tooltip clamp / keyboard reach | open | The relation tooltip inherits both. |

---

## 2 Prior art

- **Combat Mission (WEGO).** After both sides commit, the 60-second turn replays with a **free camera**. You can watch it from any angle and rewind, and units can be selected while watching. The target line turns colour when there is no line of sight. This is the closest match to U1Q3: playback is a viewing mode, not a lock. ([Battlefront forum](https://community.battlefront.com/topic/75400-is-it-possible-to-rewind-the-action), [forum on replay camera](https://community.battlefront.com/topic/118054-in-game-replays/), [target line LOS colour](https://community.battlefront.com/topic/110180-newb-questions))
- **Frozen Synapse.** Plan, "Prime" (commit), then an Outcome mode replays the simultaneous turn. Its readability lesson is that the outcome must be inspectable after the fact. ([Wikipedia](https://en.wikipedia.org/wiki/Frozen_Synapse), [Pocket Gamer review](https://www.pocketgamer.com/frozen-synapse-prime/review/))
- **Steel Division (Eugen).** "Phase 0" deployment: each player places units in their own area **and gives first orders that execute when the battle starts**, out of real time. This is the direct precedent for fusing deployment with turn-1 planning (§3.3). ([Eugen Systems](https://eugensystems.com/?p=18897), [gamepressure guide](https://www.gamepressure.com/steel-division-2/the-division-into-phases-and-planning/z6c69d))
- **Total War.** A pre-battle deployment phase: your zone, the enemy zone (off-limits), and neutral ground. Vanguard units may deploy outside the zone but never into the enemy's, and are often hidden in woods. Battles that begin as **ambushes skip deployment**. This suggests "vanguard" and "ambush" as later, data-driven exceptions. ([TW:WH wiki, Vanguard Deployment](https://totalwarwarhammer.fandom.com/wiki/Vanguard_Deployment), [Rome II manual, Deploying Your Forces](https://r2encv2.totalwar.com/en/manual/single-player/0077_enc_page_battle_play_phase_deployment/index.html))
- **Company of Heroes and XCOM-likes** have no free deployment: forces arrive by call-in, or start at a fixed drop point. They show that deployment is optional for short, scripted fights. This supports a per-scenario `deployment: "fixed"` switch for the tutorial (§3.3).

---

## 3 Proposed GDD text

Insert each block as written. **[U1Q…]** marks settled owner statements; **(proposed)** marks the rest.

### 3.1 Rules Spec (02) §2.2 Turn sequence: step 4 "Execute"

Replace the step-4 bullet with:

```markdown
4. **Execute:** time-sliced simulated resolution (R1Q8). Watching playback isn't timed, and while watching, the overworld is locked (R3Q2). Ranked may skip straight to results (R3Q2).
   - **Watching a battle** (U1Q3a, U1Q3b): playback only shows a turn that has already resolved, so watching never changes it. During playback the player can pan and zoom the battle camera with every input (wheel, drag, keys, stick), hover squads, and select them. Selection made while watching carries into the next Planning. Orders and reactions are still refused until Planning (proposed).
   - **What a squad is doing about another** (U1Q3c, U1Q3d): see §2.6 "Pair relations". During playback, the relations are those of the moment being shown (proposed).
```

### 3.2 Rules Spec (02) §2.6 "Other combat rules": extend "Shown"

Replace the **Shown** sub-bullet with:

```markdown
  - **Shown:** with one squad selected, each visible enemy is marked "in range" (it has a shot), "no line of fire" (in reach, but no unit has a line), and "spotted" when only allies see it. The marks come from the same rule (LineOfFire) the attack orders use. They show in Planning and during playback (U1Q3c; proposed for playback).
  - **Pair relations** (U1Q3c, U1Q3d): with a squad selected (or inspected) and another hovered, a tooltip lists what each is doing about the other; the right-click comparison menu lists all of it. Each line is one *relation fact*, and each fact names the rule it comes from:
    - **Range** (§2.6 Range and vision): in range, no line of fire, too close (inside a fire mode's minimum range), or out of range with the gap in metres; with how many of the selected squad's units have a shot. From the per-unit shot gate the fire pass uses (proposed).
    - **Sight** (§2.7): sees it with its own eyes, or only through allies' spotting (proposed).
    - **Targeting** (§2.6 Attack orders): firing at it, or aiming at it but not firing, with the hold-fire reason (reloading, cooling down, no line of fire, ...); or ordered to attack it and closing in; or, with no attack order, it is the enemy the squad would engage next (the same nearest-visible-in-reach rule the sim uses) (proposed).
    - **Under fire** (§2.6): the hovered squad fired at the selected one recently (proposed).
    - **Fleeing** (§2.6, fall back): falling back or withdrawing away from it, when it is the enemy the fall-back runs from (proposed).
    - **Moving toward / away** (behaviour only): which way it is moving relative to the other squad (proposed).
    - **Coming contact** (§2.2 Forecast, Planning only): the forecast contact between the two, its time and outcome summary, with the forecast caveat beside it (proposed).
    - **Reaction** (§2.2 reaction window only): the hovered enemy triggers a reaction of the selected squad, or a queued reaction targets it (proposed).
  - **Same rules, not a copy** (U1Q3d): relation facts are computed by the functions the simulation runs (shot gate, target pick, fall-back threat, LineOfFire, the forecast), never by a parallel formula. During playback they are computed on the battle state at the moment shown (proposed).
  - **Fog** (proposed): relations exist only between squads the viewer can see. About an enemy squad, only what its behaviour shows: whether it fired at a squad, whether it is moving, which way, and what its public weapon range reaches. Never its orders, its chosen target before it fires, its hold-fire reasons or its reload. This is the rule `BattleActivity.squad_seen` already applies to activity.
```

### 3.3 Rules Spec (02) §2.4 Battles: new subsection after "Start and duration"

```markdown
### Deployment (U1Q4)
A battle starts with a deployment step: each side places its squads inside its deployment area before battle turn 1 (U1Q4).
- **When** (proposed): in the Planning phase in which the battle is first planned (the one after the engagement became a battle). It is not an extra turn: the same Planning also drafts battle turn 1's orders, as in Steel Division's phase 0. The battle's turn limit is unchanged.
- **Hidden and simultaneous** (proposed): both sides place at once. While a battle is deploying, a player sees their own squads, every side's deployment area, the terrain and the zones, but no enemy squad, even one that would be in sight. Placements are secret like orders. Battle turn 1's orders therefore can't target an enemy squad (none is visible); move, attack-move, hold and the other orders work.
- **What is placed** (proposed): each squad's position (its formation anchor) and its facing, anywhere in the side's deployment area. The anchor snaps to the nearest cell the squad can enter (§2.14). Squads may share ground, since nothing collides (§2.14). Formation shape is the squad template's until squads have formations of their own.
- **Defaults** (proposed): every squad starts at its automatic place: the scenario's `placed` position if it has one, else the even deal down the area as today. A squad the player doesn't move stays there. A timeout keeps whatever has been placed. AI controllers and neutral guards use the automatic places unless their controller places them.
- **Reveal** (proposed): placements apply first, in canonical order (players ascending, then squad ID), then vision is computed, then reinforcements and orders apply as usual. The reaction window that follows sees the revealed deployment. An enemy seen at Reveal is a valid trigger (§2.2 "Only visible triggers").
- **Joining late** (proposed): a player who becomes a new side (Joining late, above) deploys the same way into its arrival area in the Planning before it arrives. The arrival area is chosen when that Planning starts (squads don't move between Execute and Reveal) and shown to that player only.
- **Reinforcements** (proposed): a squad sent as a reinforcement may be given a place (and facing) inside its side's deployment area when it is sent. Otherwise it arrives at the area's centre as today. It appears at Reveal.
- **Scenario switch** (proposed): a scenario's `deployment` is `open` (default) or `fixed` (no step: squads start at their automatic places, for scripted and tutorial battles). An ambush start that skips deployment is a later option.
- **Determinism** (proposed): placements are inputs like orders (validated by the sim, logged, saved with the battle and replayed). Automatic places are exactly today's deployment, so a battle with no placement input runs as before.
- **Time** (proposed): deployment uses the Planning timer. A player gets `deployment_bonus` extra seconds (clock config, default 15 s) for each battle they deploy in that Planning, on top of the parallel-battle bonus.
```

In the same section, replace the **Reinforcements** sentence "They join at its side's deployment area before the next battle turn" with "They join at its side's deployment area before the next battle turn, where the player placed them or at its centre (Deployment, below)". Append to **Joining late › Where**: "It places its squads there itself (Deployment, below); its squads not placed spread along the area and face the middle of the field."

### 3.4 Rules Spec (02) §2.2 Turn sequence: step 1 and step 3

Append to step 1 (Planning):

```markdown
   - **Deployment** (U1Q4): a battle planned for the first time is also deployed in this Planning (§2.4 Deployment).
```

Append to step 3 (Reveal):

```markdown
   - **Order at Reveal** (proposed): deployments, then vision, then reinforcements, then orders; the reaction window then opens on what is visible.
```

### 3.5 Data Model (03) §3.5 Battle and campaign content: "Scenario"

Append to the **Scenario** bullet:

```markdown
  - **Deployment** (proposed, U1Q4): `deployment` is `open` (default: sides place their squads in their areas before turn 1) or `fixed` (no deployment step). Each side's `deploy` rectangle is where it may place. Pre-placed `placed` entries (side, squad, x, y, optional facing) are the squads' automatic places; with `locked: true` they can't be moved in deployment.
```

### 3.6 Systems Architecture (04) §4.4 Game API, plus the war room bullets (§4.8)

Add to the Game API:

```markdown
- **Relations** (proposed, U1Q3c): `BattleSession.relation(player, a, b)` and `OverworldSession.battle_relation(player, engagement, a, b)` return the relation facts between two squads the player sees (Rules Spec §2.6 "Pair relations"): `[{kind, value, from, to, rule, data}]`, fog-filtered for `player`. `OverworldSession.playback_relation(player, engagement, frame, a, b)` answers the same for a moment of the last turn's playback: the session keeps the turn's start state and re-runs the battle to that frame on a private copy (deterministic, so it is the state that was), then asks the same function. The UI, the AI and the harness all use these calls.
- **Deployment** (proposed, U1Q4): `submit_battle_deployment(player, engagement, placements)` in Planning while the battle is deploying; `placements` is `[{squad, x, y, facing}]` (fixed); errors as for orders. `observe_battle` carries `deploying`, the player's area (or arrival area) and every side's area.
```

Replace war room **Turn playback** "Space or a click skips it." with "Space or Esc skips it. A click selects and inspects a squad. The battle camera pans and zooms as in Planning, and hovering shows relations (U1Q3)". Remove "panning and zooming inside a battle" from **Not built**.

### 3.7 Glossary (07)

```markdown
- **Deployment**: the step before a battle's first turn where each side places its squads, hidden, inside its deployment area. *(U1Q4)*
- **Deployment area**: the part of a battlefield where a side places its squads and where its reinforcements arrive. *(U1Q4)*
- **Relation**: one fact about what a squad is doing about another (in range, targeting, under fire, fleeing...), shown on hover and in the comparison menu. *(U1Q3)*
```

---

## 4 Open questions for the owner

| # | Question | Blocking? | Recommended default |
|---|---|---|---|
| Q1 | Should deployment **share** the first Planning with turn-1 orders, or take a **pulse of its own** (the battle doesn't execute that turn, and turn 1 is planned after seeing the enemy deployment)? | Blocks D1 only | **Shared** (Steel Division). No extra overworld pulse, and T1 is already "scouting and positioning". A separate pulse can be a clock-config option later. |
| Q2 | Are enemy **deployment areas** shown during deployment, with enemy squads hidden? | No | Yes. Areas are scenario data, and terrain and zones are public. |
| Q3 | R3Q2 locks the **overworld** while watching. May the overworld **camera** pan and zoom during playback (no selection, no orders)? | No (E1 is battle-only) | Allow the camera only. U1Q3a says "move the map"; R3Q2's lock is read as "no interaction". |
| Q4 | Right click is the **order** button in Planning. How is the comparison menu opened there? | No | Right click opens it **during playback** (no orders then). In Planning, a remappable GUIDE action `compare_squads` (key C, pad: hold the inspect button) opens it. The hover tooltip works in every phase. |
| Q5 | May an enemy squad's facts use its **public weapon range**, for example "you are inside its range"? The range ring already reflects its real weapons, including gear. | No | Yes, as the existing range ring does. Never its orders or hold reasons. |
| Q6 | "**Under fire**" window: how recent must a volley be to count? | No | Data `relation_recent_fire_ticks`, default one second of ticks. |
| Q7 | **sw-tdz** placed squads: accept that bead's suggested answers, plus "placed entries are deployment defaults; `locked` pins them"? | Blocks D7 only | Yes to all six suggestions. Placed entries are defaults, movable unless `locked`. |
| Q8 | Placing **facing**: any angle, or snapped? Placing **formation**? | No | The sim takes any angle and the UI snaps to 8 directions. Formation waits for per-squad formations (movement topic). |
| Q9 | **Story / Angelfall** battles: deploy or fixed? | No | `fixed` until the tutorial teaches deployment. |
| Q10 | **Ambush** starts (Total War skips deployment) and **vanguard**-style deployment outside the area? | No | Later. Recorded as data hooks only. |
| Q11 | `deployment_bonus`: 15 s per newly deploying battle; ranked lower? | No | 15 s casual, 10 s ranked (clock config). |

---

## 5 Bead breakdown

Ordered. Each bead is about a day. Runners: **swarm** = small, well-specified, Qwen4-safe; **autopilot** = Haiku-sized; **autopilot-large** = needs Opus.

### Execution clarity

**E0. Apply U1 execution-clarity and deployment GDD text**: task, P1, runner autopilot
- *Why:* the GDD is the authority, and §3's text must land before code that cites it.
- *What:* insert §3.1–§3.7 into GDD 02, 03, 04 and 07 as accepted by the owner. Fix the GDD 04 drift (l.114 "or a click", l.117 "panning and zooming"). Add the U1Q3/U1Q4 entries to the decision log.
- *Acceptance:* every inserted rule carries U1Q3/U1Q4 or the owner's resolved decision IDs, and no "(proposed)" tag is left on an accepted item.
- *Deps:* owner answers to §4 (at least Q1).

**E1. Playback: battle camera and hover pass through the playback blocker**: feature, P1, runner swarm
- *Why:* U1Q3a. Today the STOP blocker eats wheel, middle-drag and motion during playback (`war_room.gd:463-471`).
- *What:* the battle view (the map region) receives mouse input during playback. Either open `_blocker` only over the panel regions, or give the stage region `MOUSE_FILTER_IGNORE`. Keep `_on_playback_clicked` semantics by routing left click through `_on_battle_pressed`, which already gates on `_play` (`:1239`). In `context_view.gd:1201`, emit `squad_hovered` during playback (use `_battle_squads()` from frames). In `war_room.gd:848-851`, refresh the hover card during playback, rebuilt only when the hovered id or frame changes, as `_play_card_frame` does. Side-panel buttons stay blocked. Overworld playback is unchanged (R3Q2).
- *Files:* `src/presentation/war_room/war_room.gd`, `context_view.gd`, possibly `src/presentation/ui/ui_window.gd`.
- *Acceptance:* GUT, during playback in a battle: a wheel event over the view changes `contexts.zoom`; middle-drag changes `battle_centre`; mouse motion over a squad emits `squad_hovered`; a left click inspects and never skips; a right click issues no order; an End turn / panel button click does nothing. The sw-ll4.27.4 tests stay green. `hx godot check` and the full `hx godot test` pass.
- *Deps:* sw-ll4.27.6 (owns `context_view.gd` hover; land it first).

**E2. Playback: select squads while watching**: feature, P2, runner swarm
- *Why:* U1Q3b. Clicks during playback only set `_inspected`.
- *What:* during playback, left click, shift/ctrl click, box-select and `next_squad` change `BattlePlanner.selection` (own squads), but never drafts. `show_playback` draws selection rings and the selected squad's range/sight rings, as Planning does. Selection persists into the next Planning.
- *Files:* `war_room.gd` (`_on_battle_pressed` ~1231-1257, `_cycle_squad` 1582-1595), `context_view.gd` (`show_playback`, `_draw_battle`).
- *Acceptance:* GUT: select during playback, then skip; the planner selection is intact, drafts are unchanged and `submit_battle_orders` is not called. A mock PNG of the playback with selection (`hx godot mock`).
- *Deps:* E1.

**E3. SquadRelation read model (sim)**: feature, P1, runner autopilot-large
- *Why:* U1Q3c and U1Q3d. One function that serves tooltip, menu, API and AI, and that can't disagree with the sim.
- *What:* `src/sim/battle/squad_relation.gd`, `static func facts(state, viewer, a, b) -> Array` of `{kind, value, from, to, rule, data}`. Kinds: `range` (per-unit `CombatSystem.shot_gate` summary plus `LineOfFire.check`), `sight` (`own_sight` / `seen_by`), `targeting` (`engaged`, `BattleActivity.squad`, dominant `hold`), `ordered` (ATTACK target / closing), `would_engage`, `under_fire`, `fleeing`, `moving`. Refactor without behaviour change: extract `CombatSystem.pick_target(state, row) -> squad id` (static, pure) from `_engage` and have `_engage` call it; extract `BattleOrders.nearest_visible_enemy(state, row)` from `fall_back_point`. Fog filter as in §3.2 (`viewer` 0 = all-seeing). It returns nothing if `b` (or `a`) is unseen by the viewer.
- *Files:* new `squad_relation.gd`; `combat_system.gd`, `battle_orders.gd` (extractions); tests in `tests/sim/`.
- *Acceptance:* GUT per kind. A seeded test asserts `pick_target` equals the `engaged` value `_engage` sets on the next tick, over a multi-squad fixture. A fog test: a hidden enemy gives `[]`, and an enemy-side fact never exposes order, engaged-before-fire, hold or reload. Harness golden hashes are unchanged (`hx sim run duel_crossroads --seeds 3` gives the same hashes as main). Full test gate.
- *Deps:* none (sw-ll4.27.2 closed).

**E4. Game API: live relation queries**: feature, P1, runner autopilot
- *What:* `BattleSession.relation`, `OverworldSession.battle_relation` (any phase but Execute). In Planning, the `contact` fact is joined from the player's last `forecast_battle` result (cached per player and battle, cleared on draft change). In the reaction window, the `reaction` fact comes from `reaction_opportunities` and queued reactions.
- *Files:* `src/api/battle_session.gd`, `src/api/overworld_session.gd`; GDD 04 Game API line (via E0).
- *Acceptance:* GUT: API facts equal `SquadRelation.facts` for the player. The contact fact matches the forecast contact (tick, dealt/taken) and carries `Telegraph.CAVEAT`. A not-in-battle player gets `[]`.
- *Deps:* E3, sw-abk.

**E5. PlaybackProbe: relations at a playback moment**: feature, P1, runner autopilot-large
- *Why:* frames lack order, target, engaged and weapon (§1.3). Re-simulation gives the exact state at frame *i* with zero format change.
- *What:* in `_record_turn`, keep `b.state.snapshot()` from before `execute_turn` (after Reveal applied the orders). Add `src/api/playback_probe.gd`: a private copy (`rules.forecast_copy()`, fresh `BattleSim`, no tick hook), stepped forward lazily to the requested frame, restarted from the snapshot on a backward seek. `playback_relation(player, eid, frame, a, b)` calls `SquadRelation.facts` on it. The probe is dropped when playback is dropped. Add a PerfRecorder scope `playback_probe`.
- *Acceptance:* GUT: the probe stepped to the last frame has `state_hash()` equal to the real battle's end state. A relation at frame *i* equals one computed by a tick-hook capture of the real run at tick *i*. Fog parity with live (hidden enemies give `[]`). Measured worst case (full-turn re-sim on the 200×100 fixture) is recorded in the bead notes. It works in the replay viewer (`MatchReplay`).
- *Deps:* E3. Related: sw-ll4.26.6 (index by frame, not `t`).

**E6. Relation tooltip (hover)**: feature, P2, runner swarm
- *What:* with a selected or inspected squad and a different hovered squad, a tooltip of at most 3 lines (priority: targeting/under fire, then range, then fleeing/moving, then contact). Text from translation keys `relation.<kind>.<value>` with English fallbacks, through the glossary tooltip system. Terms are added as `term` data. Shapes or glyphs carry meaning, never colour alone. It appears in Planning (from E4) and playback (from E5).
- *Files:* `context_view.gd` (via sw-ll4.27.6's mark-at-point lookup), new `src/presentation/war_room/relation_text.gd` (pure, static), `data/packages/core/defs/glossary.json`.
- *Acceptance:* GUT on `RelationText.lines(facts)` (pure): ordering, cap and translation keys. A mock PNG (`relation_tooltip_mock.gd`) for mortar × enemy in range, out of range, and fleeing. The tooltip is clamped on screen (sw-dqj).
- *Deps:* E1, E4, E5, sw-ll4.27.6, sw-dqj.

**E7. Comparison context menu**: feature, P2, runner swarm
- *What:* a `UiWindow` menu listing every relation fact with its rule reference (a glossary link to the §2.6 term). View actions: show both cards, centre the camera on the pair. In Planning only, order actions ("Attack", "Attack-move toward") emit through `PlanningInput.command` / the planner, never straight to the session. Opened by right click during playback, and by GUIDE `compare_squads` in every phase (keyboard and pad bindings, Controls help entry).
- *Files:* new `src/presentation/war_room/relation_menu.gd`, `war_room.gd`, `src/presentation/input/default_keys.gd`, `controls_help.gd`.
- *Acceptance:* GUT: right click during playback opens the menu and issues no order. `compare_squads` opens it in Planning, and its "Attack" drafts an attack through the planner. Esc closes it. Keyboard focus walks the entries (sw-wqc).
- *Deps:* E6. Related: sw-wqc, sw-wut.

### Deployment

**D1. Sim: deployment step (placements, hidden, applied at Reveal)**: feature, P1, runner autopilot-large
- *Why:* U1Q4.
- *What:* add a `BattleState.deploying` flag (saved, hashed), set when a battle is built if the scenario's `deployment` is `open`, and cleared after Reveal applies placements. `src/sim/battle/battle_deploy.gd`: `validate(state, player, p)` (own squad, inside the side's `deploy` rect, at most once per squad, int fixed coordinates, facing an int angle) and `apply(state, player, placements)`. Apply moves the anchor through `BattleSetup.open_point`, re-lays units by `Formation.offset`, and sets facing. While `deploying`: `observe_state`, `inspect` and `IntentForecast` treat every non-own, non-allied squad as unseen, and the build-time `VisionSystem.run` result is not exposed. At Reveal (`_reveal_battles`, `BattleSession` equivalent): apply deployments, then `Centroids.update` and vision, then reinforcements, then orders. Automatic places stay byte-identical to `deploy_side`.
- *Files:* `battle_state.gd`, new `battle_deploy.gd`, `battle_rules.gd` (scenario `deployment`), `overworld_battles.gd`, `src/api/battle_session.gd`, `src/api/overworld_session.gd`.
- *Acceptance:* GUT: same placements and seed give the same hash. Invalid placements are refused (outside the area, enemy squad, duplicate). An impassable placement is snapped. No enemy squad appears in `observe_battle` while deploying, even within sight. With no placement input, harness and golden hashes equal main. An enemy revealed by deployment is a valid reaction trigger. Full test gate.
- *Deps:* E0 (Q1 answered). Related: sw-tdz.

**D2. API, input log, saves and replay for deployment**: feature, P1, runner autopilot
- *What:* `submit_battle_deployment` (Planning, battle deploying), logged as input kind `battle_deploy`. Drafts are kept in `OverworldBattle.deploys` and saved in `to_dict`/`from_dict`. `replay_inputs` handles the kind. `observe_battle` gains `deploying`, `areas`, and the player's own area. Optional controller hook `deploy(obs) -> placements` in `ProfileController` and the headless runner (default: none, so automatic places).
- *Acceptance:* GUT: a save mid-deployment reloads with the drafts. `rebuild` from inputs reproduces the hashes. A replay of a match with deployments shows no hash mismatch. The headless overworld runs unchanged.
- *Deps:* D1.

**D3. Deployment UI in the battle view**: feature, P1, runner autopilot
- *What:* while `deploying`: own area highlighted, enemy areas hatched and labelled. Drag an own squad to place it (ghost snapped to an enterable cell, refused cells marked by shape), with a facing handle and a rotate key (snap to 8). Box-select plus drag places a group keeping offsets. A "Reset to automatic" button. Phase banner: "Deployment: place your squads; the enemy can't see them until Reveal". Turn-1 order drafting works as in Planning. Controls help and the status hint are updated. Pad: cycle squad plus stick nudge (until sw-wut).
- *Files:* `src/presentation/planning/battle_planner.gd` (placement drafts), `war_room.gd`, `context_view.gd`, `controls_help.gd`, new mock `deployment_mock.gd`.
- *Acceptance:* GUT: a drag produces a placement inside the area, and a drop outside clamps to the area edge. Placement drafts submit through `submit_battle_deployment` only. A mock PNG. Full test gate.
- *Deps:* D2, E1.

**D4. Late joiners and reinforcements deploy**: feature, P2, runner autopilot-large
- *What:* compute a joining side's arrival area at the start of Planning, with the same function `_join` uses (extract it), and expose it to that player only. Its placements apply at Reveal. `reinforce` orders accept an optional `{x, y, facing}` inside the side's area (validated), defaulting to the centre as today.
- *Files:* `overworld_battles.gd` (`_join`, `reinforce`), `overworld_orders.gd`, `overworld_session.gd`, D3's UI.
- *Acceptance:* GUT: the arrival area at Planning start equals the one used at Reveal. A placed reinforcement spawns where placed. Defaults are unchanged without placement. The joiner's area is not in other players' observation.
- *Deps:* D2.

**D5. Deployment time bonus**: feature, P3, runner swarm
- *What:* `ClockConfig.deployment_bonus_ms` (data; default 15000, ranked 10000) is added per battle the player deploys in this Planning.
- *Files:* `src/sim/core/clock_config.gd`, `src/sim/core/pulse_clock.gd`.
- *Acceptance:* GUT on remaining time with 0, 1 and 2 deploying battles, saved and restored.
- *Deps:* D1.

**D6. Scenario deployment switch and placed defaults**: feature, P3, runner swarm
- *What:* scenario `deployment: "open" | "fixed"`, with Angelfall set to `fixed`. sw-tdz `placed` entries are the automatic places, with `locked` respected by `BattleDeploy.validate`.
- *Files:* `battle_rules.gd`, `data/packages/core/defs/angelfall.json`, `scenarios.json`, schema.
- *Acceptance:* GUT: a `fixed` scenario never sets `deploying`. A locked placed squad refuses a placement.
- *Deps:* D1, sw-tdz (owner answers, §4 Q7).

**D7. AI deployment heuristic**: feature, P3, runner autopilot-large
- *What:* the utility profile places squads by role: indirect-fire squads at the back edge of the area, short-range squads forward, squads with concealment in cover cells. A harness variant compares it with automatic places.
- *Files:* `src/api/profile_controller.gd`, utility controller, `data/sim/` variant.
- *Acceptance:* `hx sim run <scenario> --variant baseline --variant deploy_smart --seeds 5` recorded in the bead notes. Deterministic per seed.
- *Deps:* D2.

**Suggested order:** E0 → E1 → E3 → (E2, E4, D1) → E5 → (E6, D2) → (E7, D3) → D4 → (D5, D6, D7).
