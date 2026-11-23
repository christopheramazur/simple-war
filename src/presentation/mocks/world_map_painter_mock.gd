extends RefCounted
## Mock (sw-7ii): the War Data screen's World maps tab with the test vale
## open as a mirror map, a village of player 1 selected and the other half's
## objects and starts drawn as ghosts. Nothing is saved. Render with
## `hx godot mock res://src/presentation/mocks/world_map_painter_mock.gd`.

const FRAME := Vector2(1280, 720)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var bg := ColorRect.new()
	bg.color = Color("1b1f26")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var p := WarDataPanel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.ready.connect(_paint.bind(p))
	root.add_child(p)
	return root


static func _paint(p: WarDataPanel) -> void:
	var wp := p.world_painter()
	p._tabs.current_tab = wp.get_index()
	wp.open_map("test_vale")
	wp.set_map_value("mirror", true)
	wp.set_feature(wp.feature_ids.find("hex_forest"))
	wp.press(Vector2i(4, 9), false)
	wp.release(Vector2i(4, 9))
	wp.set_tool(OverworldPainter.Tool.PLACE)
	wp.press(Vector2i(1, 6), false)
	wp.release(Vector2i(1, 6))
	wp.view.hover = Vector2i(9, 3)
	wp.changed()
