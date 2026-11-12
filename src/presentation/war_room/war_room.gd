class_name WarRoom
extends Control
## The multi-battle view (GDD 04 §4.8, R2Q19, R3Q20, R4Q15): the overworld
## or a focused battle in the main view, picture-in-picture battle views,
## the battles menu and the player's commanders. Presentation only: what is
## shown lives in ViewContexts; the session is read through observe /
## observe_battle. Runs standalone (F6) on a demo session with two battles.
##
## Controls: Tab / Shift+Tab swap battles (Tab tabs in from the overworld),
## Esc exits a battle, F follows the selected commander, Backspace or a
## right click deselects all, mouse wheel zooms (zooming in on a battle hex
## enters it), left click selects a commander or hex, Space ends the turn.
## PiP views: click to swap into the main view, drag to move.

## Emitted for the Space key / End turn button; the owner advances the
## session. The demo handles it itself.
signal end_turn_requested

const SIDE_W: float = 250.0
const PIP_SIZE: Vector2 = Vector2(240, 160)
const PANEL: Color = Color("1d2128")
const DIM: Color = Color("8a93a3")

@export var player: int = 1
## Applied once the demo is built (the mock uses it): "", "battle" (focus
## the first battle) or "pip" (focus the first, pin the second).
@export var demo_view: String = ""

var session: OverworldSession
var contexts: ViewContexts

var _main: ContextView
var _pip_layer: Control
var _menu: VBoxContainer
var _cmds: VBoxContainer
var _hud: Label
var _dirty: bool = false


func _ready() -> void:
	_build_ui()
	if session == null:
		session = demo_session()
		end_turn_requested.connect(_demo_end_turn)
	contexts = ViewContexts.new(player)
	contexts.changed.connect(_queue_refresh)
	contexts.sync(session.observe(player))
	match demo_view:
		"battle":
			contexts.tab_in()
		"pip":
			var all := contexts.battles()
			if all.size() >= 2:
				contexts.focus_battle(all[0])
				contexts.pin(all[1])
				contexts.select_commander(contexts.menu()[0]["commanders"][0])
	_refresh()


func _exit_tree() -> void:
	if contexts != null and contexts.changed.is_connected(_queue_refresh):
		contexts.changed.disconnect(_queue_refresh)


## A demo: test_vale with player 1 fighting the bandit camp and player 2's
## commander at once.
static func demo_session() -> OverworldSession:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var w := s.rules.width
	var a := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(12, 4, w))
	s.set_route(1, a, PackedInt64Array([Hex.plot(11, 3, w)]))
	var b := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(5, 5, w))
	Commanders.spawn(s.state, 2, "field_commander", Hex.plot(6, 5, w))
	s.set_route(1, b, PackedInt64Array([Hex.plot(6, 5, w)]))
	for i in 2:  # planning -> intermission -> planning: the battles begin
		for p in s.players():
			s.ready(p)
	return s


# --- building ----------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(stage)
	_main = ContextView.new()
	_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main.hex_clicked.connect(_on_hex_clicked)
	_main.battle_clicked.connect(_on_battle_clicked)
	_main.zoomed.connect(func(f: float) -> void: contexts.zoom_by(f))
	stage.add_child(_main)
	_pip_layer = Control.new()
	_pip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_pip_layer)
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -26
	_hud.add_theme_color_override("font_color", DIM)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_hud)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(SIDE_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	side.add_theme_stylebox_override("panel", sb)
	row.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	side.add_child(col)
	col.add_child(_title("Battles"))
	_menu = VBoxContainer.new()
	col.add_child(_menu)
	col.add_child(_title("Commanders"))
	_cmds = VBoxContainer.new()
	col.add_child(_cmds)
	var end := Button.new()
	end.text = "End turn (Space)"
	end.pressed.connect(func() -> void: end_turn_requested.emit())
	col.add_child(end)


func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	return l


# --- projection ----------------------------------------------------------------

## Redraws once per frame, after the input that changed the contexts (a
## button may not be freed while it emits).
func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	if contexts.focus == ViewContexts.OVERWORLD:
		_main.show_overworld(session.observe(player), session.rules.feature_ids, contexts)
	else:
		_main.title = battle_name(contexts.focus)
		_main.show_battle(session.observe_battle(player, contexts.focus))
	_refresh_pips()
	_refresh_menu()
	_refresh_commanders()
	var where := "Overworld" if contexts.focus == ViewContexts.OVERWORLD else battle_name(contexts.focus)
	var follow := "" if contexts.followed < 0 else "  ·  following %d" % contexts.followed
	_hud.text = "  %s%s  ·  zoom %.2f  ·  turn %d   [Tab swap · Esc exit · F follow · wheel zoom · Space end turn]" % [
		where, follow, contexts.zoom, session.turns_resolved() + 1]


func _refresh_pips() -> void:
	_clear(_pip_layer)
	for i in contexts.pips.size():
		var eid := contexts.pips[i]
		var pip := _PipPanel.new()
		pip.engagement = eid
		pip.size = PIP_SIZE
		var home := Vector2(12, 12 + i * (PIP_SIZE.y + 10))
		pip.position = home + contexts.pip_offsets.get(eid, Vector2.ZERO)
		pip.home = home
		pip.chosen.connect(func(e: int) -> void: contexts.focus_battle(e))
		pip.moved.connect(func(e: int, off: Vector2) -> void: contexts.move_pip(e, off))
		_pip_layer.add_child(pip)
		pip.view.title = battle_name(eid)
		pip.view.show_battle(session.observe_battle(player, eid))


func _refresh_menu() -> void:
	_clear(_menu)
	for m: Dictionary in contexts.menu():
		var line := HBoxContainer.new()
		var go := Button.new()
		go.text = ("▶ " if m["focused"] else "") + "%s (%d commander%s)" % [battle_name(m["engagement"]), m["commanders"].size(),
			"" if m["commanders"].size() == 1 else "s"]
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.pressed.connect(contexts.focus_battle.bind(m["engagement"]))
		line.add_child(go)
		var pin := Button.new()
		pin.text = "Unpin" if m["pinned"] else "PiP"
		pin.disabled = m["focused"]
		pin.pressed.connect(contexts.toggle_pin.bind(m["engagement"]))
		line.add_child(pin)
		_menu.add_child(line)
	if contexts.focus != ViewContexts.OVERWORLD:
		var back := Button.new()
		back.text = "Exit to overworld (Esc)"
		back.pressed.connect(contexts.exit)
		_menu.add_child(back)


## A short, stable name for a battle while it lasts (its engagement slot).
static func battle_name(eid: int) -> String:
	return "Battle %d" % ((eid & 0xffffffff) + 1)


func _refresh_commanders() -> void:
	_clear(_cmds)
	for cmd: Dictionary in session.observe(player).get("commanders", []):
		if cmd["player"] != player:
			continue
		var b := Button.new()
		var tags := []
		if cmd["id"] == contexts.selected:
			tags.append("selected")
		if cmd["id"] == contexts.followed:
			tags.append("followed")
		if cmd["engagement"] >= 0:
			tags.append("in battle")
		b.text = "Commander %d%s" % [cmd["id"] & 0xffff, "" if tags.is_empty() else " (%s)" % ", ".join(tags)]
		b.pressed.connect(contexts.select_commander.bind(cmd["id"]))
		_cmds.add_child(b)


# --- input ---------------------------------------------------------------------

func _on_hex_clicked(p: int, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		contexts.deselect_all()
		return
	if p < 0:
		return
	for cmd: Dictionary in session.observe(player).get("commanders", []):
		if cmd["plot"] == p and cmd["player"] == player:
			contexts.select_commander(cmd["id"])
			return
	contexts.select_hex(p)


func _on_battle_clicked(button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		contexts.deselect_all()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_TAB:
			contexts.cycle(-1 if k.shift_pressed else 1)
		KEY_ESCAPE:
			contexts.exit()
		KEY_F:
			contexts.follow()
		KEY_BACKSPACE:
			contexts.deselect_all()
		KEY_SPACE:
			end_turn_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()


func _demo_end_turn() -> void:
	for i in 3:
		for p in session.players():
			session.ready(p)
		if session.clock.phase == PulseClock.Phase.PLANNING:
			break
	contexts.sync(session.observe(player))


## A movable picture-in-picture battle view: click to swap it in, drag to
## move it.
class _PipPanel extends Panel:
	signal chosen(engagement: int)
	signal moved(engagement: int, offset: Vector2)

	var engagement: int = -1
	var home: Vector2 = Vector2.ZERO
	var view: ContextView
	var _drag_from: Vector2 = Vector2.ZERO
	var _dragged: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("12151a")
		sb.border_color = Color("e6b450")
		sb.set_border_width_all(2)
		add_theme_stylebox_override("panel", sb)
		view = ContextView.new()
		view.compact = true
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.offset_left = 2
		view.offset_top = 2
		view.offset_right = -2
		view.offset_bottom = -2
		add_child(view)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.global_position
				_dragged = false
			elif _dragged:
				moved.emit(engagement, position - home)
			else:
				chosen.emit(engagement)
			accept_event()
			return
		var mm := event as InputEventMouseMotion
		if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if mm.global_position.distance_to(_drag_from) > 4.0:
				_dragged = true
			position += mm.relative
			accept_event()
