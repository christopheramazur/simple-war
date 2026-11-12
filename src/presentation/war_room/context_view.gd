class_name ContextView
extends Control
## Draws one presentation context into its rect: the overworld as the player
## knows it (OverworldSession.observe) or a battle (observe_battle).
## Stateless projection (GDD 04 §4.8): it keeps only the last observation it
## was given, and reports clicks and zooms as signals for its owner.

signal hex_clicked(plot: int, button: int)
signal battle_clicked(button: int)
signal zoomed(factor: float)

const HEX_SIZE: float = 26.0
const ONE: float = 65536.0
const BG: Color = Color("12151a")
const FOG: Color = Color("1b1f26")
const LINE: Color = Color("323a46")
const TEXT: Color = Color("dde2ea")
const SELECT: Color = Color("e6b450")
const BATTLE: Color = Color("e8735f")
const PLAYER_COLORS: Dictionary = {1: Color(0.25, 0.55, 1.0), 2: Color(1.0, 0.35, 0.3), 30: Color(0.85, 0.85, 0.85)}
## Plot colour: the first listed feature present wins; else plains.
const FEATURE_COLORS: Array = [
	["hex_lake", Color("2d4f6e")], ["hex_village", Color("b9a46a")], ["hex_barracks", Color("9a7f5e")],
	["hex_depot", Color("8f8a6c")], ["hex_mine", Color("6f6a64")], ["hex_bandit_camp", Color("7a4a42")],
	["hex_shrine", Color("8d7aa8")], ["hex_supply_cache", Color("c8b25c")], ["hex_arms_cache", Color("c8b25c")],
	["hex_ore_deposit", Color("75706a")], ["hex_road", Color("8b8476")], ["hex_hills", Color("6e6a52")],
	["hex_forest", Color("3f5a40")], ["hex_plains", Color("5d6b4c")],
]

## "overworld", "battle" or "" (nothing yet).
var mode: String = ""
var compact: bool = false
## Shown in a corner of a battle view (top right; top left when compact).
var title: String = ""
var _obs: Dictionary = {}
var _names: PackedStringArray = PackedStringArray()
var _width: int = 0
var _height: int = 0
var _camera: int = -1
var _zoom: float = 1.0
var _selected: int = -1
var _selected_plot: int = -1
var _battles: Dictionary = {}


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## Shows the overworld: `obs` from OverworldSession.observe, `names` the
## feature template IDs (OverworldRules.feature_ids), the contexts for the
## camera and selection.
func show_overworld(obs: Dictionary, names: PackedStringArray, ctx: ViewContexts) -> void:
	mode = "overworld"
	_obs = obs
	_names = names
	_width = obs.get("width", 0)
	_height = obs.get("height", 0)
	_camera = ctx.camera_plot
	_zoom = ctx.zoom
	_selected = ctx.selected
	_selected_plot = ctx.selected_plot
	_battles = {}
	for eid in ctx.battles():
		_battles[ctx.battle_plot(eid)] = eid
	queue_redraw()


## Shows a battle (OverworldSession.observe_battle).
func show_battle(obs: Dictionary) -> void:
	mode = "battle"
	_obs = obs
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if mode == "overworld":
		_draw_overworld()
	elif mode == "battle":
		_draw_battle()


# --- overworld ---------------------------------------------------------------

func _hex_size() -> float:
	return HEX_SIZE * _zoom


func _centre(p: int) -> Vector2:
	var col := p % _width
	var row := p / _width
	var s := _hex_size()
	return Vector2(sqrt(3.0) * s * (col + 0.5 * (row & 1)), 1.5 * s * row)


func _origin() -> Vector2:
	var cam := _centre(_camera) if _camera >= 0 else Vector2.ZERO
	return size / 2.0 - cam


func _draw_overworld() -> void:
	if _width == 0:
		return
	var o := _origin()
	var s := _hex_size()
	var plots: Dictionary = _obs.get("plots", {})
	for p in _width * _height:
		var c := o + _centre(p)
		if c.x < -s * 2 or c.y < -s * 2 or c.x > size.x + s * 2 or c.y > size.y + s * 2:
			continue
		var col := FOG
		if plots.has(p):
			col = _plot_color(plots[p])
			if not plots[p]["visible"]:
				col = col.darkened(0.45)
		var pts := _hex_points(c, s * 0.97)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, LINE, 1.0)
		if _battles.has(p):
			draw_arc(c, s * 0.62, 0, TAU, 24, BATTLE, 3.0)
		if p == _selected_plot:
			draw_polyline(pts, SELECT, 2.5)
	for cmd: Dictionary in _obs.get("commanders", []):
		var c := o + _centre(cmd["plot"])
		var r := s * 0.36
		draw_circle(c, r, PLAYER_COLORS.get(cmd["player"], TEXT))
		if cmd["id"] == _selected:
			draw_arc(c, r + 3.0, 0, TAU, 20, SELECT, 2.5)


func _plot_color(entry: Dictionary) -> Color:
	var ids := {}
	for f: Dictionary in entry["features"]:
		if f["tmpl"] >= 0 and f["tmpl"] < _names.size():
			ids[_names[f["tmpl"]]] = true
	for pair: Array in FEATURE_COLORS:
		if ids.has(pair[0]):
			return pair[1]
	return FOG


func _hex_points(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(c + Vector2(cos(a), sin(a)) * s)
	return pts


## The plot under a point of this view, or -1.
func plot_at(pos: Vector2) -> int:
	if mode != "overworld" or _width == 0:
		return -1
	var o := _origin()
	var best := -1
	var best_d := _hex_size() * _hex_size()
	for p in _width * _height:
		var d := (o + _centre(p)).distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


# --- battle ------------------------------------------------------------------

func _draw_battle() -> void:
	var w := float(_obs.get("width", 0))
	var h := float(_obs.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var pad := 6.0 if compact else 16.0
	var k := minf((size.x - pad * 2) / w, (size.y - pad * 2) / h)
	var area := Rect2((size - Vector2(w, h) * k) / 2.0, Vector2(w, h) * k)
	draw_rect(area, Color("2a3029"))
	draw_rect(area, LINE, false, 1.0)
	for sq: Dictionary in _obs.get("squads", []):
		if sq.get("destroyed", false) or sq.get("withdrawn", false):
			continue
		var c := area.position + Vector2(sq["x"] / ONE, sq["y"] / ONE) * k
		var r := clampf(2.0 + 0.6 * float(sq["alive"]), 3.0, 9.0) * (0.7 if compact else 1.0)
		draw_circle(c, r, PLAYER_COLORS.get(sq["player"], TEXT))
	if not title.is_empty():
		var font := get_theme_default_font()
		var fs := 12 if compact else 15
		var w_text := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := pad if compact else size.x - pad - w_text
		draw_string(font, Vector2(x, pad + fs), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)


# --- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoomed.emit(1.25)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoomed.emit(0.8)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			if mode == "overworld":
				hex_clicked.emit(plot_at(mb.position), mb.button_index)
			else:
				battle_clicked.emit(mb.button_index)
		_:
			return
	accept_event()
