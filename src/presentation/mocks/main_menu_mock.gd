extends RefCounted
## Mock (sw-ip8.6): the main menu next to a skirmish against the Utility
## profile on the AI factory's map after six turns with no orders from the
## player. Render with `hx godot mock res://src/presentation/mocks/main_menu_mock.gd`.

const FRAME := Vector2(920, 560)
const GAP := 16.0


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y + GAP * 2)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var menu_holder := Control.new()
	menu_holder.position = Vector2(GAP, GAP)
	menu_holder.size = FRAME
	menu_holder.clip_contents = true
	root.add_child(menu_holder)
	menu_holder.add_child(load("res://src/presentation/main_menu/main_menu.tscn").instantiate())
	var room_holder := Control.new()
	room_holder.position = Vector2(GAP * 2 + FRAME.x, GAP)
	room_holder.size = FRAME
	room_holder.clip_contents = true
	root.add_child(room_holder)
	var w := MainMenu.skirmish_room("profile_utility", MainMenu.FACTORY_MAP, 3)
	w.ready.connect(func() -> void:
		for i in 6:
			w.end_turn_requested.emit())
	room_holder.add_child(w)
	return root
