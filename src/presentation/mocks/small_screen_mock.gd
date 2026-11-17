extends RefCounted
## Mock: the war room and the main menu in a small logical screen (853 x
## 480: a 1080p window at 150% UI scale), side by side. Render with
## `hx godot mock res://src/presentation/mocks/small_screen_mock.gd`.

const FRAME := Vector2(853, 480)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + 48, FRAME.y + 32)
	var bg := ColorRect.new()
	bg.color = Color("400000")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 2:
		var holder := Control.new()
		holder.position = Vector2(16 + i * (FRAME.x + 16), 16)
		holder.size = FRAME
		holder.clip_contents = true
		root.add_child(holder)
		if i == 0:
			var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
			w.record_match = false
			w.demo_view = "move"
			holder.add_child(w)
		else:
			holder.add_child(load("res://src/presentation/main_menu/main_menu.tscn").instantiate())
	return root
