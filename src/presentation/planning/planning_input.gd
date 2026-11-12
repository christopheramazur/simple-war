class_name PlanningInput
extends Node
## Keyboard and button commands for planning, through GUIDE (GDD 01 Input
## and UI, R1Q4): every action is a remappable GUIDEAction in one mapping
## context, so input methods and mappings can all be rebound. It turns
## triggered actions into `command(name, arg)` for its owner; pointer work
## (click, box select, right-click orders) stays with the view that knows
## the positions.
##
## Commands: hold, attack_move (arms the next right click), fall_back,
## withdraw, run, recall_group / assign_group / add_group (arg 0-9),
## recall_bookmark / set_bookmark (arg 1-4), abilities (opens the menu).

signal command(name: StringName, arg: int)

const _KEYS: Array = [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const _BOOKMARK_KEYS: Array = [KEY_F1, KEY_F2, KEY_F3, KEY_F4]

var context: GUIDEMappingContext
## Action name -> GUIDEAction (for remapping UIs and tests).
var actions: Dictionary = {}


func _init() -> void:
	context = GUIDEMappingContext.new()
	context.display_name = "Planning"
	_bind(&"hold", "Hold", 0, [_key(KEY_H)])
	_bind(&"attack_move", "Attack-move", 0, [_key(KEY_A)])
	_bind(&"fall_back", "Fall back", 0, [_key(KEY_B)])
	_bind(&"withdraw", "Withdraw", 0, [_key(KEY_W, false, true)])
	_bind(&"run", "Run", 0, [_key(KEY_R)])
	_bind(&"abilities", "Ability menu", 0, [_key(KEY_Q)])
	for n in 10:
		_bind(StringName("recall_group_%d" % n), "Recall group %d" % n, n, [_key(_KEYS[n])])
		_bind(StringName("assign_group_%d" % n), "Assign group %d" % n, n, [_key(_KEYS[n], true)])
		_bind(StringName("add_group_%d" % n), "Add to group %d" % n, n, [_key(_KEYS[n], false, true)])
	for i in _BOOKMARK_KEYS.size():
		_bind(StringName("recall_bookmark_%d" % (i + 1)), "Camera bookmark %d" % (i + 1), i + 1, [_key(_BOOKMARK_KEYS[i])])
		_bind(StringName("set_bookmark_%d" % (i + 1)), "Set camera bookmark %d" % (i + 1), i + 1, [_key(_BOOKMARK_KEYS[i], true)])


func _ready() -> void:
	var guide := _guide()
	if guide != null:
		guide.enable_mapping_context(context)


func _exit_tree() -> void:
	var guide := _guide()
	if guide != null and guide.is_mapping_context_enabled(context):
		guide.disable_mapping_context(context)


## The command an action name stands for: "assign_group_3" -> assign_group.
static func command_of(action: StringName) -> StringName:
	var s := String(action)
	for prefix in ["recall_group", "assign_group", "add_group", "recall_bookmark", "set_bookmark"]:
		if s.begins_with(prefix + "_"):
			return StringName(prefix)
	return action


func _bind(name: StringName, display: String, arg: int, inputs: Array) -> void:
	var a := GUIDEAction.new()
	a.name = name
	a.display_name = display
	a.display_category = "Planning"
	a.is_remappable = true
	var m := GUIDEActionMapping.new()
	m.action = a
	var ims: Array[GUIDEInputMapping] = []
	for input: GUIDEInput in inputs:
		var im := GUIDEInputMapping.new()
		im.input = input
		var trig: Array[GUIDETrigger] = [GUIDETriggerPressed.new()]
		im.triggers = trig
		ims.append(im)
	m.input_mappings = ims
	var ms := context.mappings.duplicate()
	ms.append(m)
	context.mappings = ms
	actions[name] = a
	var cmd := command_of(name)
	a.triggered.connect(func() -> void: command.emit(cmd, arg))


static func _key(k: Key, ctrl: bool = false, shift: bool = false) -> GUIDEInputKey:
	var i := GUIDEInputKey.new()
	i.key = k
	i.control = ctrl
	i.shift = shift
	i.allow_additional_modifiers = false
	return i


func _guide() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(^"GUIDE")
