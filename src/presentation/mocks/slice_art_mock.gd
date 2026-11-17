extends RefCounted
## Mock: the vertical-slice art (sw-kys.3). Left: a skirmish overworld with a
## commander selected (hex tiles, feature icons, commander portraits). Right:
## the demo battle (textured ground, unit sprites). Render with
## `hx godot mock res://src/presentation/mocks/slice_art_mock.gd`.

const FRAME := Vector2(960, 600)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + 48, FRAME.y + 32)
	var bg := ColorRect.new()
	bg.color = Color("101216")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 2:
		var holder := Control.new()
		holder.position = Vector2(16 + i * (FRAME.x + 16), 16)
		holder.size = FRAME
		holder.clip_contents = true
		root.add_child(holder)
		var w: WarRoom
		if i == 0:
			w = MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
			w.demo_view = "move"
		else:
			w = load("res://src/presentation/war_room/war_room.tscn").instantiate()
			w.demo_view = "plan"
		w.record_match = false
		holder.add_child(w)
	return root
