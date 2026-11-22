class_name OptionsScreen
extends UiWindow
## The options screen (sw-ll4.19; display part of sw-ll4.10): window mode,
## window size, vsync, UI scale and turn playback time. An overlay any
## screen can open over itself (`open_over`; Esc closes it). Each change applies at once
## and is saved (GameSettings). Runs standalone (F6).

signal setting_changed(key: String)

var _mode: OptionButton
var _size: OptionButton
var _vsync: CheckBox
var _fps: OptionButton
var _scale: OptionButton
var _theme: OptionButton
var _palette: OptionButton
var _turn: OptionButton
var _alert: OptionButton
var _said: Label
var _sizes: Array[Vector2i] = []


## Opens the options over `parent` (a full-rect Control or the scene root).
static func open_over(parent: Node) -> OptionsScreen:
	var o := OptionsScreen.new()
	o.id = &"options"
	UiRoot.of(parent).open(o)
	return o


func _ready() -> void:
	UiTheme.ensure(get_window())
	var col := dialog(440)
	col.add_child(UiTheme.label("Options", "TitleLabel"))
	col.add_child(_heading("Display"))
	_mode = OptionButton.new()
	_mode.name = "Mode"
	for m in GameSettings.MODES:
		_mode.add_item(GameSettings.MODE_NAMES[m])
	_mode.select(maxi(GameSettings.MODES.find(String(GameSettings.value("window_mode"))), 0))
	_mode.item_selected.connect(func(i: int) -> void: _change("window_mode", GameSettings.MODES[i]))
	col.add_child(_row("Window mode", _mode))
	_size = OptionButton.new()
	_size.name = "Size"
	var screen := Vector2i(3840, 2160)
	if DisplayServer.get_name() != "headless":
		screen = DisplayServer.screen_get_size(get_window().current_screen)
	_sizes = GameSettings.sizes_for(screen)
	var now := Vector2i(int(GameSettings.value("width")), int(GameSettings.value("height")))
	for i in _sizes.size():
		_size.add_item("%d × %d" % [_sizes[i].x, _sizes[i].y])
		if _sizes[i] == now:
			_size.select(i)
	_size.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("width", _sizes[i].x)
		_change("height", _sizes[i].y))
	col.add_child(_row("Window size", _size))
	_vsync = CheckBox.new()
	_vsync.name = "VSync"
	_vsync.text = "On"
	_vsync.button_pressed = bool(GameSettings.value("vsync"))
	_vsync.toggled.connect(func(on: bool) -> void: _change("vsync", on))
	col.add_child(_row("VSync", _vsync))
	_fps = OptionButton.new()
	_fps.name = "MaxFps"
	for i in GameSettings.MAX_FPS.size():
		var f := GameSettings.MAX_FPS[i]
		_fps.add_item("Unlimited" if f <= 0 else "%d fps" % f)
		if f == int(GameSettings.value("max_fps")):
			_fps.select(i)
	_fps.item_selected.connect(func(i: int) -> void: _change("max_fps", GameSettings.MAX_FPS[i]))
	col.add_child(_row("Frame rate limit", _fps))
	_scale = OptionButton.new()
	_scale.name = "Scale"
	for i in GameSettings.UI_SCALES.size():
		_scale.add_item("%d%%" % int(GameSettings.UI_SCALES[i] * 100))
		if is_equal_approx(GameSettings.UI_SCALES[i], float(GameSettings.value("ui_scale"))):
			_scale.select(i)
	_scale.item_selected.connect(func(i: int) -> void: _change("ui_scale", GameSettings.UI_SCALES[i]))
	col.add_child(_heading("Interface"))
	_theme = OptionButton.new()
	_theme.name = "Theme"
	var theme_ids := UiTheme.ids()
	for i in theme_ids.size():
		_theme.add_item(str(UiTheme.profile(theme_ids[i])["name"]))
		if theme_ids[i] == str(GameSettings.value("ui_theme")):
			_theme.select(i)
	_theme.item_selected.connect(func(i: int) -> void: _change("ui_theme", theme_ids[i]))
	col.add_child(_row("Theme", _theme))
	_palette = OptionButton.new()
	_palette.name = "TeamPalette"
	var palette_ids := TeamPalette.ids()
	for i in palette_ids.size():
		_palette.add_item(str(TeamPalette.preset(palette_ids[i])["name"]))
		if palette_ids[i] == str(GameSettings.value("team_palette")):
			_palette.select(i)
	_palette.item_selected.connect(func(i: int) -> void: _change("team_palette", palette_ids[i]))
	col.add_child(_row("Team colours", _palette))
	col.add_child(_row("UI scale", _scale))
	var where := UiTheme.label("Your own themes: put a .json file like the ones in data/ui/themes into %s" % ProjectSettings.globalize_path(UiTheme.USER_DIR), "CaptionDimLabel")
	where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	where.custom_minimum_size = Vector2(390, 0)
	col.add_child(where)
	col.add_child(_heading("Game"))
	_turn = OptionButton.new()
	_turn.name = "Turn"
	for i in GameSettings.TURN_SECONDS.size():
		var s := GameSettings.TURN_SECONDS[i]
		_turn.add_item("Instant" if s <= 0.0 else "%d seconds" % int(s))
		if is_equal_approx(s, float(GameSettings.value("turn_seconds"))):
			_turn.select(i)
	_turn.item_selected.connect(func(i: int) -> void: _change("turn_seconds", GameSettings.TURN_SECONDS[i]))
	col.add_child(_row("A turn plays out over", _turn))
	_alert = OptionButton.new()
	_alert.name = "AlertSeconds"
	for i in GameSettings.ALERT_SECONDS.size():
		var a := GameSettings.ALERT_SECONDS[i]
		_alert.add_item("Until dismissed" if a <= 0.0 else "%d seconds" % int(a))
		if is_equal_approx(a, float(GameSettings.value("alert_seconds"))):
			_alert.select(i)
	_alert.item_selected.connect(func(i: int) -> void: _change("alert_seconds", GameSettings.ALERT_SECONDS[i]))
	col.add_child(_row("Battle alerts stay new for", _alert))
	_said = UiTheme.label("", "DimLabel", true)
	_said.custom_minimum_size = Vector2(390, 0)
	col.add_child(_said)
	var close := Button.new()
	close.name = "Close"
	close.text = "Close (Esc)"
	close.custom_minimum_size = Vector2(0, 38)
	close.pressed.connect(close_screen)
	col.add_child(close)
	_sync()


func _change(key: String, v: Variant) -> void:
	var err := GameSettings.set_value(key, v)
	GameSettings.apply(get_window())
	_sync()
	if not err.is_empty():
		_said.text = err
	setting_changed.emit(key)


func _sync() -> void:
	var windowed := String(GameSettings.value("window_mode")) == "windowed"
	_size.disabled = not windowed
	_said.text = "" if windowed else "Fullscreen uses the screen's own resolution. Window size applies in Windowed mode."


func close_screen() -> void:
	close()


func _heading(text: String) -> Label:
	return UiTheme.label(text, "AccentLabel")


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
