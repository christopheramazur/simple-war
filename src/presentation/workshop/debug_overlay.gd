class_name DebugOverlay
extends Control
## The behaviour workshop's debug overlay (sw-tho3.6, U1 B6, GDD 05 §5.7):
## draws one WorkshopDebug frame over a ContextView, using the view's camera
## (battle_area / to_view), so it pans and zooms with the battlefield.
##
## It reads frame Dictionaries only and holds no sim object: show_frame
## takes a deep copy of plain data. Layers switch on and off with set_layer:
##   ranges   each squad's longest weapon range (team colour)
##   fire     lines of fire: green solid = shot, amber dashed = blocked,
##            grey thin = out of range (or min range, no target)
##   victims  each unit's chosen victim
##   routes   route legs (anchor, then each waypoint; a square = it stops)
##   spacing  unit pairs closer than the squad's spacing limit
##   holds    hold-fire reason glyphs by each unit (HOLD_GLYPH)
##   labels   large labels: per squad its name, activity and hold reasons
##            spelt out and counted; spacing gaps in metres
##
## Put it over the view (as its child, anchored full rect, or anywhere with
## the same screen rect); it never takes input. Without a view it fits the
## field to its own rect (F6, tests).

signal layers_changed

const LAYERS: PackedStringArray = ["ranges", "fire", "victims", "routes", "spacing", "holds", "labels"]
const SHOT: Color = Color("4cd964")
const BLOCKED: Color = Color("ffb020")
const NO_SHOT: Color = Color(0.62, 0.64, 0.68, 0.55)
const VICTIM: Color = Color(1.0, 0.35, 0.75, 0.8)
const ROUTE: Color = Color("4fd2ff")
const SPACING: Color = Color("ff4d4d")
const TEXT: Color = Color("f2f4f8")
const SHADOW: Color = Color(0, 0, 0, 0.75)
const TEAM: Dictionary = {1: Color("5aa0ff"), 2: Color("ff7a5a"), 3: Color("b98cff"), 4: Color("e6d75a")}
## Short hold glyphs (BattleActivity.Hold names); large labels spell them out.
const HOLD_GLYPH: Dictionary = {
	"UNARMED": "U", "FALLING_BACK": "F", "RELOADING": "R", "COOLDOWN": "C",
	"NO_MOVING_FIRE": "M", "MIN_RANGE": "m", "OUT_OF_RANGE": "O", "NO_LOS": "L",
	"NOT_SPOTTED": "S", "NO_TARGET": "T",
}
const FONT_SMALL: int = 11
const FONT_MID: int = 14
const FONT_LARGE: int = 18

## The view whose camera this overlay follows (may be null).
var view: ContextView
## Layer name -> shown.
var layers: Dictionary = {
	"ranges": true, "fire": true, "victims": true, "routes": true,
	"spacing": true, "holds": true, "labels": false,
}
## How many times the overlay has drawn (tests, profiling).
var draws: int = 0

var _frame: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Follows `v`'s camera: redraws whenever the view does.
func attach(v: ContextView) -> void:
	if view != null and view.draw.is_connected(queue_redraw):
		view.draw.disconnect(queue_redraw)
	view = v
	if v != null:
		v.draw.connect(queue_redraw)
	queue_redraw()


## Shows a WorkshopDebug frame ({} clears).
func show_frame(frame: Dictionary) -> void:
	_frame = frame.duplicate(true)
	queue_redraw()


func frame() -> Dictionary:
	return _frame


func set_layer(layer: String, on: bool) -> void:
	if not layer in LAYERS or bool(layers[layer]) == on:
		return
	layers[layer] = on
	layers_changed.emit()
	queue_redraw()


func is_layer_on(layer: String) -> bool:
	return bool(layers.get(layer, false))


# --- camera ------------------------------------------------------------------

## Pixels per metre.
func _k() -> float:
	var w := float(_frame.get("width", 0))
	if w <= 0.0:
		return 1.0
	if view != null:
		return view.battle_area().size.x / w
	return minf(size.x / w, size.y / maxf(float(_frame.get("height", 1)), 1.0))


## Battlefield metres to this overlay's local pixels.
func to_px(m: Vector2) -> Vector2:
	if view != null:
		return get_global_transform().affine_inverse() * (view.get_global_transform() * view.to_view(m))
	var k := _k()
	var field := Vector2(float(_frame.get("width", 0)), float(_frame.get("height", 0))) * k
	return (size - field) / 2.0 + m * k


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	draws += 1
	if _frame.is_empty() or float(_frame.get("width", 0)) <= 0.0:
		return
	var k := _k()
	var font := get_theme_default_font()
	var big := is_layer_on("labels")
	var squads := {}
	for s: Dictionary in _frame["squads"]:
		squads[s["id"]] = s
	var units := {}
	for u: Dictionary in _frame["units"]:
		units[u["id"]] = u
	if is_layer_on("ranges"):
		_draw_ranges(k)
	if is_layer_on("routes"):
		_draw_routes()
	if is_layer_on("fire"):
		_draw_fire(squads)
	if is_layer_on("victims"):
		_draw_victims(units, k)
	if is_layer_on("spacing"):
		_draw_spacing(units, k, font, big)
	if is_layer_on("holds"):
		_draw_holds(k, font, big)
	if big:
		_draw_labels(font)


func _team(player: int) -> Color:
	return TEAM.get(player, Color.WHITE)


func _p(d: Dictionary) -> Vector2:
	return to_px(Vector2(d["x"], d["y"]))


func _draw_ranges(k: float) -> void:
	for s: Dictionary in _frame["squads"]:
		var r := float(s["range"]) * k
		if r <= 0.0:
			continue
		var col := _team(s["player"])
		var c := _p(s)
		draw_circle(c, r, Color(col, 0.06))
		draw_arc(c, r, 0.0, TAU, maxi(24, int(r / 4.0)), Color(col, 0.55), 1.5, true)


func _draw_routes() -> void:
	for rt: Dictionary in _frame["routes"]:
		var pts := PackedVector2Array()
		for m: Vector2 in rt["points"]:
			pts.append(to_px(m))
		if pts.size() < 2:
			continue
		draw_polyline(pts, Color(ROUTE, 0.85), 2.0, true)
		for i in range(1, pts.size()):
			draw_circle(pts[i], 3.0, ROUTE)
		if rt["final"]:
			var e := pts[pts.size() - 1]
			draw_rect(Rect2(e - Vector2(5, 5), Vector2(10, 10)), ROUTE, false, 2.0)


func _draw_fire(squads: Dictionary) -> void:
	for f: Dictionary in _frame["fire"]:
		if not squads.has(f["from"]) or not squads.has(f["to"]):
			continue
		var a := _p(squads[f["from"]])
		var b := _p(squads[f["to"]])
		match f["los"]:
			"shot":
				draw_line(a, b, SHOT, 3.0, true)
				_arrow(a, b, SHOT, 10.0)
			"blocked":
				draw_dashed_line(a, b, BLOCKED, 2.5, 8.0)
				_arrow(a, b, BLOCKED, 9.0)
			_:
				draw_dashed_line(a, b, NO_SHOT, 1.2, 4.0)


func _arrow(a: Vector2, b: Vector2, col: Color, length: float) -> void:
	var d := (b - a)
	if d.length() < 1.0:
		return
	d = d.normalized()
	var tip := b - d * 6.0
	var side := Vector2(-d.y, d.x) * length * 0.45
	draw_colored_polygon(PackedVector2Array([tip, tip - d * length + side, tip - d * length - side]), col)


func _draw_victims(units: Dictionary, k: float) -> void:
	for u: Dictionary in _frame["units"]:
		var v: int = u["victim"]
		if v < 0 or not units.has(v) or u["hp"] <= 0:
			continue
		var a := _p(u)
		var b := _p(units[v])
		draw_line(a, b, VICTIM, 1.0, true)
		draw_arc(b, maxf(k * 0.6, 3.0), 0.0, TAU, 12, VICTIM, 1.0, true)


func _draw_spacing(units: Dictionary, k: float, font: Font, big: bool) -> void:
	var rad := maxf(k * 0.7, 4.0)
	for v: Dictionary in _frame["spacing"]:
		if not units.has(v["a"]) or not units.has(v["b"]):
			continue
		var a := _p(units[v["a"]])
		var b := _p(units[v["b"]])
		draw_line(a, b, SPACING, 2.0, true)
		draw_arc(a, rad, 0.0, TAU, 16, SPACING, 2.0, true)
		draw_arc(b, rad, 0.0, TAU, 16, SPACING, 2.0, true)
		if big:
			_text(font, (a + b) / 2.0 + Vector2(0, -rad - 2), "%.1f<%.1f m" % [v["gap"], v["min"]], FONT_SMALL, SPACING)


func _draw_holds(k: float, font: Font, big: bool) -> void:
	var off := Vector2(maxf(k * 0.6, 4.0), -maxf(k * 0.6, 4.0))
	for u: Dictionary in _frame["units"]:
		var h: String = u["hold"]
		if h.is_empty() or u["hp"] <= 0:
			continue
		_text(font, _p(u) + off, HOLD_GLYPH.get(h, "?"), FONT_MID if big else FONT_SMALL, BLOCKED)


## One block per squad: name and player, activity, then its units' hold
## reasons counted (spelt out).
func _draw_labels(font: Font) -> void:
	var holds := {}
	for u: Dictionary in _frame["units"]:
		var h: String = u["hold"]
		if h.is_empty() or u["hp"] <= 0:
			continue
		var per: Dictionary = holds.get(u["squad"], {})
		per[h] = int(per.get(h, 0)) + 1
		holds[u["squad"]] = per
	for s: Dictionary in _frame["squads"]:
		var lines: Array = [
			["%s · P%d" % [s["label"], s["player"]], FONT_LARGE, _team(s["player"]).lightened(0.3)],
			[_words(s["activity"]), FONT_LARGE, TEXT],
		]
		var per: Dictionary = holds.get(s["id"], {})
		if not per.is_empty():
			var parts := PackedStringArray()
			for h: String in per:
				parts.append("%s %d" % [_words(h), per[h]])
			lines.append([", ".join(parts), FONT_MID, BLOCKED])
		# Odd players' blocks sit left of the squad, even players' right, so
		# two squads in contact keep their labels apart.
		var left := int(s["player"]) % 2 == 1
		var y := _p(s).y - 30.0
		for line: Array in lines:
			var w := font.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, line[1]).x
			var x := _p(s).x - 18.0 - w if left else _p(s).x + 18.0
			_text(font, Vector2(x, y), line[0], line[1], line[2])
			y += float(line[1]) + 2.0


static func _words(name: String) -> String:
	return name.to_lower().replace("_", " ")


func _text(font: Font, at: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, SHADOW)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
