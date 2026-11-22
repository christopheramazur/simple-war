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
	for input: GUIDEInput in inputs:
		var im := GUIDEInputMapping.new()
		im.input = input
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
	keys[name] = inputs
	return a


static func key(k: Key, ctrl: bool = false, shift: bool = false, extra_ok: bool = false) -> GUIDEInputKey:
	var i := GUIDEInputKey.new()
	i.key = k
	i.control = ctrl
	i.shift = shift
	i.allow_additional_modifiers = extra_ok
	return i


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
