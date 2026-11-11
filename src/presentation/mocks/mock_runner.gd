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


func _initialize() -> void:
	var args := _user_args()
	_out = args.get("out", "")
	var script: Script = load(args.get("mock", "")) if args.has("mock") else null
	if script == null or _out.is_empty() or not script.can_instantiate():
		push_error("mock_runner: need --mock <res://script.gd> (which must parse) --out <path.png>")
		_failed = true
		quit(1)
		return
	var mock: Control = script.build()
	var size := Vector2i(mock.custom_minimum_size)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = size
	DisplayServer.window_set_size(size)
	root.add_child(mock)


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
	return true


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
