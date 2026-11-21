class_name OverworldSession
extends RefCounted
## The Game API for the overworld (GDD 04 §4.4, R7Q14): the one interface
## the human UI, AI controllers, the network layer, tests and the AI factory
## use. Mirrors BattleSession.
##
## Inputs:   set_route, set_drop_off, set_activity, transfer_squad (also picks up
##           from a detachment), set_battleforce, set_output,
##           set_supply_line, rally, equip, unequip, give_item,
##           take_items, answer_offer
##           (Planning only), save_preset, ready, advance(ms);
##           submit_reaction (Reaction only).
## Queries:  observe(player) - fog-filtered state plus last turn's visible
##           events (OverworldVision); path(player, commander, to) - the
##           cheapest affordable route as the player knows the map.
## Battles:  every engagement becomes a battle at the start of the next
##           turn (OverworldBattles) and runs one battle turn per overworld
##           turn on the same pulse: submit_battle_orders, reinforce and
##           leave_battle in Planning; observe_battle shows one;
##           forecast_battle previews drafted orders (intent ghosts).
## Clock:    the shared PulseClock (R2Q3). Reveal sends reinforcements in
##           and applies every battle's orders. While any battle runs (and
##           the clock config allows it), a reaction window follows: each
##           battle's coming turn is forecast (Reactions), players react
##           through submit_reaction, and a player with nothing to react to
##           is ready at once (GDD 02 §2.2). Each player's battle count sets
##           its bonus time. Execute runs the battle turns, applies finished
##           battles, resolves the overworld turn, then starts new battles.
## Records:  every input is logged with its turn and phase, and the state
##           hash after every resolved turn is kept, so a replay (initial
##           state + inputs) is checked turn by turn (R8Q5, R6Q20).

const SAVE_VERSION: int = 1

## Why the last load_save / rebuild returned null (empty on success).
static var last_error: String = ""

var map_id: String
var templates: TemplateTable
var seed_value: int
var data_hash: String
var rules: OverworldRules
var state: OverworldState
var clock: PulseClock
var bus: PulseBus
## [{"turn", "phase", "player", "kind", "payload"}]
var input_log: Array = []
## State hash (hex) after each resolved turn; [i] is after turn i + 1.
var turn_hashes: PackedStringArray = PackedStringArray()
## Every event of the last resolved turn (unfiltered; observe filters).
var last_events: Array[SimEvent] = []
## Battles in progress: engagement ID -> OverworldBattle.
var battles: Dictionary = {}
## Problems building battles (bad battlefield data); such engagements end.
var errors: PackedStringArray = PackedStringArray()
var _next_context: int = 100
## One sim runs every battle (it holds no per-battle state).
var _battle_sim := BattleSim.new()

var _players: PackedInt64Array = PackedInt64Array()
var _execute_pending: bool = false
## The clock config's own reaction_enabled: the window opens only on turns
## with battles, and only if this allows it.
var _reactions_allowed: bool = true
## Reaction window: engagement ID -> Reactions.forecast opportunities.
var _opportunities: Dictionary = {}
## Set on entering the reaction window: ready the players with nothing to
## react to (done in _pump, outside the clock's call stack).
var _auto_ready: bool = false
## A replay (MatchReplay): the session takes no orders, readies or time
## from outside; only replay_inputs moves it.
var locked: bool = false
## Presentation opt-in: keep every battle's last turn tick by tick
## (`playback`). Read-only; it never changes a result.
var keep_playback: bool = false
## Engagement ID -> {"rules", "players", "frames", "shots"} of the last turn.
var _playback: Dictionary = {}
## Engagement ID -> player -> worst own SIMPL band index last recorded (at
## the battle's start and after each of its turns): the glance summary's
## backward-looking trend reference. Only the session records it; saved
## with the game, it never feeds back into the simulation.
var _band_history: Dictionary = {}
## Set while rebuilding: the hashes the replay must reproduce.
var _expected: PackedStringArray = PackedStringArray()
var _diverged: int = -1


## Creates a session at turn 1, Planning, with the map's starting
## commanders. Returns null (and sets last_error) if the data is invalid.
static func create(templates: TemplateTable, hash_hex: String, map: String, seed_in: int, clock_config: ClockConfig = null) -> OverworldSession:
	last_error = ""
	var r := OverworldRules.compile(templates, map, hash_hex)
	if not r.is_valid():
		last_error = "; ".join(r.errors)
		return null
	if r.players().is_empty():
		last_error = "map '%s' has no players" % map
		return null
	var s := OverworldSession.new()
	s._setup(templates, r, map, seed_in, hash_hex, clock_config)
	s.clock.start()
	return s


func _setup(t: TemplateTable, r: OverworldRules, map: String, seed_in: int, hash_hex: String, clock_config: ClockConfig) -> void:
	templates = t
	rules = r
	map_id = map
	seed_value = seed_in
	data_hash = hash_hex
	state = OverworldState.create(1, rules, seed_in)
	for st in rules.starts:
		Commanders.spawn_index(state, st["player"], st["commander"], st["plot"])
	OverworldVision.update(state)
	_players = rules.players()
	bus = PulseBus.new()
	bus.register_context(state)
	var cfg := _config_from(_config_dict(clock_config if clock_config != null else ClockConfig.new()))
	_reactions_allowed = cfg.reaction_enabled
	cfg.reaction_enabled = false
	clock = PulseClock.new(cfg)
	for p in _players:
		clock.add_player(p)
		clock.set_battles(p, 0)
	clock.phase_changed.connect(_on_phase)
	clock.pulse_point.connect(_on_pulse)


## The battle simulator every battle runs on (harness profiling and
## SimMetrics hook into it; it holds no per-battle state).
func battle_sim() -> BattleSim:
	return _battle_sim


func players() -> PackedInt64Array:
	return _players.duplicate()


func phase_name() -> String:
	return PulseClock.Phase.keys()[clock.phase]


## Overworld turns resolved so far.
func turns_resolved() -> int:
	return state.turn


# --- inputs ----------------------------------------------------------------

## Sets (or, with an empty route, clears) a commander's route. "" or why not.
func set_route(player: int, commander_id: int, plots: PackedInt64Array) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.set_route(state, player, commander_id, plots)
	if err.is_empty():
		_log(player, "route", {"commander": commander_id, "plots": plots.duplicate()})
	return err


## Plans (or, with plot -1, clears) a commander's drop-off: after route step
## `step` (-1 = before moving), its battleforce without its own squad is
## dropped on that hex or one next to it. "" or why not.
func set_drop_off(player: int, commander_id: int, step: int, plot: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.set_drop_off(state, player, commander_id, step, plot)
	if err.is_empty():
		_log(player, "drop", {"commander": commander_id, "step": step, "plot": plot})
	return err


## Selects which production option an owned feature makes. "" or why not.
func set_output(player: int, feature_id: int, option: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.set_output(state, player, feature_id, option)
	if err.is_empty():
		_log(player, "output", {"feature": feature_id, "option": option})
	return err


## Sends an owned feature's output along a supply line to a plot or one of
## the player's commanders (both -1 clears it). "" or why not.
func set_supply_line(player: int, feature_id: int, plot: int, commander: int = -1) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.set_line(state, player, feature_id, plot, commander)
	if err.is_empty():
		_log(player, "supply", {"feature": feature_id, "plot": plot, "commander": commander})
	return err


## Steers a detachment by hand along `plots` (sw-kys.8; Convoys.set_route):
## a chain of neighbouring hexes, possibly several turns long. Empty halts
## it. "" or why not.
func set_convoy_route(player: int, detachment_id: int, plots: PackedInt64Array) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.set_route(state, player, detachment_id, plots)
	if err.is_empty():
		_log(player, "convoy_route", {"detachment": detachment_id, "plots": plots.duplicate()})
	return err


## What a detachment of `player` can enter this turn: {"budget" (the map's
## convoy movement points), "reach" (plot -> cost)}; {} if not its own or
## in a battle.
func convoy_reach(player: int, detachment_id: int) -> Dictionary:
	var row := state.detachments.row_of(detachment_id)
	if row < 0 or state.detachments.player[row] != player or state.detachments.engagement[row] >= 0:
		return {}
	return {"budget": rules.convoy_mp,
		"reach": OverworldPath.reach(state, state.detachments.plot[row], rules.convoy_mp, player)}


## The cheapest way for a detachment to plot `to`, as the player knows the
## map, whole (a convoy keeps walking on later turns). With `via` (the route
## it already has), the way continues from its end and the result is the
## whole route: waypoints. Empty if none.
func convoy_path(player: int, detachment_id: int, to: int, via: PackedInt64Array = PackedInt64Array()) -> PackedInt64Array:
	var row := state.detachments.row_of(detachment_id)
	if row < 0 or state.detachments.player[row] != player:
		return PackedInt64Array()
	var from := state.detachments.plot[row] if via.is_empty() else via[via.size() - 1]
	var way := OverworldPath.find(state, from, to, player)
	if way.is_empty():
		return PackedInt64Array()
	var out := via.duplicate()
	out.append_array(way)
	return out


## Sends a detachment as a convoy to a plot or one of the player's
## commanders (both -1 halts it). "" or why not.
func rally(player: int, detachment_id: int, plot: int, commander: int = -1) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.rally(state, player, detachment_id, plot, commander)
	if err.is_empty():
		_log(player, "rally", {"detachment": detachment_id, "plot": plot, "commander": commander})
	return err


## Equips `count` items of a stack in a commander's War Chest to a squad
## of its army (R4Q10). "" or why not.
func equip(player: int, commander_id: int, item_id: int, squad_id: int, count: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.equip(state, player, commander_id, item_id, squad_id, count)
	if err.is_empty():
		_log(player, "equip", {"commander": commander_id, "item": item_id, "squad": squad_id, "count": count})
	return err


## Returns `count` equipped items to the commander's War Chest.
func unequip(player: int, commander_id: int, item_id: int, count: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.unequip(state, player, commander_id, item_id, count)
	if err.is_empty():
		_log(player, "unequip", {"commander": commander_id, "item": item_id, "count": count})
	return err


## Hands items between friendly commanders sharing a hex (R7Q9).
func give_item(player: int, from_commander: int, item_id: int, count: int, to_commander: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.give(state, player, from_commander, item_id, count, to_commander)
	if err.is_empty():
		_log(player, "give", {"from": from_commander, "item": item_id, "count": count, "to": to_commander})
	return err


## A commander takes the War Chest of the player's detachment on its hex.
func take_items(player: int, commander_id: int, detachment_id: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.take(state, player, commander_id, detachment_id)
	if err.is_empty():
		_log(player, "take", {"commander": commander_id, "detachment": detachment_id})
	return err


## Answers an offer made to the player this turn (an uncertain feature,
## R6Q14) with one of its choices; the map's triggers decide what it does.
func answer_offer(player: int, feature_id: int, choice: String) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldTurn.answer(state, player, feature_id, choice)
	if err.is_empty():
		_log(player, "answer", {"feature": feature_id, "choice": choice})
	return err


## Plans (or, with "", clears) a commander's activity; recruit names the
## squad in `option`. "" or why not.
func set_activity(player: int, commander_id: int, activity: String, option: String = "") -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.set_activity(state, player, commander_id, activity, option)
	if err.is_empty():
		_log(player, "activity", {"commander": commander_id, "activity": activity, "option": option})
	return err


## Sets a commander's battleforce plan: a preset name ("" = strongest) or
## hand-picked squads, and whether the commander's own squad leads it.
func set_battleforce(player: int, commander_id: int, preset: String, squads: PackedInt64Array = PackedInt64Array(), lead: bool = true) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldBattleforce.set_plan(state, player, commander_id, preset, squads, lead)
	if err.is_empty():
		_log(player, "battleforce", {"commander": commander_id, "preset": preset, "squads": squads.duplicate(), "lead": lead})
	return err


## Saves one of the player's own battleforce presets (any phase).
func save_preset(player: int, name: String, prefer: PackedStringArray, avoid: PackedStringArray = PackedStringArray()) -> String:
	if not _players.has(player):
		return "unknown player"
	var err := OverworldBattleforce.save_preset(state, player, name, prefer, avoid)
	if err.is_empty():
		_log(player, "preset", {"name": name, "prefer": prefer.duplicate(), "avoid": avoid.duplicate()})
	return err


## Orders for the player's squads in one battle this turn (BattleOrders).
## Replaces earlier ones; returns errors, keeping the valid orders.
func submit_battle_orders(player: int, engagement_id: int, orders: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	var err := _planning(player)
	var b: OverworldBattle = battles.get(engagement_id)
	if err.is_empty() and (b == null or not b.state.players.has(player)):
		err = "not in that battle"
	if not err.is_empty():
		errs.append(err)
		return errs
	var kept := []
	for i in orders.size():
		var e := BattleOrders.validate(b.state, player, orders[i])
		if e.is_empty():
			kept.append((orders[i] as Dictionary).duplicate(true))
		else:
			errs.append("order %d: %s" % [i, e])
	b.orders[player] = kept
	_log(player, "battle_orders", {"engagement": engagement_id, "orders": kept})
	return errs


## The planning forecast for one of the player's battles (IntentForecast):
## the coming battle turn with these drafted orders, as the player knows
## it. Nothing is submitted or changed. Planning only ({} otherwise).
func forecast_battle(player: int, engagement_id: int, orders: Array) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if clock.phase != PulseClock.Phase.PLANNING or b == null or not b.state.players.has(player):
		return {}
	return IntentForecast.run(b.state, _battle_sim, player, orders)


## forecast_battle as a job for a worker thread (IntentForecast.job): an
## invalid Callable when there is nothing to forecast. Callers must let it
## finish before the turn resolves.
func forecast_job(player: int, engagement_id: int, orders: Array) -> Callable:
	var b: OverworldBattle = battles.get(engagement_id)
	if clock.phase != PulseClock.Phase.PLANNING or b == null or not b.state.players.has(player):
		return Callable()
	return IntentForecast.job(b.state, player, orders)


## Sends a squad from a staying commander's army into its battle.
func reinforce(player: int, commander_id: int, squad_id: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		var eid := state.commanders.get_value(commander_id, &"engagement") if state.commanders.is_alive(commander_id) else -1
		var b: OverworldBattle = battles.get(eid)
		if b == null:
			err = "is not in a battle"
		else:
			err = OverworldOrders.reinforce(state, player, commander_id, squad_id, _in_field(b, commander_id))
	if err.is_empty():
		_log(player, "reinforce", {"commander": commander_id, "squad": squad_id})
	return err


## Reaction opportunities for the player during the reaction window, across
## its battles: [{"engagement", "squad", "player", "trigger", "tick",
## "reactions"}], by engagement then forecast order.
func reaction_opportunities(player: int) -> Array:
	if clock.phase != PulseClock.Phase.REACTION:
		return []
	var out := []
	var eids: Array = _opportunities.keys()
	eids.sort()
	for eid: int in eids:
		for o: Dictionary in _opportunities[eid]:
			if o["player"] == player:
				var x := o.duplicate()
				x["engagement"] = eid
				out.append(x)
	return out


## Queues a reaction for one of the player's squads in a battle (Reaction
## phase only). "" or why not.
func submit_reaction(player: int, engagement_id: int, squad: int, reaction: String, trigger: int) -> String:
	if clock.phase != PulseClock.Phase.REACTION:
		return "reactions are only accepted in the reaction window"
	var b: OverworldBattle = battles.get(engagement_id)
	var ok := false
	for o: Dictionary in _opportunities.get(engagement_id, []):
		if o["player"] == player and o["squad"] == squad and o["trigger"] == trigger and reaction in o["reactions"]:
			ok = true
			break
	if b == null or not ok:
		return "no such reaction opportunity"
	var err := Reactions.queue(b.state, squad, reaction, trigger)
	if err.is_empty():
		_log(player, "reaction", {"engagement": engagement_id, "squad": squad, "reaction": reaction, "trigger": trigger})
	return err


## A commander whose own squad is not fighting leaves its battle.
func leave_battle(player: int, commander_id: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.leave_battle(state, player, commander_id)
	if err.is_empty():
		_log(player, "leave", {"commander": commander_id})
	return err


## What the player can still bring into battle `eid`, per commander of its
## there (sw-dek): [{"commander", "open" (battleforce slots free), "squads":
## [{"squad", "tmpl", "alive", "size", "sent" (joins at the next Reveal),
## "why" (why it can't be sent now, "" if it can)}]}]. Commanders with nothing
## in reserve are left out.
func reserves(player: int, eid: int) -> Array:
	var out := []
	var b: OverworldBattle = battles.get(eid)
	if b == null:
		return out
	var c := state.commanders
	var q := state.squads
	var joined := {}
	for bid: int in b.links:
		joined[b.links[bid]] = true
	var phase_err := _planning(player)
	for row in c.count():
		if c.player[row] != player or c.engagement[row] != eid:
			continue
		var cid := c.id_at(row)
		var in_field := _in_field(b, cid)
		var squads := []
		for id in OverworldArmies.of(state, cid):
			var r := q.row_of(id)
			var sent := q.deployed[r] == eid and not joined.has(id)
			if q.own[r] == 1 or q.alive[r] <= 0 or (q.deployed[r] >= 0 and not sent):
				continue
			var why := ""
			if not sent:
				why = phase_err if not phase_err.is_empty() else OverworldOrders.reinforce_error(state, player, cid, id, in_field)
			squads.append({"squad": id, "tmpl": q.tmpl[r], "alive": q.alive[r], "size": q.size[r], "sent": sent, "why": why})
		if not squads.is_empty():
			out.append({"commander": cid, "open": maxi(rules.bf_cap_squads - in_field, 0), "squads": squads})
	return out


## The commander's squads still fighting in battle b, plus those on the way.
func _in_field(b: OverworldBattle, cid: int) -> int:
	var n := 0
	var linked := {}
	for bid: int in b.links:
		var id: int = b.links[bid]
		linked[id] = true
		if id < 0 or not state.squads.is_alive(id) or state.squads.get_value(id, &"holder") != cid:
			continue
		var row := b.state.squads.row_of(bid)
		if row >= 0 and b.state.squads.is_active(row):
			n += 1
	for id in OverworldBattleforce.deployed_in(state, b.engagement):
		if not linked.has(id) and state.squads.get_value(id, &"holder") == cid:
			n += 1
	return n


## Moves a squad between two of the player's commanders on one hex (R7Q9).
func transfer_squad(player: int, squad_id: int, to_commander: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.transfer_squad(state, player, squad_id, to_commander)
	if err.is_empty():
		_log(player, "transfer", {"squad": squad_id, "to": to_commander})
	return err


func ready(player: int) -> void:
	if locked or not _players.has(player):
		return
	_log(player, "ready", null)
	clock.mark_ready(player)
	_pump()


## Feeds elapsed time (ms). Headless drivers may skip it and rely on ready.
func advance(ms: int) -> void:
	if locked or ms <= 0:
		return
	_log(0, "advance", ms)
	clock.advance(ms)
	_pump()


func _planning(player: int) -> String:
	if locked:
		return "this is a replay: it takes no orders"
	if clock.phase != PulseClock.Phase.PLANNING:
		return "orders are only accepted during planning"
	if not _players.has(player):
		return "unknown player"
	return ""


# --- clock -----------------------------------------------------------------

func _on_pulse(point: StringName, _turn: int) -> void:
	bus.flush(point)


func _on_phase(phase: PulseClock.Phase, _turn: int) -> void:
	match phase:
		PulseClock.Phase.REVEAL:
			_reveal_battles()
			clock.config.reaction_enabled = _reactions_allowed and not battles.is_empty()
		PulseClock.Phase.REACTION:
			_opportunities = {}
			var ids: Array = battles.keys()
			ids.sort()
			for eid: int in ids:
				_opportunities[eid] = Reactions.forecast((battles[eid] as OverworldBattle).state, _battle_sim)
			_auto_ready = true
		PulseClock.Phase.EXECUTE:
			_execute_pending = true


## Runs work the clock asked for, outside the clock's own call stack.
func _pump() -> void:
	while _execute_pending or _auto_ready:
		if _auto_ready:
			_auto_ready = false
			for p in _players:
				if clock.phase == PulseClock.Phase.REACTION and reaction_opportunities(p).is_empty():
					clock.mark_ready(p)
			continue
		_execute_pending = false
		_opportunities = {}
		PerfRecorder.begin(&"sim_battles")
		_run_battles()
		PerfRecorder.end(&"sim_battles")
		PerfRecorder.begin(&"sim_overworld")
		last_events = OverworldTurn.resolve(state)
		PerfRecorder.end(&"sim_overworld")
		_start_battles()
		if rules.triggers != null:
			rules.triggers.run(state, state.events.all(), false)  # battles starting, guards dispersed
		_count_battles()
		last_events.append_array(state.events.drain())
		var h := state_hash_hex()
		var i := turn_hashes.size()
		turn_hashes.append(h)
		if _diverged < 0 and i < _expected.size() and _expected[i] != h:
			_diverged = i + 1
		clock.execute_finished()


## Reveal: reinforcements join every battle, the neutral side (guards,
## Angels) gets its orders from GuardController, and every side's orders
## apply.
func _reveal_battles() -> void:
	var ids: Array = battles.keys()
	ids.sort()
	for eid: int in ids:
		var b: OverworldBattle = battles[eid]
		OverworldBattles.reinforce(state, b)
		var n := OverworldBattles.NEUTRAL
		if b.state.players.has(n):
			b.orders[n] = GuardController.orders(BattleSession.observe_state(b.state, n), b.rules, n)
		for p in b.state.players:
			BattleOrders.apply(b.state, p, b.orders.get(p, []))
		b.orders = {}


## Each player's battle count drives its bonus time (R3Q1).
func _count_battles() -> void:
	for p in _players:
		var n := 0
		for eid: int in battles:
			if (battles[eid] as OverworldBattle).state.players.has(p):
				n += 1
		clock.set_battles(p, n)


## One battle turn in every battle, then finished battles are applied.
func _run_battles() -> void:
	var ids: Array = battles.keys()
	ids.sort()
	var done := []
	_playback = {}
	for eid: int in ids:
		var b: OverworldBattle = battles[eid]
		if keep_playback:
			_record_turn(eid, b)
		else:
			_battle_sim.execute_turn(b.state)
		_record_bands(eid, b)
		if b.state.is_over():
			done.append(eid)
	for eid: int in done:
		var b: OverworldBattle = battles[eid]
		OverworldBattles.finish(state, b)
		bus.unregister_context(b.context_id)
		battles.erase(eid)
		_band_history.erase(eid)


## Runs one battle turn, keeping a frame per tick (and one before the
## first): PLAYBACK_STRIDE ints per unit, and the turn's shot and hit traces
## (BattleState.trace_shots). Whatever hook the sim already has still runs.
func _record_turn(eid: int, b: OverworldBattle) -> void:
	var frames: Array[PackedInt64Array] = []
	var first_tick := b.state.tick
	var was := _battle_sim.tick_hook
	var capture := func(st: BattleState) -> void:
		if was.is_valid():
			was.call(st)
		if frames.size() <= b.rules.ticks_per_turn:
			frames.append(_frame(st))
	frames.append(_frame(b.state))
	_battle_sim.tick_hook = capture
	b.state.trace_shots = true
	b.state.shot_trace = PackedInt64Array()
	b.state.hit_trace = PackedInt64Array()
	_battle_sim.execute_turn(b.state)
	b.state.trace_shots = false
	_battle_sim.tick_hook = was
	var last := frames.size() - 1
	var shots := []
	for e in b.state.turn_log:
		if e.type == &"squad_fired":
			shots.append([clampi(e.tick - first_tick + 1, 0, last), int(e.data["squad"]), int(e.data["target"])])
	# Frame i holds the state after tick first_tick + i - 1, so what happened
	# in a tick shows from the frame after it.
	var volleys := []
	var st := b.state.shot_trace
	for o in range(0, st.size(), BattleState.SHOT_STRIDE):
		volleys.append([clampi(st[o] - first_tick + 1, 0, last), st[o + 1], st[o + 2], st[o + 3] == 1])
	var hits := []
	var ht := b.state.hit_trace
	for o in range(0, ht.size(), BattleState.HIT_STRIDE):
		hits.append([clampi(ht[o] - first_tick + 1, 0, last), ht[o + 1], ht[o + 2], ht[o + 3]])
	b.state.shot_trace = PackedInt64Array()
	b.state.hit_trace = PackedInt64Array()
	_playback[eid] = {"rules": b.rules, "players": b.state.players.duplicate(), "frames": frames,
		"shots": shots, "volleys": volleys, "hits": hits}


## Ints per unit in a playback frame: ID, squad, player, x, y, squad facing,
## seen_by, template, HP, max HP, activity (BattleSession.ACT_* bits).
const PLAYBACK_STRIDE: int = 11
static func _frame(st: BattleState) -> PackedInt64Array:
	var u := st.units
	var sq := st.squads
	var f := PackedInt64Array()
	for row in u.count():
		var srow := sq.row_of(u.squad[row])
		if srow < 0 or not sq.is_active(srow):
			continue
		f.append_array(PackedInt64Array([u.id_at(row), u.squad[row], sq.player[srow], u.x[row], u.y[row], sq.facing[srow], sq.seen_by[srow],
			u.tmpl[row], u.hp[row], u.hp_max[row], BattleSession.activity(st, row)]))
	return f


## The last resolved turn of every battle `player` fought in, tick by tick
## and as the player saw it (needs keep_playback): engagement ID ->
## {"rules" (BattleRules), "width", "height", "frames": one Dictionary per
## tick (the first is the turn's start), squad ID -> {"player", "facing",
## "ids": unit IDs, "units": their points in metres, "tmpls": unit template
## IDs, "hp": HP fractions (0..1), "acts": activity bits (ACT_*)}, "shots":
## [[frame, squad, target]] where the player saw both ends, "volleys":
## [[frame, shooter unit, victim unit, hit]] every shot where the player saw
## both units, landing (or passing) at that frame, and "hits": [[frame,
## victim unit, damage (fixed), by unit]] every hit on a unit the player saw}.
## A battle that ended this turn is still here.
func playback(player: int) -> Dictionary:
	PerfRecorder.begin(&"playback_build")
	var out := {}
	var me := BattleSquads.bit(player)
	for eid: int in _playback:
		var rec: Dictionary = _playback[eid]
		if not (rec["players"] as PackedInt64Array).has(player):
			continue
		var r: BattleRules = rec["rules"]
		var frames := []
		# Per frame, the unit IDs the player saw.
		var seen := []
		for f: PackedInt64Array in rec["frames"]:
			var squads := {}
			var units := {}
			for o in range(0, f.size(), PLAYBACK_STRIDE):
				if f[o + 2] != player and f[o + 6] & me == 0:
					continue
				if not squads.has(f[o + 1]):
					squads[f[o + 1]] = {"player": f[o + 2], "facing": f[o + 5], "ids": [], "units": [], "tmpls": [], "hp": [], "acts": []}
				var d: Dictionary = squads[f[o + 1]]
				(d["ids"] as Array).append(f[o])
				(d["units"] as Array).append(Vector2(f[o + 3], f[o + 4]) / float(Fixed.ONE))
				var t := f[o + 7]
				(d["tmpls"] as Array).append(r.unit_ids[t] if t >= 0 and t < r.unit_ids.size() else "")
				(d["hp"] as Array).append(clampf(float(f[o + 8]) / maxf(float(f[o + 9]), 1.0), 0.0, 1.0))
				(d["acts"] as Array).append(f[o + 10])
				units[f[o]] = true
			frames.append(squads)
			seen.append(units)
		var shots := []
		for sh: Array in rec["shots"]:
			var at: Dictionary = frames[sh[0]]
			if at.has(sh[1]) and at.has(sh[2]):
				shots.append(sh)
		# A shot is shown when the player saw both units the tick before it
		# (a victim it killed is gone from the frame it lands in).
		var volleys := []
		for v: Array in rec.get("volleys", []):
			var at: Dictionary = seen[maxi(v[0] - 1, 0)]
			if at.has(v[1]) and at.has(v[2]):
				volleys.append(v)
		var hits := []
		for h: Array in rec.get("hits", []):
			if (seen[maxi(h[0] - 1, 0)] as Dictionary).has(h[1]):
				hits.append(h)
		out[eid] = {"rules": r, "width": r.width, "height": r.height, "frames": frames, "shots": shots,
			"volleys": volleys, "hits": hits}
	PerfRecorder.end(&"playback_build")
	return out


## Battles begin at the start of a turn (R2Q1): every engagement without one
## gets it now, or ends at once if nobody opposes.
func _start_battles() -> void:
	for eid in state.engagements.ids():
		if battles.has(eid) or not state.engagements.is_alive(eid):
			continue
		var before := errors.size()
		var b := OverworldBattles.build(templates, data_hash, state, eid, _next_context,
			(seed_value * 7919 + _next_context) & 0x7fffffff, errors)
		if b == null:
			if errors.size() > before:
				push_warning("OverworldSession: %s" % errors[errors.size() - 1])
			OverworldBattles.finish_unopposed(state, eid)
			continue
		_next_context += 1
		battles[eid] = b
		bus.register_context(b.state)
		_record_bands(eid, b)


## The overworld's hash combined with every battle's (desync checks).
func state_hash_hex() -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(state.state_hash())
	var ids: Array = battles.keys()
	ids.sort()
	for eid: int in ids:
		h.update(PackedInt64Array([eid, _next_context]).to_byte_array())
		h.update((battles[eid] as OverworldBattle).state.state_hash())
	return h.finish().hex_encode()


# --- queries ---------------------------------------------------------------

## What `player` may know (OverworldVision.observe), plus the clock, the map
## size and the visible events of the last resolved turn.
func observe(player: int) -> Dictionary:
	var o := OverworldVision.observe(state, player)
	o["phase"] = phase_name()
	o["remaining_ms"] = clock.remaining_ms(player)
	o["width"] = rules.width
	o["height"] = rules.height
	var evs := []
	for e in OverworldVision.filter_events(state, player, last_events):
		evs.append(e.to_dict())
	o["events"] = evs
	for bt: Dictionary in o["battles"]:
		bt["battle"] = battles.has(bt["engagement"])
	o["reactions"] = reaction_opportunities(player)
	o["outcome"] = state.outcome.duplicate()
	return o


## One battle as `player` sees it ({} unless the player fights in it): the
## battle observation, plus "engagement" and "links" (battle squad ID ->
## overworld squad ID, own squads only).
func observe_battle(player: int, engagement_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or not b.state.players.has(player):
		return {}
	var o := BattleSession.observe_state(b.state, player)
	o["engagement"] = engagement_id
	o["phase"] = phase_name()
	var mine := {}
	for bid: int in b.links:
		var id: int = b.links[bid]
		if id >= 0 and b.state.squads.row_of(bid) >= 0 and b.state.squads.player[b.state.squads.row_of(bid)] == player:
			mine[bid] = id
	o["links"] = mine
	return o


## The glance summary of one battle for `player` ({} unless it fights in
## it): the worst SIMPL band across its OWN squads still fighting, as
## {"band" (name), "pool" (its SIMPL pool), "squad" (battle squad ID),
## "trend", "prev_band" (the last recorded worst band, "" before any
## record)}. The trend is backward-looking — the current worst band against
## the one recorded after the battle's previous turn (or its start):
## "worsening", "improving", "steady", or "new" with no record yet. Never a
## forecast of pending orders (GDD 02 §2.2 Vacuum stays "Not yet").
## Read-only, any phase; enemy pools are never read (fog-safe).
func battle_summary(player: int, engagement_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or not b.state.players.has(player):
		return {}
	var worst := _worst_own_band(b, player)
	if worst.is_empty():
		return {}
	var prev: int = (_band_history.get(engagement_id, {}) as Dictionary).get(player, -1)
	var trend := "new"
	if prev >= 0:
		trend = "worsening" if worst["band"] < prev else ("improving" if worst["band"] > prev else "steady")
	return {"band": DataSchema.BANDS[worst["band"]], "pool": DataSchema.SIMPL[worst["pool"]], "squad": worst["squad"],
		"trend": trend, "prev_band": DataSchema.BANDS[prev] if prev >= 0 else ""}


## The lowest band across the player's own active squads and all five SIMPL
## pools, by the sim's own mapping (Pools.band): {"band", "pool", "squad"}
## of the first worst entry (store order breaks ties), or {} with no own
## squad fighting.
static func _worst_own_band(b: OverworldBattle, player: int) -> Dictionary:
	var out := {}
	var sq := b.state.squads
	for row in sq.count():
		if sq.player[row] != player or not sq.is_active(row):
			continue
		for p in DataSchema.SIMPL.size():
			var band := Pools.band(b.state, row, p)
			if out.is_empty() or band < int(out["band"]):
				out = {"band": band, "pool": p, "squad": sq.id_at(row)}
	return out


## Records every side's worst own band: the trend's reference point.
func _record_bands(eid: int, b: OverworldBattle) -> void:
	var h: Dictionary = _band_history.get(eid, {})
	for p in b.state.players:
		var w := _worst_own_band(b, p)
		if not w.is_empty():
			h[p] = w["band"]
	_band_history[eid] = h


## The inspection window's data for one squad of a battle (Inspection), as
## BattleSession.inspect: own squads always, enemy squads only while seen.
func inspect_battle(player: int, engagement_id: int, squad_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or not b.state.players.has(player):
		return {}
	var row := b.state.squads.row_of(squad_id)
	if row < 0:
		return {}
	var own := b.state.squads.player[row] == player
	if not own and (b.state.squads.seen_by[row] & BattleSquads.bit(player) == 0 or not b.state.squads.is_active(row)):
		return {}
	return Inspection.squad(b.state, squad_id, player)


## What `player` knows about one hex, for inspecting it (hover cards, the
## selection panel): {"plot", "known" (ever seen), "visible" (in sight
## now), "cost" (movement points to enter, -1 impassable), "features":
## [{"id", "name", "owner", "controllable", "guard": squad names,
## "value_per_turn", "cache_value", "activities": names, "recruits":
## [{"id", "name", "cost"}], "hires": [{"id", "name", "cost"}], "produces": [{"name", "turns", "cost", "selected",
## "progress" (own, selected option only; else -1)}], "line" (own: where
## its output goes: {"plot", "commander"} or {})}], "commanders": [{"id",
## "player", "squads" (own: army size, else -1), "engagement"}],
## "detachments": [{"id", "player", "convoy", "squads" (own: names)}],
## "battle" (an engagement there)}. Read-only, any phase.
func inspect_plot(player: int, plot: int) -> Dictionary:
	var out := {"plot": plot, "known": false, "visible": false, "cost": -1, "features": [], "commanders": [], "detachments": [], "battle": false}
	if plot < 0 or plot >= rules.plot_count() or not _players.has(player):
		return out
	var obs := OverworldVision.observe(state, player)
	var entry: Dictionary = (obs["plots"] as Dictionary).get(plot, {})
	if entry.is_empty():
		return out
	out["known"] = true
	out["visible"] = bool(entry.get("visible", false))
	out["cost"] = OverworldVision.known_costs(state, player)[plot]
	var production: Dictionary = obs.get("production", {})
	var lines: Dictionary = obs.get("supply_lines", {})
	for f: Dictionary in entry.get("features", []):
		var t := int(f["tmpl"])
		if t < 0 or t >= rules.hf_names.size():
			continue
		var fid := int(f["id"])
		var guard := PackedStringArray()
		for g in rules.hf_guard[t]:
			var gi := rules.squad_index(g)
			guard.append(rules.sq_names[gi] if gi >= 0 else g)
		var acts := PackedStringArray()
		for i in OverworldRules.ACTIVITIES.size():
			if rules.hf_activities[t] & (1 << i) != 0:
				acts.append(OverworldRules.ACTIVITIES[i])
		var recruits := []
		for i in range(0, rules.hf_recruits[t].size(), 2):
			recruits.append({"id": rules.squad_ids[rules.hf_recruits[t][i]], "name": rules.sq_names[rules.hf_recruits[t][i]], "cost": rules.hf_recruits[t][i + 1]})
		var hires := []
		for i in range(0, rules.hf_hires[t].size(), 2):
			var cm := rules.hf_hires[t][i]
			hires.append({"id": rules.commander_ids[cm], "name": rules.cm_names[cm], "cost": rules.hf_hires[t][i + 1]})
		var produces := []
		var opts := rules.hf_produces[t]
		var made: Dictionary = production.get(fid, {})
		@warning_ignore("integer_division")
		for i in opts.size() / OverworldRules.PRODUCTION_STRIDE:
			var o := i * OverworldRules.PRODUCTION_STRIDE
			var what := rules.sq_names[opts[o]] if opts[o] >= 0 else "%d × %s" % [opts[o + 4], rules.it_names[opts[o + 3]] if opts[o + 3] >= 0 else "item"]
			var chosen: bool = not made.is_empty() and int(made["output"]) == i
			produces.append({"name": what, "turns": opts[o + 1], "cost": opts[o + 2], "selected": chosen,
				"progress": int(made["progress"]) if chosen else -1})
		out["features"].append({"id": fid, "name": rules.hf_names[t], "owner": int(f.get("owner", 0)),
			"controllable": rules.hf_controllable[t] == 1, "guard": guard, "value_per_turn": rules.hf_value_per_turn[t],
			"cache_value": rules.hf_cache_value[t], "activities": acts, "recruits": recruits, "hires": hires, "produces": produces,
			"line": (lines.get(fid, {}) as Dictionary).duplicate()})
	for c: Dictionary in obs.get("commanders", []):
		if int(c["plot"]) == plot:
			out["commanders"].append({"id": c["id"], "player": c["player"], "engagement": c["engagement"],
				"squads": (c["army"] as Array).size() if c.has("army") else -1})
	for d: Dictionary in obs.get("detachments", []):
		if int(d["plot"]) == plot:
			var names := PackedStringArray()
			for q: Dictionary in d.get("squads", []):
				names.append(rules.sq_names[int(q["tmpl"])])
			out["detachments"].append({"id": d["id"], "player": d["player"], "convoy": d.get("convoy", false), "squads": names})
	for b: Dictionary in obs.get("battles", []):
		if int(b["plot"]) == plot:
			out["battle"] = true
	return out


## A commander's movement this turn, as the player knows the map:
## {"budget", "spent" (by its planned route), "reach": plot -> cheapest cost
## from where it stands}. {} if it is not the player's.
func reach(player: int, commander_id: int) -> Dictionary:
	var row := state.commanders.row_of(commander_id)
	if row < 0 or state.commanders.player[row] != player:
		return {}
	var budget := Commanders.budget(state, row)
	var costs := OverworldVision.known_costs(state, player)
	var spent := 0
	for p: int in state.routes.get(commander_id, PackedInt64Array()):
		spent += maxi(costs[p], 0)
	var held := state.commanders.engagement[row] >= 0
	return {"budget": budget, "spent": spent,
		"reach": {} if held else OverworldPath.reach(state, state.commanders.plot[row], budget, player)}


## The cheapest route for a commander to plot `to`, as the player knows the
## map, cut to what it can afford this turn. Empty if none. With `via` (a
## route it already plans), the way continues from that route's end and the
## result is the whole route: waypoints.
func path(player: int, commander_id: int, to: int, via: PackedInt64Array = PackedInt64Array()) -> PackedInt64Array:
	var row := state.commanders.row_of(commander_id)
	if row < 0 or state.commanders.player[row] != player:
		return PackedInt64Array()
	var from := state.commanders.plot[row] if via.is_empty() else via[via.size() - 1]
	var full := OverworldPath.find(state, from, to, player)
	var costs := OverworldVision.known_costs(state, player)
	var budget := Commanders.budget(state, row)
	var out := via.duplicate()
	var spent := 0
	for p in via:
		spent += maxi(costs[p], 0)
	if full.is_empty():
		return PackedInt64Array()
	for p in full:
		spent += costs[p]
		if spent > budget:
			break
		out.append(p)
	return out


# --- persistence and replays (R8Q5) ----------------------------------------

## A save: the input log, per-turn hashes and data identity, plus a
## snapshot at a phase boundary to resume from.
func save() -> PackedByteArray:
	assert(clock.phase != PulseClock.Phase.EXECUTE, "OverworldSession.save: not during execute")
	var events := []
	for e in last_events:
		events.append(e.to_dict())
	var data := {
		"version": SAVE_VERSION, "map": map_id, "seed": seed_value, "data_hash": data_hash,
		"clock_config": _saved_config(), "inputs": input_log.duplicate(true),
		"hashes": turn_hashes.duplicate(), "state": state.snapshot(), "clock": clock.snapshot(),
		"last_events": events, "hash": state_hash_hex(),
		"battles": _battles_dict(), "next_context": _next_context,
		"opportunities": _opportunities.duplicate(true), "band_history": _band_history.duplicate(true),
	}
	return var_to_bytes(data).compress(FileAccess.COMPRESSION_GZIP)


## Loads a save from its snapshot. Null if the content differs.
static func load_save(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> OverworldSession:
	last_error = ""
	var data: Variant = _decode(bytes)
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != SAVE_VERSION:
		last_error = "unreadable save"
		return null
	if data["data_hash"] != hash_hex:
		last_error = "content differs from the save's (different mods or version)"
		return null
	var r := OverworldRules.compile(templates, data["map"], hash_hex)
	var s := OverworldSession.new()
	s._setup(templates, r, data["map"], data["seed"], hash_hex, _config_from(data["clock_config"]))
	s.state.restore(data["state"])
	s.clock.restore(data["clock"])
	s.input_log = data["inputs"]
	s.turn_hashes = data["hashes"]
	for e: Dictionary in data["last_events"]:
		var ev := SimEvent.new(e["type"], e["data"])
		ev.source = e["source"]
		ev.seq = e["seq"]
		ev.tick = e["tick"]
		s.last_events.append(ev)
	var bd: Dictionary = data.get("battles", {})
	for eid: int in bd:
		var b := OverworldBattles.from_dict(templates, hash_hex, bd[eid])
		s.battles[eid] = b
		s.bus.register_context(b.state)
	s._next_context = data.get("next_context", 100)
	s._opportunities = data.get("opportunities", {})
	s._band_history = data.get("band_history", {})
	if s.state_hash_hex() != data["hash"]:
		last_error = "the saved state does not match its hash"
		return null
	return s


## The clock config as created (reaction_enabled as allowed, not as this
## turn has it).
func _saved_config() -> Dictionary:
	var d := _config_dict(clock.config)
	d["reaction_enabled"] = _reactions_allowed
	return d


func _battles_dict() -> Dictionary:
	var out := {}
	for eid: int in battles:
		out[eid] = OverworldBattles.to_dict(battles[eid])
	return out


## Replays a save's inputs from the start without trusting its snapshot,
## checking the state hash after every turn. Null on the first turn that
## differs (last_error names it) or if the end state differs.
static func rebuild(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> OverworldSession:
	last_error = ""
	var data: Variant = _decode(bytes)
	if typeof(data) != TYPE_DICTIONARY or data.get("data_hash") != hash_hex:
		last_error = "unreadable save or different content"
		return null
	var s := create(templates, hash_hex, data["map"], data["seed"], _config_from(data["clock_config"]))
	if s == null:
		return null
	s._expected = data["hashes"]
	s.replay_inputs(data["inputs"])
	s._expected = PackedStringArray()
	if s._diverged > 0:
		last_error = "turn %d did not reproduce its recorded hash" % s._diverged
		return null
	if s.turn_hashes.size() != (data["hashes"] as PackedStringArray).size() or s.state_hash_hex() != data["hash"]:
		last_error = "inputs did not reproduce the saved state"
		return null
	return s


## Re-applies logged inputs in order.
func replay_inputs(inputs: Array) -> void:
	var was := locked
	locked = false
	_replay(inputs)
	locked = was


func _replay(inputs: Array) -> void:
	for i: Dictionary in inputs:
		var p: Variant = i["payload"]
		match i["kind"]:
			"route":
				set_route(i["player"], p["commander"], p["plots"])
			"activity":
				set_activity(i["player"], p["commander"], p["activity"], p.get("option", ""))
			"answer":
				answer_offer(i["player"], p["feature"], p["choice"])
			"drop":
				set_drop_off(i["player"], p["commander"], p["step"], p["plot"])
			"output":
				set_output(i["player"], p["feature"], p["option"])
			"supply":
				set_supply_line(i["player"], p["feature"], p["plot"], p["commander"])
			"rally":
				rally(i["player"], p["detachment"], p["plot"], p["commander"])
			"convoy_route":
				set_convoy_route(i["player"], p["detachment"], p["plots"])
			"equip":
				equip(i["player"], p["commander"], p["item"], p["squad"], p["count"])
			"unequip":
				unequip(i["player"], p["commander"], p["item"], p["count"])
			"give":
				give_item(i["player"], p["from"], p["item"], p["count"], p["to"])
			"take":
				take_items(i["player"], p["commander"], p["detachment"])
			"transfer":
				transfer_squad(i["player"], p["squad"], p["to"])
			"battleforce":
				set_battleforce(i["player"], p["commander"], p["preset"], p["squads"], p["lead"])
			"battle_orders":
				submit_battle_orders(i["player"], p["engagement"], p["orders"])
			"reinforce":
				reinforce(i["player"], p["commander"], p["squad"])
			"leave":
				leave_battle(i["player"], p["commander"])
			"reaction":
				submit_reaction(i["player"], p["engagement"], p["squad"], p["reaction"], p["trigger"])
			"preset":
				save_preset(i["player"], p["name"], p["prefer"], p["avoid"])
			"ready":
				ready(i["player"])
			"advance":
				advance(p)


func _log(player: int, kind: String, payload: Variant) -> void:
	input_log.append({"turn": state.turn + 1, "phase": clock.phase, "player": player, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else payload})


static func _decode(bytes: PackedByteArray) -> Variant:
	var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return null
	return bytes_to_var(raw)


static func _config_dict(c: ClockConfig) -> Dictionary:
	return BattleSession._config_dict(c)


static func _config_from(d: Dictionary) -> ClockConfig:
	return BattleSession._config_from(d)
