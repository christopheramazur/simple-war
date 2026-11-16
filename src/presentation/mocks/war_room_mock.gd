extends RefCounted
## Mock (sw-ip8.2, sw-ip8.3, sw-ll4.19): the war room in four states on one sheet, fed by
## the demo OverworldSession: the overworld with a commander selected (its
## reach lit) and the battles menu, a
## focused battle with a second battle in a picture-in-picture view, and
## planning (sw-ip8.3): a selection with a drafted move into a new line,
## its intent ghosts and the order and ability panel; and a battle turn
## halfway through its playback. Render
## with `hx godot mock res://src/presentation/mocks/war_room_mock.gd`.

const FRAME := Vector2(1230, 680)
const GAP := 16.0


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y * 2 + GAP * 3)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 4:
		var holder := Control.new()
		holder.position = Vector2(GAP + (i % 2) * (FRAME.x + GAP), GAP + (i / 2) * (FRAME.y + GAP))
		holder.size = FRAME
		root.add_child(holder)
		var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
		w.demo_view = ["move", "pip", "plan", "play"][i]
		holder.add_child(w)
	return root
