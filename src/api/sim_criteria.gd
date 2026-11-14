class_name SimCriteria
extends RefCounted
## The AI factory's criteria library v1, decision side (GDD 05 §5.4, Round
## B1). One library, two uses (B1Q1): the harness scores FITNESS from the
## end-of-game forms (harness/src/hx/fitness.py); a profile's utility process
## weighs the DECISION-time forms here, estimated from what its player
## observes, through its mask. Library: data/sim/criteria.json.
##
## A mask is a set of schedules, criterion -> {"base", "gates": [{"condition",
## "points": [[x, y], ...]}]}: a criterion it leaves out is hidden (weight
## 0). A gate is a piecewise-linear curve over one condition; once it
## changes it holds at least `hold` turns (hysteresis, B1Q6). The same
## format is the fitness spec's "shaping" (data/sim/fitness/*.json), and
## data/sim/fitness/gate_cases.json checks both implementations agree.
##
## Values are in [0, 1] (margin in [-1, 1]). Pure functions of an
## observation and the rules: nothing here reads hidden state.

const LIBRARY := "res://data/sim/criteria.json"
const THREAT_RANGE := 2  # as SimMetrics.THREAT_RANGE
const EPS := 1e-9

static var _library: Dictionary = {}


## The criteria library (cached).
static func library() -> Dictionary:
	if _library.is_empty():
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(LIBRARY)) == OK and typeof(j.data) == TYPE_DICTIONARY:
			_library = j.data
	return _library


## Piecewise-linear over [x, y] points, flat beyond the ends.
static func curve(points: Array, x: float) -> float:
	if x <= float(points[0][0]):
		return float(points[0][1])
	for i in range(1, points.size()):
		var x0 := float(points[i - 1][0])
		var x1 := float(points[i][0])
		if x <= x1:
			var y0 := float(points[i - 1][1])
			return y0 if x1 == x0 else y0 + (float(points[i][1]) - y0) * (x - x0) / (x1 - x0)
	return float(points[points.size() - 1][1])


## Weighted mean of criterion values: what a utility process maximises.
static func utility(values: Dictionary, weights: Dictionary) -> float:
	var total := 0.0
	var sum := 0.0
	for c: String in values:
		var w := float(weights.get(c, 0.0))
		total += w
		sum += w * float(values[c])
	return 0.0 if total <= 0.0 else sum / total


# --- overworld -------------------------------------------------------------

static func _hostile(obs: Dictionary, player: int) -> bool:
	return player > 0 and player != int(obs["player"])


static func _squads_value(rules: OverworldRules, squads: Array) -> float:
	var v := 0.0
	for q: Dictionary in squads:
		v += float(rules.sq_value[int(q["tmpl"])]) * int(q["alive"]) / maxi(int(q["size"]), 1)
	return v


## What a hostile commander is guessed to lead: its template's starting army
## (enemy armies are never shown, R5Q9).
static func _commander_guess(rules: OverworldRules, tmpl: int) -> float:
	var v := 0.0
	if rules.cm_own_squad[tmpl] >= 0:
		v += rules.sq_value[rules.cm_own_squad[tmpl]]
	for sq in rules.cm_army[tmpl]:
		v += rules.sq_value[sq]
	return v


static func _mean_squad(rules: OverworldRules) -> float:
	if rules.sq_value.is_empty():
		return 0.0
	var t := 0
	for v in rules.sq_value:
		t += v
	return float(t) / rules.sq_value.size()


## Own and (guessed) visible hostile force: [own, enemy, hostile forces as
## [plot, value]...].
static func _forces(obs: Dictionary, rules: OverworldRules) -> Array:
	var me := int(obs["player"])
	var own := 0.0
	var enemy := 0.0
	var foes := []
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) == me:
			own += _squads_value(rules, c.get("army", []))
		elif _hostile(obs, int(c["player"])):
			var g := _commander_guess(rules, int(c["tmpl"]))
			enemy += g
			foes.append([int(c["plot"]), g])
	for d: Dictionary in obs["detachments"]:
		if int(d["player"]) == me:
			own += _squads_value(rules, d.get("squads", []))
		elif _hostile(obs, int(d["player"])):
			var g := _mean_squad(rules)
			enemy += g
			foes.append([int(d["plot"]), g])
	return [own, enemy, foes]


static func _share(own: float, total: float, none: float = 0.5) -> float:
	return none if total <= 0.0 else own / total


## Safety and threat of the weakest own commander: [safety, threat].
static func _commander_risk(obs: Dictionary, rules: OverworldRules, foes: Array) -> Array:
	var me := int(obs["player"])
	var safety := 1.0
	var threat := 0.0
	var any := false
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) != me:
			continue
		any = true
		var a := _squads_value(rules, c.get("army", []))
		var e := 0.0
		for f: Array in foes:
			if Hex.plot_distance(int(c["plot"]), f[0], rules.width) <= THREAT_RANGE:
				e += f[1]
		safety = minf(safety, _share(a, a + e, 1.0))
		threat = maxf(threat, e / maxf(a, 1.0))
	return [safety if any else 0.0, threat]


## Decision-time criterion values from an overworld observation
## (OverworldSession.observe). Criteria without an overworld decision form
## (value efficiency: battles; tempo, pressure: forecasts) are left out.
static func overworld(obs: Dictionary, rules: OverworldRules) -> Dictionary:
	var me := int(obs["player"])
	var f := _forces(obs, rules)
	var owned := 0
	var known := 0
	var producing := 0
	var known_producing := 0
	for p: int in obs["plots"]:
		for ft: Dictionary in obs["plots"][p]["features"]:
			known += 1
			var makes := rules.production_count(int(ft["tmpl"])) > 0
			if makes:
				known_producing += 1
			if int(ft["owner"]) == me:
				owned += 1
				if makes:
					producing += 1
	var target := float((library().get("criteria", {}) as Dictionary).get("exploration", {}).get("params", {}).get("target_pct", 60))
	var fog := 100.0 * (obs["plots"] as Dictionary).size() / maxi(rules.plot_count(), 1)
	var ratio := _share(f[0], f[0] + f[1])
	return {
		"margin": ratio * 2.0 - 1.0,
		"force_ratio": ratio,
		"objective_control": _share(owned, known, 0.0),
		"economy": _share(producing, known_producing),
		"exploration": clampf(fog / maxf(target, EPS), 0.0, 1.0),
		"commander_safety": _commander_risk(obs, rules, f[2])[0],
	}


## The schedule conditions an overworld player can know (B1Q6). Pass the
## turn of first contact (-1 = none yet); contact = a hostile force seen now.
static func overworld_conditions(obs: Dictionary, rules: OverworldRules, contact_turn: int) -> Dictionary:
	var f := _forces(obs, rules)
	var turn := int(obs["turn"])
	if contact_turn < 0 and not (f[2] as Array).is_empty():
		contact_turn = turn
	var ratio := _share(f[0], f[0] + f[1])
	return {
		"turn": float(turn),
		"contact": 1.0 if contact_turn >= 0 else 0.0,
		"since_contact": -1.0 if contact_turn < 0 else float(turn - contact_turn),
		"fog_pct": 100.0 * (obs["plots"] as Dictionary).size() / maxi(rules.plot_count(), 1),
		"force_ratio": ratio,
		"threat": _commander_risk(obs, rules, f[2])[1],
		"bank": float(obs.get("value", 0)),
		"ahead": ratio * 2.0 - 1.0,
	}


# --- battles ---------------------------------------------------------------

static func _battle_value(rules: BattleRules, q: Dictionary) -> float:
	var st := rules.squad_ids.find(String(q["template"]))
	if st < 0:
		return 0.0
	return float(rules.sq_value[st]) * int(q["alive"]) / maxi(rules.sq_members[st].size(), 1)


## Decision-time criterion values from a battle observation
## (BattleSession.observe / observe_state).
static func battle(obs: Dictionary, rules: BattleRules) -> Dictionary:
	var me := int(obs["player"])
	var own := 0.0
	var enemy := 0.0
	var lost := 0.0
	for q: Dictionary in obs["squads"]:
		if bool(q.get("withdrawn", false)):
			continue
		var v := _battle_value(rules, q)
		if int(q["player"]) == me:
			own += v
			var st := rules.squad_ids.find(String(q["template"]))
			if st >= 0:
				var n := rules.sq_members[st].size()
				lost += float(rules.sq_value[st]) * (n - int(q["alive"])) / maxi(n, 1)
		else:
			enemy += v
	var held := 0
	var open := 0
	for z: Dictionary in obs["zones"]:
		if bool(z.get("locked", false)):
			continue
		open += 1
		if int(z["owner"]) == me:
			held += 1
	var scores: Dictionary = obs.get("scores", {})
	var mine := float((scores.get(me, {}) as Dictionary).get("influence", 0))
	var best := 0.0
	for p: int in scores:
		if p != me:
			best = maxf(best, float(scores[p]["influence"]))
	var destroyed := float((scores.get(me, {}) as Dictionary).get("value", 0))
	return {
		"margin": 0.0 if mine + best <= 0.0 else (mine - best) / (mine + best),
		"value_efficiency": _share(destroyed, destroyed + lost),
		"force_ratio": _share(own, own + enemy),
		"objective_control": _share(held, open, 0.0),
	}


## The schedule conditions a battle player can know (B1Q6).
static func battle_conditions(obs: Dictionary, rules: BattleRules, contact_turn: int) -> Dictionary:
	var me := int(obs["player"])
	var turn := int(obs["turn"])
	var seen := false
	for q: Dictionary in obs["squads"]:
		if int(q["player"]) != me and not bool(q.get("destroyed", false)):
			seen = true
	if contact_turn < 0 and seen:
		contact_turn = turn
	var v := battle(obs, rules)
	return {
		"turn": float(turn),
		"contact": 1.0 if contact_turn >= 0 else 0.0,
		"since_contact": -1.0 if contact_turn < 0 else float(turn - contact_turn),
		"fog_pct": 0.0,
		"force_ratio": v["force_ratio"],
		"threat": 0.0,
		"bank": 0.0,
		"ahead": v["margin"],
	}


## One criterion's weight over a game: base x the product of its gates,
## each held at least `hold` turns once it changes (mirrors hx fitness).
class Schedule extends RefCounted:
	var base := 1.0
	var gates: Array = []
	var hold := 3
	var _held: Array = []
	var _since: Array = []

	func _init(entry: Dictionary, hold_turns: int = 3) -> void:
		base = float(entry.get("base", 1.0))
		gates = entry.get("gates", [])
		hold = hold_turns
		for g in gates:
			_held.append(null)
			_since.append(0)

	func weight(conditions: Dictionary, turn: int) -> float:
		var w := base
		for i in gates.size():
			var g: Dictionary = gates[i]
			var raw := SimCriteria.curve(g["points"], float(conditions.get(g["condition"], 0.0)))
			if _held[i] == null or (absf(raw - float(_held[i])) > SimCriteria.EPS and turn - int(_since[i]) >= hold):
				_held[i] = raw
				_since[i] = turn
			w *= float(_held[i])
		return w


## A profile's mask (B1Q6, R6Q24): what its decision process thinks it is
## scored on, changing with the game. It also remembers first contact.
class Mask extends RefCounted:
	var schedules: Dictionary = {}  # criterion -> Schedule
	var contact_turn := -1

	func _init(spec: Dictionary, hold_turns: int = 3) -> void:
		for c: String in spec:
			schedules[c] = SimCriteria.Schedule.new(spec[c], hold_turns)

	## Criterion -> weight this turn; hidden criteria are absent.
	func weights(conditions: Dictionary) -> Dictionary:
		if conditions.get("contact", 0.0) > 0.0 and contact_turn < 0:
			contact_turn = int(conditions["turn"]) - maxi(int(conditions.get("since_contact", 0.0)), 0)
		var out := {}
		for c: String in schedules:
			out[c] = (schedules[c] as SimCriteria.Schedule).weight(conditions, int(conditions["turn"]))
		return out

	## Values and weights for an overworld observation, and their utility.
	func overworld(obs: Dictionary, rules: OverworldRules) -> Dictionary:
		var cond := SimCriteria.overworld_conditions(obs, rules, contact_turn)
		var w := weights(cond)
		var v := SimCriteria.overworld(obs, rules)
		return {"values": v, "weights": w, "conditions": cond, "utility": SimCriteria.utility(v, w)}

	## Values and weights for a battle observation, and their utility.
	func battle(obs: Dictionary, rules: BattleRules) -> Dictionary:
		var cond := SimCriteria.battle_conditions(obs, rules, contact_turn)
		var w := weights(cond)
		var v := SimCriteria.battle(obs, rules)
		return {"values": v, "weights": w, "conditions": cond, "utility": SimCriteria.utility(v, w)}
