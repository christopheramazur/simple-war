class_name BattleSession
extends RefCounted
## The Game API for one battle: the single interface used by the human UI, AI
## controllers, the network layer, tests and the AI factory (R7Q14).
##
## Inputs:   submit_orders, ready, submit_reaction, advance(ms).
## Outputs:  observe(player) - visibility-filtered state and events;
##           inspect(player, squad) - inspection window data (stats with
##           traces, effects, abilities);
##           bus.published  - presentation feed (read-only).
## Clock:    advance(ms) drives timers; Execute is never timed and runs at
##           full speed headless (`execute_turn` is synchronous).
## Records:  every input is logged with the turn and phase it arrived in, so
##           initial snapshot + input log rebuilds any later state (R8Q5).

const SAVE_VERSION: int = 1

## Why the last load_save / rebuild returned null (empty on success).
static var last_error: String = ""

var scenario_id: String
var seed_value: int
var data_hash: String
var rules: BattleRules
var state: BattleState
var sim: BattleSim
var clock: PulseClock
var bus: PulseBus
## [{"turn", "phase", "player", "kind", "payload"}]
var input_log: Array = []
var initial_snapshot: Dictionary = {}

var _orders: Dictionary = {}
var _opportunities: Array = []
var _execute_pending: bool = false
var _replaying: bool = false


## Creates a session at turn 1, Planning. Returns null if the data is invalid.
static func create(templates: TemplateTable, hash_hex: String, scenario: String, seed_in: int, clock_config: ClockConfig = null) -> BattleSession:
	var r := BattleRules.compile(templates, scenario, hash_hex)
	if not r.is_valid():
		push_error("BattleSession: %s" % "; ".join(r.errors))
		return null
	var s := BattleSession.new()
	s._setup(r, scenario, seed_in, hash_hex, clock_config)
	s.clock.start()
	s._pump()
	return s


func _setup(r: BattleRules, scenario: String, seed_in: int, hash_hex: String, clock_config: ClockConfig) -> void:
	rules = r
	scenario_id = scenario
	seed_value = seed_in
	data_hash = hash_hex
	sim = BattleSim.new()
	state = BattleSetup.create(1, rules, seed_in)
	bus = PulseBus.new()
	bus.register_context(state)
	TransferSystem.new().attach(bus)
	clock = PulseClock.new(clock_config if clock_config != null else ClockConfig.new())
	for p in state.players:
		clock.add_player(p)
		clock.set_battles(p, 1)
	clock.phase_changed.connect(_on_phase)
	clock.pulse_point.connect(_on_pulse)
	VisionSystem.new().run(state)
	state.turn_log.append_array(state.events.drain())
	initial_snapshot = state.snapshot()


func players() -> PackedInt64Array:
	return state.players.duplicate()


func is_over() -> bool:
	return state.is_over()


func phase_name() -> String:
	return PulseClock.Phase.keys()[clock.phase]


# --- inputs ----------------------------------------------------------------

## Replaces the player's orders for this turn (Planning only). Returns errors;
## valid orders are kept even if others in the list were rejected.
func submit_orders(player: int, orders: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if clock.phase != PulseClock.Phase.PLANNING or is_over():
		errors.append("orders are only accepted during planning")
		return errors
	if not state.players.has(player):
		errors.append("unknown player")
		return errors
	var kept := []
	for i in orders.size():
		var err := BattleOrders.validate(state, player, orders[i])
		if err.is_empty():
			kept.append((orders[i] as Dictionary).duplicate(true))
		else:
			errors.append("order %d: %s" % [i, err])
	_orders[player] = kept
	_log(player, "orders", kept)
	return errors


func ready(player: int) -> void:
	if not state.players.has(player) or is_over():
		return
	_log(player, "ready", null)
	clock.mark_ready(player)
	_pump()


## Feeds elapsed time (ms). Headless drivers may skip it entirely and rely on
## `ready`; timers then never expire.
func advance(ms: int) -> void:
	if ms <= 0 or is_over():
		return
	_log(0, "advance", ms)
	clock.advance(ms)
	_pump()


## Reaction opportunities for the player during the reaction window.
func reaction_opportunities(player: int) -> Array:
	if clock.phase != PulseClock.Phase.REACTION:
		return []
	return _opportunities.filter(func(o: Dictionary) -> bool: return o["player"] == player)


func submit_reaction(player: int, squad: int, reaction: String, trigger: int) -> String:
	if clock.phase != PulseClock.Phase.REACTION:
		return "reactions are only accepted in the reaction window"
	var ok := false
	for o: Dictionary in _opportunities:
		if o["player"] == player and o["squad"] == squad and o["trigger"] == trigger and reaction in o["reactions"]:
			ok = true
			break
	if not ok:
		return "no such reaction opportunity"
	var err := Reactions.queue(state, squad, reaction, trigger)
	if err.is_empty():
		_log(player, "reaction", {"squad": squad, "reaction": reaction, "trigger": trigger})
	return err


# --- clock hooks -----------------------------------------------------------

func _on_phase(phase: PulseClock.Phase, _turn: int) -> void:
	match phase:
		PulseClock.Phase.REVEAL:
			for p in state.players:
				BattleOrders.apply(state, p, _orders.get(p, []))
			_orders.clear()
		PulseClock.Phase.REACTION:
			_opportunities = Reactions.forecast(state, sim)
		PulseClock.Phase.EXECUTE:
			_execute_pending = true


func _on_pulse(point: StringName, _turn: int) -> void:
	bus.flush(point)


## Runs work the clock asked for, outside the clock's own call stack.
func _pump() -> void:
	while _execute_pending:
		_execute_pending = false
		_opportunities = []
		sim.execute_turn(state)
		clock.execute_finished()


# --- observation -----------------------------------------------------------

## What `player` may know: own squads in full, enemy squads only while seen,
## public scores and zones, and this turn's events that involve what they see.
func observe(player: int) -> Dictionary:
	var d := observe_state(state, player)
	d["phase"] = phase_name()
	d["remaining_ms"] = clock.remaining_ms(player)
	d["reserve_ms"] = clock.reserve_ms(player)
	return d


## The clock-free part of observe, for any battle state (also battles run by
## the overworld session on the shared pulse).
static func observe_state(state: BattleState, player: int) -> Dictionary:
	var rules := state.rules
	var sq := state.squads
	var u := state.units
	var me := BattleSquads.bit(player)
	var squads := []
	var visible := {}
	for row in sq.count():
		var sid := sq.id_at(row)
		var own := sq.player[row] == player
		if not own and (sq.seen_by[row] & me == 0 or not sq.is_active(row)):
			continue
		visible[sid] = true
		var d := {
			"id": sid, "player": sq.player[row], "template": rules.squad_ids[sq.tmpl[row]],
			"x": sq.cx[row], "y": sq.cy[row], "alive": sq.alive[row],
			"destroyed": sq.destroyed[row] == 1, "withdrawn": sq.withdrawn[row] == 1,
		}
		if own:
			d["order"] = BattleOrders.TYPES.find_key(sq.order[row])
			d["engaged"] = sq.engaged[row]
			d["hp_lost"] = sq.hp_lost[row]
			d["hp_max"] = sq.hp_max[row]
			d["abilities"] = Abilities.view(state, sid)
			var pools := {}
			for p in 5:
				pools[DataSchema.SIMPL[p]] = {
					"value": Pools.value(state, row, p), "capacity": Pools.capacity(state, row, p),
					"band": DataSchema.BANDS[Pools.band(state, row, p)],
				}
			d["pools"] = pools
		squads.append(d)
	var units := []
	for row in u.count():
		if not visible.has(u.squad[row]):
			continue
		units.append({"id": u.id_at(row), "squad": u.squad[row], "x": u.x[row], "y": u.y[row], "hp": u.hp[row]})
	var zones := []
	for z in rules.zone_ids.size():
		zones.append({"id": rules.zone_ids[z], "x": rules.zn_x[z], "y": rules.zn_y[z], "radius": rules.zn_radius[z],
			"owner": state.zone_owner[z], "amount": state.zone_amount[z], "threshold": rules.zn_threshold[z]})
	var scores := {}
	for p in state.players:
		scores[p] = {"influence": state.influence[p], "value": state.value_score[p]}
	var events := []
	for e in state.turn_log:
		if _event_visible(e, player, visible):
			events.append(e.to_dict())
	return {
		"player": player, "turn": state.turn + 1,
		"width": rules.width, "height": rules.height,
		"squads": squads, "units": units, "zones": zones, "scores": scores, "events": events,
		"result": state.result.duplicate(true),
	}


## The inspection window's data for one squad (Inspection), in any phase.
## Visible means inspectable (E2Q12): own squads always, enemy squads only
## while `player` sees them; {} otherwise. Enemy pools and abilities stay
## hidden, and their deception-tagged effects show their disguise.
func inspect(player: int, squad_id: int) -> Dictionary:
	var row := state.squads.row_of(squad_id)
	if row < 0:
		return {}
	var own := state.squads.player[row] == player
	if not own and (state.squads.seen_by[row] & BattleSquads.bit(player) == 0 or not state.squads.is_active(row)):
		return {}
	return Inspection.squad(state, squad_id, player)


static func _event_visible(e: SimEvent, player: int, visible: Dictionary) -> bool:
	var d := e.data
	if d.has("player") and not d.has("squad"):
		return true
	if e.type in [&"squad_revealed", &"squad_hidden"]:
		return d["player"] == player
	for key in ["squad", "target", "by", "trigger"]:
		if d.has(key) and visible.has(d[key]):
			return true
	return false


# --- persistence (R8Q5) ---------------------------------------------------

## A save: snapshot at a pulse boundary + the full input log + data identity.
func save() -> PackedByteArray:
	assert(clock.phase != PulseClock.Phase.EXECUTE, "BattleSession.save: not during execute")
	var data := {
		"version": SAVE_VERSION, "scenario": scenario_id, "seed": seed_value, "data_hash": data_hash,
		"clock_config": _config_dict(clock.config), "initial": initial_snapshot, "inputs": input_log.duplicate(true),
		"state": state.snapshot(), "clock": clock.snapshot(), "orders": _orders.duplicate(true),
		"opportunities": _opportunities.duplicate(true), "hash": state.state_hash().hex_encode(),
	}
	return var_to_bytes(data).compress(FileAccess.COMPRESSION_GZIP)


## Loads a save. Fails (null) if the data hash differs from the save's.
static func load_save(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> BattleSession:
	last_error = ""
	var data: Variant = _decode(bytes)
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != SAVE_VERSION:
		last_error = "unreadable save"
		return null
	if data["data_hash"] != hash_hex:
		last_error = "content differs from the save's (different mods or version)"
		return null
	var r := BattleRules.compile(templates, data["scenario"], hash_hex)
	var s := BattleSession.new()
	s._setup(r, data["scenario"], data["seed"], hash_hex, _config_from(data["clock_config"]))
	s.initial_snapshot = data["initial"]
	s.state.restore(data["state"])
	Centroids.update(s.state)
	s.clock.restore(data["clock"])
	s._orders = data["orders"]
	s._opportunities = data["opportunities"]
	s.input_log = data["inputs"]
	return s


## Rebuilds the save's state by re-simulating its input log from the start,
## without trusting its snapshot (e.g. a damaged save). Returns null if the
## inputs no longer reproduce the recorded hash.
static func rebuild(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> BattleSession:
	last_error = ""
	var data: Variant = _decode(bytes)
	if typeof(data) != TYPE_DICTIONARY or data.get("data_hash") != hash_hex:
		last_error = "unreadable save or different content"
		return null
	var s := create(templates, hash_hex, data["scenario"], data["seed"], _config_from(data["clock_config"]))
	s.replay_inputs(data["inputs"])
	if s.state.state_hash().hex_encode() != data["hash"]:
		last_error = "inputs did not reproduce the saved state"
		return null
	return s


## Re-applies logged inputs in order (replays and rebuilds).
func replay_inputs(inputs: Array) -> void:
	_replaying = true
	for i: Dictionary in inputs:
		match i["kind"]:
			"orders":
				submit_orders(i["player"], i["payload"])
			"ready":
				ready(i["player"])
			"advance":
				advance(i["payload"])
			"reaction":
				var p: Dictionary = i["payload"]
				submit_reaction(i["player"], p["squad"], p["reaction"], p["trigger"])
	_replaying = false


func _log(player: int, kind: String, payload: Variant) -> void:
	input_log.append({"turn": state.turn + 1, "phase": clock.phase, "player": player, "kind": kind,
		"payload": payload.duplicate(true) if payload is Array or payload is Dictionary else payload})


static func _decode(bytes: PackedByteArray) -> Variant:
	var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return null
	return bytes_to_var(raw)


static func _config_dict(c: ClockConfig) -> Dictionary:
	var out := {}
	for p: Dictionary in c.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[p["name"]] = c.get(p["name"])
	return out


static func _config_from(d: Dictionary) -> ClockConfig:
	var c := ClockConfig.new()
	for k: String in d:
		c.set(k, d[k])
	return c
