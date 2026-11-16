extends RefCounted
## Mock (sw-ll4.19): the options screen over the main menu. Render with
## `hx godot mock res://src/presentation/mocks/options_mock.gd`.

const FRAME := Vector2(1280, 720)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var menu: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.ready.connect(func() -> void: OptionsScreen.open_over(menu), CONNECT_DEFERRED)
	return root
