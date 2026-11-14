class_name ProfileController
extends RefCounted
## A controller profile (GDD 05 §5.4, R7Q15, A2Q5): one genome that plays
## both layers. It composes an overworld decision process and a battle
## decision process, a mask (what the processes think they are scored on,
## A1Q3, A2Q8), deterministic fuzz (A1Q4) and a think-time limit (B1Q11).
## Works as a HeadlessDuel and a HeadlessOverworld controller.
##
## A profile is plain data, a `controller_profile` template's values or a
## factory genome:
##   {"overworld": {"process", "params"}, "battle": {"process", "params"},
##    "mask": criterion -> {"base", "gates"} (default: the default fitness
##      spec's shaping), "hold_turns" (3), "fuzz" (0-100, % of the best
##      score), "fuzz_seed", "think_ms" (2000)}
## Processes: overworld utility (default), expand, scripted, idle; battle
## utility (default), zone, evacuation, scripted, idle. A missing section
## gets its default, so every profile plays both layers. A scripted
## section's params may name a "then" section that takes over after its
## last step (a scripted opening handing over, R7Q15).
##
## Faults (A2Q1): a decision that takes longer than think_ms, or that
## doesn't return a list (a script error), sets `fault` and `fault_turn`;
## the profile then does nothing more. The harness scores a fault as a
## forfeit. Think time is wall-clock, so it only decides runaway profiles.

const DEFAULT_SPEC := "res://data/sim/fitness/default.json"
const DEFAULT_THINK_MS := 2000

var player: int
var profile: Dictionary
var think_ms := DEFAULT_THINK_MS
var fault := ""
var fault_turn := -1
var max_think_us := 0
var _overworld: Object
var _battle_section: Dictionary = {}
var _battles: Dictionary = {}  # engagement (0 = a standalone battle) -> process
var _rules: BattleRules
var _fuzz := 0.0
var _rng: SimRng
var _mask_spec: Dictionary = {}
var _hold := 3
var _leaders: Dictionary = {}  # overworld squad ID of each own commander's own squad

static var _default_mask: Dictionary = {}


## seed_value varies the fuzz per match (the run's seed).
func _init(player_id: int, profile_in: Dictionary = {}, seed_value: int = 0) -> void:
	player = player_id
	profile = profile_in
	think_ms = int(profile.get("think_ms", DEFAULT_THINK_MS))
	_fuzz = clampf(float(profile.get("fuzz", 0)) / 100.0, 0.0, 1.0)
	_rng = SimRng.new(hash([int(profile.get("fuzz_seed", 0)), seed_value, player_id]))
	_mask_spec = profile.get("mask", default_mask())
	_hold = int(profile.get("hold_turns", 3))
	_overworld = _make_overworld(profile.get("overworld", {}))
	_battle_section = profile.get("battle", {})


func _make_overworld(section: Dictionary) -> Object:
	var params: Dictionary = section.get("params", {})
	match String(section.get("process", "utility")):
		"expand":
			return ExpandController.new(player)
		"scripted":
			var sp := ScriptedProcess.new(player, params)
			if params.has("then"):
				sp.then = _make_overworld(params["then"])
			return sp
		"idle":
			return SimVariant.IdleController.new(player)
	return UtilityOverworld.new(player, SimCriteria.Mask.new(_mask_spec, _hold), params, _fuzz, _rng)


func _make_battle(section: Dictionary) -> Object:
	var params: Dictionary = section.get("params", {})
	match String(section.get("process", "utility")):
		"zone":
			return ZoneController.new(player, params)
		"evacuation":
			return EvacuationController.new(player)
		"scripted":
			var sp := ScriptedProcess.new(player, params)
			if params.has("then"):
				sp.then = _make_battle(params["then"])
			return sp
		"idle":
			return SimVariant.IdleController.new(player)
	return UtilityBattle.new(player, SimCriteria.Mask.new(_mask_spec, _hold), params, _fuzz, _rng)


## The default fitness spec's shaping: the criteria a profile sees when its
## mask isn't set.
static func default_mask() -> Dictionary:
	if _default_mask.is_empty():
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(DEFAULT_SPEC)) == OK and typeof(j.data) == TYPE_DICTIONARY:
			_default_mask = j.data.get("shaping", {})
	return _default_mask


## Battle rules are public data; utility battles value squads with them.
func set_battle_rules(rules: BattleRules) -> void:
	_rules = rules


## The battle process of a standalone battle (engagement 0); for tests.
func battle_process() -> Object:
	return _battle(0)


## The overworld process; for tests.
func overworld_process() -> Object:
	return _overworld


func _battle(key: int) -> Object:
	if not _battles.has(key):
		_battles[key] = _make_battle(_battle_section)
	var proc: Object = _battles[key]
	var ub := _utility(proc)
	if ub != null:
		ub.rules = _rules
	return proc


## The utility battle process inside proc (itself, or a scripted opening's
## successor), if any.
static func _utility(proc: Object) -> UtilityBattle:
	while proc is ScriptedProcess:
		proc = (proc as ScriptedProcess).then
	return proc as UtilityBattle


func plan(obs: Dictionary, session: OverworldSession) -> Array:
	_leaders = {}
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) == player:
			for q: Dictionary in c.get("army", []):
				if bool(q.get("own", false)):
					_leaders[int(q["id"])] = true
	return _timed(func() -> Variant: return _overworld.plan(obs, session), int(obs.get("turn", 0)))


func battle_orders(obs: Dictionary) -> Array:
	var proc := _battle(int(obs.get("engagement", 0)))
	var ub := _utility(proc)
	if ub != null:
		var links: Dictionary = obs.get("links", {})
		var leaders := {}
		for bid: int in links:
			if _leaders.has(int(links[bid])):
				leaders[bid] = true
		ub.leaders = leaders
	return _timed(func() -> Variant: return proc.orders(obs), int(obs.get("turn", 0)))


func orders(obs: Dictionary) -> Array:
	return battle_orders(obs)


func reactions(opportunities: Array) -> Array:
	if not fault.is_empty():
		return []
	var proc := _battle(0)
	return proc.reactions(opportunities) if proc.has_method("reactions") else []


func _timed(decide: Callable, turn: int) -> Array:
	if not fault.is_empty():
		return []
	var t0 := Time.get_ticks_usec()
	var out: Variant = decide.call()
	var us := Time.get_ticks_usec() - t0
	max_think_us = maxi(max_think_us, us)
	if typeof(out) != TYPE_ARRAY:
		_fail("crash", turn)
		return []
	if us > think_ms * 1000:
		_fail("think_time", turn)
		return []
	return out


func _fail(why: String, turn: int) -> void:
	fault = why
	fault_turn = turn


## A profile that crashed or overran its think time forfeits (A2Q1).
## Returns whether any did; the report lists faults and the slowest
## decision per player (think_ms.max).
static func record_faults(controllers: Dictionary, m: SimMetrics, report: Dictionary) -> bool:
	var any := false
	var think := {}
	for p: int in controllers:
		var c: Object = controllers[p]
		if not c is ProfileController:
			continue
		var pc := c as ProfileController
		think[str(p)] = pc.max_think_us / 1000.0
		if not pc.fault.is_empty():
			any = true
			m.forfeit(p, pc.fault_turn)  # the first forfeit counts
			report["fault"] = "%d:%s" % [p, pc.fault]
	report["think_ms_max"] = think
	return any
