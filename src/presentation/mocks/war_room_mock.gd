extends RefCounted
## Mock (sw-ip8.2, sw-ip8.3): the war room in three states on one sheet, fed by
## the demo OverworldSession: the overworld with the battles menu, a
## focused battle with a second battle in a picture-in-picture view, and
## planning (sw-ip8.3): a selection with a drafted move into a new line,
## its intent ghosts and the order and ability panel. Render
## with `hx godot mock res://src/presentation/mocks/war_room_mock.gd`.

const FRAME := Vector2(920, 560)
const GAP := 16.0


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y * 2 + GAP * 3)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 3:
		var holder := Control.new()
		holder.position = Vector2(GAP + (i % 2) * (FRAME.x + GAP), GAP + (i / 2) * (FRAME.y + GAP))
		holder.size = FRAME
		root.add_child(holder)
		var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
		w.demo_view = ["", "pip", "plan"][i]
		holder.add_child(w)
	return root
