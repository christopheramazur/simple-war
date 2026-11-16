extends GutTest
## The map painter (GDD 04 §4.9, O1Q6, sw-ll4.6): MapCanvas (the model) and
## the Maps tab (MapPainter). Saves run on a copy of the core package.

const CORE := "res://data/packages/core"
const COPY := "user://test_pkg_painter"


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


func _open(m: PackageEditor, id: String) -> MapCanvas:
	return MapCanvas.open(m.templates, JSON.parse_string(m.definition_text(id)))


## The canvas's cells as feature names and facings, to compare with what the
## game compiles.
func _seen(c: MapCanvas) -> Array:
	var comp := c.composite()
	var out := []
	for i in c.width * c.height:
		out.append([c.features[comp["feature"][i]], comp["facing"][i]])
	return out


func _compiled(t: TemplateTable, scenario: String) -> Array:
	var r := BattleRules.compile(t, scenario)
	assert_eq(r.errors, PackedStringArray())
	var out := []
	for i in r.width * r.height:
		out.append([r.feature_ids[r.terrain[i]], r.facing[i]])
	return out


func test_the_canvas_shows_what_the_game_compiles() -> void:
	var m := PackageEditor.open(COPY)
	var c := _open(m, "crossroads_map")
	assert_eq([c.width, c.height, c.features[c.base]], [200, 100, "open"])
	assert_eq(c.stamps.size(), 2, "stamps stay objects")
	assert_eq(c.notes.size(), 0)
	assert_eq(_seen(c), _compiled(m.templates, "duel_crossroads"))


func test_saving_an_untouched_map_changes_no_terrain() -> void:
	var m := PackageEditor.open(COPY)
	var before := _compiled(m.templates, "duel_crossroads")
	var c := _open(m, "crossroads_map")
	var text := c.definition_text()
	assert_string_contains(text, "{\"feature\": \"road\", \"x\": 0, \"y\": 48, \"w\": 200, \"h\": 4, \"facing\": \"e\"}")
	assert_string_contains(text, "{\"stamp\": \"ruin_block\", \"x\": 92, \"y\": 52, \"rotate\": 180}")
	assert_eq(m.replace("crossroads_map", text), PackedStringArray())
	assert_eq(_compiled(m.templates, "duel_crossroads"), before)
	assert_eq(_open(m, "crossroads_map").definition_text(), text, "saving again writes the same text")


func test_painted_cells_merge_into_rectangles_in_row_order() -> void:
	var m := PackageEditor.open(COPY)
	var c := MapCanvas.create(m.templates, "t_map", 20, 10, "open")
	var forest := c.features.find("forest")
	var road := c.features.find("road")
	c.begin()
	c.rect(2, 1, 6, 3, forest, 0)
	c.paint(7, 1, forest, 0)
	c.line(0, 8, 19, 8, road, 2)
	assert_eq(c.cells(), [
		{"feature": "forest", "x": 2, "y": 1, "w": 6},
		{"feature": "forest", "x": 2, "y": 2, "w": 5, "h": 2},
		{"feature": "road", "x": 0, "y": 8, "w": 20, "facing": "e"},
	] as Array[Dictionary])
	c.begin()
	c.rect(2, 1, 7, 3, c.base, 0)
	assert_eq(c.cells().size(), 1, "painting the base back removes the shapes")


func test_brush_size_fill_and_undo() -> void:
	var m := PackageEditor.open(COPY)
	var c := MapCanvas.create(m.templates, "t_map", 12, 12, "open")
	var wall := c.features.find("wall")
	var water := c.features.find("water")
	c.begin()
	c.paint(5, 5, wall, 0, 3)
	assert_eq(c.cells(), [{"feature": "wall", "x": 4, "y": 4, "w": 3, "h": 3}] as Array[Dictionary])
	# A ring of wall, then fill the inside: the fill stops at the wall.
	c.begin()
	c.rect(0, 0, 11, 11, wall, 0)
	c.rect(1, 1, 10, 10, c.base, 0)
	c.begin()
	c.fill(5, 5, water, 0)
	assert_eq(c.feat[0], wall)
	assert_eq(c.feat[5 * 12 + 5], water)
	assert_eq(c.cells().size(), 5, "four wall sides and the water")
	c.undo()
	assert_eq(c.feat[5 * 12 + 5], c.base)
	c.redo()
	assert_eq(c.feat[5 * 12 + 5], water)
	c.undo()
	c.undo()
	c.undo()
	assert_eq(c.cells().size(), 0)
	assert_false(c.can_undo())


func test_mirrors_paint_the_other_side_and_turn_facings() -> void:
	var m := PackageEditor.open(COPY)
	var c := MapCanvas.create(m.templates, "t_map", 10, 6, "open")
	var road := c.features.find("road")
	c.mirror = MapCanvas.Mirror.LEFT_RIGHT
	c.begin()
	c.paint(1, 2, road, 2)
	assert_eq([c.feat[2 * 10 + 8], c.face[2 * 10 + 8]], [road, 4], "east becomes west across the middle")
	c.mirror = MapCanvas.Mirror.TURN
	c.begin()
	c.paint(0, 0, road, 1)
	assert_eq([c.feat[5 * 10 + 9], c.face[5 * 10 + 9]], [road, 3])
	c.mirror = MapCanvas.Mirror.FOUR
	c.begin()
	c.paint(3, 1, road, 0)
	assert_eq([c.feat[1 * 10 + 6], c.feat[4 * 10 + 3], c.feat[4 * 10 + 6]], [road, road, road])


func test_stamps_and_resizing() -> void:
	var m := PackageEditor.open(COPY)
	var c := MapCanvas.create(m.templates, "t_map", 40, 30, "open")
	assert_ne(c.add_stamp("t_map", 0, 0, 0), "", "not itself")
	c.begin()
	assert_eq(c.add_stamp("ruin_block", 10, 5, 90), "")
	assert_eq(c.stamp_rect(0), Rect2i(10, 5, 8, 16), "a quarter turn swaps its sides")
	assert_eq(c.stamp_at(17, 20), 0)
	assert_eq(c.stamp_at(18, 20), -1)
	assert_eq(c.features[c.composite()["feature"][20 * 40 + 17]], "ruins")
	assert_eq(c.feat[20 * 40 + 17], c.base, "the painted layer under it is untouched")
	c.begin()
	c.paint(39, 29, c.features.find("forest"), 0)
	c.begin()
	c.resize(30, 20)
	assert_eq(c.cells(), [{"stamp": "ruin_block", "x": 10, "y": 5, "rotate": 90}] as Array[Dictionary])
	c.undo()
	assert_eq([c.width, c.cells().size()], [40, 2])


func test_the_maps_tab_paints_and_saves_a_new_map() -> void:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	var mp: MapPainter = p._maps
	assert_true(mp.open_map("field_map"))
	assert_eq(mp.canvas.width, 120)
	assert_true(mp.new_map("test_yard", 30, 20, "open"))
	mp.set_feature(mp.feature_ids.find("wall"))
	mp.set_tool(MapPainter.Tool.RECT)
	mp.view.press(Vector2i(5, 5), false)
	mp.view.release(Vector2i(14, 5))
	mp.set_tool(MapPainter.Tool.BRUSH)
	mp.set_facing(2)
	mp.set_feature(mp.feature_ids.find("road"))
	mp.view.press(Vector2i(0, 10), false)
	mp.view.drag(Vector2i(29, 10))
	mp.view.release(Vector2i(29, 10))
	# The right button paints the base back.
	mp.view.press(Vector2i(14, 5), true)
	mp.view.release(Vector2i(14, 5))
	assert_false(mp.open_map("field_map"), "unsaved changes are not dropped")
	assert_eq(mp.save(), PackedStringArray())
	assert_false(mp.canvas.dirty)
	assert_eq(p.model.templates.values_of("test_yard")["cells"].size(), 2)
	var text := FileAccess.get_file_as_string(COPY.path_join(p.model.file_of("test_yard")))
	assert_string_contains(text, "\t\t\t\t{\"feature\": \"wall\", \"x\": 5, \"y\": 5, \"w\": 9},\n\t\t\t\t{\"feature\": \"road\", \"x\": 0, \"y\": 10, \"w\": 30, \"facing\": \"e\"}\n")
	assert_eq(JSON.parse_string(text) is Dictionary, true, "the file is still JSON")
	assert_true(mp.open_map("field_map"))


func test_a_map_that_breaks_the_package_is_not_saved() -> void:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	var mp: MapPainter = p._maps
	mp.open_map("ruin_block")
	mp.set_tool(MapPainter.Tool.STAMP)
	mp.stamp_id = "crossroads_map"
	mp.view.press(Vector2i(0, 0), false)
	var errs := mp.save()
	assert_gt(errs.size(), 0, "crossroads stamps ruin_block, so this is a loop")
	assert_true(mp.canvas.dirty)
	assert_eq((PackageEditor.open(COPY).templates.values_of("ruin_block")["cells"] as Array).size(), 1)
