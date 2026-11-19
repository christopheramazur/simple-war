class_name UiWindow
extends Control
## The base of every popup, overlay and floating card (sw-ijp.2). A window
## says what it is (its layer, whether it takes the keyboard, which view
## contexts it belongs to); the screen's UiRoot decides where it goes,
## stacks it, closes it on Esc and gives focus back. Windows hold no game
## state: they show what they are given and emit what the player chose.

signal closed

enum Layer { HUD, BLOCKER, MODAL }

## A name the root can find it by ("options", "help"); "" for none.
var id: StringName = &""
var layer: Layer = Layer.MODAL
## While it is the top window: takes focus, and keys don't reach the
## screen beneath it.
var captures_keys: bool = true
var esc_closes: bool = true
## The view contexts it shows in (UiRoot.context); empty for all.
var contexts: PackedStringArray = []
## Whether its owner wants it shown; the context decides the rest.
var wanted: bool = true: set = set_wanted
## What gets focus when it opens; null for its first focusable control.
var focus_target: Control
var root: UiRoot


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_wanted(on: bool) -> void:
	wanted = on
	gate()


## Shows it when wanted and in one of its contexts.
func gate() -> void:
	visible = wanted and (contexts.is_empty() or root == null or contexts.has(String(root.context)))


func close() -> void:
	if is_queued_for_deletion():
		return
	if root != null:
		root.forget(self)
	closed.emit()
	queue_free()


## The usual modal body: the screen shaded, a centred panel `width` wide,
## and the column to fill.
func dialog(width: float) -> VBoxContainer:
	add_child(UiTheme.backdrop("ScreenShadePanel"))
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.theme_type_variation = &"ModalPanel"
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.theme_type_variation = &"ModalGap"
	panel.add_child(col)
	return col
