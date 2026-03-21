extends RefCounted
## Builds a mapping context for battlefield: mouse, wheel, confirm keys.
## Used with the GUIDE autoload ([code]get_node("/root/GUIDE")[/code]).

const _GuideMappingContext := preload("res://addons/guide/guide_mapping_context.gd")
const _GuideAction := preload("res://addons/guide/guide_action.gd")
const _GuideActionMapping := preload("res://addons/guide/guide_action_mapping.gd")
const _GuideInputMapping := preload("res://addons/guide/guide_input_mapping.gd")
const _GuideInputMouseButton := preload("res://addons/guide/inputs/guide_input_mouse_button.gd")
const _GuideInputKey := preload("res://addons/guide/inputs/guide_input_key.gd")

var mapping_context: _GuideMappingContext

var primary_click: _GuideAction
var secondary_click: _GuideAction
var wheel_up: _GuideAction
var wheel_down: _GuideAction
var confirm: _GuideAction


func _init() -> void:
	primary_click = _make_bool_action(&"battlefield_primary_click")
	secondary_click = _make_bool_action(&"battlefield_secondary_click")
	wheel_up = _make_bool_action(&"battlefield_wheel_up")
	wheel_down = _make_bool_action(&"battlefield_wheel_down")
	confirm = _make_bool_action(&"battlefield_confirm")

	var left_btn: _GuideInputMouseButton = _GuideInputMouseButton.new()
	left_btn.button = MOUSE_BUTTON_LEFT
	var im_left: _GuideInputMapping = _GuideInputMapping.new()
	im_left.input = left_btn

	var right_btn: _GuideInputMouseButton = _GuideInputMouseButton.new()
	right_btn.button = MOUSE_BUTTON_RIGHT
	var im_right: _GuideInputMapping = _GuideInputMapping.new()
	im_right.input = right_btn

	var wu: _GuideInputMouseButton = _GuideInputMouseButton.new()
	wu.button = MOUSE_BUTTON_WHEEL_UP
	var im_wu: _GuideInputMapping = _GuideInputMapping.new()
	im_wu.input = wu

	var wd: _GuideInputMouseButton = _GuideInputMouseButton.new()
	wd.button = MOUSE_BUTTON_WHEEL_DOWN
	var im_wd: _GuideInputMapping = _GuideInputMapping.new()
	im_wd.input = wd

	var key_enter: _GuideInputKey = _GuideInputKey.new()
	key_enter.key = KEY_ENTER
	var im_ke: _GuideInputMapping = _GuideInputMapping.new()
	im_ke.input = key_enter

	var key_kp: _GuideInputKey = _GuideInputKey.new()
	key_kp.key = KEY_KP_ENTER
	var im_kp: _GuideInputMapping = _GuideInputMapping.new()
	im_kp.input = key_kp

	var maps: Array[_GuideInputMapping] = [im_left]
	var maps_r: Array[_GuideInputMapping] = [im_right]
	var maps_wu: Array[_GuideInputMapping] = [im_wu]
	var maps_wd: Array[_GuideInputMapping] = [im_wd]
	var maps_cf: Array[_GuideInputMapping] = [im_ke, im_kp]

	mapping_context = _GuideMappingContext.new()
	mapping_context.display_name = "Battlefield"
	mapping_context.mappings = [
		_action_mapping(primary_click, maps),
		_action_mapping(secondary_click, maps_r),
		_action_mapping(wheel_up, maps_wu),
		_action_mapping(wheel_down, maps_wd),
		_action_mapping(confirm, maps_cf),
	]


func _make_bool_action(action_name: StringName) -> _GuideAction:
	var a: _GuideAction = _GuideAction.new()
	a.name = action_name
	a.action_value_type = _GuideAction.GUIDEActionValueType.BOOL
	a.block_lower_priority_actions = false
	return a


func _action_mapping(action: _GuideAction, input_mappings: Array[_GuideInputMapping]) -> _GuideActionMapping:
	var am: _GuideActionMapping = _GuideActionMapping.new()
	am.action = action
	am.input_mappings = input_mappings
	return am
