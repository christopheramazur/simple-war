class_name PipPanel
extends Panel
## A movable picture-in-picture battle view: click to swap it in, drag to
## move it.
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
