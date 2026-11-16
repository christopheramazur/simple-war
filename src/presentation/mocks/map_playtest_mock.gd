extends RefCounted
## Mock (sw-ll4.7): "Play this map" from the map editor. The Field map with
## an unsaved wall across the middle (one gap) and a pond, opened as a
## playtest battle against the utility profile. Nothing is saved. Render with
## `hx godot mock res://src/presentation/mocks/map_playtest_mock.gd`.

const FRAME := Vector2(1280, 720)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var screen := MainMenu.editor_screen()
	var panel: WarDataPanel = screen.find_child("WarData", true, false)
	panel.ready.connect(_play.bind(screen, panel), CONNECT_DEFERRED)
	root.add_child(screen)
	return root


static func _play(screen: Control, panel: WarDataPanel) -> void:
	var mp := panel.painter()
	mp.open_map("field_map")
	var c := mp.canvas
	var wall := c.features.find("wall")
	c.begin()
	c.rect(60, 0, 60, 30, wall, 0)
	c.rect(60, 42, 60, 79, wall, 0)
	c.rect(30, 55, 44, 66, c.features.find("water"), 0)
	MainMenu.play_map(screen, panel, "profile_utility")
