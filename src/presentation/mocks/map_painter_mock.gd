extends RefCounted
## Mock (sw-ll4.6): the War Data screen's Maps tab with the Crossroads map
## open and some unsaved paint on it: a walled yard with a road through it,
## painted with the left-and-right mirror on. Nothing is saved. Render with
## `hx godot mock res://src/presentation/mocks/map_painter_mock.gd`.

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
	var mp: MapPainter = p._maps
	p._tabs.current_tab = mp.get_index()
	mp.open_map("crossroads_map")
	var c := mp.canvas
	c.mirror = MapCanvas.Mirror.LEFT_RIGHT
	mp._mirror.select(c.mirror)
	var wall := c.features.find("wall")
	c.begin()
	c.rect(15, 60, 35, 60, wall, 0)
	c.rect(15, 60, 15, 90, wall, 0)
	c.rect(15, 90, 35, 90, wall, 0)
	c.rect(35, 60, 35, 72, wall, 0)
	c.rect(35, 78, 35, 90, wall, 0)
	c.line(25, 52, 25, 99, c.features.find("road"), 3, 2)
	mp.set_feature(wall)
	mp.changed()
