extends GutTest
## The overworld map painter's model (GDD 04 §4.9, sw-96x): OverworldCanvas
## and the wall shapes ConnectShape draws from neighbours. Saves run on a
## copy of the core package.

const CORE := "res://data/packages/core"
const COPY := "user://test_pkg_ow_canvas"


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


func _open(m: PackageEditor, id: String) -> OverworldCanvas:
	return OverworldCanvas.open(m.templates, JSON.parse_string(m.definition_text(id)))


func test_a_map_opens_and_saves_back_to_the_same_game() -> void:
	var m := PackageEditor.open(COPY)
	var c := _open(m, "test_vale")
	assert_eq([c.width, c.height, c.fills], [16, 12, PackedStringArray(["hex_plains"])])
	assert_eq(c.features[c.ground_at(3, 2)], "hex_forest")
	assert_eq(c.features[c.ground_at(0, 6)], "hex_road")
	var v := c.object_at(1, 6)
	assert_eq([c.objects[v]["feature"], c.objects[v]["owner"]], ["hex_village", 1])
	assert_eq(c.starts.size(), 4)
	assert_true(c.notes.size() > 0, "the scatter is kept and the editor says so")
	var before := m.templates.values_of("test_vale")
	assert_eq(m.replace("test_vale", c.definition_text()), PackedStringArray())
	var after := m.templates.values_of("test_vale")
	assert_eq(after["starts"], before["starts"])
	assert_eq(after["elimination"], true, "what it does not edit is kept")
	assert_eq(after["battle_scenario"], before["battle_scenario"])
	# The same hexes hold the same features once generated.
	var again := _open(m, "test_vale")
	for row in 12:
		for col in 16:
			assert_eq(again.features_at(col, row).size() > 0, true)
			assert_eq(again.ground_at(col, row), c.ground_at(col, row), "ground %d,%d" % [col, row])
	assert_eq(again.objects.size(), c.objects.size())
	var scatters := 0
	for p: Dictionary in after["passes"]:
		scatters += 1 if p["op"] == "scatter" else 0
	assert_eq(scatters, 1)


func test_painting_merges_into_rectangles_and_undoes() -> void:
	var m := PackageEditor.open(COPY)
	var c := OverworldCanvas.create(m.templates, "t_ow", 6, 4, "hex_plains")
	var forest := c.features.find("hex_forest")
	c.begin()
	c.rect(1, 0, 3, 2, forest)
	c.begin()
	c.paint(5, 3, forest)
	assert_eq(c.passes(), [
		{"op": "fill", "feature": "hex_plains"},
		{"op": "rect", "feature": "hex_forest", "col": 1, "row": 0, "w": 3, "h": 3},
		{"op": "rect", "feature": "hex_forest", "col": 5, "row": 3, "w": 1, "h": 1},
	])
	c.undo()
	assert_eq(c.ground_at(5, 3), -1)
	c.redo()
	assert_eq(c.ground_at(5, 3), forest)
	c.begin()
	c.fill(1, 0, -1)
	assert_eq(c.ground_at(2, 1), -1)
	assert_eq(c.ground_at(5, 3), forest, "fill stays inside the joined hexes")


func test_a_line_and_a_brush_use_hexes() -> void:
	var m := PackageEditor.open(COPY)
	var c := OverworldCanvas.create(m.templates, "t_ow", 8, 6, "hex_plains")
	var road := c.features.find("hex_road")
	c.begin()
	c.line(0, 3, 7, 3, road)
	for col in 8:
		assert_eq(c.ground_at(col, 3), road)
	c.begin()
	c.paint(4, 1, c.features.find("hex_hills"), 1)
	var painted := 0
	for i in c.ground:
		painted += 1 if i == c.features.find("hex_hills") else 0
	assert_eq(painted, 7, "a brush of radius 1 is a hex and its six neighbours")


func test_objects_have_owners_and_mirror_ghosts() -> void:
	var m := PackageEditor.open(COPY)
	var c := OverworldCanvas.create(m.templates, "t_ow", 10, 8, "hex_plains")
	c.mirror = true
	assert_eq(c.place("hex_village", 1, 2, 1), "")
	assert_eq(c.place("hex_nowhere", 1, 2, 1), "unknown feature 'hex_nowhere'")
	assert_eq(c.place("hex_village", 99, 2, 1), "off the map")
	assert_eq(c.place("hex_village", 1, 2, 2), "")
	assert_eq(c.objects.size(), 1, "placing again changes the owner")
	c.set_owner(0, 1)
	assert_eq(c.add_start(1, "field_commander", 2, 2), "")
	var g := c.ghosts()
	assert_eq(g["objects"], [{"feature": "hex_village", "col": 8, "row": 5, "owner": 2}])
	assert_eq(g["starts"], [{"player": 2, "commander": "field_commander", "col": 7, "row": 5}])
	assert_eq(c.move_object(0, 4, 4), "")
	c.remove_start(0)
	assert_eq(c.starts.size(), 0)
	c.mirror = false
	assert_eq(c.ghosts()["objects"], [])


func test_a_new_map_joins_the_package_and_plays() -> void:
	var m := PackageEditor.open(COPY)
	var c := OverworldCanvas.create(m.templates, "t_ow_new", 8, 6, "hex_plains")
	c.place("hex_village", 1, 2, 1)
	c.place("hex_village", 6, 3, 2)
	c.add_start(1, "field_commander", 2, 2)
	c.add_start(2, "field_commander", 5, 3)
	
	assert_eq(m.add(c.definition_text(), m.file_of("test_vale")), PackedStringArray())
	var back := _open(m, "t_ow_new")
	assert_eq([back.width, back.objects.size(), back.starts.size()], [8, 2, 2])


func test_connect_shapes_follow_the_neighbours() -> void:
	assert_eq(ConnectShape.of(0)["shape"], "isolated")
	assert_eq(ConnectShape.of(ConnectShape.N), {"shape": "end", "turn": 0})
	assert_eq(ConnectShape.of(ConnectShape.S), {"shape": "end", "turn": 2})
	assert_eq(ConnectShape.of(ConnectShape.N | ConnectShape.S), {"shape": "straight", "turn": 0})
	assert_eq(ConnectShape.of(ConnectShape.E | ConnectShape.W), {"shape": "straight", "turn": 1})
	assert_eq(ConnectShape.of(ConnectShape.N | ConnectShape.E), {"shape": "corner", "turn": 0})
	assert_eq(ConnectShape.of(ConnectShape.S | ConnectShape.W), {"shape": "corner", "turn": 2})
	assert_eq(ConnectShape.of(ConnectShape.N | ConnectShape.E | ConnectShape.S), {"shape": "tee", "turn": 0})
	assert_eq(ConnectShape.of(ConnectShape.E | ConnectShape.S | ConnectShape.W), {"shape": "tee", "turn": 1})
	assert_eq(ConnectShape.of(15)["shape"], "cross")


func test_a_battle_map_wall_draws_from_its_neighbours() -> void:
	var m := PackageEditor.open(COPY)
	var c := MapCanvas.create(m.templates, "t_wall", 5, 5, "open")
	var wall := c.features.find("wall")
	c.begin()
	c.rect(1, 2, 3, 2, wall, 0)
	c.paint(2, 3, wall, 0)
	assert_eq(c.shape_at(1, 2), {"shape": "end", "turn": 1})
	assert_eq(c.shape_at(2, 2), {"shape": "tee", "turn": 1})
	assert_eq(c.shape_at(2, 3), {"shape": "end", "turn": 0})
	assert_eq(c.shape_at(0, 0), {}, "open ground has no `connects`")
