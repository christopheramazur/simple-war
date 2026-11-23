extends GutTest
## The World maps tab (GDD 04 §4.9, sw-7ii): OverworldPainter over an
## OverworldCanvas, driven by hex presses as the view sends them. Saves run
## on a copy of the core package.

const CORE := "res://data/packages/core"
const COPY := "user://test_pkg_ow_painter"


func before_each() -> void:
	_copy(CORE, COPY)


func after_all() -> void:
	_remove(COPY)


func _copy(from: String, to: String) -> void:
	_remove(to)
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	for f in d.get_files():
		if not f.ends_with(".import"):
			DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for sub in d.get_directories():
		_copy(from.path_join(sub), to.path_join(sub))


func _remove(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _painter() -> OverworldPainter:
	var p := OverworldPainter.new()
	p.size = Vector2(900, 600)
	add_child_autofree(p)
	p.set_model(PackageEditor.open(COPY))
	return p


func _click(p: OverworldPainter, hex: Vector2i, erase: bool = false) -> void:
	p.press(hex, erase)
	p.release(hex)


func test_it_lists_and_opens_overworld_maps_and_saves_them_unchanged() -> void:
	var p := _painter()
	assert_true(p.map_ids().has("test_vale"))
	assert_false(p.map_ids().has("ow_field"), "battle scenarios are not overworld maps")
	assert_true(p.open_map("test_vale"))
	assert_eq([p.canvas.width, p.canvas.height], [16, 12])
	assert_true(p.feature_ids.has("hex_forest"))
	var before := p.model.templates.values_of("test_vale")
	assert_eq(p.save(), PackedStringArray())
	var after := p.model.templates.values_of("test_vale")
	assert_eq(after["starts"], before["starts"])
	assert_eq(after["elimination"], true)
	assert_false(p.canvas.dirty)


func test_ground_tools_paint_hexes_and_undo() -> void:
	var p := _painter()
	p.open_map("test_vale")
	var forest := p.feature_ids.find("hex_forest")
	var hills := p.canvas.features.find("hex_hills")
	p.set_feature(p.feature_ids.find("hex_hills"))
	p.set_tool(OverworldPainter.Tool.BRUSH)
	p.radius = 1
	_click(p, Vector2i(8, 5))
	assert_eq(p.canvas.ground_at(8, 5), hills)
	assert_eq(p.canvas.ground_at(9, 5), hills, "the radius takes in the neighbours")
	p.undo()
	assert_ne(p.canvas.ground_at(9, 5), hills)
	p.set_tool(OverworldPainter.Tool.RECT)
	p.press(Vector2i(0, 9), false)
	p.release(Vector2i(2, 10))
	assert_eq(p.canvas.ground_at(2, 10), hills)
	p.set_tool(OverworldPainter.Tool.BRUSH)
	_click(p, Vector2i(2, 10), true)
	assert_eq(p.canvas.ground_at(2, 10), -1, "the right button clears the painted feature")
	p.set_tool(OverworldPainter.Tool.PICK)
	_click(p, Vector2i(3, 2))
	assert_eq(p.feature, forest)


func test_place_and_start_tools_make_objects_with_owners() -> void:
	var p := _painter()
	p.open_map("test_vale")
	var n := p.canvas.objects.size()
	p.set_feature(p.feature_ids.find("hex_village"))
	p.set_owner_player(2)
	p.set_tool(OverworldPainter.Tool.PLACE)
	_click(p, Vector2i(5, 8))
	assert_eq(p.canvas.objects.size(), n + 1)
	var o := p.canvas.object_at(5, 8, "hex_village")
	assert_eq(p.canvas.objects[o]["owner"], 2)
	assert_eq(p.selected, {"kind": "object", "index": o})
	# Dragging the selected object moves it.
	p.press(Vector2i(5, 8), false)
	p.drag(Vector2i(6, 8))
	p.release(Vector2i(6, 8))
	assert_eq(p.canvas.object_at(5, 8, "hex_village"), -1)
	assert_true(p.canvas.object_at(6, 8, "hex_village") >= 0)
	_click(p, Vector2i(6, 8), true)
	assert_eq(p.canvas.objects.size(), n, "the right button removes it")
	var s := p.canvas.starts.size()
	p.set_owner_player(1)
	p.set_tool(OverworldPainter.Tool.START)
	_click(p, Vector2i(7, 7))
	assert_eq(p.canvas.starts.size(), s + 1)
	assert_eq(p.canvas.starts[s]["player"], 1)
	assert_true(p.commander_ids.has(p.canvas.starts[s]["commander"]))
	p.set_owner_player(2)
	p._apply_owner()
	assert_eq(p.canvas.starts[s]["player"], 2, "the owner list changes the selected start's player")
	p.remove_selected()
	assert_eq(p.canvas.starts.size(), s)
	assert_eq(p.save(), PackedStringArray())


func test_mirror_maps_paint_both_halves_and_ghost_objects() -> void:
	var p := _painter()
	p.open_map("test_vale")
	assert_true(p.set_map_value("mirror", true))
	assert_true(p.canvas.mirror)
	var hills := p.canvas.features.find("hex_hills")
	p.set_feature(p.feature_ids.find("hex_hills"))
	p.set_tool(OverworldPainter.Tool.BRUSH)
	_click(p, Vector2i(1, 1))
	var twin := p.canvas.partner(1, 1)
	assert_eq(twin, Vector2i(14, 10))
	assert_eq(p.canvas.ground_at(twin.x, twin.y), hills, "the partner hex is painted too")
	assert_true((p.canvas.ghosts()["starts"] as Array).size() > 0, "starts have ghosts on the other half")
	p.undo()
	assert_ne(p.canvas.ground_at(twin.x, twin.y), hills)
	p.redo()
	assert_eq(p.save(), PackedStringArray())
	assert_eq(p.model.templates.values_of("test_vale")["mirror"], true)


func test_map_settings_are_saved_and_undone() -> void:
	var p := _painter()
	p.open_map("test_vale")
	assert_true(p.set_map_value("elimination", false))
	assert_true(p.set_map_value("name", "Renamed vale"))
	p.undo()
	assert_eq(p.canvas.name, "Test vale")
	assert_eq(p.canvas.value("elimination"), false)
	assert_eq(p.save(), PackedStringArray())
	assert_eq(p.model.templates.values_of("test_vale")["elimination"], false)
	p.resize(16, 11)
	assert_false(p.set_map_value("mirror", true), "a mirror map needs an even height")


func test_a_new_map_joins_the_package_when_saved() -> void:
	var p := _painter()
	p.set_feature(p.feature_ids.find("hex_plains"))
	assert_true(p.new_map("painted_isle", 10, 8))
	assert_false(p.new_map("test_vale", 10, 8), "ids are unique")
	p.set_feature(p.feature_ids.find("hex_forest"))
	p.set_tool(OverworldPainter.Tool.FILL)
	_click(p, Vector2i(3, 3))
	p.set_feature(p.feature_ids.find("hex_village"))
	p.set_owner_player(1)
	p.set_tool(OverworldPainter.Tool.PLACE)
	_click(p, Vector2i(1, 1))
	assert_eq(p.save(), PackedStringArray())
	assert_eq(p.model.templates.kind_of("painted_isle"), "overworld_map")
	assert_true(p.map_ids().has("painted_isle"))
	var v := p.model.templates.values_of("painted_isle")
	assert_eq([v["width"], v["height"]], [10, 8])
	var places := (v["passes"] as Array).filter(func(q: Dictionary) -> bool: return q["op"] == "place")
	assert_eq(places, [{"op": "place", "feature": "hex_village", "col": 1, "row": 1, "owner": 1}])


func test_the_view_finds_the_hex_under_the_mouse() -> void:
	var p := _painter()
	p.open_map("test_vale")
	var v := p.view
	v.zoom = 20.0
	v.origin = Vector2(30, 30)
	for hex: Vector2i in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(15, 11), Vector2i(7, 6)]:
		assert_eq(v.hex_at(v.centre(hex.x, hex.y)), hex)
		assert_eq(v.hex_at(v.centre(hex.x, hex.y) + Vector2(5, -6)), hex, "near the centre is the same hex")


func test_the_panel_opens_an_overworld_map_in_the_world_tab() -> void:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	p.select("test_vale")
	assert_not_null(p.world_painter().canvas)
	assert_eq(p.world_painter().canvas.id, "test_vale")
	p.world_painter().set_map_value("elimination", false)
	assert_eq(p.world_painter().save(), PackedStringArray())
	assert_eq(p.model.templates.values_of("test_vale")["elimination"], false)
