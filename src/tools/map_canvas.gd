class_name MapCanvas
extends RefCounted
## The map painter's model (GDD 04 §4.9, O1Q6): one `battle_map` as a grid of
## painted cells with its stamps on top. It loads a map's shape list (Data
## Model §3.5), takes paint operations with mirroring and undo, and writes
## the shape list back: runs of the same feature and facing merged into
## rectangles in row order, then the stamps. No UI; MapPainter draws it.
##
## Stamps always draw above painted cells here. A hand-written map that fills
## over a stamp loads with a note and saves with the stamp on top.

enum Mirror { NONE, LEFT_RIGHT, TOP_BOTTOM, FOUR, TURN }

const UNDO_MAX := 64

var id: String = ""
var name: String = ""
var width: int = 0
var height: int = 0
## Indices into `features`.
var base: int = 0
var features: PackedStringArray = PackedStringArray()
## The painted layer: a feature index and a facing (0 none, 1 n, 2 e, 3 s,
## 4 w) per cell. A cell left as the base with no facing is not saved.
var feat: PackedInt32Array = PackedInt32Array()
var face: PackedByteArray = PackedByteArray()
## Stamp entries in file order: {"stamp", "x", "y", "rotate"}.
var stamps: Array[Dictionary] = []
var mirror: int = Mirror.NONE
var dirty: bool = false
## Goes up with every change, so a view knows when to redraw.
var revision: int = 0
## What loading changed or could not show.
var notes: PackedStringArray = PackedStringArray()
## The stamps the edit since the last `begin` turned into painted cells, so
## that paint could land on top of them (see `_flatten_at`).
var flattened: PackedStringArray = PackedStringArray()

var _t: TemplateTable
var _def: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _composite: Dictionary = {}
var _composite_rev: int = -1
## Stamped maps drawn on a grid, by "map@rotate" (see `_stamp_grid`).
var _grids: Dictionary = {}


## Opens an existing battle map. `def` is its definition as written (so
## fields this editor doesn't know are kept on save).
static func open(t: TemplateTable, def: Dictionary) -> MapCanvas:
	var c := MapCanvas.new()
	c._t = t
	c._def = def.duplicate(true)
	c.id = str(def.get("id", ""))
	c._list_features()
	var v := t.values_of(c.id)
	c.name = str(v.get("name", c.id))
	c.width = int(v["width"])
	c.height = int(v["height"])
	c.base = maxi(c.features.find(str(v["base"])), 0)
	c._clear()
	var stamped := false
	for e: Dictionary in v.get("cells", []):
		if e.has("stamp"):
			stamped = true
			c.stamps.append({"stamp": str(e["stamp"]), "x": int(e["x"]), "y": int(e["y"]), "rotate": int(e.get("rotate", 0))})
		elif e.has("feature"):
			if stamped and c.notes.is_empty():
				c.notes.append("This map paints over a stamp; the editor draws stamps on top and will save it that way.")
			var f := c.features.find(str(e["feature"]))
			var fc := DataSchema.FACINGS.find(str(e.get("facing", ""))) + 1
			for y in range(int(e["y"]), mini(int(e["y"]) + int(e.get("h", 1)), c.height)):
				for x in range(int(e["x"]), mini(int(e["x"]) + int(e.get("w", 1)), c.width)):
					c.feat[y * c.width + x] = f
					c.face[y * c.width + x] = fc
	return c


## A new, empty map. Not in the package until it is saved.
static func create(t: TemplateTable, map_id: String, w: int, h: int, base_feature: String) -> MapCanvas:
	var c := MapCanvas.new()
	c._t = t
	c._def = {"id": map_id, "kind": "battle_map", "values": {}}
	c.id = map_id
	c.name = map_id.capitalize()
	c._list_features()
	c.width = w
	c.height = h
	c.base = maxi(c.features.find(base_feature), 0)
	c._clear()
	c.dirty = true
	return c


## The package was reloaded: read stamps and features from the new table.
func set_templates(t: TemplateTable) -> void:
	_t = t
	_grids = {}
	revision += 1


func mark_saved() -> void:
	dirty = false


# --- painting --------------------------------------------------------------------

## Call once before each stroke or edit: everything until the next `begin`
## is one undo step.
func begin() -> void:
	flattened = PackedStringArray()
	_undo.append(_snapshot())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()


## A square brush `size` cells wide around x, y.
func paint(x: int, y: int, feature: int, facing: int, size: int = 1) -> void:
	var x0 := x - (size - 1) / 2
	var y0 := y - (size - 1) / 2
	for yy in size:
		for xx in size:
			_mark(x0 + xx, y0 + yy, feature, facing)


func rect(x0: int, y0: int, x1: int, y1: int, feature: int, facing: int) -> void:
	for y in range(maxi(mini(y0, y1), 0), mini(maxi(y0, y1), height - 1) + 1):
		for x in range(maxi(mini(x0, x1), 0), mini(maxi(x0, x1), width - 1) + 1):
			_mark(x, y, feature, facing)


## A line of brush marks from one cell to another.
func line(x0: int, y0: int, x1: int, y1: int, feature: int, facing: int, size: int = 1) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	# A line dragged far off the map still ends: it is at most this long.
	for _i in dx - dy + 1:
		paint(x, y, feature, facing, size)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


## Fills the cells joined to x, y (by an edge) that look the same as it,
## stamps included: what the map shows, not only the painted layer.
func fill(x: int, y: int, feature: int, facing: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var shown := composite()
	var sf: PackedInt32Array = shown["feature"]
	var sfc: PackedByteArray = shown["facing"]
	var start := y * width + x
	var f := sf[start]
	var fc := sfc[start]
	if f == feature and fc == facing:
		return
	var seen := PackedByteArray()
	seen.resize(width * height)
	var stack := PackedInt32Array([start])
	seen[start] = 1
	var region := PackedInt32Array()
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		region.append(i)
		var cx := i % width
		for n: int in [i - width, i + width, i - 1 if cx > 0 else -1, i + 1 if cx < width - 1 else -1]:
			if n >= 0 and n < seen.size() and seen[n] == 0 and sf[n] == f and sfc[n] == fc:
				seen[n] = 1
				stack.append(n)
	for i in region:
		_mark(i % width, i / width, feature, facing)


## Changes the map's size, keeping the top-left corner.
func resize(w: int, h: int) -> void:
	var nfeat := PackedInt32Array()
	nfeat.resize(w * h)
	nfeat.fill(base)
	var nface := PackedByteArray()
	nface.resize(w * h)
	for y in mini(h, height):
		for x in mini(w, width):
			nfeat[y * w + x] = feat[y * width + x]
			nface[y * w + x] = face[y * width + x]
	width = w
	height = h
	feat = nfeat
	face = nface
	_changed()


func set_base(feature: int) -> void:
	# Cells that were the old base stay what they look like.
	for i in feat.size():
		if feat[i] == base and face[i] == 0:
			feat[i] = feature
	base = feature
	_changed()


# --- stamps ----------------------------------------------------------------------

## Places another map as a stamp. Returns why not, or "".
func add_stamp(map_id: String, x: int, y: int, rotate: int) -> String:
	if map_id == id:
		return "a map can't stamp itself"
	if _t.kind_of(map_id) != "battle_map":
		return "'%s' is not a battle map" % map_id
	stamps.append({"stamp": map_id, "x": x, "y": y, "rotate": rotate})
	_changed()
	return ""


## The topmost stamp covering a cell, or -1.
func stamp_at(x: int, y: int) -> int:
	for i in range(stamps.size() - 1, -1, -1):
		if stamp_rect(i).has_point(Vector2i(x, y)):
			return i
	return -1


func remove_stamp(index: int) -> void:
	stamps.remove_at(index)
	_changed()


func stamp_rect(index: int) -> Rect2i:
	var s := stamps[index]
	return Rect2i(Vector2i(s["x"], s["y"]), stamp_size(s["stamp"], s["rotate"]))


## A map's size when stamped with a rotation.
func stamp_size(map_id: String, rotate: int) -> Vector2i:
	if _t.kind_of(map_id) != "battle_map":
		return Vector2i.ONE
	var v := _t.values_of(map_id)
	var s := Vector2i(int(v["width"]), int(v["height"]))
	return Vector2i(s.y, s.x) if rotate % 180 != 0 else s


# --- undo ------------------------------------------------------------------------

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


# --- reading ---------------------------------------------------------------------

## What the game will see: the painted layer with the stamps on top.
## {"feature": PackedInt32Array, "facing": PackedByteArray}. Don't change it.
func composite() -> Dictionary:
	if _composite_rev == revision:
		return _composite
	var cf := feat.duplicate()
	var cface := face.duplicate()
	for s in stamps:
		var grid := _stamp_grid(s)
		if grid.is_empty():
			continue
		var sw: int = grid["w"]
		var sfeat: PackedInt32Array = grid["feature"]
		var sface: PackedByteArray = grid["facing"]
		for sy in int(grid["h"]):
			var y := int(s["y"]) + sy
			if y < 0 or y >= height:
				continue
			for sx in sw:
				var x := int(s["x"]) + sx
				if x >= 0 and x < width and sfeat[sy * sw + sx] >= 0:
					cf[y * width + x] = sfeat[sy * sw + sx]
					cface[y * width + x] = sface[sy * sw + sx]
	_composite = {"feature": cf, "facing": cface}
	_composite_rev = revision
	return _composite


## The map's shape list: painted cells merged into rectangles in row order,
## then the stamps.
func cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var done := PackedByteArray()
	done.resize(width * height)
	for y in height:
		for x in width:
			var i := y * width + x
			if done[i] == 1 or (feat[i] == base and face[i] == 0):
				continue
			var f := feat[i]
			var fc := face[i]
			var w := 1
			while x + w < width and done[i + w] == 0 and feat[i + w] == f and face[i + w] == fc:
				w += 1
			var h := 1
			while y + h < height and _row_is(x, y + h, w, f, fc, done):
				h += 1
			for yy in h:
				for xx in w:
					done[(y + yy) * width + x + xx] = 1
			var e := {"feature": features[f], "x": x, "y": y}
			if w > 1:
				e["w"] = w
			if h > 1:
				e["h"] = h
			if fc > 0:
				e["facing"] = DataSchema.FACINGS[fc - 1]
			out.append(e)
	for s in stamps:
		var e := {"stamp": s["stamp"], "x": s["x"], "y": s["y"]}
		if int(s["rotate"]) != 0:
			e["rotate"] = s["rotate"]
		out.append(e)
	return out


## The template's definition text, laid out like the hand-written data files
## (one shape per line), ready for PackageEditor.replace or add.
func definition_text() -> String:
	var head := PackedStringArray()
	for k: String in _def:
		if k != "values":
			head.append("%s: %s" % [JSON.stringify(k), _json(_def[k])])
	var lines := PackedStringArray()
	lines.append("\"name\": %s," % _json(name))
	lines.append("\"width\": %d, \"height\": %d, \"base\": %s," % [width, height, _json(features[base])])
	var v: Dictionary = _def.get("values", {})
	for k: String in v:
		if not k in ["name", "width", "height", "base", "cells"]:
			lines.append("%s: %s," % [JSON.stringify(k), _json(v[k])])
	var text := "{" + ", ".join(head) + ", \"values\": {\n"
	for l in lines:
		text += "\t\t\t" + l + "\n"
	var entries := PackedStringArray()
	for e in cells():
		entries.append("\t\t\t\t" + _json(e))
	if entries.is_empty():
		return text + "\t\t\t\"cells\": []}}"
	return text + "\t\t\t\"cells\": [\n" + ",\n".join(entries) + "\n\t\t\t]}}"


# --- internals -------------------------------------------------------------------

func _list_features() -> void:
	features = PackedStringArray()
	for fid in _t.ids():
		if _t.kind_of(fid) == "feature" and not _t.is_abstract(fid):
			features.append(fid)


func _clear() -> void:
	feat = PackedInt32Array()
	feat.resize(width * height)
	feat.fill(base)
	face = PackedByteArray()
	face.resize(width * height)
	stamps = []


func _changed() -> void:
	dirty = true
	revision += 1


func _mark(x: int, y: int, feature: int, facing: int) -> void:
	_put(x, y, feature, facing)
	match mirror:
		Mirror.LEFT_RIGHT:
			_put(width - 1 - x, y, feature, _flip_x(facing))
		Mirror.TOP_BOTTOM:
			_put(x, height - 1 - y, feature, _flip_y(facing))
		Mirror.FOUR:
			_put(width - 1 - x, y, feature, _flip_x(facing))
			_put(x, height - 1 - y, feature, _flip_y(facing))
			_put(width - 1 - x, height - 1 - y, feature, _flip_x(_flip_y(facing)))
		Mirror.TURN:
			_put(width - 1 - x, height - 1 - y, feature, _flip_x(_flip_y(facing)))


func _put(x: int, y: int, feature: int, facing: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	if not stamps.is_empty():
		_flatten_at(x, y)
	var i := y * width + x
	if feat[i] == feature and face[i] == facing:
		return
	feat[i] = feature
	face[i] = facing
	_changed()


static func _flip_x(facing: int) -> int:
	return 4 if facing == 2 else 2 if facing == 4 else facing


static func _flip_y(facing: int) -> int:
	return 3 if facing == 1 else 1 if facing == 3 else facing


func _row_is(x: int, y: int, w: int, f: int, fc: int, done: PackedByteArray) -> bool:
	for xx in w:
		var i := y * width + x + xx
		if done[i] == 1 or feat[i] != f or face[i] != fc:
			return false
	return true


func _snapshot() -> Dictionary:
	return {"feat": feat.duplicate(), "face": face.duplicate(), "stamps": stamps.duplicate(true),
		"width": width, "height": height, "base": base}


func _restore(s: Dictionary) -> void:
	feat = s["feat"]
	face = s["face"]
	stamps = s["stamps"]
	width = s["width"]
	height = s["height"]
	base = s["base"]
	_changed()


## Paint lands on top: if a stamp shows at x, y, that stamp becomes painted
## cells first, with every stamp below it that it overlaps (so nothing that
## was hidden under it shows through), and the edit paints over them. The
## names go in `flattened`; undo brings the stamps back.
func _flatten_at(x: int, y: int) -> void:
	var hit := -1
	for i in range(stamps.size() - 1, -1, -1):
		if _stamp_paints(i, x, y):
			hit = i
			break
	if hit < 0:
		return
	var take := {hit: true}
	var grew := true
	while grew:
		grew = false
		for j in hit:
			if take.has(j):
				continue
			for k: int in take:
				if k > j and stamp_rect(j).intersects(stamp_rect(k)):
					take[j] = true
					grew = true
					break
	var order: Array = take.keys()
	order.sort()
	for i: int in order:
		var s := stamps[i]
		var grid := _stamp_grid(s)
		if grid.is_empty():
			continue
		var sw: int = grid["w"]
		var sfeat: PackedInt32Array = grid["feature"]
		var sface: PackedByteArray = grid["facing"]
		for sy in int(grid["h"]):
			var yy := int(s["y"]) + sy
			if yy < 0 or yy >= height:
				continue
			for sx in sw:
				var xx := int(s["x"]) + sx
				if xx >= 0 and xx < width and sfeat[sy * sw + sx] >= 0:
					feat[yy * width + xx] = sfeat[sy * sw + sx]
					face[yy * width + xx] = sface[sy * sw + sx]
	order.reverse()
	for i: int in order:
		flattened.append(str(stamps[i]["stamp"]))
		stamps.remove_at(i)
	_changed()


## Whether stamp `index` paints the cell x, y (its own cells, not the gaps).
func _stamp_paints(index: int, x: int, y: int) -> bool:
	var s := stamps[index]
	if not stamp_rect(index).has_point(Vector2i(x, y)):
		return false
	var grid := _stamp_grid(s)
	if grid.is_empty():
		return false
	return (grid["feature"] as PackedInt32Array)[(y - int(s["y"])) * int(grid["w"]) + x - int(s["x"])] >= 0


## A stamp entry's map drawn on a grid and turned, as the composite places
## it. Empty if it can't be drawn.
func _stamp_grid(s: Dictionary) -> Dictionary:
	var key := "%s@%d" % [s["stamp"], int(s["rotate"])]
	if not _grids.has(key):
		var grid := _raster(s["stamp"], PackedStringArray([id]))
		_grids[key] = {} if grid.is_empty() else BattleRules._turned(grid, int(s["rotate"]) / 90)
	return _grids[key]


## Another map's own entries on a grid of its size, as BattleRules draws a
## stamp: -1 where it paints nothing. Empty if it can't be drawn.
func _raster(map_id: String, chain: PackedStringArray) -> Dictionary:
	if chain.has(map_id) or chain.size() > BattleRules.MAX_STAMP_DEPTH or _t.kind_of(map_id) != "battle_map":
		return {}
	var m := _t.values_of(map_id)
	var w := int(m["width"])
	var h := int(m["height"])
	var gf := PackedInt32Array()
	gf.resize(w * h)
	gf.fill(-1)
	var gface := PackedByteArray()
	gface.resize(w * h)
	var inner := chain.duplicate()
	inner.append(map_id)
	for c: Dictionary in m.get("cells", []):
		if c.has("feature"):
			var f := features.find(str(c["feature"]))
			var fc := DataSchema.FACINGS.find(str(c.get("facing", ""))) + 1
			for y in range(int(c["y"]), mini(int(c["y"]) + int(c.get("h", 1)), h)):
				for x in range(int(c["x"]), mini(int(c["x"]) + int(c.get("w", 1)), w)):
					gf[y * w + x] = f
					gface[y * w + x] = fc
		elif c.has("stamp"):
			var stamp := _raster(str(c["stamp"]), inner)
			if stamp.is_empty():
				continue
			stamp = BattleRules._turned(stamp, int(c.get("rotate", 0)) / 90)
			var sw: int = stamp["w"]
			var sfeat: PackedInt32Array = stamp["feature"]
			var sface: PackedByteArray = stamp["facing"]
			for sy in int(stamp["h"]):
				var y := int(c["y"]) + sy
				if y >= h:
					break
				for sx in sw:
					var x := int(c["x"]) + sx
					if x < w and sfeat[sy * sw + sx] >= 0:
						gf[y * w + x] = sfeat[sy * sw + sx]
						gface[y * w + x] = sface[sy * sw + sx]
	return {"w": w, "h": h, "feature": gf, "facing": gface}


## JSON on one line with spaces after separators, keys in the order given,
## and whole numbers written without a decimal point.
static func _json(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k: Variant in v:
				parts.append("%s: %s" % [JSON.stringify(str(k)), _json(v[k])])
			return "{" + ", ".join(parts) + "}"
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item: Variant in v:
				parts.append(_json(item))
			return "[" + ", ".join(parts) + "]"
		TYPE_FLOAT:
			return str(int(v)) if v == floorf(v) else JSON.stringify(v)
	return JSON.stringify(v)
