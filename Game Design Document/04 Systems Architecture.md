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
  - **Logistics:** `set_output(player, feature, option)`, `set_supply_line(player, feature, plot, commander)` and `rally(player, detachment, plot, commander)`. `observe` adds the player's production and supply lines, and marks convoys (destinations only for allies).
  - **War Chest:** `equip(player, commander, item, squad, count)`, `unequip(player, commander, item, count)`, `give_item(player, from, item, count, to)` and `take_items(player, commander, detachment)`. `observe` adds each own or allied commander's `chest` and each detachment's `items`, and army squads list their equipped `items`.
  - **Battles:** every engagement's battle runs in the same session, one battle turn per overworld turn. The inputs are `submit_battle_orders`, `reinforce` and `leave_battle`. `observe_battle` shows a battle to the players fighting in it. The turn hash combines the overworld's and every battle's.
  - **Records:** every input is logged, and the state hash after every turn is kept. `rebuild` replays a save from its inputs and names the first turn whose hash differs.
  - **Headless play:** `HeadlessOverworld` plays turns with any controllers. `ExpandController` is the first rule-based profile: it takes features and caches, converts ore it can afford, and explores.

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

## 4.9 Tools (R8Q7, R8Q6)
- **Now:** authoring tools are Godot editor plugins and data tools; `custom_graph_editor` is used for trigger and dialogue graphs. Angelfall is built with them.
- **Later:** the in-game player campaign editor reuses the same formats and validators.

## 4.10 Addons (R8Q13)
- **Keep:** dialogic (presentation only), gut (tests), guide (input).
- **Evaluate:** `godot-rts-entity-controller`, for selection and command UI ideas only. Remove it if nothing is taken.
- **Removed:** gecs.
