class_name UiLayout
extends RefCounted
## A screen's layout as data (sw-ijp.3). The screen builds its panels and
## registers them by id; a layout file says where each goes: a row of
## regions, each a column (panels in a scrolling list, then a footer) or a
## stage (layers over the map, each anchored). Moving, hiding or resizing
## a panel is a data edit. Layouts only arrange the game's own panels: no
## code, no new widgets (GDD 04, R4Q20).
##
## Shipped layouts live in `res://data/ui/layouts/<id>.json`; a player's own
## in `user://ui_layouts/<id>.json` replaces it when it is valid.
##
## Column keys: id, kind "column", style (a panel style), gap (a gap
## style), width, min_width, max_width, width_setting (a GameSettings key
## that remembers it), grip (a drag handle on its left), views (the view
## contexts it shows in; empty for all), scroll and footer (panel ids).
## Stage keys: id, kind "stage", layers (panel ids, or {id, anchor,
## offsets [left, top, right, bottom], grow "up"}). A panel registered as
## null is not on this screen and is skipped; a panel the layout leaves out
## is kept hidden, so the screen can still fill it.

const SHIPPED_DIR := "res://data/ui/layouts"
static var user_dir: String = "user://ui_layouts"

const ANCHORS: Dictionary = {
	"full_rect": Control.PRESET_FULL_RECT, "top_wide": Control.PRESET_TOP_WIDE, "bottom_wide": Control.PRESET_BOTTOM_WIDE,
	"left_wide": Control.PRESET_LEFT_WIDE, "right_wide": Control.PRESET_RIGHT_WIDE, "center": Control.PRESET_CENTER,
	"center_top": Control.PRESET_CENTER_TOP, "center_bottom": Control.PRESET_CENTER_BOTTOM,
	"top_left": Control.PRESET_TOP_LEFT, "top_right": Control.PRESET_TOP_RIGHT,
	"bottom_left": Control.PRESET_BOTTOM_LEFT, "bottom_right": Control.PRESET_BOTTOM_RIGHT,
}
const COLUMN_KEYS: Array[String] = ["id", "kind", "style", "gap", "width", "min_width", "max_width", "width_setting", "grip", "views", "scroll", "footer"]
const STAGE_KEYS: Array[String] = ["id", "kind", "layers"]
const LAYER_KEYS: Array[String] = ["id", "anchor", "offsets", "grow"]

## Which layout file was used, for the record.
var source: String = ""
## Each region's Control by id.
var regions: Dictionary = {}
var _views: Dictionary = {}


## The layout `id`: the player's own if it is valid for these panels, else
## the shipped one. {} (with an error pushed) if neither is.
static func spec(id: String, panel_ids: Array) -> Dictionary:
	for dir: String in [user_dir, SHIPPED_DIR]:
		var path := "%s/%s.json" % [dir, id]
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var errors := validate(data, panel_ids)
		if errors.is_empty():
			(data as Dictionary)["source"] = path
			return data
		var say := "UiLayout: %s is not used: %s" % [path, "; ".join(errors)]
		if dir == SHIPPED_DIR:
			push_error(say)
		else:
			push_warning(say)
	return {}


## What is wrong with a layout for these panel ids ([] if nothing).
static func validate(data: Variant, panel_ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if not data is Dictionary or not (data as Dictionary).get("row") is Array:
		out.append("a layout needs a \"row\" list of regions")
		return out
	var placed := {}
	var region_ids := {}
	for r: Variant in data["row"]:
		if not r is Dictionary:
			out.append("a region must be an object")
			continue
		var reg: Dictionary = r
		var rid := str(reg.get("id", ""))
		if rid.is_empty() or region_ids.has(rid):
			out.append("region ids must be present and unique ('%s')" % rid)
		region_ids[rid] = true
		var kind := str(reg.get("kind", ""))
		var keys: Array[String] = COLUMN_KEYS if kind == "column" else STAGE_KEYS
		if kind != "column" and kind != "stage":
			out.append("region %s: kind must be \"column\" or \"stage\"" % rid)
			continue
		for k: String in reg:
			if not keys.has(k):
				out.append("region %s: unknown key '%s'" % [rid, k])
		var ids: Array = []
		if kind == "column":
			for k: String in ["scroll", "footer", "views"]:
				if reg.has(k) and not reg[k] is Array:
					out.append("region %s: %s must be a list" % [rid, k])
			for k: String in ["width", "min_width", "max_width"]:
				if reg.has(k) and not (reg[k] is float or reg[k] is int):
					out.append("region %s: %s must be a number" % [rid, k])
			ids = Array(reg.get("scroll", [])) + Array(reg.get("footer", []))
		else:
			for layer: Variant in reg.get("layers", []):
				if layer is Dictionary:
					for k: String in layer:
						if not LAYER_KEYS.has(k):
							out.append("layer %s: unknown key '%s'" % [layer.get("id", "?"), k])
					if layer.has("anchor") and not ANCHORS.has(str(layer["anchor"])):
						out.append("layer %s: unknown anchor '%s'" % [layer.get("id", "?"), layer["anchor"]])
					if layer.has("offsets") and not (layer["offsets"] is Array and (layer["offsets"] as Array).size() == 4):
						out.append("layer %s: offsets are [left, top, right, bottom]" % layer.get("id", "?"))
					ids.append(layer.get("id", ""))
				else:
					ids.append(layer)
		for pid: Variant in ids:
			var p := str(pid)
			if not panel_ids.has(p):
				out.append("region %s: no panel '%s' on this screen" % [rid, p])
			elif placed.has(p):
				out.append("panel '%s' is placed twice" % p)
			placed[p] = true
	return out


## Builds the layout into `host` from the registered panels (id ->
## Control, or null when not on this screen). `use_settings`: remember a
## column's width in GameSettings.
static func build(data: Dictionary, panels: Dictionary, host: Control, use_settings: bool = false) -> UiLayout:
	var lay := UiLayout.new()
	lay.source = str(data.get("source", ""))
	var row := HBoxContainer.new()
	row.name = "Layout"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.theme_type_variation = &"NoGap"
	host.add_child(row)
	var placed := {}
	for reg: Dictionary in data.get("row", []):
		var region := _stage(reg, panels, placed) if reg["kind"] == "stage" else _column(reg, panels, placed, row, use_settings)
		row.add_child(region)
		lay.regions[str(reg["id"])] = region
		if not (reg.get("views", []) as Array).is_empty():
			lay._views[region] = PackedStringArray(reg["views"])
	# What the layout leaves out stays hidden but alive, so the screen can
	# still fill it.
	var spare := Control.new()
	spare.name = "Unplaced"
	spare.hide()
	host.add_child(spare)
	for pid: String in panels:
		if panels[pid] != null and not placed.has(pid):
			spare.add_child(panels[pid])
	return lay


## Shows each region that belongs to view `v` ("overworld", "battle").
func set_view(v: String) -> void:
	for region: Control in _views:
		region.visible = (_views[region] as PackedStringArray).has(v)


static func _node_name(reg: Dictionary) -> String:
	return str(reg["id"]).capitalize().replace(" ", "")


static func _stage(reg: Dictionary, panels: Dictionary, placed: Dictionary) -> Control:
	var stage := Control.new()
	stage.name = _node_name(reg)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	for layer: Variant in reg.get("layers", []):
		var d: Dictionary = layer if layer is Dictionary else {"id": layer}
		var c: Control = panels.get(str(d["id"]))
		placed[str(d["id"])] = true
		if c == null:
			continue
		if d.has("anchor"):
			c.set_anchors_preset(ANCHORS[str(d["anchor"])])
		if d.has("offsets"):
			var o: Array = d["offsets"]
			c.offset_left = o[0]
			c.offset_top = o[1]
			c.offset_right = o[2]
			c.offset_bottom = o[3]
		if str(d.get("grow", "")) == "up":
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		stage.add_child(c)
	return stage


static func _column(reg: Dictionary, panels: Dictionary, placed: Dictionary, row: HBoxContainer, use_settings: bool) -> Control:
	var col := PanelContainer.new()
	col.name = _node_name(reg)
	col.theme_type_variation = StringName(str(reg.get("style", "")))
	var lo := float(reg.get("min_width", reg.get("width", 0)))
	var hi := float(reg.get("max_width", reg.get("width", 0)))
	var w := float(reg.get("width", 0))
	var key := str(reg.get("width_setting", ""))
	if use_settings and not key.is_empty() and GameSettings.DEFAULTS.has(key):
		w = float(GameSettings.value(key))
	col.custom_minimum_size = Vector2(clampf(w, lo, hi) if hi > 0.0 else w, 0)
	if bool(reg.get("grip", false)):
		row.add_child(_grip(col, lo, hi, key if use_settings else ""))
	var box := VBoxContainer.new()
	box.theme_type_variation = StringName(str(reg.get("gap", "")))
	col.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# SHOW_NEVER, not DISABLED: a DISABLED scroll takes its content's
	# minimum width, so a wide card would widen the column, shift the stage
	# under the cursor and end the hover that showed it: a flicker
	# (sw-7m6). The column keeps the layout's width; its panels fit it.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.theme_type_variation = box.theme_type_variation
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for part: Array in [[reg.get("scroll", []), list], [reg.get("footer", []), box]]:
		for pid: Variant in part[0]:
			placed[str(pid)] = true
			var c: Control = panels.get(str(pid))
			if c != null:
				(part[1] as Control).add_child(c)
	return col


## A handle on the column's left edge: drag to resize, remembered in
## setting `key` ("" to not remember).
static func _grip(col: Control, lo: float, hi: float, key: String) -> Control:
	var grip := Panel.new()
	grip.name = "%sGrip" % col.name
	grip.theme_type_variation = &"GripPanel"
	grip.custom_minimum_size = Vector2(5, 0)
	grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	grip.tooltip_text = "Drag to make the panel wider or narrower"
	grip.gui_input.connect(func(e: InputEvent) -> void:
		var mm := e as InputEventMouseMotion
		if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			col.custom_minimum_size.x = clampf(col.custom_minimum_size.x - mm.relative.x, lo, hi)
		var mb := e as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not key.is_empty():
			GameSettings.set_value(key, int(col.custom_minimum_size.x)))
	return grip
