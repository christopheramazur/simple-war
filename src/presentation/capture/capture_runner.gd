extends SceneTree
## Capture runner (sw-tho3.9, U1 B9, GDD 05 §5.6 proposal): stills and frame
## strips of a battle as the game's own battle view draws them, each with its
## machine truth, for the visual assessment tools (hx visual, the vision
## bench, layout lint, golden diffs).
##
##   Godot_v4.7.2-stable_win64_console.exe --path . -s res://src/presentation/capture/capture_runner.gd -- \
##       --workshop attack_move_firing_position --out captures/amfp
##
## Source (one): --workshop <id|path> [--variant v] | --duel <scenario> [--seed n]
## [--controller zone] [--turns n] | --save <battle .sav> | --match <match log
## folder> [--battle <id>].
## Options: --views 0,1 (0 = all-seeing) --kinds game,control[,greyscale,protan,
## deutan] --forms still,strip --stages deploy,contact,... --strip-frames 5
## --strip-stride 2 --size 960x640 --no-render (truth and manifest only;
## works with --headless).
##
## Writes under --out: manifest.json and truth/<shot>.json (CaptureJob),
## <shot>_<kind>.png, and layout/<shot>_<kind>.json: the label and footprint
## rectangles ContextView drew (pixels of the PNG), for layout lint.
## A strip is rendered one cell at a time (each its own frame, captioned
## with its tick by the view's title) and the cells are put side by side;
## its size keeps it near CaptureJob.STRIP_TOKENS vision tokens.
## The camera of each shot (manifest "camera": zoom and centre, metres) is
## framed on the squads its viewer sees, over all the shot's frames
## (CaptureJob.frame_camera), so the squads are big enough to read.
##
## Needs a real renderer for the PNGs, so it opens a window briefly, like
## mock_runner.gd. It only reads the source: the job re-simulates it.

const SETTLE_FRAMES: int = 6
const MAX_WAIT: int = 60

var _job: CaptureJob
var _out: String = ""
## [{shot, kind ("game" | "control")}] still to render.
var _queue: Array = []
var _cur: Dictionary = {}
var _cell: int = 0
var _cells: Array[Image] = []
var _rects: Array = []
var _view: ContextView
var _frames: int = 0
var _failed: bool = false
var _done: bool = false
var _recs: Dictionary = {}
var _colors: Dictionary = {}


func _initialize() -> void:
	var args := _user_args()
	_out = String(args.get("out", ""))
	var src := _source(args)
	if _out.is_empty() or src.is_empty():
		push_error("capture_runner: need --out <dir> and one source (--workshop, --duel, --save, --match)")
		_fail()
		return
	if not _out.is_absolute_path():
		_out = ProjectSettings.globalize_path("res://").path_join(_out)
	_job = CaptureJob.prepare(src, _options(args))
	if not _job.is_ok():
		for e in _job.errors:
			push_error("capture_runner: " + e)
		_fail()
		return
	var err := _job.write(_out)
	if err != OK:
		push_error("capture_runner: could not write %s (%d)" % [_out, err])
		_fail()
		return
	print("capture_runner: %d shots, stages %s, missing %s -> %s" % [_job.shots.size(), _job.stages.keys(), _job.missing, _out])
	if args.has("no-render") or _job.shots.is_empty():
		_done = true
		return
	for s: Dictionary in _job.shots:
		var kinds: Array = (s["images"] as Dictionary).keys()
		var game := false
		for k: String in kinds:
			if k != "control":
				game = true
		if game:
			_queue.append({"shot": s, "kind": "game"})
		if kinds.has("control"):
			_queue.append({"shot": s, "kind": "control"})
	_colors = ContextView.feature_colors(WorkshopRun.loader_for("core").templates)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	UiTheme.apply(root, UiTheme.DEFAULT_ID)


func _fail() -> void:
	_failed = true
	quit(1)


func _process(_delta: float) -> bool:
	if _failed:
		return true
	if _done:
		quit(0)
		return true
	if _cur.is_empty():
		if _queue.is_empty():
			print("capture_runner: done")
			quit(0)
			return true
		_cur = _queue.pop_front()
		_cell = 0
		_cells = []
		_rects = []
		_show_cell()
		return false
	_frames += 1
	if _frames == 1:
		_hide_others()
	var want: Vector2i = _cell_size()
	var img := root.get_texture().get_image()
	if _frames < SETTLE_FRAMES or (img.get_size() != want and _frames < MAX_WAIT):
		return false
	if img.get_size() != want:
		push_error("capture_runner: window is %s, not %s" % [img.get_size(), want])
		_fail()
		return true
	_take_cell(img)
	_cell += 1
	if _cell < (_cur["shot"]["frames"] as Array).size():
		_show_cell()
	else:
		_finish_shot()
		_cur = {}
	return false


func _cell_size() -> Vector2i:
	var c: Array = _cur["shot"]["cell"]
	return Vector2i(int(c[0]), int(c[1]))


func _show_cell() -> void:
	if _view != null:
		_view.get_parent().remove_child(_view)
		_view.free()
	var shot: Dictionary = _cur["shot"]
	var turn := int(shot["turn"])
	var viewer := int(shot["viewer"])
	var frame: int = shot["frames"][_cell]
	var key := "%d:%d" % [turn, viewer]
	if not _recs.has(key):  # one record per turn and view: BattleFx is built once
		_recs[key] = _job.playback(turn, viewer)
	var t := _job.truth_at(turn, frame)
	var size := _cell_size()
	var v := ContextView.new()
	v.art = ArtSet.core()
	v.terrain_colors = _colors
	v.custom_minimum_size = Vector2(size)
	v.size = Vector2(size)
	v.title = ("%s · tick %d" % [shot["stage"], shot["ticks"][_cell]]) if shot["form"] == "still" \
		else "tick %d" % shot["ticks"][_cell]
	var cam: Dictionary = shot["camera"]
	v.set_camera(float(cam["zoom"]), Vector2(float(cam["centre"][0]), float(cam["centre"][1])))
	root.size = size
	DisplayServer.window_set_size(size)
	root.add_child(v)
	v.show_playback_frame(_recs[key], frame, (t.get("obs", {}) as Dictionary).get(viewer, {}))
	if _cur["kind"] == "control":
		var o := DebugOverlay.new()
		o.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.add_child(o)
		o.attach(v)
		o.set_layer("labels", true)
		o.show_frame(t.get("debug", {}))
	_view = v
	_frames = 0


func _take_cell(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	_cells.append(img)
	var dx := float(_cell * _cell_size().x)
	var frame: int = _cur["shot"]["frames"][_cell]
	for d: Dictionary in _view.drawn:
		var r: Rect2 = d["rect"]
		var rec := {"kind": d["kind"], "squad": d["squad"], "player": d["player"], "frame": frame,
			"rect": [snappedf(r.position.x + dx, 0.01), snappedf(r.position.y, 0.01), snappedf(r.size.x, 0.01), snappedf(r.size.y, 0.01)]}
		if d.has("fg"):
			var fg: Color = d["fg"]
			rec["fg"] = [snappedf(fg.r, 0.0001), snappedf(fg.g, 0.0001), snappedf(fg.b, 0.0001), snappedf(fg.a, 0.0001)]
		_rects.append(rec)


func _finish_shot() -> void:
	var shot: Dictionary = _cur["shot"]
	var kind: String = _cur["kind"]
	var size := _cell_size()
	var img := Image.create_empty(size.x * _cells.size(), size.y, false, Image.FORMAT_RGBA8)
	for i in _cells.size():
		img.blit_rect(_cells[i], Rect2i(Vector2i.ZERO, size), Vector2i(i * size.x, 0))
	var images: Dictionary = shot["images"]
	var out := {}
	if kind == "control":
		out["control"] = img
	else:
		for k: String in images:
			if k == "game":
				out[k] = img
			elif k != "control":
				out[k] = CvdSim.simulate(img, k)
	for k: String in out:
		var path := _out.path_join(images[k])
		var err := (out[k] as Image).save_png(path)
		if err != OK:
			push_error("capture_runner: could not save %s (%d)" % [path, err])
		else:
			print("capture_runner: wrote %s" % images[k])
	if (shot["layout"] as Dictionary).has(kind):
		var lay := {"shot": shot["id"], "kind": kind, "image": images[kind], "size": [img.get_width(), img.get_height()],
			"cell": shot["cell"], "rects": _rects}
		CaptureJob._write_text(_out.path_join(shot["layout"][kind]), CaptureJob.to_json(lay))


## Autoloads (addons) may draw their own UI; keep only the view visible.
func _hide_others() -> void:
	for c in root.get_children():
		if c == _view:
			continue
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		for sub in c.find_children("*", "CanvasLayer", true, false):
			(sub as CanvasLayer).visible = false
		if c is CanvasItem:
			(c as CanvasItem).visible = false


static func _source(a: Dictionary) -> Dictionary:
	if a.has("workshop"):
		return {"kind": "workshop", "id": a["workshop"], "variant": a.get("variant", WorkshopScenario.BASE)}
	if a.has("duel"):
		return {"kind": "duel", "scenario": a["duel"], "seed": int(a.get("seed", "1")),
			"controller": a.get("controller", "zone"), "turns": int(a.get("turns", "50"))}
	if a.has("save"):
		return {"kind": "save", "path": a["save"]}
	if a.has("match"):
		var m := {"kind": "match", "path": a["match"]}
		if a.has("battle"):
			m["battle"] = int(a["battle"])
		return m
	return {}


static func _options(a: Dictionary) -> Dictionary:
	var o := {}
	for k in ["kinds", "forms", "stages"]:
		if a.has(k):
			o[k] = Array(String(a[k]).split(",", false))
	if a.has("views"):
		var v := []
		for s in String(a["views"]).split(",", false):
			v.append(int(s))
		o["views"] = v
	if a.has("strip-frames"):
		o["strip_frames"] = int(a["strip-frames"])
	if a.has("strip-stride"):
		o["strip_stride"] = int(a["strip-stride"])
	if a.has("size"):
		var p := String(a["size"]).split("x")
		o["size"] = [int(p[0]), int(p[1])]
	return o


static func _user_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if not a[i].begins_with("--"):
			i += 1
			continue
		var k: String = a[i].substr(2)
		if i + 1 < a.size() and not a[i + 1].begins_with("--"):
			out[k] = a[i + 1]
			i += 2
		else:
			out[k] = true
			i += 1
	return out
