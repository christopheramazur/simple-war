class_name UiTheme
extends RefCounted
## The game's look as data (sw-ll4.26; the Theme part of sw-ll4.9). A
## profile is a small JSON file: colours, text size, border width, corner
## radius and padding. This turns the chosen profile into one Godot Theme
## and puts it on the window, so every menu, panel, dropdown and field is
## styled from one place.
##
## Shipped profiles live in `res://data/ui/themes/`; a player's own go in
## `user://ui_themes/` (same format; a file with a shipped profile's id
## replaces it). The chosen profile's id is the `ui_theme` setting.
##
## What a player needs to tell apart is drawn apart: fields that take
## input (text boxes, number boxes, dropdowns, lists) share the `field`
## colour and its border; things that act when pressed (buttons, tabs)
## share the `button` colours; panels and plain text have neither.
##
## Screens never pick colours or sizes themselves (sw-ijp.1). They name a
## style from `res://data/ui/styles.json` through `theme_type_variation`:
## `<Size><Tone>Label` (SmallDimLabel, HeroGoodLabel), `<Tone>Bar`, and the
## panels, gaps and special labels listed there. Each is built from the
## profile, so every theme reaches every screen.

const SHIPPED_DIR := "res://data/ui/themes"
const USER_DIR := "user://ui_themes"
const STYLES_PATH := "res://data/ui/styles.json"
const DEFAULT_ID := "default"
## Used for anything a profile leaves out.
const FALLBACK: Dictionary = {
	"id": "default", "name": "Default (dark)", "font_size": 16, "border_width": 1, "corner_radius": 4, "padding": 8,
	"colors": {
		"background": "12151a", "panel": "1d2128", "text": "dde2ea", "dim": "8a93a3", "accent": "e6b450",
		"button": "2b323d", "button_border": "465064", "button_hover": "38414f", "button_pressed": "4a5567",
		"field": "0d1014", "field_border": "5b6779", "selection": "3b4d6b",
		"soft": "b9c0cc", "line": "323a46", "good": "74d18a", "bad": "e8735f",
		"overlay": "181b22", "shade": "080a0d",
		"stamina": "5bb6d9", "instinct": "b38be0", "morale": "74d18a", "prowess": "e6b450", "legend": "e07ab0",
	},
}

static var _profiles: Dictionary = {}
static var _loaded: bool = false
static var _styles: Dictionary = {}


## Every profile by id: the shipped ones, then the player's own.
static func profiles() -> Dictionary:
	if not _loaded:
		_loaded = true
		_profiles = {DEFAULT_ID: FALLBACK.duplicate(true)}
		for dir: String in [SHIPPED_DIR, USER_DIR]:
			var d := DirAccess.open(dir)
			if d == null:
				continue
			var files := Array(d.get_files())
			files.sort()
			for f: String in files:
				if not f.ends_with(".json"):
					continue
				var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + f))
				if data is Dictionary and not str((data as Dictionary).get("id", "")).is_empty():
					_profiles[str(data["id"])] = complete(data)
	return _profiles


## Reads the profile files again (after one was added or changed).
static func reload() -> void:
	_loaded = false
	_styles = {}


## The named styles (data/ui/styles.json).
static func styles() -> Dictionary:
	if _styles.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(STYLES_PATH))
		if data is Dictionary:
			_styles = data
		else:
			push_error("UiTheme: can't read %s" % STYLES_PATH)
	return _styles


## A label in a named style.
static func label(text: String, style: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = style
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A flat panel in a named style, filling its parent.
static func backdrop(style: String) -> Panel:
	var p := Panel.new()
	p.theme_type_variation = style
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	return p


## Profile ids in menu order: the default first, then by name.
static func ids() -> PackedStringArray:
	var all := profiles()
	var rest: Array = all.keys().filter(func(k: String) -> bool: return k != DEFAULT_ID)
	rest.sort_custom(func(a: String, b: String) -> bool: return str(all[a]["name"]) < str(all[b]["name"]))
	var out := PackedStringArray([DEFAULT_ID])
	out.append_array(PackedStringArray(rest))
	return out


static func profile(id: String) -> Dictionary:
	var all := profiles()
	return all[id] if all.has(id) else all[DEFAULT_ID]


## A profile with everything it leaves out filled in from the fallback.
static func complete(p: Dictionary) -> Dictionary:
	var out := FALLBACK.duplicate(true)
	for k: String in p:
		if k == "colors" and p[k] is Dictionary:
			for c: String in p[k]:
				if Color.html_is_valid(str(p[k][c])):
					out["colors"][c] = str(p[k][c])
		elif k != "colors":
			out[k] = p[k]
	return out


static func color(p: Dictionary, name: String) -> Color:
	return Color.html(str(p["colors"].get(name, FALLBACK["colors"][name])))


## Puts the chosen profile's theme on a window (every Control in it
## inherits it).
static func apply(window: Window, id: String = "") -> void:
	if window == null:
		return
	if id.is_empty():
		id = str(GameSettings.value("ui_theme"))
	window.theme = build(profile(id))


## Themes a window nothing has themed yet (a scene run on its own, F6).
static func ensure(window: Window) -> void:
	if window != null and window.theme == null:
		apply(window)


## A Godot Theme made from a profile.
static func build(p: Dictionary) -> Theme:
	var t := Theme.new()
	var size := int(p["font_size"])
	var bw := int(p["border_width"])
	var rad := int(p["corner_radius"])
	var pad := int(p["padding"])
	var text := color(p, "text")
	var dim := color(p, "dim")
	var accent := color(p, "accent")
	t.default_font_size = size
	# Buttons: things that act when pressed.
	var b_normal := _box(color(p, "button"), color(p, "button_border"), bw, rad, pad)
	var b_hover := _box(color(p, "button_hover"), accent, bw, rad, pad)
	var b_pressed := _box(color(p, "button_pressed"), accent, bw, rad, pad)
	var b_off := _box(Color(color(p, "button"), 0.5), Color(color(p, "button_border"), 0.4), bw, rad, pad)
	var focus := _box(Color(0, 0, 0, 0), accent, maxi(bw, 1) + 1, rad, pad)
	for type: String in ["Button", "MenuButton"]:
		t.set_stylebox("normal", type, b_normal)
		t.set_stylebox("hover", type, b_hover)
		t.set_stylebox("pressed", type, b_pressed)
		t.set_stylebox("hover_pressed", type, b_pressed)
		t.set_stylebox("disabled", type, b_off)
		t.set_stylebox("focus", type, focus)
		_font_colors(t, type, text, dim)
	# Fields: things that take input. Dropdowns are fields, not buttons.
	var f_normal := _box(color(p, "field"), color(p, "field_border"), maxi(bw, 1), rad, pad)
	var f_hover := _box(color(p, "field"), accent, maxi(bw, 1), rad, pad)
	var f_off := _box(Color(color(p, "field"), 0.5), Color(color(p, "field_border"), 0.4), maxi(bw, 1), rad, pad)
	t.set_stylebox("normal", "OptionButton", f_normal)
	t.set_stylebox("hover", "OptionButton", f_hover)
	t.set_stylebox("pressed", "OptionButton", f_hover)
	t.set_stylebox("disabled", "OptionButton", f_off)
	t.set_stylebox("focus", "OptionButton", focus)
	_font_colors(t, "OptionButton", text, dim)
	for type: String in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, f_normal)
		t.set_stylebox("focus", type, f_hover)
		t.set_stylebox("read_only", type, f_off)
		t.set_color("font_color", type, text)
		t.set_color("font_placeholder_color", type, Color(dim, 0.7))
		t.set_color("caret_color", type, accent)
		t.set_color("selection_color", type, color(p, "selection"))
	for type: String in ["ItemList", "Tree"]:
		t.set_stylebox("panel", type, _box(color(p, "field"), color(p, "field_border"), maxi(bw, 1), rad, 4))
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("selected", type, _box(color(p, "selection"), Color(0, 0, 0, 0), 0, 2, 2))
		t.set_stylebox("selected_focus", type, _box(color(p, "selection"), Color(0, 0, 0, 0), 0, 2, 2))
		t.set_color("font_color", type, text)
		t.set_color("font_selected_color", type, Color.WHITE)
	for type: String in ["CheckBox", "CheckButton"]:
		_font_colors(t, type, text, dim)
		t.set_stylebox("focus", type, focus)
	# Popups, tooltips, tabs, text.
	t.set_stylebox("panel", "PopupMenu", _box(color(p, "panel"), color(p, "field_border"), maxi(bw, 1), rad, 6))
	t.set_stylebox("hover", "PopupMenu", _box(color(p, "selection"), Color(0, 0, 0, 0), 0, 2, 2))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "TooltipPanel", _box(color(p, "background"), accent, 1, rad, 8))
	t.set_color("font_color", "TooltipLabel", text)
	t.set_font_size("font_size", "TooltipLabel", maxi(size - 2, 10))
	t.set_stylebox("tab_selected", "TabContainer", _box(color(p, "panel"), accent, bw, rad, pad))
	t.set_stylebox("tab_unselected", "TabContainer", _box(color(p, "background"), color(p, "button_border"), bw, rad, pad))
	t.set_stylebox("tab_hovered", "TabContainer", b_hover)
	t.set_stylebox("panel", "TabContainer", _box(color(p, "panel"), Color(0, 0, 0, 0), 0, 0, 6))
	t.set_color("font_selected_color", "TabContainer", text)
	t.set_color("font_unselected_color", "TabContainer", dim)
	t.set_color("font_hovered_color", "TabContainer", text)
	t.set_color("font_color", "Label", text)
	t.set_color("default_color", "RichTextLabel", text)
	var line := StyleBoxLine.new()
	line.color = Color(color(p, "field_border"), 0.7)
	t.set_stylebox("separator", "HSeparator", line)
	_add_styles(t, p)
	return t


## The named styles, built from the profile. Text sizes are written for the
## default size and grow with the profile's.
static func _add_styles(t: Theme, p: Dictionary) -> void:
	var s := styles()
	var scale := float(p["font_size"]) / float(FALLBACK["font_size"])
	var sizes: Dictionary = s.get("text_sizes", {})
	var tones: Dictionary = s.get("tones", {})
	for size_name: String in sizes:
		for tone: String in tones:
			if not (size_name + tone).is_empty():
				_add_label(t, size_name + tone + "Label", {"size": sizes[size_name], "color": tones[tone]}, p, scale)
	for tone: String in tones:
		if not tone.is_empty():
			_add_panel(t, tone + "Bar", {"bg": tones[tone]}, p)
	var labels: Dictionary = s.get("labels", {})
	for style: String in labels:
		_add_label(t, style, labels[style], p, scale)
	var panels: Dictionary = s.get("panels", {})
	for style: String in panels:
		_add_panel(t, style, panels[style], p)
	var gaps: Dictionary = s.get("gaps", {})
	for style: String in gaps:
		var g: Variant = gaps[style]
		var h := int(g["h"]) if g is Dictionary else int(g)
		var v := int(g["v"]) if g is Dictionary else int(g)
		t.set_type_variation(style, "Container")
		t.set_constant("separation", style, h)
		t.set_constant("h_separation", style, h)
		t.set_constant("v_separation", style, v)


## Works on a Label and on a RichTextLabel.
static func _add_label(t: Theme, style: String, d: Dictionary, p: Dictionary, scale: float) -> void:
	t.set_type_variation(style, "Label")
	var size := int(d.get("size", 0))
	if size > 0:
		t.set_font_size("font_size", style, roundi(size * scale))
		t.set_font_size("normal_font_size", style, roundi(size * scale))
	if not str(d.get("color", "")).is_empty():
		t.set_color("font_color", style, _resolve(p, d["color"]))
		t.set_color("default_color", style, _resolve(p, d["color"]))
	if d.has("outline"):
		t.set_color("font_outline_color", style, _resolve(p, d["outline"]))
		t.set_constant("outline_size", style, int(d.get("outline_size", 0)))
	if d.has("line_spacing"):
		t.set_constant("line_spacing", style, int(d["line_spacing"]))


static func _add_panel(t: Theme, style: String, d: Dictionary, p: Dictionary) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(_resolve(p, d["bg"]), float(d.get("alpha", 1.0)))
	var width := int(d.get("border_width", 0))
	if width > 0:
		sb.border_color = _resolve(p, d["border"])
		sb.set_border_width_all(maxi(width, int(p["border_width"])))
	sb.set_corner_radius_all(int(d.get("radius", 0)))
	var m: Variant = d.get("margin")
	if m is Array:
		sb.content_margin_left = m[0]
		sb.content_margin_top = m[1]
		sb.content_margin_right = m[2]
		sb.content_margin_bottom = m[3]
	elif m != null:
		sb.set_content_margin_all(m)
	t.set_type_variation(style, "PanelContainer")
	t.set_stylebox("panel", style, sb)


## A profile colour by name, or a literal hex colour.
static func _resolve(p: Dictionary, name: Variant) -> Color:
	var key := str(name)
	if p["colors"].has(key):
		return Color.html(str(p["colors"][key]))
	if not Color.html_is_valid(key):
		push_error("UiTheme: unknown colour '%s'" % key)
		return Color.MAGENTA
	return Color.html(key)


static func _font_colors(t: Theme, type: String, text: Color, dim: Color) -> void:
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_pressed_color", type, Color.WHITE)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_disabled_color", type, Color(dim, 0.6))


static func _box(bg: Color, border: Color, width: int, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	@warning_ignore("integer_division")
	sb.content_margin_top = pad / 2
	@warning_ignore("integer_division")
	sb.content_margin_bottom = pad / 2
	return sb
