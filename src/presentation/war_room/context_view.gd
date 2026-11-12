class_name ContextView
extends Control
## Draws one presentation context into its rect: the overworld as the player
## knows it (OverworldSession.observe) or a battle (observe_battle).
## Stateless projection (GDD 04 §4.8): it keeps only the last observation it
## was given, and reports clicks and zooms as signals for its owner.

signal hex_clicked(plot: int, button: int)
## A click in a battle at a battlefield point (metres).
signal battle_pressed(at: Vector2, button: int, shift: bool, ctrl: bool, alt: bool, double: bool)
## A box dragged in a battle (metres).
signal battle_box(rect: Rect2, add: bool)
signal zoomed(factor: float)

const HEX_SIZE: float = 26.0
const ONE: float = 65536.0
const BG: Color = Color("12151a")
const FOG: Color = Color("1b1f26")
const LINE: Color = Color("323a46")
const TEXT: Color = Color("dde2ea")
const SELECT: Color = Color("e6b450")
const BATTLE: Color = Color("e8735f")
const GHOST: Color = Color(0.85, 0.9, 1.0, 0.55)
const PLAYER_COLORS: Dictionary = {1: Color(0.25, 0.55, 1.0), 2: Color(1.0, 0.35, 0.3), 30: Color(0.85, 0.85, 0.85)}
## Plot colour: the first listed feature present wins; else plains.
const FEATURE_COLORS: Array = [
	["hex_spaceport", Color("9fb3c8")], ["hex_angel_blockade", Color("d9d2f2")], ["hex_cliffs", Color("4a4440")],
	["hex_frontier_town", Color("b9a46a")],
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
## Own commanders' planned routes: commander ID -> plots.
var _routes: Dictionary = {}
var _overlay: Dictionary = {}
var _press_at: Vector2 = Vector2.ZERO
var _box: Rect2 = Rect2()
var _pressing: bool = false


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
	_routes = obs.get("routes", {})
	queue_redraw()


## Shows a battle (OverworldSession.observe_battle). `overlay` (all
## optional): "selected" (squad IDs), "ghosts" and "contacts"
## (IntentForecast), "drafts" (squad ID -> order), "reactable" (squad ID
## -> queued reaction name or "").
func show_battle(obs: Dictionary, overlay: Dictionary = {}) -> void:
	mode = "battle"
	_obs = obs
	_overlay = overlay
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
		var route: PackedInt64Array = _routes.get(cmd["id"], PackedInt64Array())
		var prev := o + _centre(cmd["plot"])
		for p in route:
			var nxt := o + _centre(p)
			draw_dashed_line(prev, nxt, SELECT, 2.0, 6.0)
			prev = nxt
		if not route.is_empty():
			draw_arc(prev, s * 0.2, 0, TAU, 12, SELECT, 2.0)
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
	var area := battle_area()
	if area.size == Vector2.ZERO:
		return
	var k := area.size.x / float(_obs["width"])
	draw_rect(area, Color("2a3029"))
	draw_rect(area, LINE, false, 1.0)
	var font := get_theme_default_font()
	var pos := {}
	for sq: Dictionary in _obs.get("squads", []):
		if not (sq.get("destroyed", false) or sq.get("withdrawn", false)):
			pos[sq["id"]] = area.position + Vector2(sq["x"] / ONE, sq["y"] / ONE) * k
	# Intent ghosts: the forecast path and end of each own squad.
	var ghosts: Dictionary = _overlay.get("ghosts", {})
	for id: int in ghosts:
		if not pos.has(id):
			continue
		var pts: PackedInt64Array = ghosts[id]
		var prev: Vector2 = pos[id]
		for j in range(0, pts.size(), 2):
			var g := area.position + Vector2(pts[j] / ONE, pts[j + 1] / ONE) * k
			draw_dashed_line(prev, g, GHOST, 1.5, 4.0)
			prev = g
		draw_arc(prev, 5.0, 0, TAU, 16, GHOST, 1.5)
	var drafts: Dictionary = _overlay.get("drafts", {})
	for id: int in drafts:
		var o: Dictionary = drafts[id]
		if o.get("type") == "attack" and pos.has(id) and pos.has(o.get("target")):
			draw_line(pos[id], pos[o["target"]], BATTLE, 1.5)
	var selected: Array = _overlay.get("selected", [])
	var reactable: Dictionary = _overlay.get("reactable", {})
	for sq: Dictionary in _obs.get("squads", []):
		if not pos.has(sq["id"]):
			continue
		var c: Vector2 = pos[sq["id"]]
		var r := clampf(2.0 + 0.6 * float(sq["alive"]), 3.0, 9.0) * (0.7 if compact else 1.0)
		draw_circle(c, r, PLAYER_COLORS.get(sq["player"], TEXT))
		if selected.has(sq["id"]):
			draw_arc(c, r + 3.0, 0, TAU, 20, SELECT, 2.0)
		if reactable.has(sq["id"]) and not compact:
			var q: String = reactable[sq["id"]]
			var mark := "!" if q.is_empty() else ReactionRadial.glyph(q)
			draw_arc(c, r + 7.0, 0, TAU, 20, SELECT, 1.5)
			draw_string(font, c + Vector2(r + 6, -r - 4), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SELECT)
	for ct: Dictionary in _overlay.get("contacts", []):
		var id: int = ct["squad"]
		if ghosts.has(id) and pos.has(id) and not compact:
			var pts: PackedInt64Array = ghosts[id]
			var g := area.position + Vector2(pts[pts.size() - 2] / ONE, pts[pts.size() - 1] / ONE) * k
			draw_string(font, g + Vector2(6, 4), "⚔", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BATTLE)
	if _box.size != Vector2.ZERO:
		draw_rect(_box.abs(), Color(SELECT, 0.15))
		draw_rect(_box.abs(), SELECT, false, 1.0)
	if not title.is_empty():
		var fs := 12 if compact else 15
		var pad := 6.0 if compact else 16.0
		var w_text := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := pad if compact else size.x - pad - w_text
		draw_string(font, Vector2(x, pad + fs), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)


## The battlefield's rect in this view (Rect2() if no battle).
func battle_area() -> Rect2:
	var w := float(_obs.get("width", 0))
	var h := float(_obs.get("height", 0))
	if mode != "battle" or w <= 0 or h <= 0:
		return Rect2()
	var pad := 6.0 if compact else 16.0
	var k := minf((size.x - pad * 2) / w, (size.y - pad * 2) / h)
	return Rect2((size - Vector2(w, h) * k) / 2.0, Vector2(w, h) * k)


## A view point to battlefield metres, and back.
func to_battle(p: Vector2) -> Vector2:
	var area := battle_area()
	return (p - area.position) * float(_obs.get("width", 1)) / maxf(area.size.x, 1.0)


func to_view(m: Vector2) -> Vector2:
	var area := battle_area()
	return area.position + m * area.size.x / float(_obs.get("width", 1))


## The squad nearest a battlefield point within `radius` metres, or -1.
func squad_at(m: Vector2, radius: float = 4.0) -> int:
	var best := -1
	var best_d := radius * radius
	for sq: Dictionary in _obs.get("squads", []):
		if sq.get("destroyed", false) or sq.get("withdrawn", false):
			continue
		var d := Vector2(sq["x"] / ONE, sq["y"] / ONE).distance_squared_to(m)
		if d <= best_d:
			best_d = d
			best = sq["id"]
	return best


# --- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and _pressing and mode == "battle":
		if mm.position.distance_to(_press_at) > 6.0:
			_box = Rect2(_press_at, mm.position - _press_at)
			queue_redraw()
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mode == "battle" and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_pressing = true
			_press_at = mb.position
			_box = Rect2()
			if mb.double_click:
				_pressing = false
				battle_pressed.emit(to_battle(mb.position), MOUSE_BUTTON_LEFT, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed, true)
		elif _pressing:
			_pressing = false
			if _box.size != Vector2.ZERO:
				var a := to_battle(_box.position)
				var b := to_battle(_box.end)
				_box = Rect2()
				queue_redraw()
				battle_box.emit(Rect2(a, b - a).abs(), mb.shift_pressed)
			else:
				battle_pressed.emit(to_battle(mb.position), MOUSE_BUTTON_LEFT, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed, false)
		accept_event()
		return
	if not mb.pressed:
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
				battle_pressed.emit(to_battle(mb.position), mb.button_index, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed, false)
		_:
			return
	accept_event()
