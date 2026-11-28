class_name GuideKeys
extends RefCounted
## A code-built GUIDE mapping context (the project pattern, see
## PlanningInput): remappable actions, each with default keys, plus enable
## and disable tied to a node's lifecycle, and display text for help screens.
## `actions` maps name -> GUIDEAction (for remap UIs and tests); `keys` maps
## name -> the default GUIDEInputKey list.

const DOWN := 1
const PRESSED := 0
const PULSE := 2

var context := GUIDEMappingContext.new()
var actions: Dictionary = {}
var keys: Dictionary = {}
## name -> the default gamepad inputs (joy buttons and stick axes), kept apart
## from `keys` so keyboard help text never lists them (sw-dqq).
var pads: Dictionary = {}
var category: String = ""


func _init(display: String) -> void:
	context.display_name = display
	category = display


## Adds an action fired by any of `inputs` (GUIDEInputKey list). `kind` is
## PRESSED (once per press), DOWN (held) or PULSE (once, then repeating
## while held, like key repeat).
func bind(name: StringName, display: String, inputs: Array, kind: int = PRESSED) -> GUIDEAction:
	var a := GUIDEAction.new()
	a.name = name
	a.display_name = display
	a.display_category = category
	a.is_remappable = true
	var m := GUIDEActionMapping.new()
	m.action = a
	var ims: Array[GUIDEInputMapping] = []
	var key_inputs: Array = []
	var pad_inputs: Array = []
	for input: GUIDEInput in inputs:
		if input is GUIDEInputKey:
			key_inputs.append(input)
		else:
			pad_inputs.append(input)
		var im := GUIDEInputMapping.new()
		im.input = input
		if input.has_meta(&"limit"):
			var lim := GUIDEModifierPositiveNegative.new()
			lim.range = input.get_meta(&"limit")
			var mods: Array[GUIDEModifier] = [lim]
			im.modifiers = mods
		var trig: Array[GUIDETrigger] = []
		match kind:
			DOWN:
				trig.append(GUIDETriggerDown.new())
			PULSE:
				var p := GUIDETriggerPulse.new()
				p.initial_delay = 0.4
				p.pulse_interval = 0.06
				trig.append(p)
			_:
				trig.append(GUIDETriggerPressed.new())
		im.triggers = trig
		ims.append(im)
	m.input_mappings = ims
	var ms := context.mappings.duplicate()
	ms.append(m)
	context.mappings = ms
	actions[name] = a
	keys[name] = key_inputs
	pads[name] = pad_inputs
	return a


static func key(k: Key, ctrl: bool = false, shift: bool = false, extra_ok: bool = false) -> GUIDEInputKey:
	var i := GUIDEInputKey.new()
	i.key = k
	i.control = ctrl
	i.shift = shift
	i.allow_additional_modifiers = extra_ok
	return i


## A gamepad button input (any pad). Names in help stay device-neutral.
static func pad(b: JoyButton) -> GUIDEInputJoyButton:
	var i := GUIDEInputJoyButton.new()
	i.button = b
	return i


## One direction of a stick or trigger axis (`positive`: toward +1, i.e.
## right / down / pulled). GUIDE triggers test the absolute value, so the
## opposite direction is clipped away by a positive/negative modifier.
static func stick(axis: JoyAxis, positive: bool) -> GUIDEInputJoyAxis1D:
	var i := GUIDEInputJoyAxis1D.new()
	i.axis = axis
	i.set_meta(&"limit", GUIDEModifierPositiveNegative.LimitRange.POSITIVE if positive else GUIDEModifierPositiveNegative.LimitRange.NEGATIVE)
	return i


## Both axes of a stick as one 2D input (a cursor or a move vector).
static func stick_pair(x: JoyAxis, y: JoyAxis) -> GUIDEInputJoyAxis2D:
	var i := GUIDEInputJoyAxis2D.new()
	i.x = x
	i.y = y
	return i


## Device-neutral name of a gamepad input: "Dpad left", "Left stick left".
static func pad_text(i: GUIDEInput) -> String:
	if i is GUIDEInputJoyButton:
		return _BUTTON_NAMES.get((i as GUIDEInputJoyButton).button, "Button %d" % (i as GUIDEInputJoyButton).button)
	if i is GUIDEInputJoyAxis1D:
		var a := (i as GUIDEInputJoyAxis1D).axis
		var pos: bool = i.get_meta(&"limit", 1) == GUIDEModifierPositiveNegative.LimitRange.POSITIVE
		match a:
			JOY_AXIS_LEFT_X:
				return "Left stick " + ("right" if pos else "left")
			JOY_AXIS_LEFT_Y:
				return "Left stick " + ("down" if pos else "up")
			JOY_AXIS_RIGHT_X:
				return "Right stick " + ("right" if pos else "left")
			JOY_AXIS_RIGHT_Y:
				return "Right stick " + ("down" if pos else "up")
			JOY_AXIS_TRIGGER_LEFT:
				return "Left trigger"
			JOY_AXIS_TRIGGER_RIGHT:
				return "Right trigger"
	return "pad input"


const _BUTTON_NAMES := {
	JOY_BUTTON_A: "South button", JOY_BUTTON_B: "East button", JOY_BUTTON_X: "West button",
	JOY_BUTTON_Y: "North button", JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_LEFT_SHOULDER: "Left bumper", JOY_BUTTON_RIGHT_SHOULDER: "Right bumper",
	JOY_BUTTON_LEFT_STICK: "Left stick click", JOY_BUTTON_RIGHT_STICK: "Right stick click",
	JOY_BUTTON_DPAD_UP: "Dpad up", JOY_BUTTON_DPAD_DOWN: "Dpad down",
	JOY_BUTTON_DPAD_LEFT: "Dpad left", JOY_BUTTON_DPAD_RIGHT: "Dpad right",
	JOY_BUTTON_MISC1: "Share",
}


## The gamepad inputs of an action as help text: "Dpad left / Left stick left".
func pad_text_of(name: StringName, joiner: String = " / ") -> String:
	var parts: PackedStringArray = []
	for i: GUIDEInput in pads.get(name, []):
		parts.append(pad_text(i))
	return joiner.join(parts)


## "Ctrl+Shift+W" for one key input.
static func key_text(i: GUIDEInputKey) -> String:
	var s := ""
	if i.control:
		s += "Ctrl+"
	if i.shift:
		s += "Shift+"
	if i.alt:
		s += "Alt+"
	return s + OS.get_keycode_string(i.key)


## The keys of an action as help text: "+ / Num +".
func text_of(name: StringName, joiner: String = " / ") -> String:
	var parts: PackedStringArray = []
	for i: GUIDEInputKey in keys.get(name, []):
		parts.append(key_text(i))
	return joiner.join(parts)


func enable(node: Node) -> void:
	var g := _guide(node)
	if g != null and not g.is_mapping_context_enabled(context):
		g.enable_mapping_context(context)


func disable(node: Node) -> void:
	var g := _guide(node)
	if g != null and g.is_mapping_context_enabled(context):
		g.disable_mapping_context(context)


## Runs `fn` whenever the action fires.
func on(name: StringName, fn: Callable) -> void:
	(actions[name] as GUIDEAction).triggered.connect(fn)


static func _guide(node: Node) -> Node:
	if not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null(^"GUIDE")
