extends RefCounted
## Mock (sw-ll4.7): the Maps tab with the Crossroads map and its scenario
## open, the Objects tool on and player 1's deployment area selected.
## Nothing is saved. Render with
## `hx godot mock res://src/presentation/mocks/map_objects_mock.gd`.

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
	p.ready.connect(_edit.bind(p))
	root.add_child(p)
	return root


static func _edit(p: WarDataPanel) -> void:
	var mp := p.painter()
	p.show_maps()
	mp.open_map("crossroads_map")
	mp.set_tool(MapPainter.Tool.OBJECT)
	mp.scenario.begin()
	mp.scenario.move_zone(1, 100, 62)
	mp.select_object({"kind": "side", "index": 0})
