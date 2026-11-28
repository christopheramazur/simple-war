class_name GamepadCursor
extends Control
## A virtual mouse cursor on the gamepad (sw-wut, GDD 01 Vision: controls
## through GUIDE, drag-select on the stick). The right stick moves a cursor
## over the window; A presses and releases the left button where it stands,
## so holding A and moving drags (a box select, a squad drag) exactly as the
## mouse does; the right bumper is a right click (move or attack order).
##
## Input goes out as synthetic mouse events through Input.parse_input_event,
## so the views under the cursor (the battle view, the panels) handle it as
## they handle a mouse; they know nothing of the pad.
##
## The buttons live in their own mapping context, enabled only while the
## cursor is active (the stick moved within _IDLE_S seconds), so A keeps its
## menu meaning when the pad is not driving the cursor.

const SPEED := 900.0  ## px per second at full stick deflection
const _IDLE_S := 6.0  ## seconds without stick input before the buttons go back
const _RING := Color(1, 1, 1, 0.95)
const _SHADE := Color(0, 0, 0, 0.8)

var move_context := GUIDEMappingContext.new()
var button_context := GUIDEMappingContext.new()
## Right stick, as a 2D axis in -1..1 (deadzone applied).
var move_action: GUIDEAction
## A: the left button, held while pressed.
var click_action: GUIDEAction
## Right bumper: the right button, held while pressed.
var order_action: GUIDEAction

var _pos := Vector2.ZERO
var _active := false
var _idle := 0.0
var _left_down := false
var _right_down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 4096
	move_context.display_name = "Gamepad cursor"
	button_context.display_name = "Gamepad cursor buttons"
	move_action = _action(&"cursor_move", "Move cursor", GUIDEAction.GUIDEActionValueType.AXIS_2D)
	click_action = _action(&"cursor_click", "Click (hold to drag)", GUIDEAction.GUIDEActionValueType.BOOL)
	order_action = _action(&"cursor_order", "Right click (order)", GUIDEAction.GUIDEActionValueType.BOOL)
	var deadzone: Array[GUIDEModifier] = [GUIDEModifierDeadzone.new()]
	_map(move_context, move_action, GuideKeys.stick_pair(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y), deadzone)
	var none: Array[GUIDEModifier] = []
	_map(button_context, click_action, GuideKeys.pad(JOY_BUTTON_A), none)
	_map(button_context, order_action, GuideKeys.pad(JOY_BUTTON_RIGHT_SHOULDER), none)


func _ready() -> void:
	var guide := _guide()
	if guide != null:
		guide.enable_mapping_context(move_context)


func _exit_tree() -> void:
	_release_buttons()
	var guide := _guide()
	if guide == null:
		return
	if guide.is_mapping_context_enabled(move_context):
		guide.disable_mapping_context(move_context)
	if guide.is_mapping_context_enabled(button_context):
		guide.disable_mapping_context(button_context)


func _process(delta: float) -> void:
	var size_now := get_viewport().get_visible_rect().size
	if size != size_now:
		size = size_now
	var stick := move_action.value_axis_2d
	if stick != Vector2.ZERO:
		_idle = 0.0
		if not _active:
			_activate()
	var bounds := Rect2(Vector2.ZERO, size_now)
	var next := advance(_pos, stick, delta, bounds)
	if next != _pos:
		var rel := next - _pos
		_pos = next
		_send_motion(rel)
		queue_redraw()
	if _active:
		_set_left(click_action.value_bool)
		_set_right(order_action.value_bool)
		if not _left_down and not _right_down:
			_idle += delta
			if _idle >= _IDLE_S:
				_deactivate()


## The cursor's next position: `pos` moved by the stick (at most unit length,
## so diagonals are not faster) over `delta` seconds, kept inside `bounds`.
static func advance(pos: Vector2, stick: Vector2, delta: float, bounds: Rect2) -> Vector2:
	if not stick.is_finite():
		return pos
	var v := stick.limit_length(1.0) * SPEED * delta
	return (pos + v).clamp(bounds.position, bounds.end)


func _activate() -> void:
	_active = true
	_idle = 0.0
	var size_now := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()
	_pos = mouse if Rect2(Vector2.ZERO, size_now).has_point(mouse) else size_now * 0.5
	var guide := _guide()
	if guide != null and not guide.is_mapping_context_enabled(button_context):
		guide.enable_mapping_context(button_context)
	queue_redraw()


func _deactivate() -> void:
	_active = false
	var guide := _guide()
	if guide != null and guide.is_mapping_context_enabled(button_context):
		guide.disable_mapping_context(button_context)
	queue_redraw()


func _set_left(down: bool) -> void:
	if down != _left_down:
		_left_down = down
		_send_button(MOUSE_BUTTON_LEFT, down)


func _set_right(down: bool) -> void:
	if down != _right_down:
		_right_down = down
		_send_button(MOUSE_BUTTON_RIGHT, down)


func _release_buttons() -> void:
	_set_left(false)
	_set_right(false)


func _mask() -> int:
	var m := 0
	if _left_down:
		m |= MOUSE_BUTTON_MASK_LEFT
	if _right_down:
		m |= MOUSE_BUTTON_MASK_RIGHT
	return m


func _send_motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _pos
	ev.global_position = _pos
	ev.relative = rel
	ev.button_mask = _mask()
	Input.parse_input_event(ev)


func _send_button(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _pos
	ev.global_position = _pos
	ev.button_mask = _mask()
	Input.parse_input_event(ev)


func _draw() -> void:
	if not _active:
		return
	draw_arc(_pos, 12.0, 0.0, TAU, 32, _SHADE, 4.0)
	draw_arc(_pos, 12.0, 0.0, TAU, 32, _RING, 2.0)
	draw_circle(_pos, 2.0, _RING)


func _action(name: StringName, display: String, type: GUIDEAction.GUIDEActionValueType) -> GUIDEAction:
	var a := GUIDEAction.new()
	a.name = name
	a.display_name = display
	a.display_category = "Gamepad cursor"
	a.action_value_type = type
	a.is_remappable = true
	return a


func _map(ctx: GUIDEMappingContext, a: GUIDEAction, input: GUIDEInput, mods: Array[GUIDEModifier]) -> void:
	var im := GUIDEInputMapping.new()
	im.input = input
	im.modifiers = mods
	var trig: Array[GUIDETrigger] = [GUIDETriggerDown.new()]
	im.triggers = trig
	var ims: Array[GUIDEInputMapping] = [im]
	var m := GUIDEActionMapping.new()
	m.action = a
	m.input_mappings = ims
	var ms := ctx.mappings.duplicate()
	ms.append(m)
	ctx.mappings = ms


func _guide() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(^"GUIDE")
