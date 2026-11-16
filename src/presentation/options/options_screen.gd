class_name OptionsScreen
extends Control
## The options screen (sw-ll4.19; display part of sw-ll4.10): window mode,
## window size, vsync, UI scale and turn playback time. An overlay any
## screen can open over itself (`open_over`). Each change applies at once
## and is saved (GameSettings). Runs standalone (F6).

signal closed

const PANEL: Color = Color("1d2128")
const DIM: Color = Color("8a93a3")

var _mode: OptionButton
var _size: OptionButton
var _vsync: CheckBox
var _scale: OptionButton
var _turn: OptionButton
var _said: Label
var _sizes: Array[Vector2i] = []


## Opens the options over `parent` (a full-rect Control or the scene root).
static func open_over(parent: Node) -> OptionsScreen:
	var o := OptionsScreen.new()
	parent.add_child(o)
	return o


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.05, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_content_margin_all(24)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)
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
	_scale = OptionButton.new()
	_scale.name = "Scale"
	for i in GameSettings.UI_SCALES.size():
		_scale.add_item("%d%%" % int(GameSettings.UI_SCALES[i] * 100))
		if is_equal_approx(GameSettings.UI_SCALES[i], float(GameSettings.value("ui_scale"))):
			_scale.select(i)
	_scale.item_selected.connect(func(i: int) -> void: _change("ui_scale", GameSettings.UI_SCALES[i]))
	col.add_child(_row("UI scale", _scale))
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
	_said = Label.new()
	_said.add_theme_color_override("font_color", DIM)
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func _sync() -> void:
	var windowed := String(GameSettings.value("window_mode")) == "windowed"
	_size.disabled = not windowed
	_said.text = "" if windowed else "Fullscreen uses the screen's own resolution. Window size applies in Windowed mode."


func close_screen() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_screen()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("e6b450"))
	return l


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
