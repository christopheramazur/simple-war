class_name UtilityDeploy
extends RefCounted
## The deployment heuristic of a controller profile (sw-bafi.16, U1 C15):
## places a side's squads in its deployment area by role instead of leaving
## them on their automatic places.
##   indirect: a member's weapon has an indirect fire mode -> the back edge;
##   concealed: an ability (or the template) gives concealment -> the
##     nearest cover cell (a feature with cover or concealment) in the area;
##     with no cover cell in reach, it is placed by its range like any other;
##   short: range at most `short_range` m -> the front edge.
## Every other squad keeps its automatic place (no placement), as do locked
## squads. A placed squad keeps the lateral coordinate of its automatic
## place, so the even spread across the area is kept and squads don't stack.
##
## Front and back are along the axis from the own area to the enemy areas
## (the dominant axis of the vector between their centres; the side's
## facing if there is no enemy area). Pure integer arithmetic on public
## data (the observation and the battle rules), so the same observation
## gives the same placements.
##
## Profile section: "deploy": {"process": "role" | "auto" (default),
##   "params": {"short_range" (m, 30), "margin" (cells from the edge, 3),
##   "cover_reach" (cells from the automatic place, 25)}}.

const DEFAULT_SHORT_RANGE := 30
const DEFAULT_MARGIN := 3
const DEFAULT_COVER_REACH := 25

var short_range := DEFAULT_SHORT_RANGE
var margin := DEFAULT_MARGIN
var cover_reach := DEFAULT_COVER_REACH


func _init(params: Dictionary = {}) -> void:
	short_range = int(params.get("short_range", DEFAULT_SHORT_RANGE))
	margin = int(params.get("margin", DEFAULT_MARGIN))
	cover_reach = int(params.get("cover_reach", DEFAULT_COVER_REACH))


## Placements [{squad, x, y, facing}] for `player` from a deploying battle
## observation; [] when not deploying, without an area or rules.
func place(obs: Dictionary, rules: BattleRules, player: int) -> Array:
	var out := []
	var area: Array = obs.get("area", [])
	if not obs.get("deploying", false) or area.size() < 4 or rules == null:
		return out
	var fwd := forward(obs, player)
	var taken := {}  # cover cells used
	var squads: Array = (obs.get("squads", []) as Array).filter(func(d: Dictionary) -> bool:
		return int(d["player"]) == player and not bool(d.get("locked", false)) and int(d.get("alive", 1)) > 0)
	squads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for d: Dictionary in squads:
		var st := rules.squad_ids.find(String(d["template"]))
		if st < 0:
			continue
		var at := PackedInt64Array()
		match role(rules, st, int(d.get("range", 0))):
			"indirect":
				at = _edge(area, fwd, -1, int(d["x"]), int(d["y"]))
			"concealed":
				at = _cover(rules, st, area, int(d["x"]), int(d["y"]), taken)
				if at.is_empty() and int(d.get("range", 0)) <= Fixed.from_int(short_range):
					at = _edge(area, fwd, 1, int(d["x"]), int(d["y"]))
			"short":
				at = _edge(area, fwd, 1, int(d["x"]), int(d["y"]))
		if at.is_empty():
			continue
		out.append({"squad": int(d["id"]), "x": at[0], "y": at[1], "facing": int(d.get("facing", 0))})
	return out


## A squad template's deployment role: "indirect", "concealed", "short" or
## "" (keeps its automatic place). `range_fx`: the squad's range (fixed).
func role(rules: BattleRules, st: int, range_fx: int) -> String:
	for ut: int in rules.sq_members[st]:
		var w := int(rules.ut_weapon[ut])
		if w >= 0 and rules.indirect(w):
			return "indirect"
	if concealed(rules, st):
		return "concealed"
	if range_fx > 0 and range_fx <= Fixed.from_int(short_range):
		return "short"
	return ""


## Whether a squad template has concealment: a base concealment stat, or an
## innate bundle or ability bundle tagged concealment.
static func concealed(rules: BattleRules, st: int) -> bool:
	if st < rules.sq_concealment.size() and rules.sq_concealment[st] > 0:
		return true
	var bundles := PackedInt64Array()
	if st < rules.sq_bundles.size():
		bundles.append_array(rules.sq_bundles[st])
	if st < rules.sq_abilities.size():
		for a: int in rules.sq_abilities[st]:
			bundles.append(rules.ab_bundle[a])
	for b: int in bundles:
		if b >= 0 and rules.fx != null and b < rules.fx.bundles.size() \
				and (rules.fx.bundles[b].get("tags", PackedStringArray()) as PackedStringArray).has("concealment"):
			return true
	return false


## The forward axis as a unit grid vector [dx, dy]: toward the enemy areas'
## centres along the dominant axis, else the side's facing (nearest axis).
static func forward(obs: Dictionary, player: int) -> Vector2i:
	var own: Array = obs.get("area", [])
	var facing := 0
	var ex := 0
	var ey := 0
	var n := 0
	for a: Dictionary in obs.get("areas", []):
		var r: Array = a["deploy"]
		if int(a["player"]) == player:
			facing = int(a.get("facing", 0))
			continue
		ex += int(r[0]) + (int(r[2]) >> 1)
		ey += int(r[1]) + (int(r[3]) >> 1)
		n += 1
	if n > 0 and own.size() >= 4:
		@warning_ignore("integer_division")
		var dx: int = ex / n - (int(own[0]) + (int(own[2]) >> 1))
		@warning_ignore("integer_division")
		var dy: int = ey / n - (int(own[1]) + (int(own[3]) >> 1))
		if dx != 0 or dy != 0:
			if absi(dx) >= absi(dy):
				return Vector2i(signi(dx), 0)
			return Vector2i(0, signi(dy))
	# Binary angle, 0 = +x, a quarter turn = +y.
	var quarter := Fixed.ANGLE_HALF >> 1
	@warning_ignore("integer_division")
	match (((facing & Fixed.ANGLE_MASK) + (quarter >> 1)) / quarter) % 4:
		1:
			return Vector2i(0, 1)
		2:
			return Vector2i(-1, 0)
		3:
			return Vector2i(0, -1)
	return Vector2i(1, 0)


## The point `margin` cells inside the area's front (side 1) or back (side
## -1) edge along `fwd`, keeping the other coordinate of (x, y).
func _edge(area: Array, fwd: Vector2i, side: int, x: int, y: int) -> PackedInt64Array:
	var m := mini(Fixed.from_int(margin), int(area[2]) >> 1) if fwd.x != 0 else mini(Fixed.from_int(margin), int(area[3]) >> 1)
	var dir := fwd * side
	if dir.x > 0:
		x = int(area[0]) + int(area[2]) - m
	elif dir.x < 0:
		x = int(area[0]) + m
	elif dir.y > 0:
		y = int(area[1]) + int(area[3]) - m
	else:
		y = int(area[1]) + m
	return PackedInt64Array([x, y])


## The centre of the nearest cover cell to (x, y) inside the area that the
## squad can enter and no other placed squad took (cells within 2 of a
## taken one count as taken), within `cover_reach` cells. Ties by cell
## index. Empty if none.
func _cover(r: BattleRules, st: int, area: Array, x: int, y: int, taken: Dictionary) -> PackedInt64Array:
	if r.terrain.size() < r.width * r.height or st >= r.sq_route_class.size():
		return PackedInt64Array()
	var costs: PackedInt32Array = r.rt_cost[r.sq_route_class[st]]
	var half := Fixed.ONE / 2
	var cx := Fixed.to_int_floor(x)
	var cy := Fixed.to_int_floor(y)
	var x0 := clampi(Fixed.to_int_floor(int(area[0])), 0, r.width - 1)
	var y0 := clampi(Fixed.to_int_floor(int(area[1])), 0, r.height - 1)
	var x1 := clampi(Fixed.to_int_floor(int(area[0]) + int(area[2])), 0, r.width - 1)
	var y1 := clampi(Fixed.to_int_floor(int(area[1]) + int(area[3])), 0, r.height - 1)
	var best := -1
	var best_d := 0
	var reach := cover_reach * cover_reach
	for qy in range(y0, y1 + 1):
		var my := Fixed.from_int(qy) + half
		if my < int(area[1]) or my > int(area[1]) + int(area[3]):
			continue
		for qx in range(x0, x1 + 1):
			var mx := Fixed.from_int(qx) + half
			if mx < int(area[0]) or mx > int(area[0]) + int(area[2]):
				continue
			var f := r.terrain[qy * r.width + qx]
			if costs[f] <= 0 or (r.f_cover_evasion[f] <= 0 and r.f_concealment[f] <= 0):
				continue
			var d := (qx - cx) * (qx - cx) + (qy - cy) * (qy - cy)
			if d > reach or _near_taken(qx, qy, taken):
				continue
			var cell := qy * r.width + qx
			if best < 0 or d < best_d or (d == best_d and cell < best):
				best = cell
				best_d = d
	if best < 0:
		return PackedInt64Array()
	@warning_ignore("integer_division")
	taken[best] = Vector2i(best % r.width, best / r.width)
	@warning_ignore("integer_division")
	return PackedInt64Array([Fixed.from_int(best % r.width) + half, Fixed.from_int(best / r.width) + half])


static func _near_taken(qx: int, qy: int, taken: Dictionary) -> bool:
	for c: Vector2i in taken.values():
		if absi(c.x - qx) <= 2 and absi(c.y - qy) <= 2:
			return true
	return false
