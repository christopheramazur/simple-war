class_name SquadRelation
extends RefCounted
## What one squad is doing about another (U1Q3c, U1Q3d; GDD 02 §2.6 "Pair
## relations", proposed). One read model for the tooltip, the comparison
## menu, the Game API, the AI and the harness, so none of them can disagree
## with the simulation: every fact comes from the function the sim runs
## (LineOfFire.unit_shot / check, own_sight and seen_by, CombatSystem.
## pick_target, BattleActivity, BattleOrders.nearest_visible_enemy), never
## from a parallel formula. Read-only and static: the state hash never moves.
##
## facts(state, viewer, a, b) returns both directions (a about b, then b about
## a), each as {kind, value, from, to, rule, data}: `from` is the squad the
## fact is about, `to` the other squad (both squad IDs). Kinds, in order:
##   range        from's weapons against to: in_range, min_range, no_line,
##                out_of_range (data.gap, metres fixed), not_spotted, unarmed.
##   sight        from's side sees to: own (its own eyes) or allies; unseen.
##   targeting    from is firing at to, or aiming at it (data.hold says why
##                it does not fire).
##   ordered      from has an attack order on to (data.closing).
##   would_engage from would pick to on the next tick but is not engaged on
##                it yet: value "likely" (sticky targeting can still change it).
##   under_fire   to fired at from within rules.recent_fire_ticks.
##   fleeing      from falls back / withdraws from to (own view: the order and
##                its threat); an enemy only "retreating": moving away from
##                to after taking fire from it (behaviour, never the order).
##   moving       from is moving toward / away from / across to (behaviour).
##
## Fog: viewer 0 sees all. Otherwise a or b unseen by the viewer gives [].
## About a squad the viewer does not own, only behaviour: firing (after it
## fires), under fire, moving, retreating, and its public weapon reach
## (LineOfFire.check against the squads' reach). Never its order, its target
## before it fires, its hold-fire reasons, its reload or what its side sees.
## Dead or out-of-action squads, unknown IDs and a == b give [].

const RULE_RANGE := "02 §2.6 Range and vision"
const RULE_SIGHT := "02 §2.7 Vision"
const RULE_TARGETING := "02 §2.6 Targeting"
const RULE_ORDERED := "02 §2.6 Attack orders"
const RULE_UNDER_FIRE := "02 §2.6 Under fire"
const RULE_FLEEING := "02 §2.6 Fall back"
const RULE_MOVING := "behaviour"

## cos 60°: moving within 60° of the line to the other squad is toward it,
## within 60° of the line away is away, anything else is across.
const HEADING_COS: int = Fixed.ONE / 2


static func facts(state: BattleState, viewer: int, a: int, b: int) -> Array:
	var sq := state.squads
	if a == b:
		return []
	var ra := sq.row_of(a)
	var rb := sq.row_of(b)
	if ra < 0 or rb < 0 or not _present(sq, ra) or not _present(sq, rb):
		return []
	if not _visible(sq, viewer, ra) or not _visible(sq, viewer, rb):
		return []
	var out := []
	_direction(state, viewer, ra, rb, out)
	_direction(state, viewer, rb, ra, out)
	return out


## Facts about squad row `x` with respect to squad row `y`.
static func _direction(state: BattleState, viewer: int, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	var own := viewer == 0 or sq.player[x] == viewer
	if sq.player[x] != sq.player[y]:
		_range(state, own, x, y, out)
		if own:
			_sight(state, x, y, out)
		_targeting(state, own, x, y, out)
		if own:
			_ordered(state, x, y, out)
			_would_engage(state, x, y, out)
		_under_fire(state, x, y, out)
		_fleeing(state, own, x, y, out)
	_moving(state, x, y, out)


static func _fact(state: BattleState, kind: String, value: String, x: int, y: int, rule: String, data: Dictionary = {}) -> Dictionary:
	var sq := state.squads
	return {"kind": kind, "value": value, "from": sq.id_at(x), "to": sq.id_at(y), "rule": rule, "data": data}


## Own view: the per-unit shot gate (LineOfFire.unit_shot) summarised, plus
## the squad-level LineOfFire.check. An enemy: only check(), whose inputs
## (reach, positions, terrain) are public; unit_shot would leak what its side
## sees.
static func _range(state: BattleState, own: bool, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	var check := LineOfFire.check(state, x, y)
	var gap := maxi(Fixed.distance(sq.cx[x], sq.cy[x], sq.cx[y], sq.cy[y]) - sq.reach[x], 0)
	if not own:
		var v := "in_range" if check == LineOfFire.SHOT else "no_line" if check == LineOfFire.BLOCKED else "out_of_range"
		out.append(_fact(state, "range", v, x, y, RULE_RANGE, {"check": check, "gap": gap if check == LineOfFire.OUT_OF_RANGE else 0}))
		return
	var u := state.units
	var counts := {LineOfFire.SHOT: 0, LineOfFire.MIN_RANGE: 0, LineOfFire.BLOCKED: 0,
		LineOfFire.OUT_OF_RANGE: 0, LineOfFire.NO_TARGET: 0}
	var armed := 0
	var unit_gap := 1 << 62
	var theirs := Centroids.units_of(state, y)
	for urow in Centroids.units_of(state, x):
		if u.hp[urow] <= 0 or u.weapon[urow] < 0:
			continue
		armed += 1
		var code := LineOfFire.unit_shot(state, urow, y)
		counts[code] = int(counts.get(code, 0)) + 1
		var rng := state.rules.wp_range[u.weapon[urow]]
		for t in theirs:
			if u.hp[t] > 0:
				unit_gap = mini(unit_gap, maxi(Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t]) - rng, 0))
	var data := {"check": check, "armed": armed, "shot": counts[LineOfFire.SHOT],
		"min_range": counts[LineOfFire.MIN_RANGE], "blocked": counts[LineOfFire.BLOCKED],
		"out_of_range": counts[LineOfFire.OUT_OF_RANGE], "not_spotted": counts[LineOfFire.NO_TARGET],
		"share": LineOfFire.shot_share(state, x, y), "gap": 0}
	var v := "unarmed"
	if armed > 0:
		v = "in_range"
		if counts[LineOfFire.SHOT] == 0:
			# The reason most units share; ties go to the one nearest a shot.
			var best := -1
			for code in [LineOfFire.MIN_RANGE, LineOfFire.BLOCKED, LineOfFire.OUT_OF_RANGE, LineOfFire.NO_TARGET]:
				if counts[code] > best:
					best = counts[code]
					v = {LineOfFire.MIN_RANGE: "min_range", LineOfFire.BLOCKED: "no_line",
						LineOfFire.OUT_OF_RANGE: "out_of_range", LineOfFire.NO_TARGET: "not_spotted"}[code]
			if v == "out_of_range" and unit_gap < (1 << 62):
				data["gap"] = unit_gap
	out.append(_fact(state, "range", v, x, y, RULE_RANGE, data))


static func _sight(state: BattleState, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	var v := "unseen"
	if sq.seen_by[y] & BattleSquads.bit(sq.player[x]) != 0:
		v = "own" if LineOfFire.own_sight(state, x, y) else "allies"
	out.append(_fact(state, "sight", v, x, y, RULE_SIGHT))


## Own view: engaged on y and either fired last tick ("firing") or not
## ("aiming", with the units' dominant hold reason). An enemy: only "firing",
## once it has fired at y (behaviour), never the engagement before that.
static func _targeting(state: BattleState, own: bool, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	if sq.engaged[x] != sq.id_at(y):
		return
	if _fired_last_tick(state, x):
		out.append(_fact(state, "targeting", "firing", x, y, RULE_TARGETING))
		return
	if not own:
		return
	var holds := {}
	var hold := BattleActivity.Hold.NONE
	var best := 0
	var u := state.units
	for urow in Centroids.units_of(state, x):
		if u.hp[urow] <= 0 or u.weapon[urow] < 0:
			continue
		var h := BattleActivity.hold(state, urow)
		holds[h] = int(holds.get(h, 0)) + 1
		if h != BattleActivity.Hold.NONE and (holds[h] > best or (holds[h] == best and h < hold)):
			best = holds[h]
			hold = h
	out.append(_fact(state, "targeting", "aiming", x, y, RULE_TARGETING,
		{"hold": hold, "holds": holds, "activity": BattleActivity.squad(state, x)}))


static func _ordered(state: BattleState, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	if sq.order[x] != BattleSquads.Order.ATTACK or sq.target[x] != sq.id_at(y):
		return
	out.append(_fact(state, "ordered", "attack", x, y, RULE_ORDERED,
		{"closing": BattleActivity.squad(state, x) == BattleActivity.Squad.CLOSING_IN}))


## The target CombatSystem would pick next tick, when it is not the current
## engagement. "likely": movement this tick can still change it.
static func _would_engage(state: BattleState, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	var id := sq.id_at(y)
	if sq.engaged[x] == id or CombatSystem.pick_target(state, x) != id:
		return
	out.append(_fact(state, "would_engage", "likely", x, y, RULE_TARGETING))


## x is under fire from y: y fired a volley at x within the window. From the
## turn's squad_fired events (behaviour any viewer saw), plus the last tick's
## engagement when the log was cleared (a restored state).
static func _under_fire(state: BattleState, x: int, y: int, out: Array) -> void:
	var ago := last_volley_ago(state, y, x)
	if ago < 0 or ago >= state.rules.recent_fire_ticks:
		return
	out.append(_fact(state, "under_fire", "recent", x, y, RULE_UNDER_FIRE, {"ticks_ago": ago}))


## Ticks since squad row `shooter` last fired a volley at squad row `victim`
## (0 = the last completed tick), or -1 if not this turn.
static func last_volley_ago(state: BattleState, shooter: int, victim: int) -> int:
	var sq := state.squads
	var sid := sq.id_at(shooter)
	var vid := sq.id_at(victim)
	if _fired_last_tick(state, shooter) and sq.engaged[shooter] == vid:
		return 0
	for i in range(state.turn_log.size() - 1, -1, -1):
		var e: SimEvent = state.turn_log[i]
		if e.type == &"squad_fired" and int(e.data["squad"]) == sid and int(e.data["target"]) == vid:
			return state.tick - 1 - e.tick
	return -1


## Own view: a fall back or withdraw order, and y is the threat it runs from
## (BattleOrders.nearest_visible_enemy). An enemy: behaviour only, it is
## moving away from y after y fired at it.
static func _fleeing(state: BattleState, own: bool, x: int, y: int, out: Array) -> void:
	var sq := state.squads
	if own:
		var o := sq.order[x]
		if o != BattleSquads.Order.FALL_BACK and o != BattleSquads.Order.WITHDRAW:
			return
		if BattleOrders.nearest_visible_enemy(state, x) != y:
			return
		out.append(_fact(state, "fleeing", "falling_back" if o == BattleSquads.Order.FALL_BACK else "withdrawing",
			x, y, RULE_FLEEING, {"moving": sq.moving[x] == 1}))
		return
	if heading(state, x, y) != "away":
		return
	var ago := last_volley_ago(state, y, x)
	if ago < 0 or ago >= state.rules.recent_fire_ticks:
		return
	out.append(_fact(state, "fleeing", "retreating", x, y, RULE_FLEEING, {"ticks_ago": ago}))


static func _moving(state: BattleState, x: int, y: int, out: Array) -> void:
	var h := heading(state, x, y)
	if h.is_empty():
		return
	out.append(_fact(state, "moving", h, x, y, RULE_MOVING))


## "toward", "away" or "across" for a moving squad row `x` relative to squad
## row `y` (its facing is its heading while it moves); "" if it stands.
static func heading(state: BattleState, x: int, y: int) -> String:
	var sq := state.squads
	if sq.moving[x] != 1:
		return ""
	var dx := sq.cx[y] - sq.cx[x]
	var dy := sq.cy[y] - sq.cy[x]
	var d := Fixed.length(dx, dy)
	if d <= 0:
		return "across"
	var f := sq.facing[x]
	var c := Fixed.div(Fixed.mul(Fixed.fcos(f), dx) + Fixed.mul(Fixed.fsin(f), dy), d)
	if c >= HEADING_COS:
		return "toward"
	if c <= -HEADING_COS:
		return "away"
	return "across"


static func _present(sq: BattleSquads, row: int) -> bool:
	return sq.is_active(row) and sq.alive[row] > 0


static func _visible(sq: BattleSquads, viewer: int, row: int) -> bool:
	return viewer == 0 or sq.player[row] == viewer or sq.seen_by[row] & BattleSquads.bit(viewer) != 0


static func _fired_last_tick(state: BattleState, row: int) -> bool:
	return state.tick > 0 and state.squads.fired_tick[row] == state.tick - 1
