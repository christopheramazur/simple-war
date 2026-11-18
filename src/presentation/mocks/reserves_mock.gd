extends RefCounted
## Mock: a battle with a reserve ready to send (sw-dek). Render with
## `hx godot mock res://src/presentation/mocks/reserves_mock.gd`.

const FRAME := Vector2(1280, 720)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var holder := Control.new()
	holder.size = FRAME
	holder.clip_contents = true
	root.add_child(holder)
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.record_match = false
	holder.add_child(w)
	w.ready.connect(func() -> void: w.contexts.tab_in())
	return root
