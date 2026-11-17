class_name GameSettings
extends RefCounted
## The player's saved settings (sw-ll4.19; the display part of sw-ll4.10):
## window mode and size, vsync, UI scale, and how long a turn takes to play
## out. Kept in `user://settings.cfg`. Presentation only: nothing here
## touches a match.

const SECTION := "settings"
const MODES: Array[String] = ["windowed", "borderless", "fullscreen"]
const MODE_NAMES: Dictionary = {"windowed": "Windowed", "borderless": "Borderless fullscreen", "fullscreen": "Exclusive fullscreen"}
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
const UI_SCALES: Array[float] = [0.75, 1.0, 1.25, 1.5, 2.0]
const TURN_SECONDS: Array[float] = [0.0, 2.0, 5.0, 10.0]
const DEFAULTS: Dictionary = {
	"window_mode": "windowed", "width": 1280, "height": 720, "vsync": true, "ui_scale": 1.0, "turn_seconds": 5.0,
	"ui_theme": "default", "side_width": 300,
}

## Where the settings are kept (tests point this elsewhere).
static var path: String = "user://settings.cfg"
static var _values: Dictionary = {}
static var _loaded_from: String = ""


static func _load() -> void:
	if _loaded_from == path:
		return
	_loaded_from = path
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in DEFAULTS:
		var v: Variant = cfg.get_value(SECTION, key, DEFAULTS[key])
		if typeof(v) == typeof(DEFAULTS[key]) or (v is int and DEFAULTS[key] is float):
			_values[key] = v


## Whether the player has saved settings (if not, the project's window is
## left as it starts).
static func saved() -> bool:
	return FileAccess.file_exists(path)


static func value(key: String) -> Variant:
	_load()
	return _values.get(key, DEFAULTS.get(key))


## Sets one setting and saves the file. Returns "" or why it was not saved.
static func set_value(key: String, v: Variant) -> String:
	_load()
	if not DEFAULTS.has(key):
		return "no such setting"
	_values[key] = v
	var cfg := ConfigFile.new()
	for k: String in _values:
		cfg.set_value(SECTION, k, _values[k])
	return "" if cfg.save(path) == OK else "could not write " + path


## Window sizes that fit the screen the window is on (always at least one).
static func sizes_for(screen: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in SIZES:
		if s.x <= screen.x and s.y <= screen.y:
			out.append(s)
	if out.is_empty():
		out.append(SIZES[0])
	return out


## Applies the display settings to a window. Does nothing without a real
## display (headless runs) or for a window embedded in another.
static func apply(window: Window) -> void:
	_load()
	if window == null:
		return
	window.content_scale_factor = float(value("ui_scale"))
	UiTheme.apply(window)
	if DisplayServer.get_name() == "headless" or window.is_embedded():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(value("vsync")) else DisplayServer.VSYNC_DISABLED)
	match String(value("window_mode")):
		"borderless":
			window.mode = Window.MODE_FULLSCREEN
		"fullscreen":
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			window.mode = Window.MODE_WINDOWED
			window.borderless = false
			var want := Vector2i(int(value("width")), int(value("height")))
			if window.size != want:
				window.size = want
				var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
				window.position = screen.position + (screen.size - want) / 2
