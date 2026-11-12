extends RefCounted
## Mock (sw-ip8.2): the war room in two states on one contact sheet, fed by
## the demo OverworldSession: the overworld with the battles menu, and a
## focused battle with a second battle in a picture-in-picture view. Render
## with `hx godot mock res://src/presentation/mocks/war_room_mock.gd`.

const FRAME := Vector2(960, 600)
const GAP := 16.0


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y + GAP * 2)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 2:
		var holder := Control.new()
		holder.position = Vector2(GAP + i * (FRAME.x + GAP), GAP)
		holder.size = FRAME
		root.add_child(holder)
		var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
		w.demo_view = "" if i == 0 else "pip"
		holder.add_child(w)
	return root
