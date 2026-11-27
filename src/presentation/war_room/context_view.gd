class_name ContextView
extends Control
## Draws one presentation context into its rect: the overworld as the player
## knows it (OverworldSession.observe) or a battle (observe_battle).
## Stateless projection (GDD 04 §4.8): it keeps only the last observation it
## was given, and reports clicks and zooms as signals for its owner.

signal hex_clicked(plot: int, button: int, shift: bool)
## The plot under the cursor changed (-1 = none); overworld only.
signal hex_hovered(plot: int)
## The squad under the cursor changed (-1 = none); battles only.
signal squad_hovered(squad: int)
## A click in a battle at a battlefield point (metres).
signal battle_pressed(at: Vector2, button: int, shift: bool, ctrl: bool, alt: bool, double: bool)
## A box dragged in a battle (metres).
signal battle_box(rect: Rect2, add: bool)
signal zoomed(factor: float)
## Asks the owner to move the battle camera (wheel zoom about the cursor,
## middle-button drag, pan_by): magnification and centre (metres).
signal battle_camera(zoom: float, centre: Vector2)
## Deployment (overlay "deploy"): own squads `ids` dragged with `anchor`
## under the cursor, by `delta` metres (a group keeps its offsets).
signal deploy_dragged(ids: Array, anchor: int, delta: Vector2)
## Deployment: the facing handle of `ids` dragged to point at `toward` (metres).
signal deploy_faced(ids: Array, toward: Vector2)

const HEX_SIZE: float = 26.0
## Pixels per battlefield metre when the ground is drawn from textures (ArtSet).
const GROUND_PX: int = ArtSet.GROUND_PX
const ONE: float = 65536.0
const BG: Color = Color("12151a")
const FOG: Color = Color("1b1f26")
const LINE: Color = Color("323a46")
const TEXT: Color = Color("dde2ea")
const SELECT: Color = Color("e6b450")
const BATTLE: Color = Color("e8735f")
const GHOST: Color = Color(0.85, 0.9, 1.0, 0.55)
const REACH: Color = Color(1.0, 1.0, 1.0, 0.16)
## A full turn of a squad's facing (binary angle).
const TURN: float = 65536.0
## Side colours come from TeamPalette at draw time (sw-ijp.5): the chosen
## preset is a setting, so a palette switch redraws without new state here.
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

## Battle terrain colours: feature ID -> Color, from the content's own
## `color` (GDD 03 §3.5; `feature_colors`). A feature not listed gets a
## colour made from its ID, so mod terrain always draws.
var terrain_colors: Dictionary = {}
## Package art (sw-kys.3): hex tiles and icons, commander and squad icons,
## battle ground textures. Null, or a template without art, draws colours.
var art: ArtSet
## Commander template IDs by index (OverworldRules.commander_ids), to find
## an observed commander's icon.
var commander_ids: PackedStringArray = PackedStringArray()

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
## The selected own detachment (sw-kys.8), -1 = none.
var _selected_det: int = -1
## Own steered convoys' routes: detachment ID -> plots.
var _convoy_routes: Dictionary = {}
var _selected_plot: int = -1
var _battles: Dictionary = {}
## Own commanders' planned routes: commander ID -> plots.
var _routes: Dictionary = {}
var _overlay: Dictionary = {}
## Overworld extras (show_overworld's `extra`).
var _extra: Dictionary = {}
var _hover_plot: int = -1
var _hover_squad: int = -1
## A battle turn being played back (OverworldSession.playback's entry) and
## how far through it (0..1); empty when the view shows the present.
var _play: Dictionary = {}
var _play_t: float = 0.0
## The played-back turn's effects (sw-aba), built once per playback entry.
var _fx: BattleFx
var _fx_src: Dictionary = {}
## Unit template ID -> white silhouette of its art, for hit flashes.
var _silhouettes: Dictionary = {}
## What the last battle draw showed: [{"id", "c" (metres), "pts", ...}].
var _shown: Array = []
var _press_at: Vector2 = Vector2.ZERO
## Battle camera (ViewContexts owns it; set_camera): magnification over the
## fitted field and the field point at the view's centre (metres).
var _cam_zoom: float = 1.0
var _cam_centre: Vector2 = ViewContexts.NO_CENTRE
var _dragging_cam: bool = false
var _box: Rect2 = Rect2()
var _pressing: bool = false
## A deployment drag from the left press: "" (none, a box or a click),
## "squad" (place) or "face" (the facing handle); the squads it moves, the
## grabbed one, and the cursor while it drags (view px).
var _drag_kind: String = ""
var _drag_ids: Array = []
var _drag_anchor: int = -1
var _drag_at: Vector2 = Vector2.ZERO
## Facing handle knobs of the last draw: squad ID -> view point.
var _handles: Dictionary = {}
## The battle terrain texture, built once per BattleRules.
var _terrain_rules: BattleRules
var _terrain_tex: ImageTexture
var _terrain_names: PackedStringArray = PackedStringArray()


## Every feature's colour in a package: its `color`, else one made from
## its ID (muted, so squads stand out).
static func feature_colors(t: TemplateTable) -> Dictionary:
	var out := {}
	for id in t.ids():
		if t.kind_of(id) == "feature" and not t.is_abstract(id):
			out[id] = feature_color(id, t.values_of(id))
	return out


static func feature_color(id: String, values: Dictionary) -> Color:
	var c := str(values.get("color", ""))
	if Color.html_is_valid(c):
		return Color.html(c)
	return Color.from_hsv(float(absi(id.hash()) % 360) / 360.0, 0.35, 0.45)


func _terrain_color(f: String) -> Color:
	return terrain_colors[f] if terrain_colors.has(f) else feature_color(f, {})


func _init() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP


## Shows the overworld: `obs` from OverworldSession.observe, `names` the
## feature template IDs (OverworldRules.feature_ids), the contexts for the
## camera and selection. `extra` (all optional): "reach" (plot -> movement
## cost: what the selected commander can enter this turn), "budget" and
## "spent" (its movement points), "preview" (a route drafted to the hovered
## hex) and "preview_to" (that hex), and while the last turn is played back
## "play" with "t" (0..1): {"span" (movement points the whole turn
## stands for), "commanders": id -> walk, "detachments": id -> walk,
## "gone": [{"player", "convoy", "walk"}] for walkers no longer there
## afterwards (a convoy that delivered)}. A walk is {"plots", "times"}: the
## hexes entered and the movement points spent on entering each, so
## everything moves at one speed and stops when its own move is done.
func show_overworld(obs: Dictionary, names: PackedStringArray, ctx: ViewContexts, extra: Dictionary = {}) -> void:
	mode = "overworld"
	_obs = obs
	_names = names
	_extra = extra
	_width = obs.get("width", 0)
	_height = obs.get("height", 0)
	_camera = ctx.camera_plot
	_zoom = ctx.zoom
	_selected = ctx.selected
	_selected_det = ctx.selected_detachment
	_selected_plot = ctx.selected_plot
	_battles = {}
	for eid in ctx.battles():
		_battles[ctx.battle_plot(eid)] = eid
	_routes = obs.get("routes", {})
	_convoy_routes = obs.get("convoy_routes", {})
	queue_redraw()


## Shows a battle (OverworldSession.observe_battle). `overlay` (all
## optional): "selected" (squad IDs), "ghosts" and "contacts"
## (IntentForecast), "drafts" (squad ID -> order), "reactable" (squad ID
## -> queued reaction name or ""), "triggers" (reactable squad ID -> the
## enemy squad IDs it would react to; drawn while it is selected),
## "telegraphs" (BattleSession.telegraphs: each committed enemy attack on an
## own squad, drawn as an arrow and a "▶ n" damage label), "terrain" (the battle's BattleRules, for
## its terrain), "pending" (drafts are queued until Planning).
func show_battle(obs: Dictionary, overlay: Dictionary = {}) -> void:
	mode = "battle"
	_obs = obs
	_overlay = overlay
	_play = {}
	_clear_hover()
	queue_redraw()


## Shows a moment of a battle turn being played back: `rec` is the
## battle's entry in OverworldSession.playback, `t` how far through (0..1).
## Squads are drawn where they were then; orders and selection are not
## drawn. `obs` (may be {}) names the squads still known; `inspected` is the
## clicked squad, highlighted while its card shows (sw-ll4.27.4). `selected`
## (squad IDs) gets the selection rings and range/sight rings as in Planning
## (sw-bafi.2); orders are still not drawn.
func show_playback(rec: Dictionary, t: float, obs: Dictionary = {}, inspected: int = -1, selected: Array = []) -> void:
	mode = "battle"
	_obs = obs.duplicate()
	_obs["width"] = rec["width"]
	_obs["height"] = rec["height"]
	_overlay = {"terrain": rec["rules"], "inspected": inspected, "selected": selected}
	_play = rec
	_play_t = clampf(t, 0.0, 1.0)
	if _fx == null or not is_same(_fx_src, rec):
		PerfRecorder.begin(&"fx_build")
		_fx = BattleFx.from_playback(rec)
		PerfRecorder.end(&"fx_build")
		_fx_src = rec
	_clear_hover()
	queue_redraw()


func _draw() -> void:
	var sec := &"draw_pip" if compact else (&"draw_overworld" if mode == "overworld" else &"draw_battle")
	PerfRecorder.begin(sec)
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if mode == "overworld":
		_draw_overworld()
	elif mode == "battle":
		_draw_battle()
	PerfRecorder.end(sec)


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
	var play: Dictionary = _extra.get("play", {})
	var t: float = _extra.get("t", 1.0)
	var reach: Dictionary = {} if not play.is_empty() else _extra.get("reach", {})
	var font := get_theme_default_font()
	var fs := int(clampf(s * 0.42, 9.0, 16.0))
	for p in _width * _height:
		var c := o + _centre(p)
		if c.x < -s * 2 or c.y < -s * 2 or c.x > size.x + s * 2 or c.y > size.y + s * 2:
			continue
		var col := FOG
		var shade := 1.0
		var tile: Texture2D = null
		var whole := false
		var icon: Texture2D = null
		if plots.has(p):
			col = _plot_color(plots[p])
			if art != null:
				var tid := _plot_art_id(plots[p], "tile")
				if not tid.is_empty():
					tile = art.texture(tid, "tile")
					whole = art.shaped(tid, "tile")
				icon = _plot_art(plots[p], "icon")
			if not plots[p]["visible"]:
				col = col.darkened(0.45)
				shade *= 0.55
		# With a commander selected, what it can't reach this turn is dimmed.
		if not reach.is_empty() and not reach.has(p):
			col = col.darkened(0.35)
			shade *= 0.65
		var pts := _hex_points(c, s * 0.97)
		if tile != null and whole:  # a pre-cut hex: drawn over the hex's box
			draw_colored_polygon(pts, FOG)
			draw_texture_rect(tile, Rect2(c - Vector2(sqrt(3.0) * s, 2.0 * s) * 0.5, Vector2(sqrt(3.0) * s, 2.0 * s)), false, Color(shade, shade, shade))
		elif tile != null:
			var uvs := PackedVector2Array()
			for q in pts:
				uvs.append((q - c) / (s * 2.0) + Vector2(0.5, 0.5))
			draw_colored_polygon(pts, Color(shade, shade, shade), uvs, tile)
		else:
			draw_colored_polygon(pts, col)
		if icon != null:
			var h := s * 0.6
			draw_texture_rect(icon, Rect2(c - Vector2(h, h * 1.1), Vector2(h, h) * 2.0), false, Color(shade, shade, shade))
		if plots.has(p) and (icon != null or whole):
			var owner := _plot_owner(plots[p])
			if owner > 0:
				var dot := c + Vector2(s * 0.48, -s * 0.42)
				var rr := maxf(s * 0.14, 3.0)
				var oc: Color = TeamPalette.color(owner, TEXT)
				if owner == 2:  # square: side identity without colour (sw-ijp.5)
					draw_rect(Rect2(dot - Vector2(rr, rr), Vector2(rr, rr) * 2.0), oc)
					draw_rect(Rect2(dot - Vector2(rr, rr), Vector2(rr, rr) * 2.0), BG, false, 1.0)
				else:
					draw_circle(dot, rr, oc)
					draw_arc(dot, rr, 0, TAU, 12, BG, 1.0)
		if reach.has(p):
			draw_colored_polygon(_hex_points(c, s * 0.97), REACH)
			if s >= 20.0:
				draw_string(font, c + Vector2(-s * 0.5, s * 0.62), str(reach[p]), HORIZONTAL_ALIGNMENT_CENTER, s, maxi(fs - 3, 8), Color(1, 1, 1, 0.6))
		pts.append(pts[0])
		draw_polyline(pts, LINE, 1.0)
		if _battles.has(p):
			draw_arc(c, s * 0.62, 0, TAU, 24, BATTLE, 3.0)
		if p == _selected_plot:
			draw_polyline(pts, SELECT, 2.5)
		if p == _hover_plot:
			draw_polyline(pts, Color(1, 1, 1, 0.5), 1.5)
	# Glance summaries after every hex: a label under a battle hex would be
	# painted over by the next row's fill (sw-1jy.5).
	for p: int in _battles:
		var c := o + _centre(p)
		if c.x < -s * 2 or c.y < -s * 2 or c.x > size.x + s * 2 or c.y > size.y + s * 2:
			continue
		_draw_battle_summary(c, s, font, fs, _battles[p])
	if play.is_empty():
		for cmd: Dictionary in _obs.get("commanders", []):
			var route: PackedInt64Array = _routes.get(cmd["id"], PackedInt64Array())
			var prev := o + _centre(cmd["plot"])
			for i in route.size():
				var nxt := o + _centre(route[i])
				draw_dashed_line(prev, nxt, SELECT, 2.0, 6.0)
				if i < route.size() - 1:
					draw_circle(nxt, 2.5, SELECT)
				prev = nxt
			if not route.is_empty():
				draw_arc(prev, s * 0.2, 0, TAU, 12, SELECT, 2.0)
		_draw_route_preview(o, s, font, fs)
	# Garrisons (squares) and convoys (diamonds, with their destination):
	# squads without a commander (sw-ip8.7).
	var det_play: Dictionary = play.get("detachments", {})
	for det: Dictionary in _obs.get("detachments", []):
		var walking: bool = det_play.has(det["id"])
		var at := o + (_along(det_play[det["id"]], t) if walking else _centre(det["plot"]))
		var c := at + Vector2(s * 0.42, s * 0.38)
		var col: Color = TeamPalette.color(det["player"], TEXT)
		var h := s * 0.22
		if det.get("convoy", false) or walking:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 1.3), c + Vector2(h * 1.3, 0), c + Vector2(0, h * 1.3), c + Vector2(-h * 1.3, 0)]), col)
			var dest := int(det.get("dest_plot", -1))
			var to_cmd := int(det.get("dest_commander", -1))
			if dest < 0 and to_cmd >= 0:
				for cmd: Dictionary in _obs.get("commanders", []):
					if cmd["id"] == to_cmd:
						dest = cmd["plot"]
			var steered: PackedInt64Array = _convoy_routes.get(det["id"], PackedInt64Array())
			if not steered.is_empty() and play.is_empty():
				var prev := c
				for q in steered:
					var nxt := o + _centre(q)
					draw_dashed_line(prev, nxt, Color(col, 0.75) if det["id"] != _selected_det else SELECT, 1.5, 4.0)
					prev = nxt
			elif dest >= 0 and play.is_empty():
				draw_dashed_line(c, o + _centre(dest), Color(col, 0.6), 1.5, 4.0)
		else:
			draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), col)
		draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), BG, false, 1.0)
		if det["id"] == _selected_det:
			draw_arc(c, h * 1.9, 0, TAU, 20, SELECT, 2.5)
		var n := (det.get("squads", []) as Array).size()
		if n > 0:
			draw_string(font, c + Vector2(h + 2, h), "P%d %d" % [int(det["player"]), n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)
	# Walkers that are gone when the turn ends (a convoy that reached its
	# commander) are still seen walking there.
	for g: Dictionary in play.get("gone", []):
		var at := o + _along(g["walk"], t)
		var col: Color = TeamPalette.color(g["player"], TEXT)
		if g.get("convoy", true):
			var c := at + Vector2(s * 0.42, s * 0.38)
			var h := s * 0.22
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 1.3), c + Vector2(h * 1.3, 0), c + Vector2(0, h * 1.3), c + Vector2(-h * 1.3, 0)]), col)
		else:
			draw_circle(at, s * 0.36, Color(col, 0.6))
	var cmd_play: Dictionary = play.get("commanders", {})
	for cmd: Dictionary in _obs.get("commanders", []):
		var c := o + (_along(cmd_play[cmd["id"]], t) if cmd_play.has(cmd["id"]) else _centre(cmd["plot"]))
		var r := s * 0.36
		var pc: Color = TeamPalette.color(cmd["player"], TEXT)
		draw_circle(c, r, pc)
		var face := _commander_icon(cmd)
		if face != null:
			draw_circle(c, r * 0.86, BG)
			draw_texture_rect(face, Rect2(c - Vector2(r, r) * 0.95, Vector2(r, r) * 1.9), false)
		var pb := c + Vector2(r * 0.9, -r * 0.8)  # side number: identity without colour (sw-ijp.5)
		draw_circle(pb, maxf(fs * 0.5, 5.0), pc)
		draw_string(font, pb + Vector2(-fs * 0.5, fs * 0.35), str(cmd["player"]), HORIZONTAL_ALIGNMENT_CENTER, fs, maxi(fs - 2, 8), BG)
		if cmd["id"] == _selected:
			draw_arc(c, r + 3.0, 0, TAU, 20, SELECT, 2.5)
		if cmd.has("army"):  # own and allied: squads besides the commander's own
			var n := (cmd["army"] as Array).filter(func(q: Dictionary) -> bool: return not q.get("own", false)).size()
			if face != null:
				var b := c + Vector2(r * 0.85, r * 0.75)
				draw_circle(b, maxf(fs * 0.55, 5.0), pc)
				draw_string(font, b + Vector2(-fs * 0.5, fs * 0.35), str(n), HORIZONTAL_ALIGNMENT_CENTER, fs, maxi(fs - 2, 8), BG)
			else:
				draw_string(font, c + Vector2(-r * 0.45, r * 0.45), str(n), HORIZONTAL_ALIGNMENT_CENTER, r * 0.9, fs, BG)


## The battle's glance summary under its hex (sw-1jy.5): the worst SIMPL
## band of the player's own squads as word + icon, and the backward-looking
## trend — never colour alone. A pure projection of show_overworld's extra
## "summaries" (OverworldSession.battle_summary).
func _draw_battle_summary(c: Vector2, s: float, font: Font, fs: int, eid: int) -> void:
	var sum: Dictionary = (_extra.get("summaries", {}) as Dictionary).get(eid, {})
	if sum.is_empty():
		return
	var text := EventText.battle_summary(sum)
	var px := maxi(fs - 2, 9)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := c + Vector2(-w * 0.5 - 3.0, s * 0.95)
	at.x = clampf(at.x, 2.0, maxf(size.x - w - 8.0, 2.0))
	draw_rect(Rect2(at, Vector2(w + 6.0, px + 4.0)), Color(BG, 0.85))
	draw_string(font, at + Vector2(3.0, px), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, TEXT)


## The route the selected commander would take to the hovered hex, and what
## it costs of this turn's movement points.
func _draw_route_preview(o: Vector2, s: float, font: Font, fs: int) -> void:
	var preview: PackedInt64Array = _extra.get("preview", PackedInt64Array())
	var to: int = _extra.get("preview_to", -1)
	if to < 0 or to != _hover_plot:
		return
	var at := o + _centre(to)
	if preview.is_empty():
		draw_string(font, at + Vector2(s * 0.5, -s * 0.5), "no way there", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BATTLE)
		return
	var from: int = _extra.get("preview_from", -1)
	var prev := o + _centre(from) if from >= 0 else o + _centre(preview[0])
	for p in preview:
		var nxt := o + _centre(p)
		draw_line(prev, nxt, GHOST, 2.0)
		prev = nxt
	var cost: int = _extra.get("preview_cost", 0)
	var budget: int = _extra.get("budget", 0)
	var text := "%d of %d movement" % [cost, budget]
	if preview[preview.size() - 1] != to:
		draw_arc(prev, s * 0.25, 0, TAU, 12, GHOST, 2.0)
		text = "out of reach this turn: stops at the ring (%d of %d)" % [cost, budget]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var corner := at + Vector2(s * 0.5, -s * 0.5 - fs)
	corner.x = minf(corner.x, size.x - w - 10.0)
	draw_rect(Rect2(corner - Vector2(4, 2), Vector2(w + 8, fs + 6)), Color(BG, 0.85))
	draw_string(font, corner + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)


## Where a walker is at `t` (0..1) of the turn, relative to the origin.
## The turn stands for `span` movement points, and the walk enters
## plots[i] at times[i] points: it moves at the common speed and then
## waits where it stopped.
func _along(walk: Dictionary, t: float) -> Vector2:
	var plots: Array = walk["plots"]
	var times: Array = walk["times"]
	if plots.is_empty():
		return Vector2.ZERO
	var at := clampf(t, 0.0, 1.0) * float((_extra.get("play", {}) as Dictionary).get("span", 1))
	for i in range(1, plots.size()):
		if at < float(times[i]):
			var from := float(times[i - 1])
			return _centre(plots[i - 1]).lerp(_centre(plots[i]), (at - from) / maxf(float(times[i]) - from, 0.001))
	return _centre(plots[plots.size() - 1])


## A plot's art: the first feature (in FEATURE_COLORS order, then the rest)
## with `field` art, or null.
func _plot_art(entry: Dictionary, field: String) -> Texture2D:
	var id := _plot_art_id(entry, field)
	return null if id.is_empty() else art.texture(id, field)


## The template ID _plot_art draws, or "".
func _plot_art_id(entry: Dictionary, field: String) -> String:
	var ids := {}
	for f: Dictionary in entry["features"]:
		if f["tmpl"] >= 0 and f["tmpl"] < _names.size():
			ids[_names[f["tmpl"]]] = true
	for pair: Array in FEATURE_COLORS:
		if ids.has(pair[0]) and art.has_art(pair[0], field):
			return pair[0]
	for id: String in ids:
		if art.has_art(id, field):
			return id
	return ""


func _plot_owner(entry: Dictionary) -> int:
	for f: Dictionary in entry["features"]:
		if int(f.get("owner", 0)) > 0:
			return int(f["owner"])
	return 0


func _commander_icon(cmd: Dictionary) -> Texture2D:
	var t := int(cmd.get("tmpl", -1))
	if art == null or t < 0 or t >= commander_ids.size():
		return null
	return art.texture(commander_ids[t])


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
	var tex := _terrain_texture(_overlay.get("terrain"))
	if tex != null:
		draw_texture_rect(tex, area, false)
	draw_rect(area, LINE, false, 1.0)
	var font := get_theme_default_font()
	if tex != null and not compact:
		_draw_legend(font, area)
	var playing := not _play.is_empty()
	if not playing:
		_draw_zones(font, area, k)
		_draw_deploy_areas(font, area, k)
	_shown = _battle_squads()
	var pos := {}
	for d: Dictionary in _shown:
		pos[d["id"]] = area.position + (d["c"] as Vector2) * k
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
	var pending: bool = _overlay.get("pending", false)
	for id: int in drafts:
		var o: Dictionary = drafts[id]
		if o.get("type") == "attack" and pos.has(id) and pos.has(o.get("target")):
			draw_line(pos[id], pos[o["target"]], BATTLE, 1.5)
		elif o.has("x") and pos.has(id) and not compact:
			# Where the squad was ordered to (the ghost shows how far it gets
			# this turn); queued orders are drawn in the select colour.
			var to := area.position + Vector2(o["x"] / ONE, o["y"] / ONE) * k
			var col := SELECT if pending else Color(SELECT, 0.45)
			draw_dashed_line(pos[id], to, col, 1.0, 2.0)
			draw_line(to + Vector2(-4, -4), to + Vector2(4, 4), col, 1.5)
			draw_line(to + Vector2(-4, 4), to + Vector2(4, -4), col, 1.5)
			if pending:
				draw_string(font, to + Vector2(6, -4), "queued", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SELECT)
	if playing and not _play.has("volleys"):
		_draw_shots(pos)
	var selected: Array = _overlay.get("selected", [])
	var reactable: Dictionary = _overlay.get("reactable", {})
	var inspected: int = _overlay.get("inspected", -1)
	var radii := {}
	for d: Dictionary in _shown:
		var id: int = d["id"]
		var c: Vector2 = pos[id]
		var hovered := id == _hover_squad and not playing
		var r := _draw_squad(d, area, k, font, selected.has(id), hovered or id == inspected)
		radii[id] = r
		if reactable.has(id) and not compact:
			var q: String = reactable[id]
			var mark := "!" if q.is_empty() else ReactionRadial.glyph(q)
			draw_arc(c, r + 7.0, 0, TAU, 20, SELECT, 1.5)
			draw_string(font, c + Vector2(r + 6, -r - 4), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SELECT)
	if playing and _fx != null:
		_draw_fx(area, k, font)
	_draw_fire_cues(font, pos, selected)
	# What a selected reactable squad would react to: a line to each
	# triggering enemy and a ring around it.
	var triggers: Dictionary = _overlay.get("triggers", {})
	for id: Variant in selected:
		if compact or not pos.has(id):
			continue
		for t: int in triggers.get(id, []):
			if pos.has(t):
				draw_dashed_line(pos[id], pos[t], SELECT, 1.5, 6.0)
				draw_arc(pos[t], 12.0, 0, TAU, 24, SELECT, 2.0)
				draw_string(font, pos[t] + Vector2(13, -10), "trigger", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SELECT)
	_draw_telegraphs(font, pos)
	if not playing:
		_draw_deploy(font, area, k, pos, radii, selected)
	for ct: Dictionary in _overlay.get("contacts", []):
		var id: int = ct["squad"]
		if ghosts.has(id) and pos.has(id) and not compact:
			var pts: PackedInt64Array = ghosts[id]
			var g := area.position + Vector2(pts[pts.size() - 2] / ONE, pts[pts.size() - 1] / ONE) * k
			draw_string(font, g + Vector2(6, 4), Telegraph.contact_label(ct, str(GameSettings.value("forecast_detail")) == "numbers"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BATTLE)
	if _box.size != Vector2.ZERO:
		draw_rect(_box.abs(), Color(SELECT, 0.15))
		draw_rect(_box.abs(), SELECT, false, 1.0)
	if not title.is_empty():
		var fs := 12 if compact else 15
		var pad := 6.0 if compact else 16.0
		var w_text := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := pad if compact else size.x - pad - w_text
		draw_string(font, Vector2(x, pad + fs), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)


## Enemy attack telegraphs (sw-7o7): a solid arrow from the attacker to the
## target squad and a boxed label with the predicted damage (Telegraph.label,
## the same formatting as the playback floats). The marker is arrow + box +
## text, so colour is never the only cue (sw-ijp.5); no pulse is paused.
func _draw_telegraphs(font: Font, pos: Dictionary) -> void:
	if compact:
		return
	var slot := {}
	for t: Dictionary in _overlay.get("telegraphs", []):
		var a: int = t["attacker"]
		var b: int = t["target"]
		if not pos.has(a) or not pos.has(b):
			continue
		var dir: Vector2 = (pos[b] - pos[a])
		dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
		var tip: Vector2 = pos[b] - dir * 14.0
		draw_line(pos[a] + dir * 14.0, tip, Telegraph.COLOR, 2.0)
		draw_colored_polygon(PackedVector2Array([tip + dir * 7.0, tip + dir.orthogonal() * 4.5, tip - dir.orthogonal() * 4.5]), Telegraph.COLOR)
		var n: int = slot.get(b, 0)
		slot[b] = n + 1
		var text := Telegraph.label(t)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var at: Vector2 = pos[b] + Vector2(14, 8 + 16 * n)
		draw_rect(Rect2(at + Vector2(-3, -12), Vector2(w + 6, 16)), Color(0.08, 0.05, 0.05, 0.85))
		draw_rect(Rect2(at + Vector2(-3, -12), Vector2(w + 6, 16)), Telegraph.COLOR, false, 1.0)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


## The squads to draw, each with its units' points ("pts", metres) and
## their centre ("c"): from the observation, or from the playback frame.
func _battle_squads() -> Array:
	var out := []
	var info := {}
	for sq: Dictionary in _obs.get("squads", []):
		info[sq["id"]] = sq
	if not _play.is_empty():
		var frames: Array = _play["frames"]
		var f := _play_t * (frames.size() - 1)
		var i := mini(int(f), frames.size() - 1)
		var a: Dictionary = frames[i]
		var b: Dictionary = frames[mini(i + 1, frames.size() - 1)]
		for id: int in a:
			var sa: Dictionary = a[id]
			var pts: Array = (sa["units"] as Array).duplicate()
			if b.has(id):
				var to := {}
				var sb: Dictionary = b[id]
				for j in (sb["ids"] as Array).size():
					to[sb["ids"][j]] = sb["units"][j]
				for j in pts.size():
					if to.has(sa["ids"][j]):
						pts[j] = (pts[j] as Vector2).lerp(to[sa["ids"][j]], f - i)
			var d: Dictionary = (info.get(id, {}) as Dictionary).duplicate()
			d.merge({"id": id, "player": sa["player"], "facing": sa["facing"], "pts": pts, "alive": pts.size(),
				"uids": sa["ids"], "tmpls": sa.get("tmpls", []), "uhp": sa.get("hp", []), "acts": sa.get("acts", []),
				"activity": sa.get("activity", -1), "own": sa.has("holds")}, true)
			if sa.has("holds"):
				d.merge({"holds": sa["holds"], "reload": sa.get("reload", []), "cooldown": sa.get("cooldown", [])}, true)
			out.append(d)
	else:
		var by := {}
		for u: Dictionary in _obs.get("units", []):
			if not by.has(u["squad"]):
				by[u["squad"]] = {"pts": [], "uids": [], "tmpls": [], "uhp": [], "acts": [], "holds": [], "reload": [], "cooldown": []}
			var b: Dictionary = by[u["squad"]]
			(b["pts"] as Array).append(Vector2(u["x"], u["y"]) / ONE)
			(b["uids"] as Array).append(u["id"])
			(b["tmpls"] as Array).append(u.get("tmpl", ""))
			(b["uhp"] as Array).append(clampf(float(u["hp"]) / maxf(float(u.get("hp_max", u["hp"])), 1.0), 0.0, 1.0))
			(b["acts"] as Array).append(int(u.get("acts", 0)))
			(b["holds"] as Array).append(int(u.get("hold", -1)))
			(b["reload"] as Array).append(int(u.get("reload", 0)))
			(b["cooldown"] as Array).append(int(u.get("cooldown", 0)))
		var viewer := int(_obs.get("player", -1))
		for sq: Dictionary in _obs.get("squads", []):
			if sq.get("destroyed", false) or sq.get("withdrawn", false):
				continue
			var d := sq.duplicate()
			d["own"] = int(sq["player"]) == viewer
			if by.has(sq["id"]):
				d.merge(by[sq["id"]], true)
			else:
				d["pts"] = [Vector2(sq["x"], sq["y"]) / ONE]
			out.append(d)
	for d: Dictionary in out:
		var c := Vector2.ZERO
		for p: Vector2 in d["pts"]:
			c += p
		d["c"] = c / maxf((d["pts"] as Array).size(), 1.0)
	return out


## With one own squad selected (sw-kys.7), what it can do about each visible
## enemy: a red crosshair ring where it has a shot, a grey dashed ring where
## the enemy is in range but no unit has a line of fire, and an eye mark on
## enemies it sees only through allies' spotting ("spotted").
func _draw_fire_cues(font: Font, pos: Dictionary, selected: Array) -> void:
	if compact or selected.size() != 1 or not _play.is_empty():
		return
	var me: Dictionary = {}
	for d: Dictionary in _shown:
		if d["id"] == selected[0] and d.has("fire"):
			me = d
	if me.is_empty():
		return
	var fire: Dictionary = me["fire"]
	var sees: Array = me.get("sees", [])
	for d: Dictionary in _shown:
		var id: int = d["id"]
		if d["player"] == me["player"] or not pos.has(id):
			continue
		var c: Vector2 = pos[id]
		var r := 16.0
		match String(fire.get(id, "")):
			"shot":
				draw_arc(c, r, 0, TAU, 28, BATTLE, 2.0)
				for a in 4:
					var v := Vector2.from_angle(a * TAU / 4.0)
					draw_line(c + v * (r - 4.0), c + v * (r + 5.0), BATTLE, 2.0)
				draw_string(font, c + Vector2(r + 4, r + 10), "in range", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BATTLE)
			"blocked":
				_dashed_circle(c, r, Color(TEXT, 0.6))
				draw_string(font, c + Vector2(r + 4, r + 10), "no line of fire", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(TEXT, 0.7))
		if not sees.has(id):
			var tw := font.get_string_size("spotted", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			_eye(c + Vector2(-r - 12, 0), Color(SELECT, 0.9))
			draw_string(font, c + Vector2(-r - 22 - tw, 4), "spotted", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(SELECT, 0.85))


func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var n := 16
	for i in n:
		if i % 2 == 0:
			draw_arc(c, r, i * TAU / n, (i + 1) * TAU / n, 4, col, 1.5)


## A small eye glyph: seen through someone else's eyes.
func _eye(c: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0 * PI
		pts.append(c + Vector2(cos(t) * 7.0, -sin(t) * 4.0))
	for i in range(11, 0, -1):
		var t := float(i) / 12.0 * PI
		pts.append(c + Vector2(cos(t) * 7.0, sin(t) * 4.0))
	pts.append(pts[0])
	draw_polyline(pts, col, 1.5)
	draw_circle(c, 2.0, col)


## One squad: its units as dots inside a tinted footprint, an arrow for
## its facing, its name and strength, and (own squads) a health bar.
## Selected, hovered or inspected squads also show their weapon range, and
## own selected ones their sight. Returns the footprint's radius in pixels.
func _draw_squad(d: Dictionary, area: Rect2, k: float, font: Font, is_selected: bool, marked: bool) -> float:
	var col: Color = TeamPalette.color(d["player"], TEXT)
	var c: Vector2 = area.position + (d["c"] as Vector2) * k
	var spread := 0.0
	for p: Vector2 in d["pts"]:
		spread = maxf(spread, p.distance_to(d["c"]))
	var r := spread * k + (3.0 if compact else 6.0)
	if not compact and (is_selected or marked):
		var reach := float(d.get("range", 0)) / ONE * k
		if reach > 0.0:
			draw_arc(c, reach, 0, TAU, 64, Color(col, 0.7), 1.0)
			draw_circle(c, reach, Color(col, 0.05))
			if marked or (_overlay.get("selected", []) as Array).size() == 1:
				draw_string(font, c + Vector2(-40, -reach - 3), "range %d m" % int(float(d["range"]) / ONE), HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(col.lightened(0.4), 0.9))
		var sight := float(d.get("sight", 0)) / ONE * k
		if is_selected and sight > 0.0 and (_overlay.get("selected", []) as Array).size() == 1:
			draw_arc(c, sight, 0, TAU, 96, Color(1, 1, 1, 0.22), 1.0)
			draw_string(font, c + Vector2(-40, sight + 12), "sight %d m" % int(float(d["sight"]) / ONE), HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(1, 1, 1, 0.5))
	# The footprint follows the formation: a soft disc under every unit.
	var ur := maxf(1.2 if compact else 2.2, 0.4 * k)
	var halo := ur + (2.0 if compact else 5.0)
	var ang := float(d.get("facing", 0)) / TURN * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var front := 0.0
	var top := c.y
	var sprite: Texture2D = art.texture(String(d["template"])) if art != null and d.has("template") else null
	var tmpls: Array = d.get("tmpls", [])
	var arted := not compact and art != null and (sprite != null or (not tmpls.is_empty() and art.has_art(String(tmpls[0]))))
	for p: Vector2 in d["pts"]:
		var at := area.position + p * k
		if not arted:  # unit art brings its own team-coloured shadow
			draw_circle(at, halo, Color(col, 0.22))
		front = maxf(front, (at - c).dot(dir))
		top = minf(top, at.y)
	# Each unit as its own art (sw-aba), on a team-coloured shadow, with
	# its health bar and activity tray; a dot without art or when compact.
	var sz := _unit_px(k, d["pts"])
	var uids: Array = d.get("uids", [])
	var uhp: Array = d.get("uhp", [])
	var acts: Array = d.get("acts", [])
	var playing := not _play.is_empty() and _fx != null
	var tilt: Dictionary = _fx.recoil(_frame_f()) if playing else {}
	var flash: Dictionary = _fx.flashes(_frame_f()) if playing else {}
	var per_unit := false
	var status := []
	for j in (d["pts"] as Array).size():
		var at := area.position + (d["pts"][j] as Vector2) * k
		var tid := String(tmpls[j]) if j < tmpls.size() else ""
		var tex: Texture2D = art.texture(tid) if art != null and not tid.is_empty() else null
		if tex == null:
			tex = sprite
		if compact or tex == null:
			draw_circle(at, ur, col)
			continue
		per_unit = true
		var uid: int = uids[j] if j < uids.size() else -1
		_draw_unit(tex, tid, at, sz, col, float(tilt.get(uid, 0.0)), float(flash.get(uid, 0.0)))
		status.append([at + Vector2(0, -sz * 0.85 - 3.0), float(uhp[j]) if j < uhp.size() else -1.0, int(acts[j]) if j < acts.size() else 0])
	# Bars over every sprite, so a neighbour never hides one.
	for st: Array in status:
		_draw_unit_status(st[0], sz, st[1], st[2])
	if per_unit:
		top -= sz * 0.85 + 5.0
	# Facing: an arrow ahead of the front rank.
	var side := dir.orthogonal() * (3.0 if compact else 5.0)
	var base := c + dir * (front + halo + 2.0)
	draw_colored_polygon(PackedVector2Array([base + dir * (5.0 if compact else 9.0), base + side, base - side]), col.lightened(0.35))
	if is_selected:
		draw_arc(c, r + 3.0, 0, TAU, 28, SELECT, 2.0)
	elif marked:
		draw_arc(c, r + 3.0, 0, TAU, 28, Color(1, 1, 1, 0.7), 1.0)
	if compact or not d.has("name"):
		return r
	top -= halo + (5.0 if is_selected or marked else 0.0)
	var text := "%s %d/%d · P%d" % [d["name"], int(d.get("alive", 0)), int(d.get("size", 0)), int(d["player"])]
	draw_string(font, Vector2(c.x - 70, top - 7), text, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, TEXT if is_selected or marked else Color(TEXT, 0.75))
	if sprite != null and not per_unit:  # no unit art: one badge by the label
		var tw := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, 140.0)
		draw_texture_rect(sprite, Rect2(Vector2(c.x - tw * 0.5 - 18, top - 21), Vector2(16, 16)), false)
	var hp_max := float(d.get("hp_max", 0))
	if hp_max > 0.0:
		var frac := clampf(1.0 - float(d.get("hp_lost", 0)) / hp_max, 0.0, 1.0)
		draw_rect(Rect2(Vector2(c.x - 15, top - 4), Vector2(30, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(c.x - 15, top - 4), Vector2(30 * frac, 3)), Color("74d18a") if frac > 0.5 else BATTLE)
	return r


## A unit's art size in pixels at `k` pixels per metre: about 2.6 m, but
## no wider than its squad's closest pair of units, so a rank stays legible.
static func _unit_px(k: float, pts: Array = []) -> float:
	var gap := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			gap = minf(gap, (pts[i] as Vector2).distance_to(pts[j]))
	return clampf(minf(k * 2.6, gap * k * 1.15), 10.0, 30.0)


## One unit's art standing at `at` (its feet), tilted by `tilt` radians
## about its feet (recoil), on a team-coloured shadow; `flash` (0..1) rings
## it in yellow-white and brightens it (a hit).
func _draw_unit(tex: Texture2D, tmpl: String, at: Vector2, sz: float, col: Color, tilt: float, flash: float) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, sz * 0.42, Color(col, 0.85))
	draw_set_transform(at, tilt, Vector2.ONE)
	var rect := Rect2(Vector2(-sz * 0.5, -sz * 0.85), Vector2(sz, sz))
	var sil := _silhouette(tmpl, tex) if flash > 0.0 else null
	if sil != null:
		var ring := Color(1.0, 0.95, 0.55, flash)
		for o: Vector2 in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
			draw_texture_rect(sil, Rect2(rect.position + o, rect.size), false, ring)
	draw_texture_rect(tex, rect, false)
	if sil != null:
		draw_texture_rect(sil, rect, false, Color(1.0, 1.0, 0.85, 0.45 * flash))
	draw_set_transform(Vector2.ZERO)


## A unit's art as a white silhouette (cached per template), or null.
func _silhouette(tmpl: String, tex: Texture2D) -> Texture2D:
	var key := tmpl if not tmpl.is_empty() else str(tex.get_rid())
	if _silhouettes.has(key):
		return _silhouettes[key]
	var img := tex.get_image()
	var sil: Texture2D = null
	if img != null:
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if img.get_pixel(x, y).a > 0.15 else 0.0))
		sil = ImageTexture.create_from_image(img)
	_silhouettes[key] = sil
	return sil


## Activity tray colours: moving, attacking, reloading.
const ACT_COLORS: Array = [Color("9fd0ff"), Color("ff9a5c"), Color("f2d25c")]


## A unit's status row centred over `at`: its health bar (`hp` 0..1, < 0
## for unknown) with its activity tray to the right (BattleSession.ACT_*).
func _draw_unit_status(at: Vector2, sz: float, hp: float, acts: int) -> void:
	var w := clampf(sz * 0.7, 8.0, 18.0)
	var x := at.x - w * 0.5
	if hp >= 0.0:
		var bar := Rect2(Vector2(x, at.y - 1.0), Vector2(w, 2.0))
		draw_rect(bar.grow(0.75), Color(0, 0, 0, 0.75))
		var hc := Color("74d18a") if hp > 0.6 else (Color("e6c450") if hp > 0.3 else BATTLE)
		draw_rect(Rect2(bar.position, Vector2(w * hp, bar.size.y)), hc)
	var g := 4.0
	var cx := x + w + 2.0 + g * 0.5
	for i in 3:
		if acts & (1 << i) == 0:
			continue
		var c := Vector2(cx, at.y)
		draw_rect(Rect2(c - Vector2(g * 0.5 + 1, g * 0.5 + 1), Vector2(g + 2, g + 2)), Color(0, 0, 0, 0.65))
		_activity_glyph(i, c, g * 0.5, ACT_COLORS[i])
		cx += g + 3.0


## Tiny activity marks: a chevron (moving), a crosshair (attacking), a
## turning arrow (reloading).
func _activity_glyph(i: int, c: Vector2, r: float, col: Color) -> void:
	match i:
		0:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.6, 0), c + Vector2(-r * 0.6, r)]), col, 1.2)
		1:
			draw_arc(c, r * 0.75, 0, TAU, 10, col, 1.0)
			draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col, 1.0)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), col, 1.0)
		2:
			draw_arc(c, r * 0.8, -PI * 0.5, PI, 8, col, 1.2)
			draw_line(c + Vector2(0, -r * 0.8), c + Vector2(r * 0.5, -r * 1.2), col, 1.2)
			draw_line(c + Vector2(0, -r * 0.8), c + Vector2(r * 0.5, -r * 0.3), col, 1.2)


## The playback moment as a frame index (float).
func _frame_f() -> float:
	return _play_t * float(maxi((_play.get("frames", []) as Array).size() - 1, 0))


## The played-back turn's effects (sw-aba): units just killed toppling and
## fading, projectiles in flight, and floating damage and "miss" text.
func _draw_fx(area: Rect2, k: float, font: Font) -> void:
	var f := _frame_f()
	var sz := _unit_px(k, [Vector2.ZERO, Vector2(2.5, 0)])
	if not compact:
		for d: Dictionary in _fx.dying(f):
			var tid := String(d["tmpl"])
			var tex: Texture2D = art.texture(tid) if art != null and not tid.is_empty() else null
			var at := area.position + (d["pos"] as Vector2) * k
			var fade: float = d["fade"]
			if tex != null:
				draw_set_transform(at, (1.0 - fade) * 1.2, Vector2.ONE)
				draw_texture_rect(tex, Rect2(Vector2(-sz * 0.5, -sz * 0.85), Vector2(sz, sz)), false, Color(1, 0.7, 0.6, fade))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_circle(at, 3.0, Color(BATTLE, fade))
	for p: Dictionary in _fx.projectiles(f):
		var col: Color = TeamPalette.color(p["player"], TEXT)
		var head := area.position + (p["at"] as Vector2) * k
		var tail := area.position + (p["tail"] as Vector2) * k
		if not area.has_point(head):  # a miss leaving the field
			continue
		var a: float = p["alpha"]
		draw_line(tail, head, Color(col.lightened(0.5), 0.55 * a), 1.0 if compact else 2.0)
		draw_circle(head, 1.5 if compact else 3.5, Color(col.lightened(0.3), 0.35 * a))
		draw_circle(head, 1.0 if compact else 2.0, Color(1.0, 0.97, 0.8, a))
	if compact:
		return
	for t: Dictionary in _fx.floaters(f):
		var rise: float = t["rise"]
		var at := area.position + (t["at"] as Vector2) * k
		var miss: bool = t["miss"]
		var fs := 10 if miss else 13
		var stack := float(t["stack"])
		var text: String = t["text"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(at.x - w * 0.5 + stack * 5.0, at.y - sz - 12.0 - rise * 14.0 - stack * 9.0)
		var a := 1.0 if rise < 0.6 else 1.0 - (rise - 0.6) / 0.4
		var col := Color(0.78, 0.8, 0.84, 0.8 * a) if miss else Color(1.0, 0.86, 0.35, a)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8 * a))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Zones: who holds each and how far its control has built.
## Deployment areas while the battle deploys (overlay "deploy"): the
## player's own lit and outlined, every other side's hatched and labelled,
## so the difference is shape and text as well as colour (sw-ijp.5).
func _draw_deploy_areas(font: Font, area: Rect2, k: float) -> void:
	var dep: Dictionary = _overlay.get("deploy", {})
	if dep.is_empty():
		return
	var me := int(dep.get("player", 0))
	for a: Dictionary in dep.get("areas", []):
		var rr: Rect2 = a["rect"]
		var r := Rect2(area.position + rr.position * k, rr.size * k)
		var p := int(a["player"])
		var col: Color = TeamPalette.color(p, TEXT)
		if p == me:
			draw_rect(r, Color(col, 0.14))
			draw_rect(r, Color(col, 0.9), false, 2.0)
			if not compact:
				var mine := "Your arrival area" if a.get("arrival", false) else "Your deployment area"
				draw_string(font, r.position + Vector2(6, 15), mine, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.4))
			continue
		_hatch(r, Color(col, 0.35), 10.0)
		draw_rect(r, Color(col, 0.6), false, 1.0)
		if not compact:
			var lc := col.lightened(0.4)
			draw_string(font, r.position + Vector2(6, 15), "Player %d deploys here" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lc)
			draw_string(font, r.position + Vector2(6, 29), "hidden until Reveal", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)


## Diagonal hatching inside a view rect.
func _hatch(r: Rect2, col: Color, step: float) -> void:
	var w := r.size.x
	var h := r.size.y
	var t := -h
	while t < w:
		var s0 := maxf(0.0, -t)
		var s1 := minf(h, w - t)
		if s1 > s0:
			draw_line(r.position + Vector2(t + s0, s0), r.position + Vector2(t + s1, s1), col, 1.0)
		t += step


## Deployment marks over the squads: a facing handle on each selected own
## squad, and while dragging, the ghosts where the squads would land (snapped
## to a cell they can enter; a cross marks a refused drop point) or the
## facing they would turn to.
func _draw_deploy(font: Font, area: Rect2, k: float, pos: Dictionary, radii: Dictionary, selected: Array) -> void:
	_handles = {}
	var dep: Dictionary = _overlay.get("deploy", {})
	if dep.is_empty() or compact:
		return
	var own: Array = dep.get("own", [])
	for d: Dictionary in _shown:
		var id: int = d["id"]
		if not selected.has(id) or not own.has(id) or not pos.has(id):
			continue
		var ang := float(d.get("facing", 0)) / TURN * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var knob: Vector2 = pos[id] + dir * (float(radii.get(id, 8.0)) + 14.0)
		_handles[id] = knob
		draw_line(pos[id], knob, SELECT, 1.5)
		draw_circle(knob, 5.0, SELECT)
		draw_arc(knob, 5.0, 0, TAU, 12, BG, 1.0)
	if _box.size != Vector2.ZERO or _drag_kind.is_empty() or _drag_at == Vector2.ZERO:
		return
	var snap: Callable = dep.get("snap", Callable())
	var cursor := to_battle(_drag_at)
	if _drag_kind == "face":
		for id: int in _drag_ids:
			if not pos.has(id):
				continue
			var a := (cursor - to_battle(pos[id])).angle()
			var step := TAU / 8.0
			var snapped := roundf(a / step) * step
			var tip: Vector2 = pos[id] + Vector2(cos(snapped), sin(snapped)) * (float(radii.get(id, 8.0)) + 22.0)
			draw_line(pos[id], tip, GHOST, 2.0)
			draw_circle(tip, 4.0, GHOST)
		return
	var delta := cursor - to_battle(_press_at)
	for d: Dictionary in _shown:
		var id: int = d["id"]
		if not _drag_ids.has(id):
			continue
		var want: Vector2 = (d["c"] as Vector2) + delta
		var land: Vector2 = snap.call(id, want) if snap.is_valid() else want
		var g := area.position + land * k
		var rad := float(radii.get(id, 8.0))
		draw_arc(g, rad, 0, TAU, 24, GHOST, 2.0)
		draw_circle(g, 2.5, GHOST)
		if land.distance_to(want) > 0.5:
			var at := area.position + want * k
			draw_dashed_line(at, g, GHOST, 1.0, 3.0)
			draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), BATTLE, 2.0)
			draw_line(at + Vector2(-5, 5), at + Vector2(5, -5), BATTLE, 2.0)
			if id == _drag_anchor:
				draw_string(font, at + Vector2(8, -6), "can't deploy here", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BATTLE)


func _draw_zones(font: Font, area: Rect2, k: float) -> void:
	for z: Dictionary in _obs.get("zones", []):
		var c := area.position + Vector2(z["x"], z["y"]) / ONE * k
		var rad := float(z["radius"]) / ONE * k
		var owner := int(z["owner"])
		var col: Color = TeamPalette.color(owner, TEXT) if owner != 0 else TeamPalette.color(TeamPalette.NEUTRAL_ID)
		var held := owner != 0 and int(z["amount"]) >= int(z["threshold"])
		draw_circle(c, rad, Color(col, 0.2 if held else 0.07))
		draw_arc(c, rad, 0, TAU, 48, Color(col, 0.8), 1.5 if held else 1.0)
		if not compact:
			var who := "unheld" if owner == 0 else ("player %d" % owner) + ("" if held else " taking")
			draw_string(font, c + Vector2(-60, rad + 13), "zone %s · %s" % [z["id"], who], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(col.lightened(0.3), 0.9))


## Shots fired in the last few ticks of the playback: a line from the
## firing squad to its target, fading.
func _draw_shots(pos: Dictionary) -> void:
	var frames: Array = _play["frames"]
	var f := _play_t * (frames.size() - 1)
	for sh: Array in _play.get("shots", []):
		var age := f - float(sh[0])
		if age < 0.0 or age > 3.0 or not pos.has(sh[1]) or not pos.has(sh[2]):
			continue
		var col: Color = TeamPalette.color(frames[sh[0]][sh[1]]["player"], TEXT)
		draw_line(pos[sh[1]], pos[sh[2]], Color(col.lightened(0.45), 0.8 * (1.0 - age / 3.0)), 1.0)


## The battle's terrain as a texture, one pixel per cell (null without
## rules or terrain).
func _terrain_texture(rules: Variant) -> ImageTexture:
	if not rules is BattleRules:
		return null
	var r := rules as BattleRules
	if r == _terrain_rules:
		return _terrain_tex
	_terrain_rules = r
	_terrain_tex = null
	_terrain_names = PackedStringArray()
	if r.width <= 0 or r.height <= 0 or r.terrain.size() < r.width * r.height:
		return null
	var cells := PackedInt32Array()
	cells.resize(r.width * r.height)
	var colors: Array[Color] = []
	for f in r.feature_ids:
		colors.append(_terrain_color(f))
	var seen := {}
	for i in cells.size():
		cells[i] = r.terrain[i]
		seen[cells[i]] = true
	_terrain_tex = ImageTexture.create_from_image(ArtSet.ground_image(art, r.width, r.height, cells, r.feature_ids, colors))
	for i in r.feature_ids.size():
		if seen.has(i):
			_terrain_names.append(r.feature_ids[i])
	return _terrain_tex


func _draw_legend(font: Font, area: Rect2) -> void:
	var x := maxf(area.position.x, 0.0) + 6.0
	var y := minf(area.end.y, size.y) - 8.0
	for f in _terrain_names:
		draw_rect(Rect2(x, y - 9, 10, 10), _terrain_color(f).lightened(0.15))
		draw_string(font, Vector2(x + 13, y), f, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT)
		x += 22.0 + font.get_string_size(f, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


## Sets the battle camera (ViewContexts.zoom and battle_centre); compact
## views always show the whole field.
func set_camera(z: float, centre: Vector2) -> void:
	_cam_zoom = maxf(z, 1.0)
	_cam_centre = centre
	queue_redraw()


## The battlefield's rect in this view (Rect2() if no battle): fitted to
## the view, then magnified about the camera centre, which is kept where
## the field still fills the view.
func battle_area() -> Rect2:
	var w := float(_obs.get("width", 0))
	var h := float(_obs.get("height", 0))
	if mode != "battle" or w <= 0 or h <= 0:
		return Rect2()
	var k := _fit_k(w, h) * (1.0 if compact else _cam_zoom)
	var c := _clamp_centre(_cam_centre, k)
	return Rect2(size / 2.0 - c * k, Vector2(w, h) * k)


func _fit_k(w: float, h: float) -> float:
	var pad := 6.0 if compact else 16.0
	return maxf(minf((size.x - pad * 2) / w, (size.y - pad * 2) / h), 0.001)


## A camera centre (metres) kept so the field never leaves a gap it could
## fill: an axis the field fits on stays centred.
func _clamp_centre(c: Vector2, k: float) -> Vector2:
	var field := Vector2(float(_obs.get("width", 0)), float(_obs.get("height", 0)))
	if c.x < 0.0 and c.y < 0.0:
		c = field / 2.0
	var pad := 6.0 if compact else 16.0
	var half := (size / 2.0 - Vector2(pad, pad)) / k
	var out := c
	for i in 2:
		out[i] = field[i] / 2.0 if half[i] * 2.0 >= field[i] else clampf(c[i], half[i], field[i] - half[i])
	return out


## Asks to zoom the battle camera by `factor`, keeping the field point under
## view point `at` where it is.
func zoom_camera(factor: float, at: Vector2) -> void:
	var w := float(_obs.get("width", 0))
	var h := float(_obs.get("height", 0))
	if mode != "battle" or compact or w <= 0 or h <= 0:
		return
	var z := clampf(_cam_zoom * factor, 1.0, ViewContexts.BATTLE_ZOOM_MAX)
	var m := to_battle(at)
	var k := _fit_k(w, h) * z
	var c := _clamp_centre(m - (at - size / 2.0) / k, k)
	set_camera(z, c)
	battle_camera.emit(z, c if z > 1.0 else ViewContexts.NO_CENTRE)


## Asks to move the battle camera by `delta` view pixels: the view looks
## that way, so the field slides the other way (a drag passes -motion).
func pan_camera(delta: Vector2) -> void:
	var area := battle_area()
	if area.size == Vector2.ZERO or compact or _cam_zoom <= 1.0:
		return
	var k := area.size.x / float(_obs["width"])
	var c := _clamp_centre((size / 2.0 - area.position + delta) / k, k)
	set_camera(_cam_zoom, c)
	battle_camera.emit(_cam_zoom, c)


## A view point to battlefield metres, and back.
func to_battle(p: Vector2) -> Vector2:
	var area := battle_area()
	return (p - area.position) * float(_obs.get("width", 1)) / maxf(area.size.x, 1.0)


func to_view(m: Vector2) -> Vector2:
	var area := battle_area()
	return area.position + m * area.size.x / float(_obs.get("width", 1))


## The squads drawn in the last battle draw (playback: the moment shown), by ID.
func drawn_ids() -> Array[int]:
	var out: Array[int] = []
	for d: Dictionary in _shown:
		out.append(d["id"])
	return out


## The drawn squads whose centre lies inside a battlefield rect (metres).
func squads_in(rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	for d: Dictionary in _shown:
		if rect.abs().has_point(d["c"]):
			out.append(d["id"])
	return out


## The squad at a battlefield point: the one with a unit (or its centre)
## nearest within `radius` metres, or -1.
func squad_at(m: Vector2, radius: float = 4.0) -> int:
	var best := -1
	var best_d := radius * radius
	var squads := _shown if mode == "battle" and not _shown.is_empty() else _battle_squads()
	for d: Dictionary in squads:
		var near := (d["c"] as Vector2).distance_squared_to(m)
		for p: Vector2 in d["pts"]:
			near = minf(near, p.distance_squared_to(m))
		if near <= best_d:
			best_d = near
			best = d["id"]
	return best


# --- input -------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and is_inside_tree():
		_clear_hover()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		queue_redraw()  # a shown view resolves the current palette (sw-ijp.5)


## No hex is under the cursor any more: it left the view, or the view stopped
## showing the overworld (sw-3zs).
func _clear_hover() -> void:
	if _hover_plot < 0:
		return
	_hover_plot = -1
	hex_hovered.emit(-1)
	queue_redraw()


## A left press while deploying: on a selected squad's facing handle it
## starts turning the selection; on an own squad, placing it (the whole
## selection if it is selected). Shift / ctrl presses stay selection clicks
## and boxes.
func _begin_deploy_drag(at: Vector2, modified: bool) -> void:
	_end_deploy_drag()
	var dep: Dictionary = _overlay.get("deploy", {})
	if dep.is_empty() or compact or modified or not _play.is_empty():
		return
	var selected: Array = _overlay.get("selected", [])
	for id: int in _handles:
		if (_handles[id] as Vector2).distance_to(at) <= 8.0:
			_drag_kind = "face"
			_drag_ids = selected.duplicate()
			_drag_anchor = id
			return
	var hit := squad_at(to_battle(at))
	if hit >= 0 and (dep.get("own", []) as Array).has(hit):
		_drag_kind = "squad"
		_drag_anchor = hit
		_drag_ids = selected.duplicate() if selected.has(hit) else [hit]


func _end_deploy_drag() -> void:
	if not _drag_kind.is_empty() and _drag_at != Vector2.ZERO:
		queue_redraw()
	_drag_kind = ""
	_drag_ids = []
	_drag_anchor = -1
	_drag_at = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging_cam:
		pan_camera(-mm.relative)
		accept_event()
		return
	if mm != null and _pressing and mode == "battle":
		if mm.position.distance_to(_press_at) > 6.0:
			if _drag_kind.is_empty():
				_box = Rect2(_press_at, mm.position - _press_at)
			else:
				_drag_at = mm.position
			queue_redraw()
		accept_event()
		return
	if mm != null:
		if mode == "overworld":
			var p := plot_at(mm.position)
			if p != _hover_plot:
				_hover_plot = p
				hex_hovered.emit(p)
				queue_redraw()
		elif mode == "battle" and not compact:
			# Playback too: the hover card follows the squad under the cursor
			# (sw-bafi.1); the owner rebuilds it only on a change.
			var sq := squad_at(to_battle(mm.position))
			if sq != _hover_squad:
				_hover_squad = sq
				squad_hovered.emit(sq)
				queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mode == "battle" and not compact and mb.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging_cam = mb.pressed
		accept_event()
		return
	if mode == "battle" and not compact and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_camera(1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, mb.position)
		accept_event()
		return
	if mode == "battle" and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_pressing = true
			_press_at = mb.position
			_box = Rect2()
			_begin_deploy_drag(mb.position, mb.shift_pressed or mb.ctrl_pressed)
			if mb.double_click:
				_pressing = false
				_end_deploy_drag()
				battle_pressed.emit(to_battle(mb.position), MOUSE_BUTTON_LEFT, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed, true)
		elif _pressing:
			_pressing = false
			var kind := _drag_kind if _drag_at != Vector2.ZERO else ""
			var ids := _drag_ids
			var anchor := _drag_anchor
			_end_deploy_drag()
			if kind == "squad":
				deploy_dragged.emit(ids, anchor, to_battle(mb.position) - to_battle(_press_at))
			elif kind == "face":
				deploy_faced.emit(ids, to_battle(mb.position))
			elif _box.size != Vector2.ZERO:
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
				hex_clicked.emit(plot_at(mb.position), mb.button_index, mb.shift_pressed)
			else:
				battle_pressed.emit(to_battle(mb.position), mb.button_index, mb.shift_pressed, mb.ctrl_pressed, mb.alt_pressed, false)
		_:
			return
	accept_event()
