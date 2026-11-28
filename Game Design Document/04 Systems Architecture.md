# 4. Systems Architecture

How the code is shaped. The engine-level rules in AGENTS.md §5 and `GD-Agentic-Skills/godot-skill-distillation.md` still apply. This document makes them concrete for Simple War.

## 4.1 Layers (R6Q24, R7Q14, R8Q11)
```
presentation, audio   (Godot scenes; read-only clients)
        │ inputs ▲ observations + events
Game API              (one headless API for UI, AI, network, tests, AI factory)
        │
simulation            (state stores + systems + event queues; no Nodes, no floats)
        │
data                  (immutable template tables from packages)
```
- **Renderer swap** (O1Q3): battles are drawn in 2D first. The map view is kept separate from the panels and reads only observations, so a 3D view can replace it without touching the simulation. Gameplay height would be a rules change (Rules Spec §2.14).
  - **In play (sw-ll4.8):** `MatchDriver` (API layer) makes the session, seats the AI, ends turns and keeps the match log (`MatchLog` and `EventText` live beside it). The war room wires input and draws. The map view (`ContextView`) takes observations and overlays and reports clicks; the panels are their own classes (`CommandPanel`, `BattlePanel`, `SquadCard`, `PipPanel`, `ControlsHelp`) that emit signals and order nothing themselves. Battle terrain is drawn in each feature's own `color` from the content, so mod terrain needs no code.
- **UI foundations** (O1Q4): built on Godot's own features, not new plugins: one `Theme` for colours, fonts and sizes; `TranslationServer` with translation files for every string; `ConfigFile` for saved settings; GUIDE for every key, with none hard-coded; split containers for resizable panels. Screens name styles from `data/ui/styles.json` (text sizes and tones, panels, gaps); each theme profile in `data/ui/themes/` supplies the colours and scale, so a look change is a data edit. Every popup, overlay and floating card is a `UiWindow` owned by its screen's `UiRoot`, which stacks them in layers (HUD, playback blocker, modals), closes the top modal on Esc, keeps keys from the screen under a modal, returns focus when one closes, and shows each window only in its view contexts (overworld, battle, playback). Where each panel sits is data too: a screen registers its panels by id and `data/ui/layouts/<screen>.json` arranges them in a row of regions (scrolling columns with footers, and the map stage with anchored layers), each region shown in chosen views. A player's own layout in `user://ui_layouts/` replaces the shipped one when it is valid; layouts only arrange the game's own panels.
- **Presentation and audio** only listen. They check what they should be doing, and nothing below them cares what they do (R8Q11).
- **The UI never holds game state.** It emits inputs (AGENTS.md §6).

## 4.2 Simulation store (R5Q17, R6Q18, research notes)
- **Not gecs:** gecs isn't the sim core. Its Entities are Nodes and its world is a global singleton (R8Q13).
- **Per-kind SoA columns:** each entity kind (units, squads, zones, hexes, convoys…) is stored as columns in `Packed*Array`s. IDs are 64-bit and generational, with a slot→row table, a free list and swap-remove.
- **One state object per context:** each battle has its own `BattleState`, and the overworld has an `OverworldState`. All are `RefCounted`. This isolates contexts: each can be created and freed cheaply, hashed and replayed on its own, run headless as a single battle, and later run on its own thread.
- **Systems are functions** that mutate state. Their call order is fixed by the caller, so it is consistent and repeatable (R5Q17).
- **Stable iteration:** systems iterate in a stable order (rows or sorted IDs, never hash order).
- **Command buffer:** structural changes (spawn, despawn) go through a command buffer applied at the end of each phase.
- **Fixed-point maths:** FPDR, with deterministic trigonometry.
- **Sim-owned PRNG:** used only for content generation.
- **State hash:** computed per tick and per turn.
- **Language:** GDScript first. Native code (a GDExtension) comes only when measurement says so (R5Q17, R7Q18). The `step(orders) -> events` / `snapshot()` interface lets a native core swap in.
- **Relationships and derived stats** (U1Q27; `OverworldStats` and the band column landed with sw-63wt.2, payload contributions with sw-63wt.3): a payload is rows pointing at their holder (`ow_squad.detachment`, `ow_item.detachment`), not a component bag. Capabilities are derived: `OverworldStats` is the one reader of a commander's, band's or feature's effective overworld `sight` and `movement_points`.
  - **What it adds up:** the template base, then payload contributions in ID order, capped.
  - **What it returns:** the value with its terms, for tooltips.
  - **Rules:** integer only and deterministic. Vision, convoy planning and glimpses call it, never the raw columns.
  - **New store state:** `ow_detachment.band` (band template index, set at every spawn and transition: drop-off, production, rally, steering, arrival, rallied survivors; −1 in older saves means "derive it: a caravan if it has a destination or a supply line, else a garrison") and `OverworldState.owner_orders` (feature ID → {"action", "option", "player"}, saved and hashed like `activities`).

## 4.3 Events (R6Q19, R7Q12, R7Q13)
- **State objects never talk to each other.** Systems read state and write events.
- **Per-context event queue:** each battle and the overworld has its own queue, which its systems write and read within a tick.
- **Pulse bus:** carries cross-context events, such as `squad_transfer_requested`, `battle_ended` and `convoy_arrived`, and the events presentation listens to. It is applied at fixed pulse points in canonical order. Presentation subscribes and never writes.
- **Cross-context transfers:** reinforcements, battle results, commanders leaving and returning convoys are events, applied by a **transfer system** at the pulse boundary, never mid-tick.
- **Signal buses:** this is AGENTS.md §5's "scoped signal bus per combat, lifecycle-only global bus", made concrete.

## 4.4 Game API (R7Q14)
- **Inputs:** orders, routes, reactions, activity choices, toggles, votes.
- **Observations:** visibility-filtered state plus events, honouring fog, Detection and Concealment (R8Q1, R8Q4). On the overworld these are `OverworldVision.observe` and `OverworldVision.filter_events`.
- **Clock:** real-time pacing for humans, and fast-forward (as fast as possible) for headless runs.
- **Callers:** the human UI, AI controllers, the network layer, test bots and the AI factory all use the same API.
- **Overworld (sw-o1m.1.5):** `OverworldSession` mirrors `BattleSession`.
  - **Inputs:** `set_route` and `set_activity` (Planning only), `ready`, `advance(ms)`.
  - **Queries:** `observe` (fog-filtered, with last turn's visible events) and `path` (the cheapest affordable route as the player knows the map).
  - **Clock:** it runs on the shared PulseClock. On turns with battles (if the clock config allows reactions) a reaction window follows Reveal: `reaction_opportunities(player)` lists them across battles (each with its `engagement`), `submit_reaction(player, engagement, squad, reaction, trigger)` queues one, and `observe` adds `reactions`. Players with nothing to react to are readied automatically. Reactions are logged and replayed, and saves keep the window's opportunities.
  - **Drop-offs:** `set_drop_off(player, commander, step, plot)` plans one; `transfer_squad` also picks squads up from a detachment. `observe` lists detachments in sight (their squads only for allies) and the player's planned drop-offs.
  - **Logistics:** `set_output(player, feature, option)`, `set_supply_line(player, feature, plot, commander)` and `rally(player, detachment, plot, commander)`. `observe` adds the player's production and supply lines, and marks convoys (destinations only for allies). Each detachment carries its `band` kind; own and allied ones also their effective `sight` and `movement` with terms (`OverworldStats`). `convoy_reach` budgets a detachment at its caravan movement points.
  - **Missions:** `observe` adds `outcome` ({} while running; else `outcome` won or lost, `key`, `text`, `turn`), set by an `end_mission` trigger; `mission_ended` is a public event.
  - **War Chest:** `equip(player, commander, item, squad, count)`, `unequip(player, commander, item, count)`, `give_item(player, from, item, count, to)` and `take_items(player, commander, detachment)`. `observe` adds each own or allied commander's `chest` and each detachment's `items`, and army squads list their equipped `items`.
  - **Battles:** every engagement's battle runs in the same session, one battle turn per overworld turn. The inputs are `submit_battle_orders`, `reinforce` and `leave_battle`. `observe_battle` shows a battle to the players fighting in it. `forecast_battle(player, engagement, orders)` (and `BattleSession.forecast(player, orders)`) previews drafted orders for intent ghosts during planning, changing nothing. The turn hash combines the overworld's and every battle's.
  - **Records:** every input is logged, and the state hash after every turn is kept. `rebuild` replays a save from its inputs and names the first turn whose hash differs.
  - **Headless play:** `HeadlessOverworld` plays turns with any controllers. `ExpandController` is the first rule-based profile: it takes features and caches, converts ore it can afford, and explores.
  - **Owner actions** (U1Q24; proposed, Round U1, awaiting review): `set_owner_action(player, feature, action, option)` (Planning only; "" clears; `buy` names a `recruits` squad or `sells` item). `observe` adds the player's `owner_orders`.
  - **Features** (U1Q23; proposed): `inspect_feature(player, feature)` returns one feature as `inspect_plot` lists it, plus `actions`: each owner action it allows, with its cost and why not. It is read-only, any phase, and works from memory for features out of sight. `inspect_plot` builds its feature list from it.
  - **Bands** (U1Q27; proposed): `observe` gives each own or allied band its `band` kind, and its effective `sight` and `movement` with terms. Enemies see the kind but not the payload.
- **Relations** (U1Q8; proposed, Round U1, awaiting review): `BattleSession.relation(player, a, b)` and `OverworldSession.battle_relation(player, engagement, a, b)` return the relation facts between two squads the player sees (Rules Spec §2.6 "Pair relations"): `[{kind, value, from, to, rule, data}]`, fog-filtered for `player`. `OverworldSession.playback_relation(player, engagement, frame, a, b)` answers the same for a moment of the last turn's playback: the session keeps the turn's start state and re-runs the battle to that frame on a private copy through the one shared `BattleCursor` (`src/api/battle_cursor.gd`; deterministic, so it is the state that was), then asks the same function. The UI, the AI and the harness all use these calls.
- **Deployment** (U1Q30, U1Q31; calls proposed): `submit_battle_deployment(player, engagement, placements)` in Planning while the battle is deploying; `placements` is `[{squad, x, y, facing}]` (fixed point); errors as for orders, and a squad whose `placed` entry is `locked` is refused. `observe_battle` carries `deploying`, the player's area (or arrival area) and every side's area, and no enemy squads while deploying. Placements are logged and replayed like orders.

## 4.5 Client/server split (R3Q11)
- **Always split:** the client and server are separate even in single-player. A client only receives and simulates what its server tells it.
- **Every peer runs a server:** each one defers to an authoritative host, and the host can change during a game.

## 4.6 Networking (R6Q20, R6Q21, R6Q22, R8Q8)
- **Lockstep:** plain per-turn lockstep. Local prediction is used only for UI previews and forecasts. There is no rollback; it is unnecessary with 60 s WeGo turns.
- **Host:** a host sequencer collects each turn's orders. Host migration is epoch-based, with a deterministic successor. Every peer keeps the current turn's orders. Deadlines are expressed as a turn-start timestamp plus a duration.
- **Desync detection:** state hashes are compared at the end of each turn.
- **Transport:** Steam lobbies plus Steam Networking Sockets with Steam Datagram Relay, through GodotSteam, which supports Godot 4.7. It sits behind a transport interface, with our own packet format and no JSON on the wire.
- **Anti-cheat stance** (R3Q11): remove cheaters rather than prevent every attack.
  - Flag vectors: seed-determined host time-sharing, and conflicting host claims.
  - Replay auditing: data values are checked against versioned data.
  - A BAR-like replay hosting site and community reports.
- **Ranked service:** a minimal free-tier serverless service.
  - It verifies Steam auth tickets and accepts results co-signed by every peer.
  - A headless auditor re-simulates sampled or disputed replays.
  - Steam leaderboards are display-only.
  - At first it records results without a rating model (R7Q10).
  - Only official widgets and tools are allowed in ranked (R4Q20).
- **Telemetry** (R8Q8): opt-in and anonymous. It covers disconnect causes, match length, crashes and performance, never chat or personal data. It goes to the same serverless service.

## 4.7 Saves and replays (R8Q5)
- **Save content:** a snapshot of every store at a pulse boundary, plus the input/telemetry log, the mod list and the data hash. A save can be rebuilt by re-simulation.
- **When saves happen:**
  - an autosave every turn
  - manual single-player saves during planning
  - autosave only in ironman and challenge modes
- **Multiplayer:** a host save resumes in a lobby with the same slots.
- **Replays:** a replay is the initial snapshot plus the input log. Harness runs produce replays too (R5Q19).

## 4.8 Presentation contexts (R2Q19, R3Q20, R4Q15)
- **Context stack:** overworld → battle, with picture-in-picture battle views, a battles menu, fast swapping and tabbing, and several battles shown at once.
- **Camera rules:**
  - **Following a commander:** follow the commander → tab into its battle → swap battles → exit returns to the followed commander.
  - **Selecting another commander** inside a battle exits to that commander.
  - **Deselect-all** exits to the current battle's overworld location.
- **Zoom transition:** zooming past a threshold with a battle hex in context transitions to that battle at the default zoom.
- **In play (sw-ip8.2):** `ViewContexts` (presentation state, fed by `observe`) holds the focus (overworld or one battle), the followed and selected commander, the selected hex, zoom and the picture-in-picture views. The war room scene (`src/presentation/war_room/`, runs standalone on a demo with two battles) projects it. Mock: `Mocks/war_room.png`.
  - **Battles shown:** only the player's own battles (an own commander or detachment fights there). The focused one fills the main view; up to 3 more sit in movable picture-in-picture views. Clicking a PiP swaps it with the focused battle, which takes its place.
  - **Battles menu:** focus any battle, pin or unpin it, or exit to the overworld.
  - **Keys:** Tab / Shift+Tab swap battles (Tab tabs in from the overworld, into the followed or selected commander's battle first), Esc exits, F follows the selected commander, Backspace or a right click deselects all, the mouse wheel zooms.
  - **Zoom transition:** zooming in to 3x on the overworld enters the battle on the hex in context: the selected hex, else the selected commander's hex, else the camera's. The battle opens at 1x.
  - **Battles ending:** a focused battle that ends exits as if by Esc; pinned ones close.
  - **Selecting** a commander that fights in the focused battle stays in it; any other exits to that commander.
- **Readability (sw-ip8.7)**, from the first skirmish playtest:
  - **Event feed:** the side panel lists what the player saw happen each turn, in plain words (`EventText`): battles starting and ending, squads lost, commanders defeated (with how many squads scattered), squads produced, recruited, picked up and sent as reinforcements, captures and convoys. Squads destroyed in a battle are reported by a `squads_lost` event when it ends.
  - **Armies and garrisons:** the selected commander's panel lists every squad in its army (units alive, whether it is in the battleforce) and offers to pick up a garrison or convoy on its hex. A selected hex lists its features, garrisons and convoys. On the map, commanders show their army size, garrisons are squares and convoys diamonds with a line to their destination.
  - **Battle terrain** is drawn in the battle view, with a legend. A move order draws a line to where the squad was sent; the ghost shows how far it gets this turn.
  - **Reaction window:** a banner says moves are locked and what can be done. Moves drawn then are kept, marked queued, and sent when Planning returns (they used to be dropped silently).
  - **Match log:** every game played from a map writes `user://matches/<started>-<map>-s<seed>/`: `log.md` (per turn: the player's clicks and their results, every player's accepted orders, everything that happened), `match.json` and the replayable `match.sav`. The newest 30 are kept.
- **Hex view (U1Q20–U1Q23; proposed, Round U1, awaiting review; proposed numbers).** Until it is built, the zoom transition above (3x enters the battle, which opens at 1x) stands.
  - **Scale:** a hex is 64 px in circumradius at zoom 1 (111 × 128 px; was 26). Zoom runs 0.25–3.0, and entering a battle moves to 2.5 (s = 160 px).
  - **Detail bands** by on-screen radius s:
    - s < 24: one glyph per hex (its first site and a count), owner marks only.
    - 24–48: every site in its slot, no names.
    - s ≥ 48: sites with owner rings and progress pips.
    - s ≥ 96: the names of owned sites.
    - At any scale the hovered and selected hex show their names on a plate. That is at most one label per hex.
  - **Layout:** `HexLayout` (presentation, static, no state) turns a hex's known features, its known road neighbours and the map's `at` overrides into site points and a mover lane. Both the war room and the World maps tab use it. Points are cached per plot until its features or its neighbours' roads change.
  - **Selection:** `ViewContexts.selected_feature` (−1 = none) sits beside `selected_plot`. Clicking a site selects it and its hex; clicking open ground selects the hex only. Selecting a commander or band, or deselecting all, clears it. `ContextView.feature_at(pos)` hit-tests the sites of the hexes in view. The hex panel lists sites as selectable rows, and hovering or selecting either highlights both.
  - **Right click:** with an owned producing site selected, a right click on a hex or on one of the player's commanders sets that site's rally point (like steering a caravan).
  - **Movers:** commanders and bands stand in the mover lane: along the hex's lower edge, or on the road when the hex has one. Up to 3 tokens, then "+n".
- **UI pass (sw-ll4.19)**, from the second skirmish playtest:
  - **Squads on the battlefield:** every unit is drawn where it stands, on a tinted footprint that follows the formation, with an arrow for the squad's facing, its name and strength (`7/8`), and a health bar for the player's own. Zones are drawn with who holds them. The battle observation carries what this needs: each squad's `name`, `size`, `facing`, `range` (its longest weapon among living units) and `sight`.
  - **Ranges:** a selected, hovered or inspected squad shows a ring at its weapon range. A single selected squad also shows its sight ring.
  - **Battle panel:** a column left of a focused battle lists the scores and zones and holds the **squad card** (`SquadCard`) of the squad clicked, else the first selected, else the one hovered: strength, order, health and SIMPL pools (own squads), weapon range and sight, and per unit type its health, each fire mode's accuracy and damage, speed and defence, then the squad's effects. Enemy squads in sight can be clicked too (`inspect_battle`). It is one page: the tabs and per-stat traces of the inspection window mock are not built.
  - **What does what:** two lines under the view give the status and what the mouse and keys do in the present context (overworld, commander selected, battle, selection, reaction window, playback). A **Controls** button lists every control.
  - **Overworld movement:** with a commander selected, the hexes it can enter this turn are lit and numbered with their movement cost (`OverworldSession.reach`), the rest are dimmed, and hovering a hex previews the route and its cost. Right click moves there. Shift + right click adds a waypoint: the route continues from where it ended (`path` with `via`). Right click on the commander clears the route.
  - **Garrisons, convoys and rally points:** a selected hex offers "Send this garrison/convoy to" for the player's detachments there and "Set rally point" for a producing feature. The next hex clicked is the destination, or one of the player's commanders if it stands there. A selected commander lists the player's other detachments with "Call here".
  - **Turn playback:** a resolved turn is played out before the next Planning is shown, over 5 seconds by default (Options: instant, 2, 5 or 10). Commanders and convoys walk the hexes they moved through. Battles replay tick by tick as the player saw them (`OverworldSession.playback`, kept only when asked through `keep_playback`), with a line for each volley. Space or Esc skips it; a click inspects the squad under it (sw-ll4.27.4). The game has already resolved by then: playback only delays what is drawn, and it never changes a result. Watching is reading, not acting (Rules Spec §2.2, U1Q32): in battle and overworld playback the camera and every information view (tooltips, panels, squad cards, inspection, relations, selecting to inspect) work, and every planning or activity control (orders, routes, reactions, deployments, purchases, owner actions, rally, production) is disabled with the reason until Planning. A battle that ended that turn is still shown to its end.
  - **Options** (`OptionsScreen`, `GameSettings`; the display part of sw-ll4.10): window mode (windowed, borderless fullscreen, exclusive fullscreen), window size, vsync, UI scale and the playback time, saved in `user://settings.cfg` and applied when the main menu opens. Reached from the main menu and the war room.
  - **Layout:** the side panel scrolls, so its buttons never fall off a 720-pixel window.
  - **Not built:** mouse panning, zooming, hovering and the information views during battle and overworld playback (U1Q6–U1Q8, U1Q32; planning has them), unit facings (only the squad has one), damage numbers during playback, playback in the Story scene (it still resolves at once).
- **Skirmish flow (sw-ll4.11):**
  - **Setup** is the main menu's skirmish block: opponent profile, map and seed.
  - **Saving:** `MatchDriver.save_game` writes the session's own save with what is being played (map, seed, opponent profile, the human's seat) and the tallies so far to `user://saves/<slot>.sav`. The war room has a **Save** button (a new slot each time), and a game started or loaded from the menu also writes the `autosave` slot after every resolved turn. A save can be taken in any phase but Execute, including mid-planning with orders given: events an order pushed at once are kept in the snapshot (sw-007).
  - **Loading:** the main menu's **Load game** lists the saves, newest first, and opens the picked one in the war room with the same opponent profile. It refuses a save made with different content. The AI's own memory is not saved: it plans afresh from the loaded state, so a loaded game can go differently from the one that was saved. A loaded game writes no match log.
  - **Results:** when the match ends, a results screen says who won and why, how many turns and battles it took, and what each side lost (squads, commanders) and took (features), tallied by `MatchDriver` from every turn's events. It offers Play again (same map, seed and opponent), Main menu, and Look at the map.
  - **Replays (sw-ll4.22):** the main menu's **Replays** lists the recorded matches (every game started from a map writes a match log with a replayable `match.sav`), newest first. `MatchReplay` starts a fresh session on the same map and seed and feeds it the recorded inputs one turn at a time, checking each turn's state hash against the recording; a mismatch is shown as a warning. The war room hosts it: Next turn (Space) plays the next recorded turn through the usual playback, Play all runs them one after another, and Other side (V) watches as the next player with that player's fog. A replay session is `locked`: it refuses every order, ready and clock input but the recording's. A match recorded with different content is refused. The newest 30 recordings are kept.
  - **Not built:** stepping a replay backwards or jumping to a turn, watching with the fog off, replays of loaded games (they write no match log), deleting or naming saves, saving a Story mission's progress from its own menu.

## 4.9 Tools (R8Q7, R8Q6)
- **Now:** authoring tools are Godot editor plugins and data tools; `custom_graph_editor` is used for trigger and dialogue graphs. Angelfall is built with them.
- **Later:** the in-game player campaign editor reuses the same formats and validators.
- **In play (sw-cgl.3):** the `simple_war_tools` editor plugin adds a **War Data** main screen (`WarDataPanel`, which also runs standalone).
  - **Template:** templates by kind. For the selected one, the panel shows its flattened values with the template that set each (provenance) and its definition text to edit. You can Validate, Apply, or Add it as a new template to a chosen data file.
  - **Edits are textual:** `PackageEditor` replaces only that template's span in its JSON file, so formatting and diffs survive. An edit is checked against the whole package first (schema, every map and scenario compiling, the glossary) and refused if anything breaks.
  - **Triggers:** a map's or scenario's triggers drawn with `custom_graph_editor` (`TriggerGraph`). The nodes are events, triggers, variables, zones and features, and links show what reads or writes what. Selecting a trigger opens its template. The graph is a view; edits happen in the definition text.
  - **Problems:** everything the package would fail to load with.
  - **Dialogue graphs** (sw-cgl.4): the `dialogue` kind (`Dialogue`) holds nodes, choices and set_var/add_var effects (dispositions are sim variables, R3Q18); the Dialogues tab draws them (`DialogueGraph`) and edits them in the graph (add a node, draw or delete a link; `DialogueEdit` applies each change, validated and saved; sw-7wt); the `start_dialogue` trigger action pushes `dialogue_started`. Dialogic playback of it is not built yet.
- **Map editor** (O1Q6; the terrain painter, "Play this map" and battle-map objects are in play, sw-ll4.6, sw-ll4.7; the trigger form and overworld maps are not built): a **Maps** tab in the War Data screen, in the spirit of StarCraft's editor. It edits `battle_map`, `scenario` and `overworld_map` templates through `PackageEditor`, so every change is validated against the whole package before it is written.
  - **Terrain:** paint cells or hexes from the feature list with brush, rectangle, line and fill tools; mirror painting for two-player maps. The editor keeps a cell grid while you paint and saves it as the map's shape list (Data Model §3.5): runs of the same feature and facing merged into rectangles, written in row order so files diff.
  - **Stamps:** place another map (a building, a bridge) as one object, move it and turn it in quarter turns. "Save selection as a map" makes a new stamp.
  - **Cell properties:** the selected cells' `facing`, set from the keyboard or a side panel.
  - **Objects:** place, move and edit zones, deployment areas, pre-placed squads, starts, and overworld features with owners.
  - **Triggers:** edit a trigger through a form built from the closed vocabulary (pick an event, checks and actions from lists), beside the existing graph view. The definition text stays available.
  - **Test:** "Play this map" starts a skirmish on it against a chosen AI profile.
  - **In play (sw-ll4.6):** `MapPainter` (the tab) over `MapCanvas` (the model, no UI), for `battle_map` templates.
    - **Tools:** brush with a size, rectangle, line, fill, pick. The right button paints the base feature. Five mirrors: none, left and right, top and bottom, four ways, half turn; facings flip with them.
    - **Stamps:** the Stamp tool places the chosen map with a quarter-turn rotation; the right button removes one. Painting on a stamp turns it into painted cells first (with any stamp below that it overlaps), so the paint shows on top; undo brings the stamp back. Fill and Pick go by what the map shows, stamps included. The Select tool (M) drags a marquee over cells or picks up a stamp to move it (Delete removes it); "Save selection as a map" writes the marquee, stamps drawn in, as a new battle map in the chosen data file (sw-ll4.17).
    - **Layers:** the editor holds one painted layer with the stamps drawn above it. Saving writes the painted layer as merged rectangles, then the stamps, so hand-written fills are merged again (a fill that was one rectangle stays one). A map that fills over a stamp loads with a note and saves with the stamp on top.
    - **Saving:** new maps are added to a chosen data file; existing ones replace their own text. Fields the editor doesn't know are kept. A map that would break the package (a stamp loop) is refused with the reasons, and so is one that a scenario played on it no longer fits (a zone centred off it, a deployment area not wholly inside it).
    - **Also:** undo and redo (64 steps), resize, change the base, zoom and drag the view. Feature colours come from the feature's `color`.
    - **Overworld maps, model only (sw-96x):** `OverworldCanvas` (no UI) holds an `overworld_map` as fills, one painted feature per hex (hex brush, rectangle, hex line, fill; `rect` and `line` passes load into it), objects (`place` passes and owned hexes, with owners) and starts, with undo, mirror-map ghosts (`partner`, players 1 and 2 swapped) and a save that merges painted hexes into rectangles and keeps `scatter` passes as written.
    - **World maps tab, in play (sw-7ii):** `OverworldPainter`, a tab of its own beside Maps (so each painter keeps its own tools), draws the open overworld map on its hexes (pointy-top, odd rows shifted) and edits it through `OverworldCanvas`. Selecting an overworld map on the left opens it there.
      - **Tools:** Brush (a hex and its neighbours out to a radius), Rectangle, Line (a hex line), Fill and Pick paint the ground; the right button clears the painted feature, leaving the fills. Place puts the chosen feature on a hex with the chosen owner; Start adds the chosen player's starting commander. Click an object or start to select it, drag to move it, right-click or Delete to remove it; the owner and commander lists change the selected one.
      - **Map settings:** name, `elimination` (the skirmish win condition) and `mirror`, each one undo step. A mirror map needs an even height. On a mirror map painting the ground paints both halves, so the view shows what the game makes; objects and starts are made on one half and their partners drawn as ghosts.
      - **Saving:** like battle maps: new maps go to a chosen data file, and a map that would break the package is refused.
      - **Layout** (U1Q21; proposed, Round U1, awaiting review): the Layout tool (Y) drags a placed site inside its hex and writes the `place` pass's `at`. Right-click resets it to its slot. The hex shows the same `HexLayout` as the game. Roads are a second painted layer (path), so a road can cross forest.
    - **Wall shapes:** `MapCanvas.shape_at` names the piece to draw (end, straight, corner, tee, cross, with quarter turns) from a feature's `connects` field (`ConnectShape`); drawing only. **Drawn (sw-bgd):** the Maps tab draws the piece in each cell from zoom 9 (where the facing arrows start), as bars from the centre to each joined side, or a post when it joins none.
  - **Objects, in play (sw-ll4.7):** a `scenario` played on the open map is open with it (`ScenarioCanvas`, the model, no UI). A map opens with the first scenario that names it; the Scenario list picks another or none, and New starts one with the core field scenario's rules, a deployment strip inside each short edge and a centre zone.
    - **Drawn over the terrain:** each side's deployment area in its player's colour, with its facing as an arrow and how many squads it lists, and each zone with its id and points.
    - **Objects tool (O):** click a zone or an area to select it, drag to move it, drag an area's corner handle to resize it; Delete removes it. The panel edits the rest: a zone's id, radius, points, threshold, decay and buffer; a side's player, facing and squads (add from the package's squads, remove one by one). A side that lists no squads is for overworld battles, where the commanders bring them.
    - **Saving:** Save writes the map and then the scenario, each checked against the whole package. Everything the editor does not edit in a scenario (ruleset, victory, triggers) is kept as written. Undo and redo act on the scenario while the Objects tool is on, and on the terrain otherwise.
    - **Victory, in play (sw-bel):** below the selected object's panel, the open scenario's victory settings: turn limit, primary score (influence or value), score target, and the annihilation and withdrawal switches. A value the scenario inherits from its parent shows as it is and is written only once changed; undo covers them.
    - **Repeat on the mirror side (sw-dn5a):** with a mirror on the map, "Repeat on mirror side" in a zone's or a side's panel copies it to its mirror cell or area, players 1 and 2 swapped (a side's facing turns with the mirror, its squads are copied). The copy is written as its own object, like mirror-painted terrain, so moving one later does not move the other. Four ways and half turn both repeat by the half turn; players other than 1 and 2 are refused.
    - **Not built:** squads placed at their own positions (a side's squads deploy evenly down its area).
  - **Play this map, in play:** the main menu's **Map editor** opens the War Data screen on the Maps tab, with an opponent list and a **Play this map** button (`MapPlaytest`).
    - **What it plays:** a battle on the open map as it is painted at that moment, saved or not, against the chosen controller profile. Nothing is written. "Back to the editor" returns to the map with its unsaved paint.
    - **How:** a battle map is not a match by itself, so the playtest adds two templates in memory: a scenario on the map and a four-hex overworld whose two commanders meet at once. The scenario is the one open in the editor, with its unsaved zones, areas and squads. With none open, it is made up: the core field scenario's rules (`ow_field`), a deployment strip inside the left and right edges, and one zone in the middle.
    - **Forces:** a side that lists squads fields exactly those. A side that lists none fields a `field_commander`'s battleforce.
    - **Limits:** two players only, and the button is on the in-game screen only, not in the Godot editor plugin.
  - **Order of work:** the map format and its loader first, then the terrain painter, then objects, then the trigger form. The panel already runs standalone, which is the path to the later in-game editor (R8Q7).
  - **Tiled:** an importer from Tiled's format is optional and comes after our own painter. Tiled is never the stored format.
- **Behaviour workshop** (U1Q5; proposed, Round U1, awaiting review): `src/presentation/workshop/behaviour_workshop.tscn`, F6. It plays one workshop scenario (Harness and AI Factory §5.7) with debug overlays, stepping and scrubbing. It reads `WorkshopRun` frames from the API layer (`src/api/workshop/`), re-simulated through the shared `BattleCursor`. The truth behind its overlays and probes is `BattleProbe` (`src/sim/battle/battle_probe.gd`), a read-only snapshot that combines `BattleActivity`, `LineOfFire` and the recent shots.
  - **In play (sw-tho3.8):** `BehaviourWorkshop` runs with F6 or `hx godot run` (`-- --scenario=<id or path> --variant=<name>`; else the first file in `data/sim/workshop`). Pickers choose the scenario and variant. `WorkshopRun` records with debug frames, and the whole run plays as one `OverworldSession.playback_entry` in `ContextView.show_playback` (with `BattleFx`), the `DebugOverlay` on top with its layers as checkboxes. Transport is the replay viewer's keys through GUIDE (`DefaultKeys.workshop`): Space, +/-, comma and period a tick, Left and Right a turn, Home, a scrub slider, F5 reloads the file at the same frame. The probe list marks each probe pass, fail or report; a click seeks to its tick (a window's first) and inspects its squad. Clicking a squad shows its `SquadCard` from `Inspection` on the exact state at that frame (`WorkshopRun.state_at`: the turn's `BattleCursor`), so a seek to frame N shows what the headless run had at frame N. A turn with mid-turn scripted orders has no cursor state; the card says so.

## 4.10 Addons (R8Q13)
- **Keep:** dialogic (presentation only), gut (tests), guide (input).
- **Removed (sw-ip8.5):** `godot-rts-entity-controller` was evaluated for selection and command UI ideas and nothing was taken. Its autoloads drew their own control-group bar over every screen, so the addon, its autoloads and its input actions are gone. Control groups are the planner's own (`BattlePlanner`).
- **Removed:** gecs.

## 4.11 Implementation status of the Rules Spec
The Rules Spec (doc 2) holds rules only. Which task built what lives in the tracker (`hx task show <id>`); this table maps rules to the tasks that implemented them.

| Rules Spec | Built by |
|---|---|
| §2.2 Intent forecast, reaction marks and queue; only visible triggers | sw-ip8.3, sw-tz1 |
| §2.3 Armies, battleforces, drop-offs and detachments | sw-o1m.2.1, sw-o1m.2.2, sw-o1m.2.4 |
| §2.4 Battles from engagements, shared pulse, leaving | sw-o1m.2.3, sw-o1m.2.5, sw-o1m.2.7 |
| §2.6 Range and vision, "in range" marks | sw-kys.6, sw-kys.7 |
| §2.9 Turn order, offers | sw-o1m.1.3, sw-cgl.2 |
| §2.9 Movement and sight | sw-o1m.1.2, sw-o1m.1.4, sw-o1m.2.4 |
| §2.9 Production, supply lines, steering, convoys | sw-o1m.2.5, sw-kys.8, sw-ll4.19 |
| §2.9 Items and chests | sw-o1m.2.6 |
| §2.11 Angels, dispersal, guards in battle | sw-cgl.2, sw-136.2, sw-cf6 |
| §2.13 Ability activation, inspection | sw-ps1.5, sw-ps1.6 |
| §2.14 Battle grid, routing, deployment | sw-ll4.2, sw-ll4.4, sw-ll4.15 |

Not built yet (still specified): the Angel roster stealing items and inverted auto-resolve for the final battles (sw-136.2 covers dispersal only), charges (§2.14), and chase and intercept (§2.9).
