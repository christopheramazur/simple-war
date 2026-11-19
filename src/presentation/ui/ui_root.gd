class_name UiRoot
extends Control
## The one owner of a screen's windows (sw-ijp.2): it puts each UiWindow on
## its layer (HUD under the playback blocker under modals), knows which are
## open, closes the top one on Esc, keeps keys from reaching the screen
## under a modal, hands focus to a new modal and back when it closes, and
## shows each window only in its view contexts. A screen makes one with
## `UiRoot.of(self)` as its last child, so it draws and hears keys first.

signal opened(window: UiWindow)
signal window_closed(window: UiWindow)

const NODE_NAME := &"UiRoot"

## The screen's current view context ("overworld", "battle", "playback").
var context: StringName = &"": set = set_context
var _layers: Array[Control] = []
var _open: Array[UiWindow] = []
var _focus_before: Dictionary = {}


func _init() -> void:
	name = NODE_NAME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for layer_name: String in UiWindow.Layer.keys():
		var l := Control.new()
		l.name = layer_name.capitalize()
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_layers.append(l)


## The root that serves `node`: the nearest one beside it or above it, else
## a new one added to `node` (a screen run on its own, or a test).
static func of(node: Node) -> UiRoot:
	var n := node
	while n != null:
		var found := n.get_node_or_null(NodePath(NODE_NAME)) as UiRoot
		if found != null:
			return found
		if n is UiRoot:
			return n
		n = n.get_parent()
	var r := UiRoot.new()
	node.add_child(r)
	return r


## Opens a window on its layer, or inside `host` (a card that floats over
## one region) while still owned here.
func open(w: UiWindow, host: Control = null) -> UiWindow:
	w.root = self
	_open.append(w)
	if not w.tree_exiting.is_connected(forget):
		w.tree_exiting.connect(forget.bind(w), CONNECT_ONE_SHOT)
	(host if host != null else _layers[w.layer]).add_child(w)
	w.gate()
	if w.captures_keys and w.layer == UiWindow.Layer.MODAL:
		var vp := get_viewport()
		_focus_before[w] = vp.gui_get_focus_owner() if vp != null else null
		_focus_first.call_deferred(w)
	opened.emit(w)
	return w


## Closes the window with this id if it is open, else opens `make`'s.
func toggle(window_id: StringName, make: Callable) -> UiWindow:
	var w := find(window_id)
	if w != null:
		w.close()
		return null
	return open(make.call())


func find(window_id: StringName) -> UiWindow:
	for w in _open:
		if w.id == window_id and not w.is_queued_for_deletion():
			return w
	return null


## The open windows, oldest first.
func windows() -> Array[UiWindow]:
	return _open.filter(func(w: UiWindow) -> bool: return not w.is_queued_for_deletion())


## The topmost shown modal, or null.
func top() -> UiWindow:
	for i in range(_open.size() - 1, -1, -1):
		var w := _open[i]
		if w.layer == UiWindow.Layer.MODAL and w.visible and not w.is_queued_for_deletion():
			return w
	return null


func set_context(c: StringName) -> void:
	context = c
	for w in _open:
		w.gate()


## Drops a closed window and gives focus back to what had it.
func forget(w: UiWindow) -> void:
	if not _open.has(w):
		return
	_open.erase(w)
	var back: Variant = _focus_before.get(w)
	_focus_before.erase(w)
	if back is Control and is_instance_valid(back) and (back as Control).is_visible_in_tree():
		(back as Control).grab_focus()
	window_closed.emit(w)


func _focus_first(w: Variant) -> void:  # untyped: it may be freed by now
	if not is_instance_valid(w) or not (w as UiWindow).is_inside_tree():
		return
	var b: Control = (w as UiWindow).focus_target
	if b == null:
		b = _first_focusable(w as UiWindow)
	if b != null:
		b.grab_focus()


static func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).is_visible_in_tree():
			return c
		var deeper := _first_focusable(c)
		if deeper != null:
			return deeper
	return null


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null:
		return
	var w := top()
	if w == null:
		return
	if k.pressed and not k.echo and k.keycode == KEY_ESCAPE and w.esc_closes:
		w.close()
		get_viewport().set_input_as_handled()
	elif w.captures_keys:
		get_viewport().set_input_as_handled()
