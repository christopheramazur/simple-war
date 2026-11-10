class_name ReplayViewer
extends Node2D
## Minimal battle replay viewer (M3). GDD 04 §4.1, R3Q21, R5Q19.
##
## Plays recorded frames (ReplayRecorder) on a 2D isometric battlefield with
## desaturated terrain so units stand out. Presentation only: it never touches
## simulation state. Runs standalone (F6): with no replay given it records and
## plays a demo Duel.
##
## Replay source, in order: the `replay_path` export, a `--replay=<path>`
## user argument (after `--`), else the demo.
## Controls: Space pause, +/- speed, Left/Right previous/next turn, Home
## restart, mouse wheel zoom, right-drag or arrow keys pan.

const UNIT_W: float = 16.0
const UNIT_H: float = 8.0
const PLAYER_COLORS: Dictionary = {1: Color(0.25, 0.55, 1.0), 2: Color(1.0, 0.35, 0.3)}
const NEUTRAL_COLOR: Color = Color(0.85, 0.85, 0.85)
## Desaturated terrain (R3Q21).
const FEATURE_COLORS: Dictionary = {
	"open": Color(0.50, 0.52, 0.47), "road": Color(0.60, 0.58, 0.54),
	"forest": Color(0.34, 0.40, 0.35), "ruins": Color(0.44, 0.42, 0.41),
}
const SHOT_LIFETIME: float = 0.35
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]

@export_file("*.sav") var replay_path: String = ""
@export var demo_seed: int = 7

var playing: bool = true
var speed_index: int = 2
## Playback position in ticks (presentation time, float is fine here).
var position_ticks: float = 0.0

var recorder: ReplayRecorder
var _iso: Transform2D
var _terrain_tex: ImageTexture
var _camera: Camera2D
var _hud: Label
var _shots: Array = []
var _last_frame: int = 0
var _panning: bool = false
var _error: String = ""


func _ready() -> void:
	_iso = Transform2D(Vector2(UNIT_W * 0.5, UNIT_H * 0.5), Vector2(-UNIT_W * 0.5, UNIT_H * 0.5), Vector2.ZERO)
	_build_hud()
	_load_replay()
	if recorder == null:
		_hud.text = "Replay viewer: %s" % _error
		return
	_build_terrain()
	_build_camera()
	_register_actions()


func _load_replay() -> void:
	var loader := PackageLoader.load_roots(PackedStringArray(["res://data/packages"]))
	if not loader.is_valid():
		_error = "content failed to load: " + "; ".join(loader.errors)
		return
	var path := replay_path
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--replay="):
			path = arg.substr(9)
	if not path.is_empty():
		var bytes := FileAccess.get_file_as_bytes(path)
		recorder = ReplayRecorder.from_save(bytes, loader.templates, loader.data_hash)
		if recorder == null:
			_error = "could not rebuild replay %s with the installed content" % path
		return
	recorder = ReplayRecorder.from_duel(loader.templates, loader.data_hash, "duel_crossroads", demo_seed,
		{1: ZoneController.new(1), 2: ZoneController.new(2, {"fall_back_pct": 60})})


func _build_terrain() -> void:
	var r := recorder.rules
	var img := Image.create(r.width, r.height, false, Image.FORMAT_RGB8)
	for y in r.height:
		for x in r.width:
			var f: String = r.feature_ids[r.terrain[y * r.width + x]]
			img.set_pixel(x, y, FEATURE_COLORS.get(f, Color(0.5, 0.5, 0.5)))
	_terrain_tex = ImageTexture.create_from_image(img)


func _build_camera() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	var r := recorder.rules
	_camera.position = _iso * Vector2(r.width * 0.5, r.height * 0.5)
	var view := get_viewport_rect().size
	var bounds := Rect2(_iso * Vector2.ZERO, Vector2.ZERO)
	for corner: Vector2 in [Vector2(r.width, 0), Vector2(0, r.height), Vector2(r.width, r.height)]:
		bounds = bounds.expand(_iso * corner)
	var fit := minf(view.x / maxf(bounds.size.x, 1.0), view.y / maxf(bounds.size.y, 1.0)) * 0.95
	_camera.position = bounds.get_center()
	_camera.zoom = Vector2(fit, fit)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


## Rebindable actions (registered at runtime until the GUIDE input layer
## lands in M4's planning UI).
func _register_actions() -> void:
	var binds := {
		&"replay_toggle": [KEY_SPACE], &"replay_faster": [KEY_EQUAL, KEY_KP_ADD],
		&"replay_slower": [KEY_MINUS, KEY_KP_SUBTRACT], &"replay_next_turn": [KEY_RIGHT],
		&"replay_prev_turn": [KEY_LEFT], &"replay_restart": [KEY_HOME],
	}
	for action: StringName in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if recorder == null:
		return
	if event.is_action_pressed(&"replay_toggle"):
		playing = not playing
	elif event.is_action_pressed(&"replay_faster"):
		speed_index = mini(speed_index + 1, SPEEDS.size() - 1)
	elif event.is_action_pressed(&"replay_slower"):
		speed_index = maxi(speed_index - 1, 0)
	elif event.is_action_pressed(&"replay_next_turn"):
		seek_turn(current_turn() + 1)
	elif event.is_action_pressed(&"replay_prev_turn"):
		seek_turn(current_turn() - 1)
	elif event.is_action_pressed(&"replay_restart"):
		seek_frame(0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Exponential (non-linear) zoom.
			var factor := 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			_camera.zoom = (_camera.zoom * factor).clamp(Vector2(0.2, 0.2), Vector2(8, 8))
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
	elif event is InputEventMouseMotion and _panning:
		_camera.position -= (event as InputEventMouseMotion).relative / _camera.zoom


func _process(delta: float) -> void:
	if recorder == null:
		return
	var pan := Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_up", &"ui_down"))
	if pan != Vector2.ZERO and not Input.is_action_pressed(&"replay_next_turn") and not Input.is_action_pressed(&"replay_prev_turn"):
		_camera.position += pan * 600.0 * delta / _camera.zoom.x
	if playing:
		advance(delta)
	_age_shots(delta)
	_update_hud()
	queue_redraw()


## Moves playback forward by `delta` seconds of real time.
func advance(delta: float) -> void:
	var last := float(recorder.frames.size() - 1)
	position_ticks = minf(position_ticks + delta * recorder.rules.tps * SPEEDS[speed_index], last)
	var frame := int(position_ticks)
	for f in range(_last_frame + 1, frame + 1):
		_spawn_shots(f)
	_last_frame = frame


func seek_frame(frame: int) -> void:
	position_ticks = clampf(frame, 0, recorder.frames.size() - 1)
	_last_frame = int(position_ticks)
	_shots.clear()


func current_turn() -> int:
	return recorder.frame_turn[int(position_ticks)]


func seek_turn(turn: int) -> void:
	for f in recorder.frames.size():
		if recorder.frame_turn[f] >= turn:
			seek_frame(f)
			return
	seek_frame(recorder.frames.size() - 1)


func _spawn_shots(frame: int) -> void:
	var centres := _squad_centres(recorder.frames[frame])
	for e: Dictionary in recorder.events[frame]:
		if e["type"] != &"squad_fired":
			continue
		var d: Dictionary = e["data"]
		if centres.has(d["squad"]) and centres.has(d["target"]):
			_shots.append([centres[d["squad"]][0], centres[d["target"]][0], centres[d["squad"]][1], SHOT_LIFETIME])


func _age_shots(delta: float) -> void:
	for s: Array in _shots:
		s[3] -= delta
	_shots = _shots.filter(func(s: Array) -> bool: return s[3] > 0.0)


## squad id -> [centre Vector2 in battlefield units, player].
func _squad_centres(f: PackedInt64Array) -> Dictionary:
	var sums := {}
	var stride := ReplayRecorder.STRIDE
	for o in range(0, f.size(), stride):
		var sid := f[o + ReplayRecorder.F_SQUAD]
		var p := Vector2(f[o + ReplayRecorder.F_X], f[o + ReplayRecorder.F_Y]) / float(Fixed.ONE)
		if not sums.has(sid):
			sums[sid] = [Vector2.ZERO, 0, f[o + ReplayRecorder.F_PLAYER]]
		sums[sid][0] += p
		sums[sid][1] += 1
	var out := {}
	for sid: int in sums:
		out[sid] = [sums[sid][0] / float(sums[sid][1]), sums[sid][2]]
	return out


func _draw() -> void:
	if recorder == null:
		return
	var r := recorder.rules
	draw_set_transform_matrix(_iso)
	draw_texture_rect(_terrain_tex, Rect2(0, 0, r.width, r.height), false)
	var frame := int(position_ticks)
	for z in r.zone_ids.size():
		var c := Vector2(r.zn_x[z], r.zn_y[z]) / float(Fixed.ONE)
		var rad := r.zn_radius[z] / float(Fixed.ONE)
		var owner := recorder.zone_owner[frame][z]
		var held := owner != 0 and recorder.zone_amount[frame][z] >= r.zn_threshold[z]
		var col: Color = PLAYER_COLORS.get(owner, NEUTRAL_COLOR)
		draw_circle(c, rad, Color(col, 0.25 if held else 0.08))
		draw_arc(c, rad, 0, TAU, 48, Color(col, 0.9), 0.4)
	for s: Array in _shots:
		var col: Color = PLAYER_COLORS.get(s[2], NEUTRAL_COLOR)
		draw_line(s[0], s[1], Color(col.lightened(0.4), s[3] / SHOT_LIFETIME), 0.25)
	var a := recorder.frames[frame]
	var b := recorder.frames[mini(frame + 1, recorder.frames.size() - 1)]
	var t := position_ticks - frame
	var next_pos := {}
	for o in range(0, b.size(), ReplayRecorder.STRIDE):
		next_pos[b[o]] = Vector2(b[o + ReplayRecorder.F_X], b[o + ReplayRecorder.F_Y])
	for o in range(0, a.size(), ReplayRecorder.STRIDE):
		var p := Vector2(a[o + ReplayRecorder.F_X], a[o + ReplayRecorder.F_Y])
		if next_pos.has(a[o]):
			p = p.lerp(next_pos[a[o]], t)
		var col: Color = PLAYER_COLORS.get(a[o + ReplayRecorder.F_PLAYER], NEUTRAL_COLOR)
		draw_circle(p / float(Fixed.ONE), 0.7, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _update_hud() -> void:
	var frame := int(position_ticks)
	var sc := recorder.scores[frame]
	var lines := PackedStringArray()
	lines.append("Turn %d   tick %d/%d   %sx%s" % [recorder.frame_turn[frame], frame, recorder.frames.size() - 1,
		str(SPEEDS[speed_index]), "" if playing else "  (paused)"])
	for i in recorder.players.size():
		lines.append("Player %d   influence %d   value %d" % [recorder.players[i], sc[i * 2], sc[i * 2 + 1]])
	if frame == recorder.frames.size() - 1 and not recorder.result.is_empty():
		var w: int = recorder.result["winner"]
		lines.append("Result: %s (%s)" % ["draw" if w == 0 else "player %d wins" % w, recorder.result["reason"]])
	lines.append("Space pause   +/- speed   Left/Right turn   Home restart   wheel zoom   right-drag pan")
	_hud.text = "\n".join(lines)
