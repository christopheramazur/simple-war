class_name ScenarioCanvas
extends RefCounted
## A `scenario`'s objects while the map editor works on them (GDD 04 §4.9,
## O1Q6, sw-ll4.7): its zones and its sides, each with a deployment area, a
## facing and the squads it fields, and its victory settings. No UI: MapPainter
## draws it over the map and turns the mouse and form into these edits.
## Everything else the scenario says (ruleset, triggers) is kept as written.
##
## Positions are whole cells (metres). Saving writes the definition text in
## the layout the hand-written files use, through PackageEditor, so a
## scenario that would break the package is refused there.

const UNDO_MAX: int = 64
## Facings a side can take: name -> binary angle (east is 0).
const FACINGS: Dictionary = {"East": 0, "South": 16384, "West": 32768, "North": 49152}
const ZONE_DEFAULTS: Dictionary = {"radius": 10, "decay": 10, "threshold": 10, "buffer": 10, "vp": 1}
## The victory settings the form edits (Data Model 03 'victory'), with the
## value battle_rules uses when nothing says otherwise.
const VICTORY_DEFAULTS: Dictionary = {"turn_limit": 10, "primary": "influence", "score_target": 0, "annihilation": true, "withdrawal": true}
const VICTORY_PRIMARIES: PackedStringArray = ["influence", "value"]

var id: String = ""
var name: String = ""
## The battle map it is played on.
var map_id: String = ""
## [{"id", "x", "y", "radius", "decay", "threshold", "buffer", "vp", ...}].
var zones: Array[Dictionary] = []
## [{"player", "facing", "deploy": {"x", "y", "w", "h"}, "squads": [ids]}].
var sides: Array[Dictionary] = []
## The victory keys this scenario writes itself. Keys it inherits stay in
## `flat_victory` (what the template gives once flattened) and are not written.
var victory: Dictionary = {}
var flat_victory: Dictionary = {}
var dirty: bool = false
## Counts edits, so a view knows when to redraw.
var revision: int = 0

var _def: Dictionary = {}
var _undo: Array = []
var _redo: Array = []


## Opens a scenario from its definition ({"id", "kind", "values"}). Zones,
## sides and the map it does not write itself come from its parent
## (`t.values_of`).
static func open(t: TemplateTable, def: Dictionary) -> ScenarioCanvas:
	var c := ScenarioCanvas.new()
	c._def = def.duplicate(true)
	c.id = str(def.get("id", ""))
	var own: Dictionary = def.get("values", {})
	var flat: Dictionary = t.values_of(c.id) if t != null and t.has(c.id) else own
	c.name = str(flat.get("name", c.id))
	c.map_id = str(flat.get("map", ""))
	for z: Variant in flat.get("zones", []):
		if z is Dictionary:
			c.zones.append(_ints((z as Dictionary).duplicate(true)))
	for s: Variant in flat.get("sides", []):
		if s is Dictionary:
			c.sides.append(_side((s as Dictionary).duplicate(true)))
	if own.get("victory") is Dictionary:
		c.victory = _ints((own["victory"] as Dictionary).duplicate(true))
	if flat.get("victory") is Dictionary:
		c.flat_victory = _ints((flat["victory"] as Dictionary).duplicate(true))
	return c


## A new scenario on a map of w x h cells: the rules of `base` (ruleset,
## turn length, victory), a deployment strip inside the left and right
## edges, and one zone in the middle. Its sides field no squads of their
## own: on the overworld the commanders bring them.
static func create(t: TemplateTable, new_id: String, map: String, w: int, h: int, base: String = "ow_field") -> ScenarioCanvas:
	var v: Dictionary = t.values_of(base).duplicate(true) if t != null and t.has(base) else {}
	for k: String in ["width", "height", "terrain_default", "terrain", "triggers", "zones", "sides"]:
		v.erase(k)
	v["name"] = new_id.capitalize()
	v["map"] = map
	var c := ScenarioCanvas.new()
	c._def = {"id": new_id, "kind": "scenario", "values": v}
	c.id = new_id
	c.name = v["name"]
	c.map_id = map
	c.victory = _ints((v.get("victory", {}) as Dictionary).duplicate(true)) if v.get("victory") is Dictionary else {}
	@warning_ignore("integer_division")
	var inset := clampi(w / 24, 1, 5)
	@warning_ignore("integer_division")
	var deep := clampi(w / 6, 2, 25)
	@warning_ignore("integer_division")
	var top := h * 15 / 100
	var tall := maxi(h - 2 * top, 1)
	c.sides = [
		{"player": 1, "facing": 0, "deploy": {"x": inset, "y": top, "w": deep, "h": tall}, "squads": []},
		{"player": 2, "facing": 32768, "deploy": {"x": w - inset - deep, "y": top, "w": deep, "h": tall}, "squads": []},
	]
	@warning_ignore("integer_division")
	c.zones = [{"id": "centre", "x": w / 2, "y": h / 2, "radius": clampi(mini(w, h) / 6, 2, 12), "decay": 10, "threshold": 10, "buffer": 10, "vp": 1}]
	c.dirty = true
	return c


func mark_saved() -> void:
	dirty = false


# --- undo ------------------------------------------------------------------------

## Starts an undo step: call once before the edits of one gesture.
func begin() -> void:
	_undo.append(_snapshot())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())


func _snapshot() -> Array:
	return [zones.duplicate(true), sides.duplicate(true), name, victory.duplicate(true)]


func _restore(snap: Array) -> void:
	zones.assign((snap[0] as Array).duplicate(true))
	sides.assign((snap[1] as Array).duplicate(true))
	name = snap[2]
	victory = (snap[3] as Dictionary).duplicate(true)
	_touch()


func _touch() -> void:
	dirty = true
	revision += 1


# --- zones -------------------------------------------------------------------------

## Adds a zone at a cell, with an id nothing else in the scenario uses.
## Returns its index.
func add_zone(x: int, y: int) -> int:
	var n := zones.size() + 1
	var zid := "zone_%d" % n
	while zones.any(func(z: Dictionary) -> bool: return z["id"] == zid):
		n += 1
		zid = "zone_%d" % n
	var z := {"id": zid, "x": x, "y": y}
	z.merge(ZONE_DEFAULTS)
	zones.append(z)
	_touch()
	return zones.size() - 1


func move_zone(i: int, x: int, y: int) -> void:
	if i < 0 or i >= zones.size() or (zones[i]["x"] == x and zones[i]["y"] == y):
		return
	zones[i]["x"] = x
	zones[i]["y"] = y
	_touch()


## Sets one of a zone's values ("id" takes text; the rest are whole
## numbers). Returns "" or why not.
func set_zone(i: int, key: String, value: Variant) -> String:
	if i < 0 or i >= zones.size():
		return "no such zone"
	if key == "id":
		var text := str(value).strip_edges()
		if text.is_empty():
			return "a zone needs an id"
		for j in zones.size():
			if j != i and zones[j]["id"] == text:
				return "another zone is already called '%s'" % text
		value = text
	else:
		value = int(value)
	if zones[i].get(key) != value:
		zones[i][key] = value
		_touch()
	return ""


func remove_zone(i: int) -> void:
	if i >= 0 and i < zones.size():
		zones.remove_at(i)
		_touch()


# --- sides -------------------------------------------------------------------------

## Adds a side for the lowest player number not yet used, with a small
## deployment area at a cell. Returns its index.
func add_side(x: int, y: int) -> int:
	var player := 1
	while sides.any(func(s: Dictionary) -> bool: return s["player"] == player):
		player += 1
	sides.append({"player": player, "facing": 0, "deploy": {"x": x, "y": y, "w": 12, "h": 20}, "squads": []})
	_touch()
	return sides.size() - 1


## Moves a side's deployment area so its top-left corner is at a cell.
func move_area(i: int, x: int, y: int) -> void:
	if i < 0 or i >= sides.size():
		return
	var d: Dictionary = sides[i]["deploy"]
	if d["x"] == x and d["y"] == y:
		return
	d["x"] = x
	d["y"] = y
	_touch()


func resize_area(i: int, w: int, h: int) -> void:
	if i < 0 or i >= sides.size():
		return
	var d: Dictionary = sides[i]["deploy"]
	w = maxi(w, 1)
	h = maxi(h, 1)
	if d["w"] == w and d["h"] == h:
		return
	d["w"] = w
	d["h"] = h
	_touch()


## Sets a side's "player" or "facing". Returns "" or why not.
func set_side(i: int, key: String, value: int) -> String:
	if i < 0 or i >= sides.size():
		return "no such side"
	if key == "player":
		if value < 1:
			return "players are numbered from 1"
		for j in sides.size():
			if j != i and sides[j]["player"] == value:
				return "player %d already has a side" % value
	if sides[i].get(key) != value:
		sides[i][key] = value
		_touch()
	return ""


func remove_side(i: int) -> void:
	if i >= 0 and i < sides.size():
		sides.remove_at(i)
		_touch()


func add_squad(i: int, squad: String) -> void:
	if i >= 0 and i < sides.size() and not squad.is_empty():
		(sides[i]["squads"] as Array).append(squad)
		_touch()


func remove_squad(i: int, at: int) -> void:
	if i >= 0 and i < sides.size() and at >= 0 and at < (sides[i]["squads"] as Array).size():
		(sides[i]["squads"] as Array).remove_at(at)
		_touch()


## What the victory setting `key` is now: the scenario's own value, else the
## one its template gives, else the default.
func victory_value(key: String) -> Variant:
	if victory.has(key):
		return victory[key]
	return flat_victory.get(key, VICTORY_DEFAULTS.get(key))


## Writes one victory setting of the scenario itself (turn limit, primary
## score, score target, annihilation, withdrawal). Returns "" or why not.
func set_victory(key: String, value: Variant) -> String:
	match key:
		"turn_limit":
			value = int(value)
			if value < 1:
				return "the turn limit is at least 1"
		"primary":
			value = str(value)
			if not VICTORY_PRIMARIES.has(value):
				return "the primary score is influence or value"
		"score_target":
			value = int(value)
			if value < 0:
				return "the score target is 0 or more (0 is none)"
		"annihilation", "withdrawal":
			value = bool(value)
		_:
			return "no victory setting '%s'" % key
	if not victory.has(key) or victory[key] != value:
		victory[key] = value
		_touch()
	return ""


func area_rect(i: int) -> Rect2i:
	var d: Dictionary = sides[i]["deploy"]
	return Rect2i(d["x"], d["y"], d["w"], d["h"])


## What is at a cell: {"kind": "zone" | "side", "index"}, or {}. A zone wins
## over an area under it; among zones, the one whose centre is nearest.
func object_at(x: int, y: int) -> Dictionary:
	var best := -1
	var best_d := 0
	for i in zones.size():
		var dx: int = x - int(zones[i]["x"])
		var dy: int = y - int(zones[i]["y"])
		var d := dx * dx + dy * dy
		var r := maxi(int(zones[i]["radius"]), 1)
		if d <= r * r and (best < 0 or d < best_d):
			best = i
			best_d = d
	if best >= 0:
		return {"kind": "zone", "index": best}
	for i in range(sides.size() - 1, -1, -1):
		if area_rect(i).has_point(Vector2i(x, y)):
			return {"kind": "side", "index": i}
	return {}


## What does not fit a map of w x h cells: zones centred off it and
## deployment areas not wholly inside it. Empty if all is well.
func problems(w: int, h: int) -> PackedStringArray:
	var out := PackedStringArray()
	for z in zones:
		if int(z["x"]) < 0 or int(z["y"]) < 0 or int(z["x"]) >= w or int(z["y"]) >= h:
			out.append("scenario '%s': zone '%s' is off the map (%d x %d)" % [id, z["id"], w, h])
	for i in sides.size():
		var r := area_rect(i)
		if r.position.x < 0 or r.position.y < 0 or r.size.x < 1 or r.size.y < 1 or r.end.x > w or r.end.y > h:
			out.append("scenario '%s': player %d's deployment area is not inside the map (%d x %d)" % [id, int(sides[i]["player"]), w, h])
	return out


# --- writing -----------------------------------------------------------------------

## The scenario's own values with the edited objects in them.
func values() -> Dictionary:
	var v: Dictionary = (_def.get("values", {}) as Dictionary).duplicate(true)
	v["name"] = name
	v["map"] = map_id
	v["zones"] = zones.duplicate(true)
	v["sides"] = sides.duplicate(true)
	if not victory.is_empty() or v.has("victory"):
		v["victory"] = victory.duplicate(true)
	return v


## The definition as text, laid out as the hand-written files are: one
## zone and one side per line.
func definition_text() -> String:
	var head := PackedStringArray()
	for k: String in _def:
		if k != "values":
			head.append("%s: %s" % [JSON.stringify(k), MapCanvas._json(_def[k])])
	var v := values()
	var lines := PackedStringArray()
	for k: String in v:
		match k:
			"zones":
				lines.append(_block("zones", zones.map(func(z: Dictionary) -> String: return MapCanvas._json(z))))
			"sides":
				lines.append(_block("sides", sides.map(func(s: Dictionary) -> String: return MapCanvas._json(s))))
			_:
				lines.append("\t\t\t%s: %s" % [JSON.stringify(k), MapCanvas._json(v[k])])
	return "{" + ", ".join(head) + ", \"values\": {\n" + ",\n".join(lines) + "}}"


static func _block(key: String, entries: Array) -> String:
	if entries.is_empty():
		return "\t\t\t\"%s\": []" % key
	var rows := PackedStringArray()
	for e: String in entries:
		rows.append("\t\t\t\t" + e)
	return "\t\t\t\"%s\": [\n%s\n\t\t\t]" % [key, ",\n".join(rows)]


## JSON numbers arrive as floats: positions and sizes are whole cells.
static func _ints(d: Dictionary) -> Dictionary:
	for k: Variant in d:
		if d[k] is float:
			d[k] = int(d[k])
	return d


static func _side(s: Dictionary) -> Dictionary:
	_ints(s)
	s["deploy"] = _ints((s.get("deploy", {"x": 0, "y": 0, "w": 1, "h": 1}) as Dictionary).duplicate())
	var squads := []
	for q: Variant in s.get("squads", []):
		squads.append(str(q))
	s["squads"] = squads
	return s
