extends SceneTree
## Renders a UI mock to PNG (E4Q3): throwaway Control scenes fed by Game API
## data, several variants per contact sheet.
##
##   Godot_v4.7.2-stable_win64_console.exe --path . -s res://src/presentation/mocks/mock_runner.gd \
##       -- --mock res://src/presentation/mocks/inspection_window_mock.gd --out mocks/inspection.png
##
## Needs a real renderer, so it opens a window briefly (--headless renders
## nothing). A mock script provides `static func build() -> Control`; the
## Control's custom_minimum_size is the image size.

const SETTLE_FRAMES: int = 6

var _out: String = ""
var _frames: int = 0
var _failed: bool = false
var _mock: Control


func _initialize() -> void:
	var args := _user_args()
	_out = args.get("out", "")
	var script: Script = load(args.get("mock", "")) if args.has("mock") else null
	if script == null or _out.is_empty() or not script.can_instantiate():
		push_error("mock_runner: need --mock <res://script.gd> (which must parse) --out <path.png>")
		_failed = true
		quit(1)
		return
	_mock = script.build()
	var size := Vector2i(_mock.custom_minimum_size)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# As the game does, whatever the local settings say; MOCK_UI_THEME picks another profile.
	var theme_id := OS.get_environment("MOCK_UI_THEME")
	UiTheme.apply(root, UiTheme.DEFAULT_ID if theme_id.is_empty() else theme_id)
	root.size = size
	DisplayServer.window_set_size(size)
	root.add_child(_mock)


func _process(_delta: float) -> bool:
	if _failed:
		return true
	_frames += 1
	if _frames == 1:
		_hide_others()
	if _frames < SETTLE_FRAMES:
		return false
	var img := root.get_texture().get_image()
	var path := _out if _out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		push_error("mock_runner: could not save %s (%d)" % [path, err])
	else:
		print("mock_runner: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
		var layout := _layout(_mock, img, path)
		if not layout.is_empty():
			print("mock_runner: layout %s" % layout)
		for variant in CvdSim.VARIANTS:
			var vpath := path.get_basename() + "_" + variant + ".png"
			var verr := CvdSim.simulate(img, variant).save_png(vpath)
			if verr != OK:
				push_error("mock_runner: could not save %s (%d)" % [vpath, verr])
			else:
				print("mock_runner: variant %s" % vpath)
	return true


## A mock that shows a battle (a ContextView) also gets <name>_layout.json
## beside its PNG: the label and footprint rectangles it drew, in image
## pixels, for `hx visual lint` (sw-tho3.12). Other mocks get none.
func _layout(mock: Control, img: Image, path: String) -> String:
	var views: Array[ContextView] = []
	_find_views(mock, views)
	if views.is_empty():
		return ""
	var rects: Array = []
	for v in views:
		var origin := v.global_position
		for d: Dictionary in v.drawn:
			var r: Rect2 = d["rect"]
			var rec := {"kind": d["kind"], "squad": d["squad"], "player": d["player"], "frame": 0,
				"rect": [snappedf(origin.x + r.position.x, 0.01), snappedf(origin.y + r.position.y, 0.01),
					snappedf(r.size.x, 0.01), snappedf(r.size.y, 0.01)]}
			if d.has("fg"):
				var fg: Color = d["fg"]
				rec["fg"] = [snappedf(fg.r, 0.0001), snappedf(fg.g, 0.0001), snappedf(fg.b, 0.0001), snappedf(fg.a, 0.0001)]
			rects.append(rec)
	var lay_path := path.get_basename() + "_layout.json"
	var lay := {"image": path.get_file(), "size": [img.get_width(), img.get_height()], "rects": rects}
	var f := FileAccess.open(lay_path, FileAccess.WRITE)
	if f == null:
		push_error("mock_runner: could not write %s" % lay_path)
		return ""
	f.store_string(JSON.stringify(lay, "	"))
	return lay_path


static func _find_views(n: Node, out: Array[ContextView]) -> void:
	if n is ContextView:
		out.append(n)
	for c in n.get_children():
		_find_views(c, out)


## Autoloads (addons) may draw their own UI; keep only the mock visible.
func _hide_others() -> void:
	for c in root.get_children():
		if c == root.get_child(root.get_child_count() - 1):
			continue
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		for sub in c.find_children("*", "CanvasLayer", true, false):
			(sub as CanvasLayer).visible = false
		if c is CanvasItem:
			(c as CanvasItem).visible = false


static func _user_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
