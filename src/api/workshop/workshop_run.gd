class_name WorkshopRun
extends RefCounted
## Runs one variant of a WorkshopScenario headless (sw-tho3.3, U1 B3, GDD 05
## §5.7) and records it: a per-tick frame in playback format (ReplayRecorder),
## a BattleProbe snapshot every `probe_stride` ticks (and wherever an `at`
## probe looks), the events and shot traces, and the state hash per turn.
##
## The battle is the package's battle scenario `map` with its sides emptied
## (BattleSetup.create), the score target off and the turn limit past the
## run, so only annihilation or withdrawal ends it early. Squads are placed
## with ScenarioBuilder; scripted orders go through BattleOrders.validate,
## the check BattleSession.submit_orders makes, and are applied per player
## at the turn's start as the session's Reveal does. There is no reaction
## window. The sim runs at full speed; the hooks only read.
##
## Same scenario + variant + data = same hash on every machine.

static var _loaders: Dictionary = {}

var scenario: WorkshopScenario
var variant: String = WorkshopScenario.BASE
var errors: PackedStringArray = PackedStringArray()
var data_hash: String = ""
var rules: BattleRules
var state: BattleState
## Playback frames (frames, events per frame) for viewers.
var recorder: ReplayRecorder
## Per frame: the turn and the tick within it. Frame 0 is the start (turn 0);
## tick -1 is "after the turn resolved".
var frame_turn: PackedInt64Array = PackedInt64Array()
var frame_tick: PackedInt64Array = PackedInt64Array()
## Per frame: the absolute sim tick just finished (-1 for non-tick frames).
var frame_abs: PackedInt64Array = PackedInt64Array()
## frame -> BattleProbe.snapshot (viewer 0).
var snapshots: Dictionary = {}
## Events per frame (SimEvent dicts), as the turn log grew.
var events: Array[Array] = []
## squad key -> squad ID; unit ID -> squad key.
var sids: Dictionary = {}
var unit_key: Dictionary = {}
## squad key -> per frame armed living units and how many fired that tick.
var duty_armed: Dictionary = {}
var duty_fired: Dictionary = {}
var turn_hashes: PackedStringArray = PackedStringArray()
var final_hash: String = ""
## Turns actually run (fewer when the battle ended early).
var turns_run: int = 0
## When set before play, every frame also gets a WorkshopDebug frame
## (frame -> Dictionary of plain data) for the debug overlay.
var debug: bool = false
var debug_frames: Dictionary = {}
## The debug capture's own route planner (the battle's cache is untouched).
var _debug_routes: BattleRoute

var _turn: int = 0
var _k: int = 0
var _seen: int = 0
var _last_tick: int = -1
var _want: Dictionary = {}
## Vector2i(turn, tick) -> orders given after that many ticks of the turn.
var _timed: Dictionary = {}


## The package's loader, cached per process (content is read-only).
static func loader_for(package: String) -> PackageLoader:
	if not _loaders.has(package):
		_loaders[package] = PackageLoader.load_dirs(PackedStringArray([WorkshopScenario.PACKAGES[package]]))
	return _loaders[package]


## Builds the battle and, when `play`, runs it (false: placed, not run).
## `with_debug` records a WorkshopDebug frame per frame (debug_frames).
static func execute(sc: WorkshopScenario, variant_name: String = WorkshopScenario.BASE, play: bool = true,
		with_debug: bool = false) -> WorkshopRun:
	var run := WorkshopRun.new()
	run.scenario = sc
	run.variant = variant_name
	run.debug = with_debug
	if not sc.is_valid():
		run.errors.append_array(sc.errors)
		return run
	var setup := sc.resolved(variant_name)
	if setup.is_empty():
		run.errors.append("%s: no variant '%s' (%s)" % [sc.path, variant_name, ", ".join(sc.variant_names())])
		return run
	if run._build(setup["squads"]) and play:
		run._play(setup["script"])
	return run


func is_ok() -> bool:
	return errors.is_empty()


func _err(msg: String) -> void:
	errors.append("%s [%s]: %s" % [scenario.path, variant, msg])


func _build(squads: Array) -> bool:
	var loader := loader_for(scenario.package)
	if not loader.is_valid():
		_err("package '%s': %s" % [scenario.package, "; ".join(loader.errors)])
		return false
	data_hash = loader.data_hash
	if not loader.templates.has(scenario.map) or loader.templates.kind_of(scenario.map) != "scenario":
		_err("map: '%s' is not a battle scenario in package '%s'" % [scenario.map, scenario.package])
		return false
	rules = BattleRules.compile(loader.templates, scenario.map, data_hash)
	if not rules.is_valid():
		_err("map '%s': %s" % [scenario.map, "; ".join(rules.errors)])
		return false
	rules.score_target = 0
	rules.turn_limit = scenario.turns + 1
	for side: Dictionary in rules.sides:
		side["squads"] = PackedInt64Array()
		side.erase("alive")
		side.erase("gear")
	if scenario.open:
		var ground := rules.feature_ids.find("open")
		if ground < 0:
			_err("open: package '%s' has no 'open' feature" % scenario.package)
			return false
		rules.terrain.fill(ground)
		rules.facing.fill(0)
	state = BattleSetup.create(1, rules, scenario.seed_value)
	for i in squads.size():
		var d: Dictionary = squads[i]
		var f := "squads[%d] (%s)" % [i, d["key"]]
		if not state.players.has(d["player"]):
			_err("%s.player: %d is not a side of '%s' (%s)" % [f, d["player"], scenario.map, state.players])
			return false
		var sid := ScenarioBuilder.place(state, d["player"], d["squad"], d["x"], d["y"], d["facing"])
		if sid < 0:
			_err("%s.squad: no squad template '%s' in package '%s'" % [f, d["squad"], scenario.package])
			return false
		sids[d["key"]] = sid
		var dummy: Dictionary = d["dummy"]
		if not dummy["armed"]:
			ScenarioBuilder.disarm(state, sid)
		if dummy["hp"] > 0:
			ScenarioBuilder.set_hp(state, sid, dummy["hp"])
		_patch(sid, d["patch"])
		for urow in Centroids.units_of(state, state.squads.row_of(sid)):
			unit_key[state.units.id_at(urow)] = d["key"]
		duty_armed[d["key"]] = PackedInt64Array()
		duty_fired[d["key"]] = PackedInt64Array()
	Centroids.update(state)
	VisionSystem.new().run(state)
	state.turn_log.append_array(state.events.drain())
	state.trace_shots = true
	return true


## Patch stats: hp (every unit, and its maximum), ammo (every armed unit),
## pools (raises the cap when the value is above it).
func _patch(sid: int, patch: Dictionary) -> void:
	var row := state.squads.row_of(sid)
	for k: String in patch:
		var v: int = patch[k]
		match k:
			"hp":
				ScenarioBuilder.set_hp(state, sid, v)
			"ammo":
				for urow in Centroids.units_of(state, row):
					if state.units.weapon[urow] >= 0:
						state.units.set_value(state.units.id_at(urow), &"ammo", v)
			_:
				var p := ["stamina", "instinct", "morale", "prowess", "legend"].find(k)
				state.squads.set_value(sid, BattleSquads.POOLS[p], v)
				if v > state.squads.get_value(sid, BattleSquads.CAPS[p]):
					state.squads.set_value(sid, BattleSquads.CAPS[p], v)


func _play(script: Dictionary) -> void:
	for p: Dictionary in scenario.probes:
		if p.has("at") and p["at"]["tick"] >= 0:
			_want["%d:%d" % [p["at"]["turn"], p["at"]["tick"]]] = true
	_timed = {}
	for k: Variant in script:
		if typeof(k) != TYPE_VECTOR2I:
			continue
		if (k as Vector2i).y >= rules.ticks_per_turn:
			_err("script %d@%d: turn %d has %d ticks" % [k.x, k.y, k.x, rules.ticks_per_turn])
			return
		_timed[k] = script[k]
	recorder = ReplayRecorder.new()
	recorder.rules = rules
	recorder.players = state.players.duplicate()
	_frame(state, 0, -1, -1)
	snapshots[0] = BattleProbe.snapshot(state, 0)
	var sim := BattleSim.new()
	sim.tick_hook = _on_tick
	for t in range(1, scenario.turns + 1):
		if state.is_over():
			break
		if not _orders("script turn %d" % t, script.get(t, [])):
			return
		_turn = t
		_k = 0
		_seen = 0
		sim.execute_turn(state)
		turns_run = t
		turn_hashes.append(state.state_hash_hex())
	final_hash = state.state_hash_hex()


## Validates a batch of orders as BattleSession.submit_orders does, then
## applies them per player in player order, as its Reveal does. `label`
## names the batch in errors. An order with `unchecked` (cross-check only)
## is validated as if its squad saw the target: 01's table B runs set orders
## without the sight check, and this is how the workshop reproduces them.
func _orders(label: String, list: Array) -> bool:
	var by_player := {}
	for i in list.size():
		var o: Dictionary = (list[i] as Dictionary).duplicate(true)
		o["squad"] = sids[o["squad"]]
		if o.has("target"):
			o["target"] = sids[o["target"]]
		var player := state.squads.player[state.squads.row_of(o["squad"])]
		if o.get("unchecked", false) and o.has("target"):
			_grant_sight(o["target"], player)
		o.erase("unchecked")
		var err := BattleOrders.validate(state, player, o)
		if not err.is_empty():
			_err("%s, order %d (%s): %s" % [label, i, list[i]["squad"], err])
			return false
		if not by_player.has(player):
			by_player[player] = []
		by_player[player].append(o)
	for p in state.players:
		if by_player.has(p):
			BattleOrders.apply(state, p, by_player[p])
	return true


## Marks `target` as seen by `player` for the order check (cross-check only).
## Vision runs again on the next tick, so this is not carried into the sim.
func _grant_sight(target: int, player: int) -> void:
	var sq := state.squads
	var row := sq.row_of(target)
	var col: PackedInt64Array = sq.take_column(&"seen_by")
	col[row] |= BattleSquads.bit(player)
	sq.put_column(&"seen_by", col)


func _on_tick(st: BattleState) -> void:
	if st.tick != _last_tick:
		var f := _frame(st, _turn, _k, st.tick - 1)
		if _k % scenario.probe_stride == 0 or _want.has("%d:%d" % [_turn, _k]):
			snapshots[f] = BattleProbe.snapshot(st, 0)
		_k += 1
		# Mid-turn orders: given once _k ticks of this turn have run.
		var due := Vector2i(_turn, _k)
		if _timed.has(due):
			_orders("script turn %d@%d" % [_turn, _k], _timed[due])
	else:
		var f := _frame(st, _turn, -1, -1)
		snapshots[f] = BattleProbe.snapshot(st, 0)


func _frame(st: BattleState, turn: int, tick: int, abs_tick: int) -> int:
	_last_tick = st.tick
	recorder.capture(st)
	var f := frame_turn.size()
	if debug:
		if _debug_routes == null:
			_debug_routes = BattleRoute.new()
		debug_frames[f] = WorkshopDebug.capture(st, _debug_routes)
	frame_turn.append(turn)
	frame_tick.append(tick)
	frame_abs.append(abs_tick)
	var evs: Array = []
	for i in range(_seen, st.turn_log.size()):
		evs.append(st.turn_log[i].to_dict())
	_seen = st.turn_log.size()
	events.append(evs)
	# Duty: armed living units, and those that fired on the tick just run.
	var armed := {}
	var fired := {}
	var u := st.units
	for row in u.count():
		var key: Variant = unit_key.get(u.id_at(row))
		if key == null or u.weapon[row] < 0 or u.hp[row] <= 0:
			continue
		armed[key] = int(armed.get(key, 0)) + 1
		if abs_tick >= 0 and u.fired_tick[row] == abs_tick:
			fired[key] = int(fired.get(key, 0)) + 1
	for key: String in duty_armed:
		# Packed arrays come out of a Dictionary as copies: put them back.
		var a: PackedInt64Array = duty_armed[key]
		var b: PackedInt64Array = duty_fired[key]
		a.append(int(armed.get(key, 0)) if abs_tick >= 0 else 0)
		b.append(int(fired.get(key, 0)))
		duty_armed[key] = a
		duty_fired[key] = b
	return f


## The frame at (turn, tick); "end" (turn -1) = the last frame; -1 if the
## run never got there.
func frame_at(turn: int, tick: int) -> int:
	if turn < 0:
		return frame_turn.size() - 1
	for f in frame_turn.size():
		if frame_turn[f] == turn and frame_tick[f] == tick:
			return f
	return -1


## Tick frames inside a window {t0, k0, t1, k1} (inclusive; k1 -1 = to the
## turn's end).
func frames_over(w: Dictionary) -> PackedInt64Array:
	var out := PackedInt64Array()
	for f in frame_turn.size():
		var t := frame_turn[f]
		var k := frame_tick[f]
		if k < 0 or t < w["t0"] or t > w["t1"]:
			continue
		if t == w["t0"] and k < w["k0"]:
			continue
		if t == w["t1"] and w["k1"] >= 0 and k > w["k1"]:
			continue
		out.append(f)
	return out
