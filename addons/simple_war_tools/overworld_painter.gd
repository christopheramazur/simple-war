@tool
class_name OverworldPainter
extends HSplitContainer
## The World maps tab of the War Data screen (GDD 04 §4.9, sw-7ii): paints
## an `overworld_map` on its hexes. The map is an OverworldCanvas; saving
## goes through PackageEditor, so a map that would break the package is
## refused. A tab of its own beside Maps (battle maps), so each painter
## keeps its own tools and the battle painter does not grow a hex mode.
##
## Tools: Brush (a hex and its neighbours out to the brush radius), Hex
## rectangle, Hex line, Fill (the joined hexes painted alike) and Pick paint
## the ground; the right button clears the painted feature, leaving the
## map's fills. Place puts the chosen feature on a hex as an object with the
## chosen owner (a village of player 1); Start adds the chosen player's
## starting commander. With Place or Start, click an object or start to
## select it and drag to move it; the right button removes the one under
## the mouse, Delete the selected one.
##
## Mirror maps (Data Model §3.3): the generator repeats every pass and start
## on the hex turned half a turn, players 1 and 2 swapped. Painting ground
## paints both halves, so the view shows what the game makes; objects and
## starts are made on one half and their partners drawn as faint ghosts.
##
## Map: name, `elimination` (a skirmish won by defeating every other team's
## commanders) and `mirror`, each one undo step; resize keeps the top-left.
##
## Mouse: middle drags the view, the wheel zooms. Keys (over the map):
## B R L F I P T pick a tool, Delete removes the selection, Ctrl+Z / Ctrl+Y
## undo and redo.

signal saved(map_id: String)

enum Tool { BRUSH, RECT, LINE, FILL, PICK, PLACE, START }

const TOOL_NAMES: PackedStringArray = ["Brush (B)", "Rectangle (R)", "Line (L)", "Fill (F)", "Pick (I)", "Place (P)", "Start (T)"]
const TOOL_TIPS: PackedStringArray = [
	"Left paints the feature on a hex and its neighbours out to the radius; right clears the painted feature",
	"Drag a block of rows and columns of the feature (right button: clear)",
	"Drag a hex line of the feature (right button: clear)",
	"Fill the joined hexes painted alike (right button: clear)",
	"Pick the feature under the cursor",
	"Place the feature as an object with the owner; click one to select or drag it, right-click to remove",
	"Add the player's starting commander; click one to select or drag it, right-click to remove",
]
const OWNER_NAMES: PackedStringArray = ["Neutral", "Player 1", "Player 2", "Player 3", "Player 4"]

var model: PackageEditor
var canvas: OverworldCanvas
var tool: int = Tool.BRUSH
## Index into canvas.features (the package's hex features).
var feature: int = 0
var radius: int = 0
## Owner for Place, player for Start (Start uses player 1 for neutral).
var owner_player: int = 0
var commander: String = ""
## The selected object or start: {"kind": "object" | "start", "index"}, or {}.
var selected: Dictionary = {}
var feature_ids: PackedStringArray = PackedStringArray()
var colors: Array[Color] = []
var commander_ids: PackedStringArray = PackedStringArray()

var view: HexView
var _maps: OptionButton
var _new_id: LineEdit
var _new_w: SpinBox
var _new_h: SpinBox
var _name: LineEdit
var _elimination: CheckBox
var _mirror: CheckBox
var _tools: Array[Button] = []
var _radius: SpinBox
var _features: ItemList
var _owner: OptionButton
var _commanders: OptionButton
var _object_box: VBoxContainer
var _file: OptionButton
var _result: Label
var _status: Label
var _undo: Button
var _redo: Button
## A drag in progress: where it began, and whether it is a stroke (paint),
## a held object or start (move), and the feature it paints.
var _stroke: bool = false
var _holding: bool = false
var _start: Vector2i
var _last: Vector2i
var _f: int = -1


func _init() -> void:
	name = "World maps"
	_build()


## Uses a (re)loaded package. An open map with unsaved paint is kept.
func set_model(m: PackageEditor) -> void:
	model = m
	if model.templates == null:
		return
	feature_ids = PackedStringArray()
	colors = []
	for id in model.templates.ids():
		if model.templates.kind_of(id) == "hex_feature" and not model.templates.is_abstract(id):
			feature_ids.append(id)
			colors.append(feature_color(id, model.templates.values_of(id)))
	commander_ids = PackedStringArray()
	for id in model.ids_of("commander"):
		if not model.templates.is_abstract(id):
			commander_ids.append(id)
	if not commander_ids.has(commander):
		commander = commander_ids[0] if not commander_ids.is_empty() else ""
	_fill_lists()
	if canvas == null:
		return
	if canvas.dirty or model.file_of(canvas.id) == "":
		canvas.set_templates(model.templates)
	else:
		open_map(canvas.id)


## The overworld maps of the package that can be painted.
func map_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if model == null or model.templates == null:
		return out
	for id in model.ids_of("overworld_map"):
		if not model.templates.is_abstract(id):
			out.append(id)
	return out


## Opens an overworld map. Refused while the open map has unsaved changes.
func open_map(id: String) -> bool:
	if canvas != null and canvas.dirty and canvas.id != id:
		_say("'%s' has unsaved changes: save it or revert it first." % canvas.id)
		_select_map(canvas.id)
		return false
	if model.file_of(id) == "" or model.templates.kind_of(id) != "overworld_map":
		_say("No overworld map '%s'." % id)
		return false
	var def: Variant = JSON.parse_string(model.definition_text(id))
	canvas = OverworldCanvas.open(model.templates, def if def is Dictionary else {"id": id, "kind": "overworld_map"})
	_opened()
	_say("\n".join(canvas.notes))
	return true


## Starts a new map filled with the selected feature. It joins the package
## when it is saved.
func new_map(id: String, w: int, h: int) -> bool:
	if canvas != null and canvas.dirty:
		_say("'%s' has unsaved changes: save it or revert it first." % canvas.id)
		return false
	if id.is_empty() or model.file_of(id) != "":
		_say("A new map needs an id nothing else uses.")
		return false
	if feature_ids.is_empty():
		_say("The package has no hex features to fill a map with.")
		return false
	canvas = OverworldCanvas.create(model.templates, id, w, h, feature_ids[feature])
	_opened()
	_say("New map '%s'. It is added to %s when you save." % [id, _file.get_item_text(_file.selected)])
	return true


## Writes the map if the package stays valid with it. Returns the errors.
func save() -> PackedStringArray:
	if canvas == null:
		return PackedStringArray(["no map is open"])
	var id := canvas.id
	var text := canvas.definition_text()
	var errs := model.add(text, _file.get_item_text(_file.selected)) if model.file_of(id) == "" else model.replace(id, text)
	if not errs.is_empty():
		_say("Not saved:\n" + "\n".join(errs))
		return errs
	canvas.mark_saved()
	saved.emit(id)
	set_model(model)
	_say("Saved '%s' to %s." % [id, model.file_of(id)])
	return errs


## Throws away unsaved changes.
func revert() -> void:
	if canvas == null:
		return
	var id := canvas.id
	canvas = null
	selected = {}
	if model.file_of(id) != "":
		open_map(id)
	else:
		_opened()
		_say("Dropped the unsaved map '%s'." % id)


func undo() -> void:
	if canvas != null:
		canvas.undo()
	_select({})
	_sync_map_fields()
	changed()


func redo() -> void:
	if canvas != null:
		canvas.redo()
	_select({})
	_sync_map_fields()
	changed()


func set_tool(t: int) -> void:
	tool = t
	for i in _tools.size():
		_tools[i].set_pressed_no_signal(i == t)
	changed()


func set_feature(index: int) -> void:
	feature = clampi(index, 0, maxi(feature_ids.size() - 1, 0))
	if feature < _features.item_count:
		_features.select(feature)


func set_owner_player(o: int) -> void:
	owner_player = clampi(o, 0, OWNER_NAMES.size() - 1)
	_owner.select(owner_player)


## Sets a map-wide value as one undo step. A mirror map needs an even height
## (the half turn is then an exact hex symmetry).
func set_map_value(key: String, v: Variant) -> bool:
	if canvas == null:
		return false
	if key == "mirror" and bool(v) and canvas.height % 2 != 0:
		_say("A mirror map needs an even height.")
		_sync_map_fields()
		return false
	canvas.begin()
	canvas.set_value(key, v)
	changed()
	return true


## Changes the map's size, keeping its top-left corner.
func resize(w: int, h: int) -> bool:
	if canvas == null:
		return false
	if canvas.mirror and h % 2 != 0:
		_say("A mirror map needs an even height.")
		return false
	canvas.begin()
	canvas.resize(w, h)
	_select({})
	changed()
	return true


## Removes the selected object or start.
func remove_selected() -> void:
	if canvas == null or selected.is_empty():
		return
	canvas.begin()
	if selected["kind"] == "object":
		canvas.remove_object(selected["index"])
	else:
		canvas.remove_start(selected["index"])
	_select({})
	changed()


# --- the tools, by hex (the view turns the mouse into these) -----------------

## A press on a hex with the current tool; `erase` is the right button.
func press(hex: Vector2i, erase: bool) -> void:
	var c := canvas
	if c == null:
		return
	_f = -1 if erase else feature
	match tool:
		Tool.BRUSH:
			c.begin()
			_paint(hex)
			_stroke = true
			_last = hex
		Tool.RECT, Tool.LINE:
			_stroke = true
			_start = hex
		Tool.FILL:
			if c.in_bounds(hex.x, hex.y):
				c.begin()
				c.fill(hex.x, hex.y, _f)
				var p := c.partner(hex.x, hex.y)
				if p != hex:
					c.fill(p.x, p.y, _f)
		Tool.PICK:
			var o := c.object_at(hex.x, hex.y)
			var f := c.ground_at(hex.x, hex.y) if o < 0 else c.features.find(c.objects[o]["feature"])
			if f < 0 and c.in_bounds(hex.x, hex.y) and not c.fills.is_empty():
				f = c.features.find(c.fills[c.fills.size() - 1])
			if f >= 0:
				set_feature(f)
		Tool.PLACE:
			_press_place(hex, erase)
		Tool.START:
			_press_start(hex, erase)
	changed()


func drag(hex: Vector2i) -> void:
	if canvas == null:
		return
	if _holding and hex != _last and canvas.in_bounds(hex.x, hex.y):
		var why := canvas.move_object(selected["index"], hex.x, hex.y) if selected["kind"] == "object" else canvas.move_start(selected["index"], hex.x, hex.y)
		if why.is_empty():
			_last = hex
			changed()
	elif _stroke and tool == Tool.BRUSH and hex != _last:
		if canvas.in_bounds(_last.x, _last.y) and canvas.in_bounds(hex.x, hex.y):
			# A fast stroke skips hexes: paint the hex line between.
			for plot in Hex.line(Hex.plot(_last.x, _last.y, canvas.width), Hex.plot(hex.x, hex.y, canvas.width), canvas.width, canvas.height):
				if plot >= 0:
					_paint(Vector2i(plot % canvas.width, plot / canvas.width))
		else:
			_paint(hex)
		_last = hex
		changed()


func release(hex: Vector2i) -> void:
	var c := canvas
	if c != null and _stroke:
		match tool:
			Tool.RECT:
				c.begin()
				c.rect(_start.x, _start.y, hex.x, hex.y, _f)
				var a := c.partner(_start.x, _start.y)
				var b := c.partner(hex.x, hex.y)
				if c.mirror:
					c.rect(a.x, a.y, b.x, b.y, _f)
			Tool.LINE:
				c.begin()
				c.line(_start.x, _start.y, hex.x, hex.y, _f)
				if c.mirror:
					var a := c.partner(_start.x, _start.y)
					var b := c.partner(hex.x, hex.y)
					c.line(a.x, a.y, b.x, b.y, _f)
	_stroke = false
	_holding = false
	changed()


func _paint(hex: Vector2i) -> void:
	canvas.paint(hex.x, hex.y, _f, radius)
	var p := canvas.partner(hex.x, hex.y)
	if p != hex:
		canvas.paint(p.x, p.y, _f, radius)


func _press_place(hex: Vector2i, erase: bool) -> void:
	var c := canvas
	var at := c.object_at(hex.x, hex.y)
	if erase:
		if at >= 0:
			c.begin()
			c.remove_object(at)
			_select({})
		return
	if at >= 0:
		_select({"kind": "object", "index": at})
		c.begin()
		_holding = true
		_last = hex
		return
	if feature >= feature_ids.size():
		return
	c.begin()
	var why := c.place(feature_ids[feature], hex.x, hex.y, owner_player)
	if not why.is_empty():
		_say("Not placed: " + why)
		return
	_select({"kind": "object", "index": c.object_at(hex.x, hex.y, feature_ids[feature])})


func _press_start(hex: Vector2i, erase: bool) -> void:
	var c := canvas
	var at := c.start_at(hex.x, hex.y)
	if erase:
		if at >= 0:
			c.begin()
			c.remove_start(at)
			_select({})
		return
	if at >= 0:
		_select({"kind": "start", "index": at})
		c.begin()
		_holding = true
		_last = hex
		return
	if commander.is_empty():
		_say("The package has no commanders to start with.")
		return
	c.begin()
	var why := c.add_start(maxi(owner_player, 1), commander, hex.x, hex.y)
	if not why.is_empty():
		_say("Not added: " + why)
		return
	_select({"kind": "start", "index": c.starts.size() - 1})


# --- view helpers --------------------------------------------------------------

## The view calls this after every edit.
func changed() -> void:
	_undo.disabled = canvas == null or not canvas.can_undo()
	_redo.disabled = canvas == null or not canvas.can_redo()
	if not selected.is_empty() and canvas != null:
		var list: Array = canvas.objects if selected["kind"] == "object" else canvas.starts
		if selected["index"] >= list.size():
			_select({})
	view.queue_redraw()


## Text under the map: the hex under the mouse.
func show_hex(hex: Vector2i) -> void:
	if canvas == null or not canvas.in_bounds(hex.x, hex.y):
		_status.text = ""
		return
	var text := "%d, %d  ·  %s" % [hex.x, hex.y, " + ".join(canvas.features_at(hex.x, hex.y))]
	var o := canvas.object_at(hex.x, hex.y)
	if o >= 0 and int(canvas.objects[o]["owner"]) != 0:
		text += "  ·  owner %d" % int(canvas.objects[o]["owner"])
	var s := canvas.start_at(hex.x, hex.y)
	if s >= 0:
		text += "  ·  start: player %d, %s" % [int(canvas.starts[s]["player"]), canvas.starts[s]["commander"]]
	if canvas.mirror:
		var p := canvas.partner(hex.x, hex.y)
		text += "  ·  mirrors %d, %d" % [p.x, p.y]
	_status.text = text + ("    (unsaved)" if canvas.dirty else "")


## The colour a hex shows: its painted feature, else its last fill.
func ground_color(col: int, row: int) -> Color:
	var g := canvas.ground_at(col, row)
	if g < 0 and not canvas.fills.is_empty():
		g = canvas.features.find(canvas.fills[canvas.fills.size() - 1])
	return color_of(canvas.features[g] if g >= 0 else "")


func color_of(fid: String) -> Color:
	var i := feature_ids.find(fid)
	return colors[i] if i >= 0 else Color("2a2f38")


## A hex feature's `color`, else one by its kind of land, else a steady
## made-up one.
static func feature_color(id: String, values: Dictionary) -> Color:
	var c := str(values.get("color", ""))
	if Color.html_is_valid(c):
		return Color.html(c)
	for key: String in LAND:
		if id.contains(key):
			return LAND[key]
	return ContextView.feature_color(id, values)


const LAND := {
	"plain": Color("6f8a4a"), "grass": Color("6f8a4a"), "field": Color("8a8a4a"),
	"forest": Color("2f5a32"), "wood": Color("2f5a32"), "hill": Color("8a7346"),
	"mountain": Color("6b6460"), "lake": Color("3b6a9a"), "water": Color("3b6a9a"),
	"sea": Color("2b4f7a"), "river": Color("4f86b8"), "road": Color("a89a78"),
	"swamp": Color("4a5a3a"), "desert": Color("c2a564"), "sand": Color("c2a564"),
}


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

	side.add_child(_heading("World map"))
	_maps = OptionButton.new()
	_maps.item_selected.connect(func(i: int) -> void: open_map(_maps.get_item_text(i)))
	side.add_child(_maps)
	var new_row := HBoxContainer.new()
	side.add_child(new_row)
	_new_id = LineEdit.new()
	_new_id.placeholder_text = "new_map_id"
	_new_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(_new_id)
	_new_w = _spin(2, 200, 16)
	_new_w.tooltip_text = "Width in hexes"
	new_row.add_child(_new_w)
	_new_h = _spin(2, 200, 12)
	_new_h.tooltip_text = "Height in hexes (even for a mirror map)"
	new_row.add_child(_new_h)
	var size_row := HBoxContainer.new()
	side.add_child(size_row)
	size_row.add_child(_button("New", func() -> void: new_map(_new_id.text.strip_edges(), int(_new_w.value), int(_new_h.value)),
		"Start a new map of this id and size, filled with the selected feature"))
	size_row.add_child(_button("Resize", func() -> void: resize(int(_new_w.value), int(_new_h.value)),
		"Change the open map to the size above, keeping its top-left corner"))
	_name = LineEdit.new()
	_name.placeholder_text = "Map name"
	_name.text_submitted.connect(func(t: String) -> void: set_map_value("name", t.strip_edges()))
	_name.focus_exited.connect(func() -> void:
		if canvas != null and _name.text.strip_edges() != canvas.name:
			set_map_value("name", _name.text.strip_edges()))
	side.add_child(_name)
	_elimination = CheckBox.new()
	_elimination.text = "Elimination (skirmish)"
	_elimination.tooltip_text = "The game is won by the team whose commanders outlast every other team's. Story maps leave this off and end through their triggers."
	_elimination.toggled.connect(func(on: bool) -> void: set_map_value("elimination", on))
	side.add_child(_elimination)
	_mirror = CheckBox.new()
	_mirror.text = "Mirror map (two players)"
	_mirror.tooltip_text = "The generator repeats every pass and start half a turn round, players 1 and 2 swapped: make one half"
	_mirror.toggled.connect(func(on: bool) -> void: set_map_value("mirror", on))
	side.add_child(_mirror)

	side.add_child(_heading("Tool"))
	var grid := GridContainer.new()
	grid.columns = 2
	side.add_child(grid)
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = TOOL_NAMES[i]
		b.tooltip_text = TOOL_TIPS[i]
		b.toggle_mode = true
		b.button_pressed = i == tool
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_tool.bind(i))
		grid.add_child(b)
		_tools.append(b)
	var radius_row := HBoxContainer.new()
	side.add_child(radius_row)
	var rl := Label.new()
	rl.text = "Brush radius"
	radius_row.add_child(rl)
	_radius = _spin(0, 8, 0)
	_radius.value_changed.connect(func(v: float) -> void: radius = int(v))
	radius_row.add_child(_radius)

	side.add_child(_heading("Feature"))
	_features = ItemList.new()
	_features.auto_height = true
	_features.item_selected.connect(func(i: int) -> void: feature = i)
	side.add_child(_features)

	side.add_child(_heading("Objects and starts"))
	_owner = OptionButton.new()
	for n in OWNER_NAMES:
		_owner.add_item(n)
	_owner.tooltip_text = "Who owns a placed feature; the player a start is for (neutral starts are player 1's)"
	_owner.item_selected.connect(func(i: int) -> void:
		owner_player = i
		_apply_owner())
	side.add_child(_field("Owner", _owner))
	_commanders = OptionButton.new()
	_commanders.tooltip_text = "The commander the Start tool adds"
	_commanders.item_selected.connect(func(i: int) -> void:
		commander = _commanders.get_item_text(i)
		_apply_commander())
	side.add_child(_field("Commander", _commanders))
	_object_box = VBoxContainer.new()
	side.add_child(_object_box)

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
	view = HexView.new()
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


func _spin(lo: int, hi: int, v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = v
	return s


func _field(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _fill_lists() -> void:
	_maps.clear()
	for id in map_ids():
		_maps.add_item(id)
	if canvas != null:
		_select_map(canvas.id)
	else:
		_maps.select(-1)
	_features.clear()
	for i in feature_ids.size():
		var img := Image.create(14, 14, false, Image.FORMAT_RGB8)
		img.fill(colors[i])
		var label := str(model.templates.values_of(feature_ids[i]).get("name", feature_ids[i]))
		_features.add_item("%s  (%s)" % [label, feature_ids[i]], ImageTexture.create_from_image(img))
	set_feature(feature)
	_commanders.clear()
	for id in commander_ids:
		_commanders.add_item(id)
	var ci := commander_ids.find(commander)
	if ci >= 0:
		_commanders.select(ci)
	var keep := _file.get_item_text(_file.selected) if _file.selected >= 0 else ""
	if keep.is_empty() and _maps.item_count > 0:
		keep = model.file_of(_maps.get_item_text(0))
	_file.clear()
	for f in model.files:
		_file.add_item(f)
	if _file.item_count > 0:
		var at := 0
		for i in _file.item_count:
			if _file.get_item_text(i) == keep:
				at = i
		_file.select(at)


func _select_map(id: String) -> void:
	for i in _maps.item_count:
		if _maps.get_item_text(i) == id:
			_maps.select(i)
			return
	_maps.select(-1)


func _opened() -> void:
	selected = {}
	_stroke = false
	_holding = false
	_fill_lists()
	_sync_map_fields()
	_fill_object_box()
	view.fit()
	changed()


func _sync_map_fields() -> void:
	var has := canvas != null
	_name.text = canvas.name if has else ""
	_elimination.set_pressed_no_signal(has and bool(canvas.value("elimination", false)))
	_mirror.set_pressed_no_signal(has and canvas.mirror)
	_name.editable = has
	_elimination.disabled = not has
	_mirror.disabled = not has
	if has:
		_new_w.value = canvas.width
		_new_h.value = canvas.height


func _select(sel: Dictionary) -> void:
	selected = sel
	_fill_object_box()
	if view != null:
		view.queue_redraw()


## The owner list changes the selected object's owner (or start's player).
func _apply_owner() -> void:
	if canvas == null or selected.is_empty():
		return
	canvas.begin()
	if selected["kind"] == "object":
		canvas.set_owner(selected["index"], owner_player)
	else:
		canvas.set_start(selected["index"], maxi(owner_player, 1), str(canvas.starts[selected["index"]]["commander"]))
	_fill_object_box()
	changed()


func _apply_commander() -> void:
	if canvas == null or selected.get("kind", "") != "start":
		return
	canvas.begin()
	canvas.set_start(selected["index"], int(canvas.starts[selected["index"]]["player"]), commander)
	_fill_object_box()
	changed()


## What is selected, shown above the Save heading.
func _fill_object_box() -> void:
	for ch in _object_box.get_children():
		ch.queue_free()
	if canvas == null or selected.is_empty():
		var hint := Label.new()
		hint.text = "Place (P) or Start (T): click one to select it." if canvas != null else ""
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_object_box.add_child(hint)
		return
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if selected["kind"] == "object":
		var o: Dictionary = canvas.objects[selected["index"]]
		l.text = "%s at %d, %d, %s" % [o["feature"], o["col"], o["row"], OWNER_NAMES[clampi(int(o["owner"]), 0, OWNER_NAMES.size() - 1)].to_lower()]
		_owner.select(clampi(int(o["owner"]), 0, OWNER_NAMES.size() - 1))
		owner_player = _owner.selected
	else:
		var s: Dictionary = canvas.starts[selected["index"]]
		l.text = "Start of player %d: %s at %d, %d" % [s["player"], s["commander"], s["col"], s["row"]]
		_owner.select(clampi(int(s["player"]), 0, OWNER_NAMES.size() - 1))
		owner_player = _owner.selected
		var ci := commander_ids.find(str(s["commander"]))
		if ci >= 0:
			_commanders.select(ci)
			commander = commander_ids[ci]
	_object_box.add_child(l)
	_object_box.add_child(_button("Remove", remove_selected, "Delete"))


func _say(text: String) -> void:
	_result.text = text


## The painted map on hexes: draws the canvas and turns the mouse into
## presses, drags and releases on hexes. Pointy-top, odd rows shifted right
## (Hex's "odd-r" layout).
class HexView:
	extends Control

	const BG := Color("12151a")
	const EDGE := Color(0, 0, 0, 0.35)
	const INK := Color("e6b450")
	const SQRT3 := 1.7320508

	var painter: OverworldPainter
	## The hex radius in pixels, and where hex (0, 0)'s centre is drawn.
	var zoom: float = 16.0
	var origin: Vector2 = Vector2.ZERO
	var hover: Vector2i = Vector2i(-1, -1)
	var _auto_fit: bool = true
	var _panning: bool = false

	func _init() -> void:
		focus_mode = Control.FOCUS_CLICK
		clip_contents = true
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
			queue_redraw()
			return
		var w := SQRT3 * (c.width + 0.5)
		var h := 1.5 * c.height + 0.5
		zoom = clampf(minf((size.x - 16) / w, (size.y - 16) / h), 2.0, 64.0)
		origin = ((size - Vector2(w, h) * zoom) / 2.0 + Vector2(SQRT3 / 2.0, 1.0) * zoom).floor()
		queue_redraw()

	func centre(col: int, row: int) -> Vector2:
		return origin + Vector2(SQRT3 * (col + 0.5 * (row & 1)), 1.5 * row) * zoom

	## The hex (col, row) under a point.
	func hex_at(pos: Vector2) -> Vector2i:
		var p := (pos - origin) / zoom
		var q := SQRT3 / 3.0 * p.x - p.y / 3.0
		var r := 2.0 / 3.0 * p.y
		var s := -q - r
		var rq := roundf(q)
		var rr := roundf(r)
		var rs := roundf(s)
		var dq := absf(rq - q)
		var dr := absf(rr - r)
		var ds := absf(rs - s)
		if dq > dr and dq > ds:
			rq = -rr - rs
		elif dr > ds:
			rr = -rq - rs
		return Hex.to_offset(Vector2i(int(rq), int(rr)))

	func corners(at: Vector2, scale: float = 1.0) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * i - 30.0)
			out.append(at + Vector2(cos(a), sin(a)) * zoom * scale)
		return out

	func _gui_input(e: InputEvent) -> void:
		if painter.canvas == null:
			return
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					if mb.pressed:
						var before := (mb.position - origin) / zoom
						zoom = clampf(zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 2.0, 96.0)
						origin = (mb.position - before * zoom).floor()
						_auto_fit = false
						queue_redraw()
				MOUSE_BUTTON_MIDDLE:
					_panning = mb.pressed
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
					if mb.pressed:
						grab_focus()
						painter.press(hex_at(mb.position), mb.button_index == MOUSE_BUTTON_RIGHT)
					else:
						painter.release(hex_at(mb.position))
			accept_event()
		elif e is InputEventMouseMotion:
			var mm := e as InputEventMouseMotion
			if _panning:
				origin += mm.relative
				_auto_fit = false
			hover = hex_at(mm.position)
			painter.drag(hover)
			painter.show_hex(hover)
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
			KEY_B: painter.set_tool(OverworldPainter.Tool.BRUSH)
			KEY_R: painter.set_tool(OverworldPainter.Tool.RECT)
			KEY_L: painter.set_tool(OverworldPainter.Tool.LINE)
			KEY_F: painter.set_tool(OverworldPainter.Tool.FILL)
			KEY_I: painter.set_tool(OverworldPainter.Tool.PICK)
			KEY_P: painter.set_tool(OverworldPainter.Tool.PLACE)
			KEY_T: painter.set_tool(OverworldPainter.Tool.START)
			KEY_DELETE: painter.remove_selected()
			_:
				return false
		return true

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		var c := painter.canvas
		if c == null:
			return
		for row in c.height:
			for col in c.width:
				var pts := corners(centre(col, row))
				draw_colored_polygon(pts, painter.ground_color(col, row))
				if zoom >= 6.0:
					pts.append(pts[0])
					draw_polyline(pts, EDGE, 1.0)
		if c.mirror:
			var mid := origin + Vector2(SQRT3 * (c.width - 0.5) / 2.0 + SQRT3 / 4.0, 1.5 * (c.height - 1) / 2.0) * zoom
			draw_arc(mid, 6.0, 0.0, TAU, 16, INK, 1.0)
		var g := c.ghosts()
		for o: Dictionary in g["objects"]:
			_draw_object(o, 0.35, false)
		for s: Dictionary in g["starts"]:
			_draw_start(s, 0.35, false)
		for i in c.objects.size():
			_draw_object(c.objects[i], 1.0, painter.selected.get("kind", "") == "object" and painter.selected["index"] == i)
		for i in c.starts.size():
			_draw_start(c.starts[i], 1.0, painter.selected.get("kind", "") == "start" and painter.selected["index"] == i)
		_draw_cursor(c)

	func _draw_object(o: Dictionary, alpha: float, chosen: bool) -> void:
		var at := centre(o["col"], o["row"])
		var pts := corners(at, 0.55)
		draw_colored_polygon(pts, Color(painter.color_of(o["feature"]).lightened(0.15), alpha))
		var own := int(o["owner"])
		pts.append(pts[0])
		var ring: Color = INK if chosen else (TeamPalette.color(own, Color(1, 1, 1, 0.7)) if own != 0 else Color(1, 1, 1, 0.7))
		draw_polyline(pts, Color(ring, alpha), 3.0 if chosen or own != 0 else 1.0)

	func _draw_start(s: Dictionary, alpha: float, chosen: bool) -> void:
		var at := centre(s["col"], s["row"]) + Vector2(0, -zoom * 0.25)
		var col: Color = TeamPalette.color(int(s["player"]), Color.WHITE)
		draw_line(at + Vector2(0, zoom * 0.6), at - Vector2(0, zoom * 0.3), Color(Color.WHITE, alpha), 2.0)
		draw_colored_polygon(PackedVector2Array([at - Vector2(0, zoom * 0.3), at + Vector2(zoom * 0.45, -zoom * 0.15), at]), Color(col, alpha))
		if chosen:
			draw_arc(centre(s["col"], s["row"]), zoom * 0.8, 0.0, TAU, 24, INK, 2.0)
		if zoom >= 10.0:
			draw_string(get_theme_default_font(), at + Vector2(zoom * 0.1, zoom * 0.55), "P%d" % int(s["player"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(zoom * 0.5), Color(Color.WHITE, alpha))

	func _draw_cursor(c: OverworldCanvas) -> void:
		if not c.in_bounds(hover.x, hover.y):
			return
		var hexes: Array[Vector2i] = [hover]
		match painter.tool:
			OverworldPainter.Tool.BRUSH:
				hexes = []
				for p in Hex.within(Hex.plot(hover.x, hover.y, c.width), painter.radius, c.width, c.height):
					hexes.append(Vector2i(p % c.width, p / c.width))
			OverworldPainter.Tool.RECT:
				if painter._stroke:
					hexes = []
					var a := painter._start
					for row in range(maxi(mini(a.y, hover.y), 0), mini(maxi(a.y, hover.y), c.height - 1) + 1):
						for col in range(maxi(mini(a.x, hover.x), 0), mini(maxi(a.x, hover.x), c.width - 1) + 1):
							hexes.append(Vector2i(col, row))
			OverworldPainter.Tool.LINE:
				var a := painter._start
				if painter._stroke and c.in_bounds(a.x, a.y):
					hexes = []
					for p in Hex.line(Hex.plot(a.x, a.y, c.width), Hex.plot(hover.x, hover.y, c.width), c.width, c.height):
						if p >= 0:
							hexes.append(Vector2i(p % c.width, p / c.width))
		for h in hexes:
			var pts := corners(centre(h.x, h.y), 0.92)
			pts.append(pts[0])
			draw_polyline(pts, INK, 2.0)
			if c.mirror:
				var p := c.partner(h.x, h.y)
				var q := corners(centre(p.x, p.y), 0.92)
				q.append(q[0])
				draw_polyline(q, Color(INK, 0.4), 1.0)
