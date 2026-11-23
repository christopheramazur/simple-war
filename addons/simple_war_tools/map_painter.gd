@tool
class_name MapPainter
extends HSplitContainer
## The Maps tab of the War Data screen (GDD 04 §4.9, O1Q6): paints a
## `battle_map`'s terrain. Brush, rectangle, line, fill and pick tools, a
## facing per cell, mirror painting, stamps (another map placed as one
## object) and undo. The map itself is a MapCanvas; saving goes through
## PackageEditor, so a map that would break the package is refused.
##
## Objects (sw-ll4.7): a `scenario` played on the open map can be open with
## it (a ScenarioCanvas). Its zones and its sides' deployment areas are
## drawn over the terrain. With the Objects tool, click one to select it,
## drag it to move it, drag an area's corner handle to resize it, and edit
## the rest (a zone's id, radius and points; a side's player, facing and
## squads) in the panel. Save writes the map and the scenario.
##
## Mouse: left paints, right paints the base feature (or removes a stamp
## with the Stamp tool), middle drags the view, the wheel zooms. Paint lands
## on top of stamps: a stamp painted on becomes painted cells (undo brings
## it back), and Fill and Pick go by what the map shows.
## Keys (over the map): B R L F I S O pick a tool, arrows set the facing,
## Backspace clears it, Delete removes the selected object, Ctrl+Z /
## Ctrl+Y undo and redo (of the scenario while the Objects tool is on).

signal saved(map_id: String)

enum Tool { BRUSH, RECT, LINE, FILL, PICK, STAMP, OBJECT, SELECT }

const TOOL_NAMES: PackedStringArray = ["Brush (B)", "Rectangle (R)", "Line (L)", "Fill (F)", "Pick (I)", "Stamp (S)", "Objects (O)", "Select (M)"]
const TOOL_TIPS: PackedStringArray = [
	"Left paints the feature, right paints the base. Paint lands on top of stamps.",
	"Drag a rectangle of the feature (right button: the base)",
	"Drag a line of brush marks (right button: the base)",
	"Fill the joined cells that look the same (right button: the base)",
	"Pick the feature and facing under the cursor",
	"Left places the chosen map as a stamp; right-click a stamp to remove it",
	"Select, move and resize the scenario's zones and deployment areas",
	"Drag a marquee over cells, or pick up a stamp to move it (Delete removes it)",
]
const MIRROR_NAMES: PackedStringArray = ["No mirror", "Left and right", "Top and bottom", "Four ways", "Half turn"]
const FACING_NAMES: PackedStringArray = ["No facing", "North", "East", "South", "West"]

var model: PackageEditor
var canvas: MapCanvas
## The scenario open with the map (its zones and sides), or null.
var scenario: ScenarioCanvas
## The selected object: {"kind": "zone" | "side", "index"}, or {}.
var selected: Dictionary = {}
var squad_ids: PackedStringArray = PackedStringArray()
var tool: int = Tool.BRUSH
## Index into canvas.features.
var feature: int = 0
var facing: int = 0
var brush: int = 1
var stamp_id: String = ""
var stamp_rotate: int = 0
## The Select tool's marquee in cells (size zero when there is none) and the
## stamp picked up by it (-1 for none).
var selection: Rect2i = Rect2i()
var selected_stamp: int = -1
## One colour per feature of `feature_ids`.
var feature_ids: PackedStringArray = PackedStringArray()
var colors: Array[Color] = []
## The edited package's art (sw-8rk): ground textures on the canvas and in the
## feature list, colours where a feature has none. Null without a package.
var art: ArtSet

var view: MapView
var _maps: OptionButton
var _scenarios: OptionButton
var _new_scenario: LineEdit
var _object_box: VBoxContainer
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
var _selection_id: LineEdit
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
	art = ArtSet.from_loader(model.loader) if model.loader != null else null
	feature_ids = PackedStringArray()
	colors = []
	for id in model.templates.ids():
		if model.templates.kind_of(id) == "feature" and not model.templates.is_abstract(id):
			feature_ids.append(id)
			colors.append(feature_color(id, model.templates.values_of(id)))
	squad_ids = PackedStringArray()
	for id in model.ids_of("squad"):
		if not model.templates.is_abstract(id):
			squad_ids.append(id)
	_fill_lists()
	if canvas == null:
		return
	var keep := scenario
	if canvas.dirty or model.file_of(canvas.id) == "":
		canvas.set_templates(model.templates)
	else:
		open_map(canvas.id)
	# The scenario that was open stays open: reread if it has no unsaved
	# changes, kept as it is otherwise.
	if keep != null and (keep.dirty or model.file_of(keep.id) == ""):
		scenario = keep
	elif keep != null:
		open_scenario(keep.id)
	_fill_scenarios()


## Opens a battle map of the package. Refused while the open map has
## unsaved changes (save or revert first). Returns whether it opened.
func open_map(id: String) -> bool:
	if canvas != null and canvas.dirty and canvas.id != id:
		_say("'%s' has unsaved changes: save it or revert it first." % canvas.id)
		_select_map(canvas.id)
		return false
	if canvas != null and canvas.id != id and scenario != null and scenario.dirty:
		_say("The scenario '%s' has unsaved changes: save it or revert it first." % scenario.id)
		_select_map(canvas.id)
		return false
	if model.file_of(id) == "" or model.templates.kind_of(id) != "battle_map":
		_say("No battle map '%s'." % id)
		return false
	var def: Variant = JSON.parse_string(model.definition_text(id))
	var other := canvas == null or canvas.id != id
	_use(MapCanvas.open(model.templates, def if def is Dictionary else {"id": id, "kind": "battle_map"}))
	_say("\n".join(canvas.notes))
	if other:
		# A map opens with the first scenario played on it, so its zones and
		# deployment areas are there to see.
		var on_it := scenarios_of(id)
		scenario = null
		open_scenario(on_it[0] if not on_it.is_empty() else "")
	return true


## The scenarios played on a battle map, by id.
func scenarios_of(map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if model == null or model.templates == null:
		return out
	for id in model.ids_of("scenario"):
		if not model.templates.is_abstract(id) and str(model.templates.values_of(id).get("map", "")) == map_id:
			out.append(id)
	return out


## Opens a scenario of the open map ("" closes the open one). Refused while
## the open scenario has unsaved changes. Returns whether it did.
func open_scenario(id: String) -> bool:
	if scenario != null and scenario.dirty and scenario.id != id:
		_say("The scenario '%s' has unsaved changes: save it or revert it first." % scenario.id)
		_fill_scenarios()
		return false
	if id.is_empty():
		scenario = null
	else:
		if canvas == null or model.file_of(id) == "" or model.templates.kind_of(id) != "scenario":
			_say("No scenario '%s'." % id)
			return false
		var def: Variant = JSON.parse_string(model.definition_text(id))
		scenario = ScenarioCanvas.open(model.templates, def if def is Dictionary else {"id": id, "kind": "scenario"})
		scenario.map_id = canvas.id
	select_object({})
	_fill_scenarios()
	changed()
	return true


## Starts a new scenario on the open map: the core field scenario's rules,
## a deployment strip inside each short edge and one zone in the middle.
## It joins the package when it is saved.
func new_scenario(id: String) -> bool:
	if canvas == null:
		_say("Open a map first.")
		return false
	if scenario != null and scenario.dirty:
		_say("The scenario '%s' has unsaved changes: save it or revert it first." % scenario.id)
		return false
	if id.is_empty() or model.file_of(id) != "":
		_say("A new scenario needs an id nothing else uses.")
		return false
	scenario = ScenarioCanvas.create(model.templates, id, canvas.id, canvas.width, canvas.height)
	select_object({})
	_fill_scenarios()
	set_tool(Tool.OBJECT)
	_say("New scenario '%s' on '%s'. It is added to %s when you save." % [id, canvas.id, _file.get_item_text(_file.selected)])
	changed()
	return true


## Selects a zone or a side of the open scenario ({} for none) and shows
## its values in the panel.
func select_object(sel: Dictionary) -> void:
	selected = sel
	_fill_object_box()
	if view != null:
		view.queue_redraw()


## Removes the selected object.
func remove_selected() -> void:
	if tool == Tool.SELECT:
		if canvas != null and selected_stamp >= 0 and selected_stamp < canvas.stamps.size():
			canvas.begin()
			canvas.remove_stamp(selected_stamp)
			selected_stamp = -1
			changed()
		return
	if scenario == null or selected.is_empty():
		return
	scenario.begin()
	if selected["kind"] == "zone":
		scenario.remove_zone(selected["index"])
	else:
		scenario.remove_side(selected["index"])
	select_object({})
	changed()


## Makes the cells inside the selection a new map, added to the chosen data
## file, so it can be stamped. Returns the errors.
func save_selection_as_map(id: String) -> PackedStringArray:
	if canvas == null or selection.size.x <= 0 or selection.size.y <= 0:
		return _refuse("Select some cells first (Select tool, drag over the map).")
	if id.is_empty() or model.file_of(id) != "":
		return _refuse("A new map needs an id nothing else uses.")
	var text := canvas.selection_text(selection, id)
	if text.is_empty():
		return _refuse("The selection is outside the map.")
	var errs := model.add(text, _file.get_item_text(_file.selected))
	if not errs.is_empty():
		_say("Not saved:
" + "
".join(errs))
		return errs
	_say("Saved the selection as the map '%s' in %s. It is in the Stamp list." % [id, model.file_of(id)])
	set_model(model)
	return errs


func _refuse(why: String) -> PackedStringArray:
	_say(why)
	return PackedStringArray([why])


## Starts a new map. It joins the package when it is saved.
func new_map(id: String, w: int, h: int, base_feature: String) -> bool:
	if canvas != null and canvas.dirty:
		_say("'%s' has unsaved changes: save it or revert it first." % canvas.id)
		return false
	if scenario != null and scenario.dirty:
		_say("The scenario '%s' has unsaved changes: save it or revert it first." % scenario.id)
		return false
	if id.is_empty() or model.file_of(id) != "":
		_say("A new map needs an id nothing else uses.")
		return false
	scenario = null
	selected = {}
	_use(MapCanvas.create(model.templates, id, w, h, base_feature))
	_fill_scenarios()
	_fill_object_box()
	_say("New map '%s'. It is added to %s when you save." % [id, _file.get_item_text(_file.selected)])
	return true


## Writes the map, and the open scenario if it has changes, if the package
## stays valid with them. Returns the errors.
func save() -> PackedStringArray:
	if canvas == null:
		return PackedStringArray(["no map is open"])
	var id := canvas.id
	# Zones and deployment areas must fit the map as it is now: the open
	# scenario as edited, and every other scenario played on this map.
	var misfits := PackedStringArray()
	if scenario != null:
		misfits.append_array(scenario.problems(canvas.width, canvas.height))
	for other in scenarios_of(id):
		if scenario == null or other != scenario.id:
			var def: Variant = JSON.parse_string(model.definition_text(other))
			if def is Dictionary:
				misfits.append_array(ScenarioCanvas.open(model.templates, def).problems(canvas.width, canvas.height))
	if not misfits.is_empty():
		_say("Not saved:
" + "
".join(misfits))
		return misfits
	var errs := _write(id, canvas.definition_text())
	var with_scenario := scenario != null and (scenario.dirty or model.file_of(scenario.id) == "")
	if not errs.is_empty() and with_scenario and model.file_of(scenario.id) != "":
		# The map may only fit once the scenario has moved (a zone brought
		# back inside a map made smaller): try the scenario first.
		if _write(scenario.id, scenario.definition_text()).is_empty():
			scenario.mark_saved()
			with_scenario = false
			errs = _write(id, canvas.definition_text())
	if not errs.is_empty():
		_say("Not saved:\n" + "\n".join(errs))
		return errs
	canvas.mark_saved()
	var said := "Saved '%s' to %s (%d shapes)." % [id, model.file_of(id), canvas.cells().size()]
	if with_scenario:
		errs = _write(scenario.id, scenario.definition_text())
		if errs.is_empty():
			scenario.mark_saved()
			said += "\nSaved the scenario '%s' to %s." % [scenario.id, model.file_of(scenario.id)]
		else:
			said += "\nThe scenario '%s' was not saved:\n%s" % [scenario.id, "\n".join(errs)]
	saved.emit(id)
	set_model(model)
	_say(said)
	return errs


## Adds a template to the chosen file, or replaces its text if it exists.
func _write(id: String, text: String) -> PackedStringArray:
	if model.file_of(id) == "":
		return model.add(text, _file.get_item_text(_file.selected))
	return model.replace(id, text)


## Throws away unsaved changes.
func revert() -> void:
	if canvas == null:
		return
	var id := canvas.id
	var sid := scenario.id if scenario != null else ""
	canvas = null
	scenario = null
	selected = {}
	if model.file_of(id) != "":
		open_map(id)
		if not sid.is_empty() and model.file_of(sid) != "":
			open_scenario(sid)
	else:
		_fill_scenarios()
		_fill_object_box()
		view.queue_redraw()
		_say("Dropped the unsaved map '%s'." % id)


## Whether the Objects tool is on with a scenario open: undo and redo then
## act on the scenario, otherwise on the map.
func _on_objects() -> bool:
	return tool == Tool.OBJECT and scenario != null


func undo() -> void:
	if _on_objects():
		scenario.undo()
		select_object({})
	elif canvas != null:
		canvas.undo()
	changed()


func redo() -> void:
	if _on_objects():
		scenario.redo()
		select_object({})
	elif canvas != null:
		canvas.redo()
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


func set_facing(f: int) -> void:
	facing = f
	_facing.select(f)


## The view calls this after every edit.
func changed() -> void:
	if _on_objects():
		_undo.disabled = not scenario.can_undo()
		_redo.disabled = not scenario.can_redo()
	else:
		_undo.disabled = canvas == null or not canvas.can_undo()
		_redo.disabled = canvas == null or not canvas.can_redo()
		if canvas != null and not canvas.flattened.is_empty():
			_say("Painted over the stamp %s: it is painted cells now (Ctrl+Z brings it back). To remove a whole stamp, right-click it with the Stamp tool." % ", ".join(canvas.flattened))
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


## A feature's list swatch (sw-8rk): its ground texture when the package has
## one (scaled to the swatch), else its colour.
func _swatch(id: String, color: Color) -> Texture2D:
	var src: Image = art.image(id, "texture") if art != null else null
	var img: Image
	if src != null:
		img = src.duplicate()
		img.resize(14, 14, Image.INTERPOLATE_NEAREST)
	else:
		img = Image.create(14, 14, false, Image.FORMAT_RGB8)
		img.fill(color)
	return ImageTexture.create_from_image(img)


## A feature's `color`, or a steady made-up one for features without it.
static func feature_color(id: String, values: Dictionary) -> Color:
	return ContextView.feature_color(id, values)


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

	side.add_child(_heading("Scenario"))
	_scenarios = OptionButton.new()
	_scenarios.tooltip_text = "A scenario played on this map: its zones and deployment areas are drawn over the terrain"
	_scenarios.item_selected.connect(func(i: int) -> void: open_scenario("" if i == 0 else _scenarios.get_item_text(i)))
	side.add_child(_scenarios)
	var sc_row := HBoxContainer.new()
	side.add_child(sc_row)
	_new_scenario = LineEdit.new()
	_new_scenario.placeholder_text = "new_scenario_id"
	_new_scenario.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc_row.add_child(_new_scenario)
	sc_row.add_child(_button("New", func() -> void: new_scenario(_new_scenario.text.strip_edges()),
		"Start a scenario on the open map: two deployment strips and a centre zone to begin with"))
	var obj_row := HBoxContainer.new()
	side.add_child(obj_row)
	obj_row.add_child(_button("Add zone", _add_zone, "A new zone in the middle of the map; drag it into place"))
	obj_row.add_child(_button("Add side", _add_side, "A new side with its deployment area; drag it into place"))
	_object_box = VBoxContainer.new()
	side.add_child(_object_box)

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
	_stamps.tooltip_text = "The map the Stamp tool places. Right-click a stamp with the Stamp tool to remove it."
	_stamps.item_selected.connect(func(i: int) -> void:
		stamp_id = _stamps.get_item_text(i)
		set_tool(Tool.STAMP))
	side.add_child(_stamps)
	_rotate = _options(PackedStringArray(["Not turned", "Turned 90°", "Turned 180°", "Turned 270°"]), func(i: int) -> void:
		stamp_rotate = i * 90
		view.queue_redraw())
	side.add_child(_rotate)
	_selection_id = LineEdit.new()
	_selection_id.placeholder_text = "id for the selection as a map"
	side.add_child(_selection_id)
	side.add_child(_button("Save selection as a map", func() -> void:
		if save_selection_as_map(_selection_id.text.strip_edges()).is_empty():
			_selection_id.text = "",
		"Select tool (M): drag over cells, or click a stamp to move it"))

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
	save_row.add_child(_button("Save map", save, "Checks the whole package with this map and its open scenario, then writes them"))
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
		var label := str(model.templates.values_of(feature_ids[i]).get("name", feature_ids[i]))
		_features.add_item("%s  (%s)" % [label, feature_ids[i]], _swatch(feature_ids[i], colors[i]))
	set_feature(feature)
	var keep := _file.get_item_text(_file.selected) if _file.selected >= 0 else ""
	if keep.is_empty() and _maps.item_count > 0:
		keep = model.file_of(_maps.get_item_text(0))
	_file.clear()
	for f in model.files:
		_file.add_item(f)
	if _file.item_count > 0:
		_file.select(maxi(_index_of(_file, keep), 0))


func _fill_scenarios() -> void:
	if _scenarios == null:
		return
	_scenarios.clear()
	_scenarios.add_item("No scenario")
	if canvas == null:
		return
	var ids := scenarios_of(canvas.id)
	if scenario != null and not ids.has(scenario.id):
		ids.append(scenario.id)  # new, or not saved on this map yet
	for id in ids:
		_scenarios.add_item(id)
	_scenarios.select(maxi(_index_of(_scenarios, scenario.id), 0) if scenario != null else 0)


func _add_zone() -> void:
	if scenario == null:
		_say("Pick or make a scenario first.")
		return
	scenario.begin()
	@warning_ignore("integer_division")
	var i := scenario.add_zone(canvas.width / 2, canvas.height / 2)
	set_tool(Tool.OBJECT)
	select_object({"kind": "zone", "index": i})
	changed()


func _add_side() -> void:
	if scenario == null:
		_say("Pick or make a scenario first.")
		return
	scenario.begin()
	@warning_ignore("integer_division")
	var i := scenario.add_side(canvas.width / 2 - 6, canvas.height / 2 - 10)
	set_tool(Tool.OBJECT)
	select_object({"kind": "side", "index": i})
	changed()


## The panel for the selected object, and under it the scenario's victory
## settings.
func _fill_object_box() -> void:
	if _object_box == null:
		return
	for c in _object_box.get_children():
		_object_box.remove_child(c)
		c.queue_free()
	_add_selection_box()
	if scenario != null:
		_add_victory_form()


## The victory settings of the open scenario (Data Model 03 'victory'). A value
## the scenario inherits shows as it is; a change writes the scenario's own.
func _add_victory_form() -> void:
	_object_box.add_child(_heading("Victory"))
	var tl := _spin(1, 999, int(scenario.victory_value("turn_limit")))
	tl.name = "VictoryTurnLimit"
	tl.tooltip_text = "The battle ends on this turn; the side in the lead wins"
	tl.value_changed.connect(func(v: float) -> void: _edit(func() -> String: return scenario.set_victory("turn_limit", int(v))))
	_object_box.add_child(_field("Turn limit", tl))
	var pr := _options(PackedStringArray(["Influence", "Value"]), func(at: int) -> void:
		_edit(func() -> String: return scenario.set_victory("primary", ScenarioCanvas.VICTORY_PRIMARIES[at])))
	pr.name = "VictoryPrimary"
	pr.tooltip_text = "The score the target and the turn limit count"
	pr.select(maxi(ScenarioCanvas.VICTORY_PRIMARIES.find(str(scenario.victory_value("primary"))), 0))
	_object_box.add_child(_field("Primary score", pr))
	var st := _spin(0, 9999, int(scenario.victory_value("score_target")))
	st.name = "VictoryScoreTarget"
	st.tooltip_text = "A side that reaches this primary score wins at once; 0 means no score win"
	st.value_changed.connect(func(v: float) -> void: _edit(func() -> String: return scenario.set_victory("score_target", int(v))))
	_object_box.add_child(_field("Score target", st))
	for key: String in ["annihilation", "withdrawal"]:
		var cb := CheckBox.new()
		cb.name = "Victory_" + key
		cb.text = {"annihilation": "A side with no squads fielded loses", "withdrawal": "A side that withdraws its last squads loses"}[key]
		cb.button_pressed = bool(scenario.victory_value(key))
		cb.toggled.connect(func(on: bool) -> void: _edit(func() -> String: return scenario.set_victory(key, on)))
		_object_box.add_child(cb)


func _add_selection_box() -> void:
	if scenario == null:
		_object_box.add_child(_hint("Pick a scenario above, or give a new one an id and press New, to place zones and deployment areas."))
		return
	if selected.is_empty():
		_object_box.add_child(_hint("With the Objects tool (O), click a zone or a deployment area to edit it. Drag to move it."))
		return
	var i: int = selected["index"]
	if selected["kind"] == "zone" and i < scenario.zones.size():
		var z: Dictionary = scenario.zones[i]
		var zid := LineEdit.new()
		zid.name = "ZoneId"
		zid.text = str(z["id"])
		zid.text_submitted.connect(func(t: String) -> void: _edit(func() -> String: return scenario.set_zone(i, "id", t)))
		zid.focus_exited.connect(func() -> void:
			if scenario != null and i < scenario.zones.size() and zid.text != str(scenario.zones[i]["id"]):
				_edit(func() -> String: return scenario.set_zone(i, "id", zid.text)))
		_object_box.add_child(_field("Zone", zid))
		for key: String in ["radius", "vp", "threshold", "decay", "buffer"]:
			var sp := _spin(0 if key != "radius" else 1, 999, int(z.get(key, 0)))
			sp.name = "Zone_" + key
			sp.value_changed.connect(func(v: float) -> void: _edit(func() -> String: return scenario.set_zone(i, key, int(v))))
			_object_box.add_child(_field({"radius": "Radius (m)", "vp": "Points", "threshold": "Threshold", "decay": "Decay", "buffer": "Buffer"}[key], sp))
		_object_box.add_child(_button("Repeat on mirror side", _repeat_on_mirror, "Copy this zone to the mirrored cell, players 1 and 2 swapped (needs a mirror on the map)"))
		_object_box.add_child(_button("Delete zone", remove_selected, "Delete key"))
	elif selected["kind"] == "side" and i < scenario.sides.size():
		var sd: Dictionary = scenario.sides[i]
		var pl := _spin(1, 8, int(sd["player"]))
		pl.name = "SidePlayer"
		pl.value_changed.connect(func(v: float) -> void: _edit(func() -> String: return scenario.set_side(i, "player", int(v))))
		_object_box.add_child(_field("Side of player", pl))
		var names := PackedStringArray(ScenarioCanvas.FACINGS.keys())
		var fc := _options(names, func(at: int) -> void: _edit(func() -> String: return scenario.set_side(i, "facing", ScenarioCanvas.FACINGS[names[at]])))
		fc.name = "SideFacing"
		fc.select(maxi(ScenarioCanvas.FACINGS.values().find(int(sd["facing"])), 0))
		_object_box.add_child(_field("Faces", fc))
		var d: Dictionary = sd["deploy"]
		_object_box.add_child(_hint("Deployment area %d × %d m at %d, %d. Drag its corner handle to resize it." % [d["w"], d["h"], d["x"], d["y"]]))
		var squads: Array = sd["squads"]
		_object_box.add_child(_hint("Squads (%d). With none, the commanders bring their own." % squads.size()))
		for j in squads.size():
			var row := HBoxContainer.new()
			var l := Label.new()
			l.text = _squad_name(str(squads[j]))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			row.add_child(l)
			row.add_child(_button("×", func() -> void:
				scenario.begin()
				scenario.remove_squad(i, j)
				_fill_object_box()
				changed(), "Remove this squad"))
			_object_box.add_child(row)
		var add_row := HBoxContainer.new()
		var pick := OptionButton.new()
		pick.name = "SquadPick"
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		for q in squad_ids:
			pick.add_item(_squad_name(q))
		add_row.add_child(pick)
		add_row.add_child(_button("Add", func() -> void:
			if pick.selected < 0:
				return
			scenario.begin()
			scenario.add_squad(i, squad_ids[pick.selected])
			_fill_object_box()
			changed(), "Add the chosen squad to this side"))
		_object_box.add_child(add_row)
		_object_box.add_child(_button("Repeat on mirror side", _repeat_on_mirror, "Copy this side to the mirrored area for the other player, facing turned the same way (needs a mirror on the map)"))
		_object_box.add_child(_button("Delete side", remove_selected, "Delete key"))


## Repeats the selected zone or side on the mirrored side of the map, and
## selects the copy. Refused, with why, if the map has no mirror or the copy
## would clash.
func _repeat_on_mirror() -> void:
	if scenario == null or selected.is_empty() or canvas == null:
		return
	var kind: String = selected["kind"]
	scenario.begin()
	var why := scenario.repeat_on_mirror(kind, selected["index"], canvas.mirror, canvas.width, canvas.height)
	if not why.is_empty():
		scenario.undo()
		_say(why)
		return
	var n := scenario.zones.size() if kind == "zone" else scenario.sides.size()
	select_object({"kind": kind, "index": n - 1})
	changed()
	_say("Repeated on the mirror side. The copy is selected; it is its own object, so moving one does not move the other.")


## One edit from the panel: an undo step, the edit, and its refusal if any.
func _edit(action: Callable) -> void:
	if scenario == null:
		return
	scenario.begin()
	var why: String = action.call()
	if not why.is_empty():
		scenario.undo()
		_say(why)
	changed()


func _squad_name(id: String) -> String:
	if model != null and model.templates != null and model.templates.has(id):
		return str(model.templates.values_of(id).get("name", id))
	return id


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("9aa3af"))
	l.add_theme_font_size_override("font_size", 12)
	return l


func _field(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


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
	if not same:
		selection = Rect2i()
		selected_stamp = -1
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
	## Wall pieces (ConnectShape) are drawn from the zoom the arrows are.
	const SHAPES_FROM := 9.0

	var painter: MapPainter
	## Pixels per cell, and where the map's top-left corner is drawn.
	var zoom: float = 4.0
	var origin: Vector2 = Vector2.ZERO
	var hover: Vector2i = Vector2i(-1, -1)

	var _tex: ImageTexture
	var _tex_rev: int = -1
	var _tex_of: MapCanvas
	## The wall piece at each cell (pieces_for): the sides it joins, -1 for none.
	var _pieces: PackedInt32Array = PackedInt32Array()
	var _pieces_rev: int = -1
	var _pieces_of: MapCanvas
	## The view shows the whole map until the user zooms or drags it.
	var _auto_fit: bool = true
	var _panning: bool = false
	var _stroke: bool = false
	var _start: Vector2i
	var _last: Vector2i
	var _f: int = 0
	var _fc: int = 0
	## An object being dragged: the selection, where the drag began, the
	## object's place (or size, for "resize") then, and whether it has moved.
	var _held: Dictionary = {}
	var _held_from: Vector2i
	var _held_base: Vector2i
	var _held_resize: bool = false
	var _held_moved: bool = false
	## The Select tool: dragging a marquee, or a stamp (and where it was).
	var _marquee: bool = false
	var _stamp_drag: bool = false
	var _stamp_from: Vector2i
	var _stamp_base: Vector2i

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
		if painter.tool == MapPainter.Tool.OBJECT:
			_press_object(cell, erase)
			return
		if painter.tool == MapPainter.Tool.SELECT:
			_press_select(cell, erase)
			return
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
					var shown := c.composite()
					painter.set_feature((shown["feature"] as PackedInt32Array)[cell.y * c.width + cell.x])
					painter.set_facing((shown["facing"] as PackedByteArray)[cell.y * c.width + cell.x])
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

	## The Select tool: a stamp under the cell is picked up to be moved,
	## otherwise a marquee starts. The right button clears both.
	func _press_select(cell: Vector2i, erase: bool) -> void:
		var c := painter.canvas
		_stamp_drag = false
		_marquee = false
		if erase:
			painter.selection = Rect2i()
			painter.selected_stamp = -1
			painter.changed()
			return
		var at := c.stamp_at(cell.x, cell.y)
		if at >= 0:
			painter.selected_stamp = at
			painter.selection = c.stamp_rect(at)
			_stamp_drag = true
			_held_moved = false
			_stamp_from = cell
			_stamp_base = painter.selection.position
		else:
			painter.selected_stamp = -1
			_marquee = true
			_start = cell
			painter.selection = Rect2i(cell, Vector2i.ONE)
		painter.changed()

	func _drag_select(cell: Vector2i) -> void:
		var c := painter.canvas
		if _stamp_drag:
			var to := _stamp_base + cell - _stamp_from
			if not _held_moved:
				if to == _stamp_base:
					return
				c.begin()
				_held_moved = true
			c.move_stamp(painter.selected_stamp, to.x, to.y)
			painter.selection = c.stamp_rect(painter.selected_stamp)
		elif _marquee:
			var lo := Vector2i(mini(_start.x, cell.x), mini(_start.y, cell.y))
			var hi := Vector2i(maxi(_start.x, cell.x), maxi(_start.y, cell.y))
			painter.selection = Rect2i(lo, hi - lo + Vector2i.ONE)
		painter.changed()

	## The Objects tool: select what is at the cell and get ready to drag it
	## (an area's corner handle resizes it). The right button deselects.
	func _press_object(cell: Vector2i, erase: bool) -> void:
		var s := painter.scenario
		_held = {}
		if s == null:
			painter._say("Pick or make a scenario first.")
			return
		if erase:
			painter.select_object({})
			return
		var sel := painter.selected
		_held_resize = false
		if sel.get("kind", "") == "side" and int(sel["index"]) < s.sides.size():
			var r := s.area_rect(sel["index"])
			if absi(cell.x - (r.end.x - 1)) <= 1 and absi(cell.y - (r.end.y - 1)) <= 1:
				_held_resize = true
		var hit := sel if _held_resize else s.object_at(cell.x, cell.y)
		if hit != sel:
			painter.select_object(hit)
		if hit.is_empty():
			return
		_held = hit
		_held_from = cell
		_held_moved = false
		if hit["kind"] == "zone":
			_held_base = Vector2i(s.zones[hit["index"]]["x"], s.zones[hit["index"]]["y"])
		else:
			var r := s.area_rect(hit["index"])
			_held_base = r.size if _held_resize else r.position

	func _drag_object(cell: Vector2i) -> void:
		var s := painter.scenario
		var c := painter.canvas
		if _held.is_empty() or s == null or cell == _held_from and not _held_moved:
			return
		if not _held_moved:
			s.begin()
			_held_moved = true
		var to := _held_base + cell - _held_from
		var i: int = _held["index"]
		if _held["kind"] == "zone":
			s.move_zone(i, clampi(to.x, 0, c.width - 1), clampi(to.y, 0, c.height - 1))
		elif _held_resize:
			var at := s.area_rect(i).position
			s.resize_area(i, clampi(to.x, 1, c.width - at.x), clampi(to.y, 1, c.height - at.y))
		else:
			var size_of := s.area_rect(i).size
			s.move_area(i, clampi(to.x, 0, maxi(c.width - size_of.x, 0)), clampi(to.y, 0, maxi(c.height - size_of.y, 0)))
		painter.changed()

	func drag(cell: Vector2i) -> void:
		if painter.tool == MapPainter.Tool.OBJECT:
			_drag_object(cell)
			return
		if painter.tool == MapPainter.Tool.SELECT:
			_drag_select(cell)
			return
		if _stroke and painter.tool == MapPainter.Tool.BRUSH and cell != _last:
			painter.canvas.line(_last.x, _last.y, cell.x, cell.y, _f, _fc, painter.brush)
			_last = cell
			painter.changed()

	func release(cell: Vector2i) -> void:
		var c := painter.canvas
		if _stamp_drag or _marquee:
			_stamp_drag = false
			_marquee = false
			_held_moved = false
			painter.changed()
			return
		if not _held.is_empty():
			var moved := _held_moved
			_held = {}
			_held_moved = false
			if moved:
				painter._fill_object_box()  # its numbers changed
			painter.changed()
			return
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
			KEY_O: painter.set_tool(MapPainter.Tool.OBJECT)
			KEY_M: painter.set_tool(MapPainter.Tool.SELECT)
			KEY_DELETE: painter.remove_selected()
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
		if zoom >= SHAPES_FROM:
			var pieces := pieces_for(c)
			for y in range(y0, y1):
				for x in range(x0, x1):
					var sides := pieces[y * c.width + x]
					if sides >= 0:
						_piece(origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * zoom, sides)
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
		if painter.scenario != null:
			_draw_objects(painter.scenario)
		if painter.selection.size.x > 0:
			var sr := painter.selection
			var box := Rect2(origin + Vector2(sr.position) * zoom, Vector2(sr.size) * zoom)
			draw_rect(box, Color(INK, 0.15))
			draw_dashed_line(box.position, box.position + Vector2(box.size.x, 0), INK, 1.0, 4.0)
			draw_dashed_line(box.position + Vector2(0, box.size.y), box.end, INK, 1.0, 4.0)
			draw_dashed_line(box.position, box.position + Vector2(0, box.size.y), INK, 1.0, 4.0)
			draw_dashed_line(box.position + Vector2(box.size.x, 0), box.end, INK, 1.0, 4.0)
		if painter.tool != MapPainter.Tool.OBJECT:
			_draw_cursor(c)

	## The open scenario's deployment areas and zones, over the terrain.
	func _draw_objects(s: ScenarioCanvas) -> void:
		var font := get_theme_default_font()
		var sel := painter.selected
		var live := painter.tool == MapPainter.Tool.OBJECT
		for i in s.sides.size():
			var side: Dictionary = s.sides[i]
			var col: Color = TeamPalette.color(int(side["player"]))
			var r := s.area_rect(i)
			var box := Rect2(origin + Vector2(r.position) * zoom, Vector2(r.size) * zoom)
			var chosen: bool = live and sel.get("kind", "") == "side" and sel["index"] == i
			draw_rect(box, Color(col, 0.2 if live else 0.12))
			draw_rect(box, INK if chosen else Color(col, 0.9), false, 2.0 if chosen else 1.0)
			var n := (side["squads"] as Array).size()
			draw_string(font, box.position + Vector2(4, 14), "P%d  ·  %s" % [side["player"], "%d squad%s" % [n, "" if n == 1 else "s"] if n > 0 else "commander's force"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col.lightened(0.5), 0.95))
			# Facing: an arrow from the middle of the area.
			var ang := float(int(side["facing"])) / 65536.0 * TAU
			var dir := Vector2(cos(ang), sin(ang))
			var mid := box.get_center()
			var tip := mid + dir * 18.0
			draw_line(mid, tip, Color(col.lightened(0.5), 0.9), 2.0)
			draw_colored_polygon(PackedVector2Array([tip + dir * 7.0, tip + dir.orthogonal() * 5.0, tip - dir.orthogonal() * 5.0]), Color(col.lightened(0.5), 0.9))
			if chosen:
				draw_rect(Rect2(box.end - Vector2(8, 8), Vector2(8, 8)), INK)
		for i in s.zones.size():
			var z: Dictionary = s.zones[i]
			var at := origin + (Vector2(int(z["x"]), int(z["y"])) + Vector2(0.5, 0.5)) * zoom
			var rad := float(int(z["radius"])) * zoom
			var chosen: bool = live and sel.get("kind", "") == "zone" and sel["index"] == i
			draw_circle(at, rad, Color(1, 1, 1, 0.1 if live else 0.06))
			draw_arc(at, rad, 0.0, TAU, 48, INK if chosen else Color(1, 1, 1, 0.8), 2.0 if chosen else 1.0)
			draw_line(at - Vector2(4, 0), at + Vector2(4, 0), Color(1, 1, 1, 0.8), 1.0)
			draw_line(at - Vector2(0, 4), at + Vector2(0, 4), Color(1, 1, 1, 0.8), 1.0)
			draw_string(font, at + Vector2(-60, rad + 14), "%s  ·  %d pt%s" % [z["id"], int(z.get("vp", 0)), "" if int(z.get("vp", 0)) == 1 else "s"],
				HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(1, 1, 1, 0.9))

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

	## The wall piece at each cell, as the sides it joins (-1: no piece), from
	## MapCanvas.shape_at. Kept until the canvas changes.
	func pieces_for(c: MapCanvas) -> PackedInt32Array:
		if _pieces_of == c and _pieces_rev == c.revision:
			return _pieces
		_pieces = PackedInt32Array()
		_pieces.resize(c.width * c.height)
		for y in c.height:
			for x in c.width:
				var p := c.shape_at(x, y)
				_pieces[y * c.width + x] = -1 if p.is_empty() else ConnectShape.sides_of(p["shape"], p["turn"])
		_pieces_of = c
		_pieces_rev = c.revision
		return _pieces

	## A wall piece at a cell's centre: a bar from the centre to the edge of
	## each side it joins, or a post when it joins none.
	func _piece(at: Vector2, sides: int) -> void:
		var ink := Color(1, 1, 1, 0.55)
		if sides == 0:
			draw_circle(at, zoom * 0.14, ink)
			return
		var half := zoom * 0.5
		var width := maxf(zoom * 0.2, 1.0)
		var dirs: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
		for side in 4:
			if sides & (1 << side):
				draw_line(at, at + dirs[side] * half, ink, width)

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
		_tex = ImageTexture.create_from_image(ArtSet.ground_image(painter.art, c.width, c.height, f, painter.feature_ids, painter.colors))
		_tex_of = c
		_tex_rev = c.revision
