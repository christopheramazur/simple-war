extends GutTest
## The map editor's objects (GDD 04 §4.9, O1Q6, sw-ll4.7): ScenarioCanvas
## (zones and sides of a scenario) and the Objects tool of the Maps tab.
## Saves run on a copy of the core package.

const CORE := "res://data/packages/core"
const COPY := "user://test_pkg_objects"


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


func _panel() -> WarDataPanel:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	return p


func test_a_scenario_opens_with_its_zones_and_sides() -> void:
	var m := PackageEditor.open(COPY)
	var c := ScenarioCanvas.open(m.templates, JSON.parse_string(m.definition_text("duel_crossroads")))
	assert_eq([c.id, c.map_id, c.zones.size(), c.sides.size()], ["duel_crossroads", "crossroads_map", 3, 2])
	assert_eq(c.zones[1], {"id": "centre", "x": 100, "y": 50, "radius": 12, "decay": 10, "threshold": 10, "buffer": 10, "vp": 2})
	assert_eq(c.area_rect(1), Rect2i(170, 15, 25, 70))
	assert_eq((c.sides[0]["squads"] as Array).size(), 5)
	assert_eq(c.object_at(100, 55), {"kind": "zone", "index": 1})
	assert_eq(c.object_at(10, 20), {"kind": "side", "index": 0})
	assert_eq(c.object_at(100, 5), {})
	# Saving it untouched changes nothing the game reads.
	var before := BattleRules.compile(m.templates, "duel_crossroads")
	assert_eq(m.replace("duel_crossroads", c.definition_text()), PackedStringArray())
	var after := BattleRules.compile(m.templates, "duel_crossroads")
	assert_eq(after.errors, PackedStringArray())
	assert_eq([after.zn_x, after.zn_y, after.zn_radius, after.sides], [before.zn_x, before.zn_y, before.zn_radius, before.sides])
	assert_eq(m.templates.values_of("duel_crossroads")["victory"]["score_target"], 20, "what it does not edit is kept")
	# A child scenario gets its parent's sides.
	var drill := ScenarioCanvas.open(m.templates, JSON.parse_string(m.definition_text("hangar_drill")))
	assert_eq(drill.sides.size(), 2)


func test_edits_and_undo() -> void:
	var m := PackageEditor.open(COPY)
	var c := ScenarioCanvas.create(m.templates, "t_scn", "field_map", 120, 80)
	assert_eq([c.zones.size(), c.sides.size()], [1, 2])
	assert_eq(c.area_rect(0), Rect2i(5, 12, 20, 56))
	c.mark_saved()
	c.begin()
	var z := c.add_zone(30, 30)
	assert_eq(c.zones[z]["id"], "zone_2")
	assert_eq(c.set_zone(z, "id", "centre"), "another zone is already called 'centre'")
	assert_eq(c.set_zone(z, "id", "north"), "")
	assert_eq(c.set_zone(z, "radius", 7), "")
	c.move_zone(z, 60, 10)
	assert_eq([c.zones[z]["x"], c.zones[z]["y"], c.zones[z]["radius"]], [60, 10, 7])
	c.begin()
	c.move_area(0, 2, 20)
	c.resize_area(0, 30, 40)
	c.add_squad(0, "rifle_squad")
	c.add_squad(0, "scout_team")
	c.remove_squad(0, 0)
	assert_eq(c.set_side(1, "player", 1), "player 1 already has a side")
	assert_eq(c.set_side(1, "facing", ScenarioCanvas.FACINGS["North"]), "")
	assert_eq(c.area_rect(0), Rect2i(2, 20, 30, 40))
	assert_eq(c.sides[0]["squads"], ["scout_team"])
	c.begin()
	assert_eq(c.sides[c.add_side(50, 50)]["player"], 3)
	assert_true(c.dirty)
	c.undo()
	assert_eq(c.sides.size(), 2)
	c.undo()
	assert_eq(c.area_rect(0), Rect2i(5, 12, 20, 56))
	c.undo()
	assert_eq(c.zones.size(), 1)
	assert_false(c.can_undo())
	c.redo()
	assert_eq(c.zones[1]["id"], "north")
	# The text is one zone and one side to a line, and is a valid scenario.
	var text := c.definition_text()
	assert_string_contains(text, "\t\t\t\t{\"id\": \"north\", \"x\": 60, \"y\": 10, \"radius\": 7, \"decay\": 10, \"threshold\": 10, \"buffer\": 10, \"vp\": 1}\n")
	assert_eq(m.add(text, m.file_of("ow_field")), PackedStringArray())
	assert_eq(BattleRules.compile(m.templates, "t_scn").errors, PackedStringArray())


func test_the_objects_tool_moves_resizes_and_saves() -> void:
	var p := _panel()
	var mp := p.painter()
	assert_true(mp.open_map("field_map"))
	assert_not_null(mp.scenario, "a map opens with a scenario played on it")
	assert_eq(mp.scenario.id, "ow_field")
	assert_eq(mp.scenarios_of("crossroads_map"), PackedStringArray(["duel_crossroads", "hangar_drill"]))
	mp.set_tool(MapPainter.Tool.OBJECT)
	# Drag the centre zone 10 cells right and 5 up.
	mp.view.press(Vector2i(60, 40), false)
	assert_eq(mp.selected, {"kind": "zone", "index": 0})
	assert_not_null(mp._object_box.find_child("ZoneId", true, false))
	mp.view.drag(Vector2i(70, 35))
	mp.view.release(Vector2i(70, 35))
	assert_eq([mp.scenario.zones[0]["x"], mp.scenario.zones[0]["y"]], [70, 35])
	# Select player 1's area, then drag its corner handle.
	mp.view.press(Vector2i(10, 30), false)
	assert_eq(mp.selected, {"kind": "side", "index": 0})
	assert_not_null(mp._object_box.find_child("SquadPick", true, false))
	var r := mp.scenario.area_rect(0)
	mp.view.press(r.end - Vector2i.ONE, false)
	mp.view.drag(r.end - Vector2i.ONE + Vector2i(6, -10))
	mp.view.release(r.end)
	assert_eq(mp.scenario.area_rect(0), Rect2i(r.position, r.size + Vector2i(6, -10)))
	# Dragging the area itself moves it, and it stays on the map.
	mp.view.press(Vector2i(10, 30), false)
	mp.view.drag(Vector2i(-50, 30))
	mp.view.release(Vector2i(-50, 30))
	assert_eq(mp.scenario.area_rect(0).position, Vector2i(0, r.position.y))
	# Undo acts on the scenario while the Objects tool is on.
	mp.undo()
	assert_eq(mp.scenario.area_rect(0).position, r.position)
	assert_false(mp.canvas.dirty, "the terrain was not touched")
	assert_false(mp.open_map("crossroads_map"), "an unsaved scenario is not dropped")
	# A new zone, deleted again with the selection.
	mp._add_zone()
	assert_eq(mp.scenario.zones.size(), 2)
	mp.remove_selected()
	assert_eq(mp.scenario.zones.size(), 1)
	assert_eq(mp.save(), PackedStringArray())
	assert_false(mp.scenario.dirty)
	var saved: Dictionary = PackageEditor.open(COPY).templates.values_of("ow_field")
	assert_eq([int(saved["zones"][0]["x"]), int(saved["zones"][0]["y"])], [70, 35])
	assert_eq(int(saved["sides"][0]["deploy"]["w"]), r.size.x + 6)
	assert_true(mp.open_map("crossroads_map"))
	assert_eq(mp.scenario.id, "duel_crossroads")


func test_a_new_scenario_on_a_new_map_is_saved_with_it() -> void:
	var p := _panel()
	var mp := p.painter()
	assert_false(mp.new_scenario("yard_fight"), "a scenario needs a map")
	assert_true(mp.new_map("yard", 40, 30, "open"))
	assert_null(mp.scenario)
	assert_true(mp.new_scenario("yard_fight"))
	assert_eq(mp.tool, MapPainter.Tool.OBJECT)
	assert_eq(mp.scenario.map_id, "yard")
	mp.view.press(Vector2i(4, 10), false)
	mp.scenario.begin()
	mp.scenario.add_squad(0, "rifle_squad")
	assert_eq(mp.save(), PackedStringArray())
	var t := PackageEditor.open(COPY).templates
	assert_eq(t.kind_of("yard_fight"), "scenario")
	assert_eq(t.values_of("yard_fight")["map"], "yard")
	assert_eq(t.values_of("yard_fight")["sides"][0]["squads"], ["rifle_squad"])
	assert_eq(BattleRules.compile(t, "yard_fight").errors, PackedStringArray())
	# A zone dragged off the map is refused by the package, not written.
	mp.scenario.begin()
	mp.scenario.move_zone(0, 500, 500)
	assert_gt(mp.save().size(), 0)
	assert_true(mp.scenario.dirty)
	mp.revert()
	assert_eq(mp.scenario.zones[0]["x"], 20)


func test_play_this_map_uses_the_open_scenario() -> void:
	var p := _panel()
	var mp := p.painter()
	mp.open_map("field_map")
	var s := mp.scenario
	s.begin()
	s.move_zone(0, 30, 20)
	s.set_zone(0, "radius", 6)
	s.move_area(0, 2, 5)
	s.resize_area(0, 10, 30)
	s.add_squad(0, "scout_team")
	s.add_squad(0, "scout_team")
	var made := MapPlaytest.start(p.model, mp.canvas, 1, s)
	assert_eq(made["errors"], PackedStringArray())
	var session: OverworldSession = made["session"]
	var b: OverworldBattle = session.battles.values()[0]
	assert_eq([b.rules.zn_x[0], b.rules.zn_y[0], b.rules.zn_radius[0]], [30 * Fixed.ONE, 20 * Fixed.ONE, 6 * Fixed.ONE], "the unsaved zone is played")
	assert_eq(b.areas[0]["deploy"], PackedInt64Array([2 * Fixed.ONE, 5 * Fixed.ONE, 10 * Fixed.ONE, 30 * Fixed.ONE]))
	var mine := []
	var theirs := 0
	for row in b.state.squads.count():
		if b.state.squads.player[row] == 1:
			mine.append(b.rules.squad_ids[b.state.squads.tmpl[row]])
		else:
			theirs += 1
	assert_eq(mine, ["scout_team", "scout_team"], "the side fields exactly the squads it lists")
	assert_gt(theirs, 0, "a side that lists none fields its commander's force")
	assert_false(PackageEditor.open(COPY).templates.has(MapPlaytest.SCENARIO), "nothing was written")
	assert_eq(PackageEditor.open(COPY).templates.values_of("ow_field")["zones"][0]["x"], 60)
