class_name WorkshopDebug
extends RefCounted
## Per-tick debug frames for the behaviour workshop's overlay (sw-tho3.6,
## U1 B6, GDD 05 §5.7). A frame is plain data: Dictionaries, Arrays,
## numbers, Strings and Vector2s in battlefield metres. No sim object (state,
## rules, route planner) is ever put in one, so a viewer that holds frames
## holds no way to change the battle.
##
## Built from BattleProbe.snapshot (viewer 0, all-seeing) plus what only a
## debug view wants: each moving squad's route legs and each squad's
## spacing violations. Capturing reads only: the state hash is unchanged.
##
## Frame Dictionary:
##   turn, tick, width, height (m)
##   squads:  [{id, player, label, x, y, range, sight (m), facing (radians,
##             +x = 0, clockwise on screen), activity (BattleActivity.Squad
##             name), target (squad ID or -1)}]
##   units:   [{id, squad, player, x, y, hp, hp_max, victim (unit ID or -1),
##             hold (BattleActivity.Hold name; "" = NONE)}]
##   fire:    [{from, to, los}]: the LoF matrix, one pair per squad against
##             each enemy it engages or can reach; los is a LOS name
##   routes:  [{squad, final (the last point is where it stops), points
##             (PackedVector2Array: the anchor, then each
##             BattleRoute.next_waypoint in turn)}]
##   spacing: [{squad, a, b (unit IDs), gap, min (m)}]

## LineOfFire.check codes by name, in enum order.
const LOS: PackedStringArray = ["out_of_range", "shot", "blocked", "min_range", "no_target"]
## Legs a route shows at most (a planner that never reaches stops here).
const MAX_LEGS: int = 12
## Two units of a squad closer than this share of its formation spacing
## are a spacing violation.
const SPACING_SHARE: float = 0.5
## Activities that follow a route.
const ROUTED: Array = [
	BattleActivity.Squad.MOVING, BattleActivity.Squad.CLOSING_IN,
	BattleActivity.Squad.FALLING_BACK, BattleActivity.Squad.WITHDRAWING,
]

const ONE: float = 65536.0


## One debug frame of `state` as it stands. `routes` is a planner of the
## caller's own (not state.rules.routes, so the battle's route cache is
## never touched); it may be reused across frames of one battle.
static func capture(state: BattleState, routes: BattleRoute) -> Dictionary:
	var snap := BattleProbe.snapshot(state, 0)
	var r := state.rules
	var sq := state.squads
	var player_of := {}
	var squads: Array = []
	for d: Dictionary in snap["squads"]:
		player_of[d["id"]] = d["player"]
		squads.append({
			"id": d["id"], "player": d["player"], "label": d["label"],
			"x": d["x"] / ONE, "y": d["y"] / ONE,
			"range": d["range"] / ONE, "sight": d["sight"] / ONE,
			"facing": d["facing"] / ONE * TAU,
			"activity": BattleActivity.Squad.find_key(d["activity"]),
			"target": d.get("target", -1),
		})
	var units: Array = []
	for d: Dictionary in snap["units"]:
		var h: int = d["hold"]
		units.append({
			"id": d["id"], "squad": d["squad"], "player": player_of.get(d["squad"], 0),
			"x": d["x"] / ONE, "y": d["y"] / ONE, "hp": d["hp"], "hp_max": d["hp_max"],
			"victim": d["victim"],
			"hold": "" if h == BattleActivity.Hold.NONE else BattleActivity.Hold.find_key(h),
		})
	var fire: Array = []
	for d: Dictionary in snap["fire"]:
		fire.append({"from": d["from"], "to": d["to"], "los": LOS[d["los"]]})
	var route_list: Array = []
	var spacing: Array = []
	for row in sq.count():
		if not sq.is_active(row) or sq.alive[row] == 0:
			continue
		var sid := sq.id_at(row)
		if BattleActivity.squad(state, row) in ROUTED and sq.route[row] != 0:
			route_list.append(_legs(state, routes, row))
		spacing.append_array(_spacing(state, row, sid))
	return {
		"turn": state.turn, "tick": state.tick, "width": r.width, "height": r.height,
		"squads": squads, "units": units, "fire": fire, "routes": route_list, "spacing": spacing,
	}


## The route a squad is on: its anchor, its current waypoint, then the
## planner's next waypoints from there to the route's destination.
static func _legs(state: BattleState, routes: BattleRoute, row: int) -> Dictionary:
	var r := state.rules
	var sq := state.squads
	var frame := 0
	for side: Dictionary in r.sides:
		if int(side["player"]) == sq.player[row] and int(side["facing"]) == Fixed.ANGLE_HALF:
			frame = Fixed.ANGLE_HALF
	var pts := PackedVector2Array([Vector2(sq.ax[row], sq.ay[row]) / ONE])
	var x := sq.wx[row]
	var y := sq.wy[row]
	var final := sq.route[row] == 2
	pts.append(Vector2(x, y) / ONE)
	var cls := r.sq_route_class[sq.tmpl[row]]
	while not final and pts.size() <= MAX_LEGS:
		var leg := routes.next_waypoint(r, cls, x, y, sq.rx[row], sq.ry[row], frame)
		if leg[0] == x and leg[1] == y:
			break
		x = leg[0]
		y = leg[1]
		final = leg[2] == 1
		pts.append(Vector2(x, y) / ONE)
	return {"squad": sq.id_at(row), "final": final, "points": pts}


## Pairs of the squad's living units closer than SPACING_SHARE of its
## formation spacing.
static func _spacing(state: BattleState, row: int, sid: int) -> Array:
	var u := state.units
	var lim := int(state.rules.sq_spacing[state.squads.tmpl[row]] * SPACING_SHARE)
	var mine := PackedInt64Array()
	for urow in Centroids.units_of(state, row):
		if u.hp[urow] > 0:
			mine.append(urow)
	var out: Array = []
	for i in mine.size():
		for j in range(i + 1, mine.size()):
			var a := mine[i]
			var b := mine[j]
			var gap := Fixed.distance(u.x[a], u.y[a], u.x[b], u.y[b])
			if gap < lim:
				out.append({"squad": sid, "a": u.id_at(a), "b": u.id_at(b), "gap": gap / ONE, "min": lim / ONE})
	return out
