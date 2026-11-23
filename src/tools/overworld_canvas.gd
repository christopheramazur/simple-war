class_name OverworldCanvas
extends RefCounted
## The map painter's model for an `overworld_map` (GDD 04 §4.9, sw-96x): the
## passes of Data Model §3.3 as something to paint. No UI.
##
## What the editor holds:
## - `fills`: the features every hex starts with (the `fill` passes).
## - `ground`: one painted feature per hex on top of that, or -1 (the `rect`
##   and `line` passes load into it, a line as the hexes it covers).
## - `objects`: the `place` passes, and any owned rect or line hex: a feature
##   on a hex, with an owner.
## - `starts`: each player's starting commanders.
## Saved as fills, then painted ground as merged rectangles, then objects,
## then any pass the editor can't edit (a `scatter`) kept as written, then
## starts. On a `mirror` map the author makes one half: `partner` is the hex
## the generator repeats a thing on, with players 1 and 2 swapped.

const UNDO_MAX := 64

var id: String = ""
var name: String = ""
var width: int = 0
var height: int = 0
var mirror: bool = false
var features: PackedStringArray = PackedStringArray()
var fills: PackedStringArray = PackedStringArray()
## Indices into `features`, per hex (row * width + col); -1 is nothing.
var ground: PackedInt32Array = PackedInt32Array()
## [{"feature": String, "col", "row", "owner"}] in file order.
var objects: Array[Dictionary] = []
## [{"player", "commander", "col", "row"}] in file order.
var starts: Array[Dictionary] = []
var dirty: bool = false
## Goes up with every change, so a view knows when to redraw.
var revision: int = 0
## What loading changed or could not show.
var notes: PackedStringArray = PackedStringArray()

var _t: TemplateTable
var _def: Dictionary = {}
var _extra: Array[Dictionary] = []
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


## Opens an existing overworld map. `def` is its definition as written (so
## fields this editor doesn't know are kept on save).
static func open(t: TemplateTable, def: Dictionary) -> OverworldCanvas:
	var c := OverworldCanvas.new()
	c._t = t
	c._def = def.duplicate(true)
	c.id = str(def.get("id", ""))
	c._list_features()
	var v := t.values_of(c.id)
	c.name = str(v.get("name", c.id))
	c.width = int(v["width"])
	c.height = int(v["height"])
	c.mirror = bool(v.get("mirror", false))
	c._clear()
	var overlap := false
	for p: Dictionary in v.get("passes", []):
		var f := c.features.find(str(p.get("feature", "")))
		match str(p.get("op", "")):
			"fill":
				c.fills.append(str(p["feature"]))
			"rect":
				for row in range(int(p["row"]), mini(int(p["row"]) + int(p.get("h", 1)), c.height)):
					for col in range(int(p["col"]), mini(int(p["col"]) + int(p.get("w", 1)), c.width)):
						overlap = c._load_ground(col, row, f, p) or overlap
			"line":
				var a := Hex.plot(int(p["col"]), int(p["row"]), c.width)
				var b := Hex.plot(int(p["to_col"]), int(p["to_row"]), c.width)
				for plot in Hex.line(a, b, c.width, c.height):
					if plot >= 0:
						overlap = c._load_ground(plot % c.width, plot / c.width, f, p) or overlap
			"place":
				c.objects.append({"feature": str(p["feature"]), "col": int(p["col"]), "row": int(p["row"]), "owner": int(p.get("owner", 0))})
			_:
				c._extra.append(p.duplicate(true))
	if overlap:
		c.notes.append("Some rect or line passes overlap; the editor keeps the last feature painted on a hex.")
	if not c._extra.is_empty():
		c.notes.append("Scatter passes are kept as written and saved after the painted hexes.")
	for s: Dictionary in v.get("starts", []):
		c.starts.append({"player": int(s["player"]), "commander": str(s["commander"]), "col": int(s["col"]), "row": int(s["row"])})
	return c


## A new, empty map filled with one feature. Not in the package until saved.
static func create(t: TemplateTable, map_id: String, w: int, h: int, base_feature: String) -> OverworldCanvas:
	var c := OverworldCanvas.new()
	c._t = t
	c._def = {"id": map_id, "kind": "overworld_map", "values": {}}
	c.id = map_id
	c.name = map_id.capitalize()
	c._list_features()
	c.width = w
	c.height = h
	c.fills.append(base_feature)
	c._clear()
	c.dirty = true
	return c


func set_templates(t: TemplateTable) -> void:
	_t = t
	revision += 1


func mark_saved() -> void:
	dirty = false
	revision += 1


func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and row >= 0 and col < width and row < height


## The hex the generator repeats a hex on (a half turn), or the hex itself
## when the map isn't a mirror map.
func partner(col: int, row: int) -> Vector2i:
	if not mirror:
		return Vector2i(col, row)
	return Vector2i(width - 1 - col, height - 1 - row)


## The feature index painted on a hex, or -1.
func ground_at(col: int, row: int) -> int:
	return ground[row * width + col] if in_bounds(col, row) else -1


## Every feature a hex shows, in drawing order: its fills, its painted
## feature, then the objects on it.
func features_at(col: int, row: int) -> PackedStringArray:
	var out := PackedStringArray(fills)
	var g := ground_at(col, row)
	if g >= 0:
		out.append(features[g])
	for o in objects:
		if o["col"] == col and o["row"] == row:
			out.append(o["feature"])
	return out


# --- painting ----------------------------------------------------------------

## Call once before each stroke or edit: everything until the next `begin`
## is one undo step.
func begin() -> void:
	_undo.append(_snapshot())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()


## Paints a feature (-1 clears the hex) on a hex and every hex within
## `radius` of it. On a mirror map the view paints the `partner` too.
func paint(col: int, row: int, feature: int, radius: int = 0) -> void:
	if not in_bounds(col, row):
		return
	for plot in Hex.within(Hex.plot(col, row, width), radius, width, height):
		_put(plot % width, plot / width, feature)
	_changed()


func rect(col0: int, row0: int, col1: int, row1: int, feature: int) -> void:
	for row in range(maxi(mini(row0, row1), 0), mini(maxi(row0, row1), height - 1) + 1):
		for col in range(maxi(mini(col0, col1), 0), mini(maxi(col0, col1), width - 1) + 1):
			_put(col, row, feature)
	_changed()


## A hex line between two hexes.
func line(col0: int, row0: int, col1: int, row1: int, feature: int) -> void:
	if not in_bounds(col0, row0) or not in_bounds(col1, row1):
		return
	for plot in Hex.line(Hex.plot(col0, row0, width), Hex.plot(col1, row1, width), width, height):
		if plot >= 0:
			_put(plot % width, plot / width, feature)
	_changed()


## Fills the hexes joined to this one that hold the same painted feature.
func fill(col: int, row: int, feature: int) -> void:
	if not in_bounds(col, row):
		return
	var old := ground_at(col, row)
	if old == feature:
		return
	var todo: Array[int] = [Hex.plot(col, row, width)]
	while not todo.is_empty():
		var p: int = todo.pop_back()
		if ground[p] != old:
			continue
		ground[p] = feature
		for n in Hex.neighbours(p, width, height):
			todo.append(n)
	_changed()


## Changes the map's size, keeping the top-left corner. Objects and starts
## that fall off it are dropped.
func resize(w: int, h: int) -> void:
	var g := PackedInt32Array()
	g.resize(w * h)
	g.fill(-1)
	for row in mini(h, height):
		for col in mini(w, width):
			g[row * w + col] = ground[row * width + col]
	width = w
	height = h
	ground = g
	objects = objects.filter(func(o: Dictionary) -> bool: return in_bounds(o["col"], o["row"]))
	starts = starts.filter(func(s: Dictionary) -> bool: return in_bounds(s["col"], s["row"]))
	_changed()


# --- objects -----------------------------------------------------------------

## Places a feature with an owner on a hex. Returns why not, or "". A hex
## holds one of each feature, so placing it again changes its owner.
func place(feature: String, col: int, row: int, owner: int = 0) -> String:
	if not in_bounds(col, row):
		return "off the map"
	if not features.has(feature):
		return "unknown feature '%s'" % feature
	var at := object_at(col, row, feature)
	if at >= 0:
		objects[at]["owner"] = owner
	else:
		objects.append({"feature": feature, "col": col, "row": row, "owner": owner})
	_changed()
	return ""


## Index of the object on a hex, of this feature if one is given, else the
## topmost (last placed). -1 for none.
func object_at(col: int, row: int, feature: String = "") -> int:
	for i in range(objects.size() - 1, -1, -1):
		var o := objects[i]
		if o["col"] == col and o["row"] == row and (feature.is_empty() or o["feature"] == feature):
			return i
	return -1


func set_owner(index: int, owner: int) -> void:
	objects[index]["owner"] = owner
	_changed()


func move_object(index: int, col: int, row: int) -> String:
	if not in_bounds(col, row):
		return "off the map"
	var dup := object_at(col, row, objects[index]["feature"])
	if dup >= 0 and dup != index:
		return "that hex already has one"
	objects[index]["col"] = col
	objects[index]["row"] = row
	_changed()
	return ""


func remove_object(index: int) -> void:
	objects.remove_at(index)
	_changed()


func add_start(player: int, commander: String, col: int, row: int) -> String:
	if not in_bounds(col, row):
		return "off the map"
	starts.append({"player": player, "commander": commander, "col": col, "row": row})
	_changed()
	return ""


## Index of the first start on a hex, or -1.
func start_at(col: int, row: int) -> int:
	for i in starts.size():
		if starts[i]["col"] == col and starts[i]["row"] == row:
			return i
	return -1


func move_start(index: int, col: int, row: int) -> String:
	if not in_bounds(col, row):
		return "off the map"
	starts[index]["col"] = col
	starts[index]["row"] = row
	_changed()
	return ""


func remove_start(index: int) -> void:
	starts.remove_at(index)
	_changed()


## What a mirror map's generator adds from the hand-made half: the partner
## of every object and start, players 1 and 2 swapped. For drawing the other
## half as ghosts. Empty lists on a map that doesn't mirror.
func ghosts() -> Dictionary:
	var out := {"objects": [], "starts": []}
	if not mirror:
		return out
	for o in objects:
		var p := partner(o["col"], o["row"])
		out["objects"].append({"feature": o["feature"], "col": p.x, "row": p.y, "owner": OverworldRules.mirror_player(o["owner"])})
	for s in starts:
		var p := partner(s["col"], s["row"])
		out["starts"].append({"player": OverworldRules.mirror_player(s["player"]), "commander": s["commander"], "col": p.x, "row": p.y})
	return out


# --- undo --------------------------------------------------------------------

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


# --- saving ------------------------------------------------------------------

## The map's pass list: fills, painted hexes merged into rectangles in row
## order, objects, then the passes the editor keeps as written.
func passes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in fills:
		out.append({"op": "fill", "feature": f})
	var done := PackedByteArray()
	done.resize(width * height)
	for row in height:
		var col := 0
		while col < width:
			var g := ground[row * width + col]
			if g < 0 or done[row * width + col] != 0:
				col += 1
				continue
			var run := 1
			while col + run < width and ground[row * width + col + run] == g and done[row * width + col + run] == 0:
				run += 1
			var rows := 1
			while row + rows < height and _same_run(done, col, row + rows, run, g):
				rows += 1
			for r in rows:
				for k in run:
					done[(row + r) * width + col + k] = 1
			out.append({"op": "rect", "feature": features[g], "col": col, "row": row, "w": run, "h": rows})
			col += run
	for o in objects:
		var p := {"op": "place", "feature": o["feature"], "col": o["col"], "row": o["row"]}
		if o["owner"] != 0:
			p["owner"] = o["owner"]
		out.append(p)
	out.append_array(_extra)
	return out


## The template's definition text, laid out like the hand-written data files
## (one pass per line), ready for PackageEditor.replace or add.
func definition_text() -> String:
	var head := PackedStringArray()
	for k: String in _def:
		if k != "values":
			head.append("%s: %s" % [JSON.stringify(k), MapCanvas._json(_def[k])])
	var v: Dictionary = _def.get("values", {})
	var text := "{" + ", ".join(head) + ", \"values\": {\n"
	text += "\t\t\t\"name\": %s,\n" % MapCanvas._json(name)
	text += "\t\t\t\"width\": %d, \"height\": %d,\n" % [width, height]
	for k: String in v:
		if not k in ["name", "width", "height", "passes", "starts"]:
			text += "\t\t\t%s: %s,\n" % [JSON.stringify(k), MapCanvas._json(v[k])]
	var entries := PackedStringArray()
	for e in passes():
		entries.append("\t\t\t\t" + MapCanvas._json(e))
	text += "\t\t\t\"passes\": [\n" + ",\n".join(entries) + "\n\t\t\t]"
	if not starts.is_empty():
		var ss := PackedStringArray()
		for s in starts:
			ss.append("\t\t\t\t" + MapCanvas._json(s))
		text += ",\n\t\t\t\"starts\": [\n" + ",\n".join(ss) + "\n\t\t\t]"
	return text + "}}"


# --- internals ---------------------------------------------------------------

func _list_features() -> void:
	features = PackedStringArray()
	for fid in _t.ids():
		if _t.kind_of(fid) == "hex_feature" and not _t.is_abstract(fid):
			features.append(fid)


func _clear() -> void:
	ground = PackedInt32Array()
	ground.resize(width * height)
	ground.fill(-1)


## Loads one hex of a rect or line pass. An owned pass becomes an object so
## the owner survives. Returns whether it overwrote a different feature.
func _load_ground(col: int, row: int, f: int, p: Dictionary) -> bool:
	if not in_bounds(col, row):
		return false
	if int(p.get("owner", 0)) != 0:
		objects.append({"feature": str(p["feature"]), "col": col, "row": row, "owner": int(p["owner"])})
		return false
	var i := row * width + col
	var was := ground[i] >= 0 and ground[i] != f
	ground[i] = f
	return was


func _put(col: int, row: int, feature: int) -> void:
	if in_bounds(col, row):
		ground[row * width + col] = feature


## Whether row `row` holds exactly this run at `col` (no wider, nothing
## already written), so a rectangle can grow down over it.
func _same_run(done: PackedByteArray, col: int, row: int, run: int, g: int) -> bool:
	for k in run:
		if ground[row * width + col + k] != g or done[row * width + col + k] != 0:
			return false
	if col + run < width and ground[row * width + col + run] == g and done[row * width + col + run] == 0:
		return false
	return true


func _changed() -> void:
	dirty = true
	revision += 1


func _snapshot() -> Dictionary:
	return {"ground": ground.duplicate(), "objects": objects.duplicate(true), "starts": starts.duplicate(true), "w": width, "h": height}


func _restore(s: Dictionary) -> void:
	ground = s["ground"]
	objects.assign(s["objects"])
	starts.assign(s["starts"])
	width = s["w"]
	height = s["h"]
	_changed()
