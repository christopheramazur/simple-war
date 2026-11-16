@tool
class_name MapPainter
extends HSplitContainer
## The Maps tab of the War Data screen (GDD 04 §4.9, O1Q6): paints a
## `battle_map`'s terrain. Brush, rectangle, line, fill and pick tools, a
## facing per cell, mirror painting, stamps (another map placed as one
## object) and undo. The map itself is a MapCanvas; saving goes through
## PackageEditor, so a map that would break the package is refused.
##
## Mouse: left paints, right paints the base feature (or removes a stamp
## with the Stamp tool), middle drags the view, the wheel zooms.
## Keys (over the map): B R L F I S pick a tool, arrows set the facing,
## Backspace clears it, Ctrl+Z / Ctrl+Y undo and redo.

signal saved(map_id: String)

enum Tool { BRUSH, RECT, LINE, FILL, PICK, STAMP }

const TOOL_NAMES: PackedStringArray = ["Brush (B)", "Rectangle (R)", "Line (L)", "Fill (F)", "Pick (I)", "Stamp (S)"]
const MIRROR_NAMES: PackedStringArray = ["No mirror", "Left and right", "Top and bottom", "Four ways", "Half turn"]
const FACING_NAMES: PackedStringArray = ["No facing", "North", "East", "South", "West"]

var model: PackageEditor
var canvas: MapCanvas
var tool: int = Tool.BRUSH
## Index into canvas.features.
var feature: int = 0
var facing: int = 0
var brush: int = 1
var stamp_id: String = ""
var stamp_rotate: int = 0
## One colour per feature of `feature_ids`.
var feature_ids: PackedStringArray = PackedStringArray()
var colors: Array[Color] = []

var view: MapView
var _maps: OptionButton
var _new_id: LineEdit
var _new_w: SpinBox
var _new_h: SpinBox
var _tools: Array[Button] = []
var _brush: SpinBox
var _features: ItemList
var _facing: OptionButton
var _mirror: OptionButton
var _stamps: OptionButton
var _rotate: OptionButton
var _file: OptionButton
var _result: Label
var _status: Label
var _undo: Button
var _redo: Button


func _init() -> void:
	name = "Maps"
	_build()


## Uses a (re)loaded package. An open map with unsaved paint is kept.
func set_model(m: PackageEditor) -> void:
	model = m
	if model.templates == null:
		return
	feature_ids = PackedStringArray()
	colors = []
	for id in model.templates.ids():
		if model.templates.kind_of(id) == "feature" and not model.templates.is_abstract(id):
			feature_ids.append(id)
			colors.append(feature_color(id, model.templates.values_of(id)))
	_fill_lists()
	if canvas == null:
		return
	if canvas.dirty or model.file_of(canvas.id) == "":
		canvas.set_templates(model.templates)
	else:
		open_map(canvas.id)


## Opens a battle map of the package. Refused while the open map has
## unsaved changes (save or revert first). Returns whether it opened.
func open_map(id: String) -> bool:
	if canvas != null and canvas.dirty and canvas.id != id:
		_say("'%s' has unsaved changes: save it or revert it first." % canvas.id)
		_select_map(canvas.id)
		return false
	if model.file_of(id) == "" or model.templates.kind_of(id) != "battle_map":
		_say("No battle map '%s'." % id)
		return false
	var def: Variant = JSON.parse_string(model.definition_text(id))
	_use(MapCanvas.open(model.templates, def if def is Dictionary else {"id": id, "kind": "battle_map"}))
	_say("\n".join(canvas.notes))
	return true


## Starts a new map. It joins the package when it is saved.
func new_map(id: String, w: int, h: int, base_feature: String) -> bool:
	if canvas != null and canvas.dirty:
		_say("'%s' has unsaved changes: save it or revert it first." % canvas.id)
		return false
	if id.is_empty() or model.file_of(id) != "":
		_say("A new map needs an id nothing else uses.")
		return false
	_use(MapCanvas.create(model.templates, id, w, h, base_feature))
	_say("New map '%s'. It is added to %s when you save." % [id, _file.get_item_text(_file.selected)])
	return true


## Writes the map if the package stays valid with it. Returns the errors.
func save() -> PackedStringArray:
	if canvas == null:
		return PackedStringArray(["no map is open"])
	var id := canvas.id
	var text := canvas.definition_text()
	var errs: PackedStringArray
	if model.file_of(id) == "":
		errs = model.add(text, _file.get_item_text(_file.selected))
	else:
		errs = model.replace(id, text)
	if not errs.is_empty():
		_say("Not saved:\n" + "\n".join(errs))
		return errs
	canvas.mark_saved()
	saved.emit(id)
	set_model(model)
	_say("Saved '%s' to %s (%d shapes)." % [id, model.file_of(id), canvas.cells().size()])
	return errs


## Throws away unsaved changes.
func revert() -> void:
	if canvas == null:
		return
	var id := canvas.id
	canvas = null
	if model.file_of(id) != "":
		open_map(id)
	else:
		view.queue_redraw()
		_say("Dropped the unsaved map '%s'." % id)


func undo() -> void:
	if canvas != null:
		canvas.undo()
		changed()


func redo() -> void:
	if canvas != null:
		canvas.redo()
		changed()


func set_tool(t: int) -> void:
	tool = t
	for i in _tools.size():
		_tools[i].set_pressed_no_signal(i == t)
	view.queue_redraw()


func set_feature(index: int) -> void:
	feature = clampi(index, 0, maxi(feature_ids.size() - 1, 0))
	if feature < _features.item_count:
		_features.select(feature)


func set_facing(f: int) -> void:
	facing = f
	_facing.select(f)


## The view calls this after every edit.
func changed() -> void:
	_undo.disabled = canvas == null or not canvas.can_undo()
	_redo.disabled = canvas == null or not canvas.can_redo()
	view.queue_redraw()


## Text under the map: the cell under the mouse.
func show_cell(cell: Vector2i) -> void:
	if canvas == null or cell.x < 0 or cell.y < 0 or cell.x >= canvas.width or cell.y >= canvas.height:
		_status.text = ""
		return
	var comp := canvas.composite()
	var i := cell.y * canvas.width + cell.x
	var f: int = comp["feature"][i]
	var text := "%d, %d  ·  %s" % [cell.x, cell.y, feature_ids[f] if f >= 0 and f < feature_ids.size() else "?"]
	var fc: int = comp["facing"][i]
	if fc > 0:
		text += "  ·  facing " + FACING_NAMES[fc].to_lower()
	var s := canvas.stamp_at(cell.x, cell.y)
	if s >= 0:
		text += "  ·  stamp " + str(canvas.stamps[s]["stamp"])
	_status.text = text + ("    (unsaved)" if canvas.dirty else "")


## A feature's `color`, or a steady made-up one for features without it.
static func feature_color(id: String, values: Dictionary) -> Color:
	var c := str(values.get("color", ""))
	if Color.html_is_valid(c):
		return Color.html(c)
	return Color.from_hsv(float(absi(id.hash()) % 360) / 360.0, 0.35, 0.45)


# --- building ------------------------------------------------------------------

func _build() -> void:
	split_offset = 250
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(240, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)

	side.add_child(_heading("Map"))
	_maps = OptionButton.new()
	_maps.item_selected.connect(func(i: int) -> void: open_map(_maps.get_item_text(i)))
	side.add_child(_maps)
	var new_row := HBoxContainer.new()
	side.add_child(new_row)
	_new_id = LineEdit.new()
	_new_id.placeholder_text = "new_map_id"
	_new_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(_new_id)
	_new_w = _spin(8, 1000, 120)
	_new_w.tooltip_text = "Width in cells (1 cell = 1 m)"
	new_row.add_child(_new_w)
	_new_h = _spin(8, 1000, 80)
	_new_h.tooltip_text = "Height in cells"
	new_row.add_child(_new_h)
	var size_row := HBoxContainer.new()
	side.add_child(size_row)
	size_row.add_child(_button("New", func() -> void: new_map(_new_id.text.strip_edges(), int(_new_w.value), int(_new_h.value), feature_ids[feature] if feature < feature_ids.size() else ""),
		"Start a new map of this id and size, with the selected feature as its base"))
	size_row.add_child(_button("Resize", _resize, "Change the open map to the size above, keeping its top-left corner"))
	size_row.add_child(_button("Set base", _set_base, "Make the selected feature the open map's base"))

	side.add_child(_heading("Tool"))
	var grid := GridContainer.new()
	grid.columns = 2
	side.add_child(grid)
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = TOOL_NAMES[i]
		b.toggle_mode = true
		b.button_pressed = i == tool
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_tool.bind(i))
		grid.add_child(b)
		_tools.append(b)
	var brush_row := HBoxContainer.new()
	side.add_child(brush_row)
	var bl := Label.new()
	bl.text = "Brush size"
	brush_row.add_child(bl)
	_brush = _spin(1, 32, 1)
	_brush.value_changed.connect(func(v: float) -> void: brush = int(v))
	brush_row.add_child(_brush)
	_mirror = _options(MIRROR_NAMES, func(i: int) -> void:
		if canvas != null:
			canvas.mirror = i
		view.queue_redraw())
	side.add_child(_mirror)

	side.add_child(_heading("Feature"))
	_features = ItemList.new()
	_features.auto_height = true
	_features.item_selected.connect(func(i: int) -> void: feature = i)
	side.add_child(_features)
	_facing = _options(FACING_NAMES, func(i: int) -> void: facing = i)
	side.add_child(_facing)

	side.add_child(_heading("Stamp"))
	_stamps = OptionButton.new()
	_stamps.item_selected.connect(func(i: int) -> void:
		stamp_id = _stamps.get_item_text(i)
		set_tool(Tool.STAMP))
	side.add_child(_stamps)
	_rotate = _options(PackedStringArray(["Not turned", "Turned 90°", "Turned 180°", "Turned 270°"]), func(i: int) -> void:
		stamp_rotate = i * 90
		view.queue_redraw())
	side.add_child(_rotate)

	side.add_child(_heading("Save"))
	var undo_row := HBoxContainer.new()
	side.add_child(undo_row)
	_undo = _button("Undo", undo, "Ctrl+Z")
	undo_row.add_child(_undo)
	_redo = _button("Redo", redo, "Ctrl+Y")
	undo_row.add_child(_redo)
	undo_row.add_child(_button("Revert", revert, "Throw away unsaved changes"))
	var save_row := HBoxContainer.new()
	side.add_child(save_row)
	save_row.add_child(_button("Save map", save, "Checks the whole package with this map, then writes it"))
	_file = OptionButton.new()
	_file.tooltip_text = "The data file a new map is added to"
	_file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file.clip_text = true
	save_row.add_child(_file)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_result)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	view = MapView.new()
	view.painter = self
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(view)
	_status = Label.new()
	right.add_child(_status)
	changed()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("e6b450"))
	return l


func _button(text: String, action: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	return b


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	return s


func _options(names: PackedStringArray, action: Callable) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.item_selected.connect(action)
	return o


func _fill_lists() -> void:
	_maps.clear()
	_stamps.clear()
	for id in model.ids_of("battle_map"):
		_maps.add_item(id)
		_stamps.add_item(id)
	if canvas != null:
		_select_map(canvas.id)
	else:
		_maps.select(-1)
	if _stamps.item_count > 0:
		var at := maxi(_index_of(_stamps, stamp_id), 0)
		_stamps.select(at)
		stamp_id = _stamps.get_item_text(at)
	_features.clear()
	for i in feature_ids.size():
		var img := Image.create(14, 14, false, Image.FORMAT_RGB8)
		img.fill(colors[i])
		var label := str(model.templates.values_of(feature_ids[i]).get("name", feature_ids[i]))
		_features.add_item("%s  (%s)" % [label, feature_ids[i]], ImageTexture.create_from_image(img))
	set_feature(feature)
	var keep := _file.get_item_text(_file.selected) if _file.selected >= 0 else ""
	if keep.is_empty() and _maps.item_count > 0:
		keep = model.file_of(_maps.get_item_text(0))
	_file.clear()
	for f in model.files:
		_file.add_item(f)
	if _file.item_count > 0:
		_file.select(maxi(_index_of(_file, keep), 0))


func _index_of(o: OptionButton, text: String) -> int:
	for i in o.item_count:
		if o.get_item_text(i) == text:
			return i
	return -1


func _select_map(id: String) -> void:
	_maps.select(_index_of(_maps, id))


func _use(c: MapCanvas) -> void:
	# Saving reopens the same map: keep the zoom and position then.
	var same := canvas != null and canvas.id == c.id and canvas.width == c.width and canvas.height == c.height
	canvas = c
	canvas.mirror = _mirror.selected
	_new_w.value = c.width
	_new_h.value = c.height
	_select_map(c.id)
	if stamp_id == c.id:
		# A map can't stamp itself: offer another one.
		for i in _stamps.item_count:
			if _stamps.get_item_text(i) != c.id:
				_stamps.select(i)
				stamp_id = _stamps.get_item_text(i)
				break
	if not same:
		view.fit()
	changed()


func _resize() -> void:
	if canvas == null:
		return
	canvas.begin()
	canvas.resize(int(_new_w.value), int(_new_h.value))
	view.fit()
	changed()


func _set_base() -> void:
	if canvas == null:
		return
	canvas.begin()
	canvas.set_base(feature)
	changed()


func _say(text: String) -> void:
	_result.text = text


## The painted map: draws the canvas and turns the mouse into edits.
class MapView:
	extends Control

	const BG := Color("12151a")
	const GRID := Color(1, 1, 1, 0.08)
	const INK := Color("e6b450")
	const GRID_FROM := 6.0
	const ARROWS_FROM := 9.0

	var painter: MapPainter
	## Pixels per cell, and where the map's top-left corner is drawn.
	var zoom: float = 4.0
	var origin: Vector2 = Vector2.ZERO
	var hover: Vector2i = Vector2i(-1, -1)

	var _tex: ImageTexture
	var _tex_rev: int = -1
	var _tex_of: MapCanvas
	## The view shows the whole map until the user zooms or drags it.
	var _auto_fit: bool = true
	var _panning: bool = false
	var _stroke: bool = false
	var _start: Vector2i
	var _last: Vector2i
	var _f: int = 0
	var _fc: int = 0

	func _init() -> void:
		focus_mode = Control.FOCUS_CLICK
		clip_contents = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		custom_minimum_size = Vector2(200, 200)
		resized.connect(func() -> void:
			if _auto_fit:
				fit())

	## Shows the whole map.
	func fit() -> void:
		var c := painter.canvas
		_auto_fit = true
		if c == null or size.x < 32 or size.y < 32:
			return
		zoom = clampf(floorf(minf((size.x - 16) / c.width, (size.y - 16) / c.height)), 1.0, 32.0)
		origin = ((size - Vector2(c.width, c.height) * zoom) / 2.0).floor()
		queue_redraw()

	func cell_at(pos: Vector2) -> Vector2i:
		return Vector2i(((pos - origin) / zoom).floor())

	## One press at a cell with the painter's tool. `erase` is the right button.
	func press(cell: Vector2i, erase: bool) -> void:
		var c := painter.canvas
		if c == null:
			return
		_f = c.base if erase else painter.feature
		_fc = 0 if erase else painter.facing
		match painter.tool:
			MapPainter.Tool.BRUSH:
				c.begin()
				c.paint(cell.x, cell.y, _f, _fc, painter.brush)
				_stroke = true
				_last = cell
			MapPainter.Tool.RECT, MapPainter.Tool.LINE:
				_stroke = true
				_start = cell
			MapPainter.Tool.FILL:
				c.begin()
				c.fill(cell.x, cell.y, _f, _fc)
			MapPainter.Tool.PICK:
				if cell.x >= 0 and cell.y >= 0 and cell.x < c.width and cell.y < c.height:
					painter.set_feature(c.feat[cell.y * c.width + cell.x])
					painter.set_facing(c.face[cell.y * c.width + cell.x])
			MapPainter.Tool.STAMP:
				var at := c.stamp_at(cell.x, cell.y)
				if erase and at >= 0:
					c.begin()
					c.remove_stamp(at)
				elif not erase and not painter.stamp_id.is_empty() and cell.x >= 0 and cell.y >= 0:
					c.begin()
					var why := c.add_stamp(painter.stamp_id, cell.x, cell.y, painter.stamp_rotate)
					if not why.is_empty():
						c.undo()
						painter._say(why)
		painter.changed()

	func drag(cell: Vector2i) -> void:
		if _stroke and painter.tool == MapPainter.Tool.BRUSH and cell != _last:
			painter.canvas.line(_last.x, _last.y, cell.x, cell.y, _f, _fc, painter.brush)
			_last = cell
			painter.changed()

	func release(cell: Vector2i) -> void:
		var c := painter.canvas
		if _stroke and c != null:
			match painter.tool:
				MapPainter.Tool.RECT:
					c.begin()
					c.rect(_start.x, _start.y, cell.x, cell.y, _f, _fc)
				MapPainter.Tool.LINE:
					c.begin()
					c.line(_start.x, _start.y, cell.x, cell.y, _f, _fc, painter.brush)
		_stroke = false
		painter.changed()

	func _gui_input(e: InputEvent) -> void:
		if painter.canvas == null:
			return
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					if mb.pressed:
						var before := (mb.position - origin) / zoom
						zoom = clampf(zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 1.0, 48.0)
						origin = (mb.position - before * zoom).floor()
						_auto_fit = false
						queue_redraw()
				MOUSE_BUTTON_MIDDLE:
					_panning = mb.pressed
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
					if mb.pressed:
						grab_focus()
						press(cell_at(mb.position), mb.button_index == MOUSE_BUTTON_RIGHT)
					else:
						release(cell_at(mb.position))
			accept_event()
		elif e is InputEventMouseMotion:
			var mm := e as InputEventMouseMotion
			if _panning:
				origin += mm.relative
				_auto_fit = false
			hover = cell_at(mm.position)
			drag(hover)
			painter.show_cell(hover)
			queue_redraw()
		elif e is InputEventKey and (e as InputEventKey).pressed:
			if _key(e as InputEventKey):
				accept_event()

	func _key(k: InputEventKey) -> bool:
		if k.ctrl_pressed or k.meta_pressed:
			match k.keycode:
				KEY_Z:
					if k.shift_pressed:
						painter.redo()
					else:
						painter.undo()
				KEY_Y:
					painter.redo()
				_:
					return false
			return true
		match k.keycode:
			KEY_B: painter.set_tool(MapPainter.Tool.BRUSH)
			KEY_R: painter.set_tool(MapPainter.Tool.RECT)
			KEY_L: painter.set_tool(MapPainter.Tool.LINE)
			KEY_F: painter.set_tool(MapPainter.Tool.FILL)
			KEY_I: painter.set_tool(MapPainter.Tool.PICK)
			KEY_S: painter.set_tool(MapPainter.Tool.STAMP)
			KEY_UP: painter.set_facing(1)
			KEY_RIGHT: painter.set_facing(2)
			KEY_DOWN: painter.set_facing(3)
			KEY_LEFT: painter.set_facing(4)
			KEY_BACKSPACE: painter.set_facing(0)
			_: return false
		return true

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		var c := painter.canvas
		if c == null:
			var font := get_theme_default_font()
			draw_string(font, Vector2(16, 28), "Pick a map on the left, or give a new one an id and press New.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9aa3af"))
			return
		if _tex == null or _tex_of != c or _tex_rev != c.revision:
			_rebuild(c)
		var area := Rect2(origin, Vector2(c.width, c.height) * zoom)
		draw_texture_rect(_tex, area, false)
		var x0 := clampi(int(floorf(-origin.x / zoom)), 0, c.width)
		var x1 := clampi(int(ceilf((size.x - origin.x) / zoom)), 0, c.width)
		var y0 := clampi(int(floorf(-origin.y / zoom)), 0, c.height)
		var y1 := clampi(int(ceilf((size.y - origin.y) / zoom)), 0, c.height)
		if zoom >= GRID_FROM:
			for x in range(x0, x1 + 1):
				draw_line(origin + Vector2(x, y0) * zoom, origin + Vector2(x, y1) * zoom, GRID)
			for y in range(y0, y1 + 1):
				draw_line(origin + Vector2(x0, y) * zoom, origin + Vector2(x1, y) * zoom, GRID)
		if zoom >= ARROWS_FROM:
			var face: PackedByteArray = c.composite()["facing"]
			for y in range(y0, y1):
				for x in range(x0, x1):
					var fc := face[y * c.width + x]
					if fc > 0:
						_arrow(origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * zoom, fc)
		for i in c.stamps.size():
			var r := c.stamp_rect(i)
			draw_rect(Rect2(origin + Vector2(r.position) * zoom, Vector2(r.size) * zoom), Color(1, 1, 1, 0.55), false, 1.0)
		draw_rect(area.grow(1), Color(1, 1, 1, 0.35), false, 1.0)
		var mid := origin + Vector2(c.width, c.height) * zoom / 2.0
		if c.mirror in [MapCanvas.Mirror.LEFT_RIGHT, MapCanvas.Mirror.FOUR]:
			draw_dashed_line(Vector2(mid.x, area.position.y), Vector2(mid.x, area.end.y), INK, 1.0, 6.0)
		if c.mirror in [MapCanvas.Mirror.TOP_BOTTOM, MapCanvas.Mirror.FOUR]:
			draw_dashed_line(Vector2(area.position.x, mid.y), Vector2(area.end.x, mid.y), INK, 1.0, 6.0)
		if c.mirror == MapCanvas.Mirror.TURN:
			draw_arc(mid, 6.0, 0.0, TAU, 16, INK, 1.0)
		_draw_cursor(c)

	func _draw_cursor(c: MapCanvas) -> void:
		var from := hover
		var to := hover
		match painter.tool:
			MapPainter.Tool.RECT:
				if _stroke:
					from = _start
			MapPainter.Tool.LINE:
				if _stroke:
					draw_line(origin + (Vector2(_start) + Vector2(0.5, 0.5)) * zoom, origin + (Vector2(hover) + Vector2(0.5, 0.5)) * zoom, INK, 2.0)
			MapPainter.Tool.STAMP:
				to = hover + c.stamp_size(painter.stamp_id, painter.stamp_rotate) - Vector2i.ONE
			MapPainter.Tool.BRUSH:
				from = hover - Vector2i.ONE * ((painter.brush - 1) / 2)
				to = from + Vector2i.ONE * (painter.brush - 1)
		var lo := Vector2(mini(from.x, to.x), mini(from.y, to.y))
		var hi := Vector2(maxi(from.x, to.x) + 1, maxi(from.y, to.y) + 1)
		draw_rect(Rect2(origin + lo * zoom, (hi - lo) * zoom), INK, false, 1.0)

	func _arrow(at: Vector2, fc: int) -> void:
		var d: Vector2 = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][fc - 1]
		var tip := at + d * zoom * 0.32
		var side := Vector2(-d.y, d.x) * zoom * 0.18
		var ink := Color(1, 1, 1, 0.7)
		draw_line(at - d * zoom * 0.32, tip, ink, 1.0)
		draw_line(tip, tip - d * zoom * 0.22 + side, ink, 1.0)
		draw_line(tip, tip - d * zoom * 0.22 - side, ink, 1.0)

	func _rebuild(c: MapCanvas) -> void:
		var f: PackedInt32Array = c.composite()["feature"]
		var palette := PackedByteArray()
		for col in painter.colors:
			palette.append_array(PackedByteArray([col.r8, col.g8, col.b8]))
		var data := PackedByteArray()
		data.resize(c.width * c.height * 3)
		var known := painter.colors.size()
		for i in f.size():
			var p := f[i] * 3
			if f[i] >= 0 and f[i] < known:
				data[i * 3] = palette[p]
				data[i * 3 + 1] = palette[p + 1]
				data[i * 3 + 2] = palette[p + 2]
		_tex = ImageTexture.create_from_image(Image.create_from_data(c.width, c.height, false, Image.FORMAT_RGB8, data))
		_tex_of = c
		_tex_rev = c.revision
