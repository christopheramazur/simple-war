class_name HexLayout
extends RefCounted
## Where a hex's sites and movers stand (GDD 02 §2.9, 04 §4.8; U1Q20-U1Q22).
##
## Presentation, static, no game state: the war room and the World maps tab
## both call it. Points are integers in thousandths of the hex circumradius
## from the hex centre, y down. The hex is pointy-top (Hex): side k faces
## -60*k degrees on screen (E, NE, NW, W, SW, SE, the order of Hex.DIRS) and
## its midpoint is APOTHEM out.
##
## Inputs are only what the viewer knows: the sites it can see (template ID,
## layout_priority, an optional map `at`), and the sides its known roads
## reach. A fog change moves sites only through these inputs, so a cache
## keyed by `cache_key` stays exact.
##
## Steps (data/ui/hex_layout.json):
## 1. Order sites by layout_priority (higher first), then template ID; give
##    them the slot table for their count (1-7). An eighth or later site
##    shares the last slot ("+n" badge: `overflow`).
## 2. Road hex: the open direction is the bisector of the widest gap between
##    road directions (ties: most downward, then lowest x). The group scales
##    by group_scale and shifts group_shift along it; a site within clearance
##    of a road segment is pushed off along its normal, and kept inside the
##    hex. While two sites overlap, the group shrinks in shrink_step steps
##    down to min_scale. Movers stand on the road.
## 3. Map overrides (`at`) are applied last, as given.

const TABLE_PATH := "res://data/ui/hex_layout.json"
## Centre-to-side-midpoint distance, in thousandths of the circumradius.
const APOTHEM: int = 866
const SIDES: int = 6
## Push and containment passes per site before giving up (dense hexes).
const SETTLE_PASSES: int = 12

static var _table: Dictionary = {}


## The layout table (loaded once; read-only).
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		if parsed is Dictionary:
			_table = parsed
		else:
			push_error("HexLayout: cannot read %s" % TABLE_PATH)
	return _table


## Unit vector of side k on screen (y down).
static func side_dir(k: int) -> Vector2:
	var a := deg_to_rad(-60.0 * k)
	return Vector2(cos(a), sin(a))


## Sites (each {"id": String, "priority": int, "at": Vector2i (optional)})
## in slot order: input indices, layout_priority descending, then template
## ID, then input order.
static func order(sites: Array) -> PackedInt32Array:
	var idx: Array = range(sites.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var pa := int(sites[a].get("priority", 0))
		var pb := int(sites[b].get("priority", 0))
		if pa != pb:
			return pa > pb
		var ia := String(sites[a].get("id", ""))
		var ib := String(sites[b].get("id", ""))
		if ia != ib:
			return ia < ib
		return a < b)
	return PackedInt32Array(idx)


## The valid road sides, sorted and unique.
static func clean_sides(road_sides: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in road_sides:
		if k >= 0 and k < SIDES and not out.has(k):
			out.append(k)
	out.sort()
	return out


## The open direction of a road hex in whole degrees (screen, y down), or -1
## with no roads: the bisector of the widest gap between road directions.
## Ties go to the most downward bisector, then the lowest x.
static func open_angle(road_sides: PackedInt32Array) -> int:
	var sides := clean_sides(road_sides)
	if sides.is_empty():
		return -1
	var angles := PackedInt32Array()
	for k in sides:
		angles.append(posmod(-60 * k, 360))
	angles.sort()
	var best := -1
	var best_gap := -1
	for i in angles.size():
		var gap := 360 if angles.size() == 1 else posmod(angles[(i + 1) % angles.size()] - angles[i], 360)
		var bis := posmod(angles[i] + gap / 2, 360)
		if gap > best_gap or (gap == best_gap and _lower_first(bis, best)):
			best = bis
			best_gap = gap
	return best


## Whether bisector a beats b on a tie: more downward, then lower x.
static func _lower_first(a: int, b: int) -> bool:
	var ya := roundi(sin(deg_to_rad(a)) * 1000.0)
	var yb := roundi(sin(deg_to_rad(b)) * 1000.0)
	if ya != yb:
		return ya > yb
	return roundi(cos(deg_to_rad(a)) * 1000.0) < roundi(cos(deg_to_rad(b)) * 1000.0)


## The sides (0..5, Hex.DIRS order) this hex's paths reach. `here`: the
## known feature templates on the hex; `neighbours`: six lists of known
## feature templates across each side (empty off the map or unknown);
## `info`: template ID -> its values ("layer", "connects"). A path joins a
## neighbour holding itself or a feature in its `connects`.
static func road_sides(here: PackedStringArray, neighbours: Array, info: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in mini(neighbours.size(), SIDES):
		var across: PackedStringArray = PackedStringArray(neighbours[k])
		var joined := false
		for fid in here:
			var v: Dictionary = info.get(fid, {})
			if String(v.get("layer", "site")) != "path":
				continue
			if across.has(fid):
				joined = true
			for other in v.get("connects", []):
				if across.has(String(other)):
					joined = true
			if joined:
				break
		if joined:
			out.append(k)
	return out


## A cache key covering every input of `compute`, fog-dependent ones (the
## known sites and road sides) included. Equal keys give equal layouts.
static func cache_key(sites: Array, road_sides: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for s in sites:
		var at: Variant = s.get("at")
		parts.append("%s|%d|%s" % [String(s.get("id", "")), int(s.get("priority", 0)),
			"" if at == null else "%d,%d" % [at.x, at.y]])
	var roads := PackedStringArray()
	for k in clean_sides(road_sides):
		roads.append(str(k))
	return ";".join(parts) + "#" + ",".join(roads)


## The layout of one hex. Returns:
## - points: Array[Vector2i], one per input site, in input order.
## - order: PackedInt32Array, input indices in slot order.
## - radius: the drawn site radius (scaled on a road hex).
## - scale: the group scale in percent (100 without a road).
## - open: the open direction in degrees, or -1 without a road.
## - lane: Array[Vector2i], where up to 3 movers stand, left to right.
## - lane_radius: the mover token radius.
## - overflow: sites sharing the last slot beyond the table (the "+n").
static func compute(sites: Array, road_sides: PackedInt32Array, tbl: Dictionary = {}) -> Dictionary:
	if tbl.is_empty():
		tbl = table()
	var roads := clean_sides(road_sides)
	var slots: Array = tbl.get("slots", [])
	var road: Dictionary = tbl.get("road", {})
	var lane_t: Dictionary = tbl.get("lane", {})
	var base_r := float(tbl.get("site_radius", 180))
	var n := sites.size()
	var shown := mini(n, slots.size())
	var ord := order(sites)
	var scale := 100
	var open := open_angle(roads)
	var placed: Array[Vector2] = []
	if shown > 0:
		var slot_pts: Array[Vector2] = []
		for p in slots[shown - 1]:
			slot_pts.append(Vector2(float(p[0]), float(p[1])))
		if roads.is_empty():
			placed = slot_pts
		else:
			scale = int(road.get("group_scale", 85))
			var step := maxi(1, int(road.get("shrink_step", 10)))
			var min_scale := int(road.get("min_scale", 60))
			while true:
				placed = _on_road(slot_pts, roads, open, scale, base_r * scale / 100.0, road)
				if scale <= min_scale or not _overlaps(placed, base_r * scale / 100.0):
					break
				scale = maxi(scale - step, min_scale)
	var points: Array[Vector2i] = []
	points.resize(n)
	for i in n:
		var slot := mini(i, shown - 1)
		var site: Dictionary = sites[ord[i]]
		var at: Variant = site.get("at")
		if at != null:
			points[ord[i]] = Vector2i(int(at.x), int(at.y))
		else:
			points[ord[i]] = Vector2i(roundi(placed[slot].x), roundi(placed[slot].y))
	return {
		"points": points,
		"order": ord,
		"radius": roundi(base_r * scale / 100.0),
		"scale": scale,
		"open": open,
		"lane": lane(roads, tbl),
		"lane_radius": int(lane_t.get("token_radius", 100)),
		"overflow": n - shown,
	}


## Where movers stand: along the lower edge, or on the road of a road hex
## (the straightest pair of road directions, or out along a dead end).
static func lane(road_sides: PackedInt32Array, tbl: Dictionary = {}) -> Array[Vector2i]:
	if tbl.is_empty():
		tbl = table()
	var lane_t: Dictionary = tbl.get("lane", {})
	var out: Array[Vector2i] = []
	var roads := clean_sides(road_sides)
	if roads.is_empty():
		for p in lane_t.get("points", []):
			out.append(Vector2i(int(p[0]), int(p[1])))
		return out
	var reach := float(lane_t.get("road_reach", 520))
	var pts: Array[Vector2] = []
	if roads.size() == 1:
		var d := side_dir(roads[0])
		pts = [Vector2.ZERO, d * reach * 0.5, d * reach]
	else:
		var a := roads[0]
		var b := roads[1]
		var best := -1
		for i in roads.size():
			for j in range(i + 1, roads.size()):
				var sep := (roads[j] - roads[i]) % SIDES
				sep = mini(sep, SIDES - sep)
				if sep > best:
					best = sep
					a = roads[i]
					b = roads[j]
		pts = [side_dir(a) * reach, Vector2.ZERO, side_dir(b) * reach]
	for p in pts:
		out.append(Vector2i(roundi(p.x), roundi(p.y)))
	out.sort_custom(func(u: Vector2i, v: Vector2i) -> bool: return u.x < v.x or (u.x == v.x and u.y < v.y))
	return out


static func _on_road(slot_pts: Array[Vector2], roads: PackedInt32Array, open: int,
		scale: int, r: float, road: Dictionary) -> Array[Vector2]:
	var o := Vector2(cos(deg_to_rad(open)), sin(deg_to_rad(open)))
	var shift := o * float(road.get("group_shift", 300))
	var clearance := float(road.get("clearance", 290))
	var out: Array[Vector2] = []
	for p in slot_pts:
		out.append(_settle(p * (scale / 100.0) + shift, r, roads, o, clearance))
	return out


## Pushes p off every road segment to the clearance, then back inside the
## hex, until both hold (or SETTLE_PASSES run out on a crowded hex).
static func _settle(p: Vector2, r: float, roads: PackedInt32Array, open: Vector2, clearance: float) -> Vector2:
	var want := clearance + 1.0
	for _pass in SETTLE_PASSES:
		var moved := false
		for k in roads:
			var d := side_dir(k)
			var t := clampf(p.dot(d), 0.0, float(APOTHEM))
			var c := d * t
			var off := p - c
			var dist := off.length()
			if dist >= want - 0.5:
				continue
			var nrm: Vector2
			if dist > 0.5:
				nrm = off / dist
			elif t <= 0.0:
				nrm = open
			else:
				nrm = Vector2(-d.y, d.x)
				if nrm.dot(open) < 0.0:
					nrm = -nrm
			p = c + nrm * want
			moved = true
		for k in SIDES:
			var m := side_dir(k)
			var excess := p.dot(m) + r - float(APOTHEM - 1)
			if excess > 0.0:
				p -= m * excess
				moved = true
		if not moved:
			break
	return p


static func _overlaps(pts: Array[Vector2], r: float) -> bool:
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if pts[i].distance_to(pts[j]) < 2.0 * r:
				return true
	return false
