class_name OverworldSession
extends RefCounted
## The Game API for the overworld (GDD 04 §4.4, R7Q14): the one interface
## the human UI, AI controllers, the network layer, tests and the AI factory
## use. Mirrors BattleSession.
##
## Inputs:   set_route, set_activity, transfer_squad, set_battleforce
##           (Planning only), save_preset, ready, advance(ms).
## Queries:  observe(player) - fog-filtered state plus last turn's visible
##           events (OverworldVision); path(player, commander, to) - the
##           cheapest affordable route as the player knows the map.
## Clock:    the shared PulseClock (R2Q3). The overworld has no reaction
##           window; Execute resolves one overworld turn synchronously.
## Records:  every input is logged with its turn and phase, and the state
##           hash after every resolved turn is kept, so a replay (initial
##           state + inputs) is checked turn by turn (R8Q5, R6Q20).

const SAVE_VERSION: int = 1

## Why the last load_save / rebuild returned null (empty on success).
static var last_error: String = ""

var map_id: String
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

var _players: PackedInt64Array = PackedInt64Array()
var _execute_pending: bool = false
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
	s._setup(r, map, seed_in, hash_hex, clock_config)
	s.clock.start()
	return s


func _setup(r: OverworldRules, map: String, seed_in: int, hash_hex: String, clock_config: ClockConfig) -> void:
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
	cfg.reaction_enabled = false
	clock = PulseClock.new(cfg)
	for p in _players:
		clock.add_player(p)
		clock.set_battles(p, 0)
	clock.phase_changed.connect(_on_phase)
	clock.pulse_point.connect(_on_pulse)


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


## Moves a squad between two of the player's commanders on one hex (R7Q9).
func transfer_squad(player: int, squad_id: int, to_commander: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.transfer_squad(state, player, squad_id, to_commander)
	if err.is_empty():
		_log(player, "transfer", {"squad": squad_id, "to": to_commander})
	return err


func ready(player: int) -> void:
	if not _players.has(player):
		return
	_log(player, "ready", null)
	clock.mark_ready(player)
	_pump()


## Feeds elapsed time (ms). Headless drivers may skip it and rely on ready.
func advance(ms: int) -> void:
	if ms <= 0:
		return
	_log(0, "advance", ms)
	clock.advance(ms)
	_pump()


func _planning(player: int) -> String:
	if clock.phase != PulseClock.Phase.PLANNING:
		return "orders are only accepted during planning"
	if not _players.has(player):
		return "unknown player"
	return ""


# --- clock -----------------------------------------------------------------

func _on_pulse(point: StringName, _turn: int) -> void:
	bus.flush(point)


func _on_phase(phase: PulseClock.Phase, _turn: int) -> void:
	if phase == PulseClock.Phase.EXECUTE:
		_execute_pending = true


## Runs work the clock asked for, outside the clock's own call stack.
func _pump() -> void:
	while _execute_pending:
		_execute_pending = false
		last_events = OverworldTurn.resolve(state)
		var h := state.state_hash_hex()
		var i := turn_hashes.size()
		turn_hashes.append(h)
		if _diverged < 0 and i < _expected.size() and _expected[i] != h:
			_diverged = i + 1
		clock.execute_finished()


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
	return o


## The cheapest route for a commander to plot `to`, as the player knows the
## map, cut to what it can afford this turn. Empty if none.
func path(player: int, commander_id: int, to: int) -> PackedInt64Array:
	var row := state.commanders.row_of(commander_id)
	if row < 0 or state.commanders.player[row] != player:
		return PackedInt64Array()
	var full := OverworldPath.find(state, state.commanders.plot[row], to, player)
	var costs := OverworldVision.known_costs(state, player)
	var budget := Commanders.budget(state, row)
	var out := PackedInt64Array()
	var spent := 0
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
		"clock_config": _config_dict(clock.config), "inputs": input_log.duplicate(true),
		"hashes": turn_hashes.duplicate(), "state": state.snapshot(), "clock": clock.snapshot(),
		"last_events": events, "hash": state.state_hash_hex(),
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
	s._setup(r, data["map"], data["seed"], hash_hex, _config_from(data["clock_config"]))
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
	if s.state.state_hash_hex() != data["hash"]:
		last_error = "the saved state does not match its hash"
		return null
	return s


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
	if s.turn_hashes.size() != (data["hashes"] as PackedStringArray).size() or s.state.state_hash_hex() != data["hash"]:
		last_error = "inputs did not reproduce the saved state"
		return null
	return s


## Re-applies logged inputs in order.
func replay_inputs(inputs: Array) -> void:
	for i: Dictionary in inputs:
		var p: Variant = i["payload"]
		match i["kind"]:
			"route":
				set_route(i["player"], p["commander"], p["plots"])
			"activity":
				set_activity(i["player"], p["commander"], p["activity"], p.get("option", ""))
			"transfer":
				transfer_squad(i["player"], p["squad"], p["to"])
			"battleforce":
				set_battleforce(i["player"], p["commander"], p["preset"], p["squads"], p["lead"])
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
