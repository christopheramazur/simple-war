extends GutTest
## Screen layouts as data (sw-ijp.3): the war room's panels are placed by
## data/ui/layouts/war_room.json, a player's own layout can move them, and
## a broken layout is refused with reasons.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const SETTINGS := "user://test_settings_layout.cfg"
const USER_DIR := "user://test_ui_layouts"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS
	UiLayout.user_dir = USER_DIR
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	DirAccess.remove_absolute(USER_DIR + "/war_room.json")


func after_all() -> void:
	DirAccess.remove_absolute(USER_DIR + "/war_room.json")
	DirAccess.remove_absolute(USER_DIR)
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"
	UiLayout.user_dir = "user://ui_layouts"


func _room() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	return w


func _panels(ids: Array) -> Dictionary:
	var out := {}
	for id: String in ids:
		var c := Label.new()
		c.name = id
		out[id] = c
	return out


func test_the_war_room_is_laid_out_from_its_file() -> void:
	var w := _room()
	assert_eq(w.layout.source, "res://data/ui/layouts/war_room.json")
	var side: Control = w.layout.regions["side"]
	assert_true(side.is_ancestor_of(w._menu), "battles are in the side column")
	assert_true(side.is_ancestor_of(w._end_button))
	assert_true(w.layout.regions["stage"].is_ancestor_of(w._main))
	assert_false(w.layout.regions["battle"].visible, "the battle column waits for a battle")
	assert_true(w.contexts.tab_in())
	w._refresh()
	assert_true(w.layout.regions["battle"].visible)


func test_a_players_layout_moves_panels() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/layouts/war_room.json"))
	var side: Dictionary = data["row"][2]
	(side["scroll"] as Array).erase("events")
	(data["row"][0]["scroll"] as Array).append("events")
	data["row"][0]["views"] = []
	var f := FileAccess.open(USER_DIR + "/war_room.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var w := _room()
	assert_eq(w.layout.source, USER_DIR + "/war_room.json")
	assert_true(w.layout.regions["battle"].is_ancestor_of(w._log_box), "events now sit in the left column")
	assert_true(w.layout.regions["battle"].visible, "shown in every view")


func test_a_broken_players_layout_falls_back_to_the_shipped_one() -> void:
	var f := FileAccess.open(USER_DIR + "/war_room.json", FileAccess.WRITE)
	f.store_string("{\"row\": [{\"id\": \"x\", \"kind\": \"column\", \"scroll\": [\"no_such_panel\"]}]}")
	f.close()
	var w := _room()
	assert_eq(w.layout.source, "res://data/ui/layouts/war_room.json")


func test_validation_says_what_is_wrong() -> void:
	var ids := ["a", "b"]
	assert_eq(UiLayout.validate({"row": [{"id": "c", "kind": "column", "scroll": ["a"], "footer": ["b"]}]}, ids).size(), 0)
	var errs := "\n".join(UiLayout.validate({"row": [
		{"id": "c", "kind": "column", "scroll": ["a", "zz"], "colour": 1},
		{"id": "c", "kind": "stage", "layers": [{"id": "a", "anchor": "middle"}]},
		{"id": "d", "kind": "grid"}]}, ids))
	assert_string_contains(errs, "no panel 'zz'")
	assert_string_contains(errs, "unknown key 'colour'")
	assert_string_contains(errs, "unique ('c')")
	assert_string_contains(errs, "placed twice")
	assert_string_contains(errs, "unknown anchor 'middle'")
	assert_string_contains(errs, "kind must be")
	assert_eq(UiLayout.validate([], ids).size(), 1)


func test_build_places_skips_and_keeps_the_rest() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var panels := _panels(["a", "b", "c"])
	panels["gone"] = null
	var lay := UiLayout.build({"row": [
		{"id": "left", "kind": "column", "width": 100, "scroll": ["a", "gone"], "footer": ["b"], "views": ["battle"]},
		{"id": "stage", "kind": "stage", "layers": []}]}, panels, host)
	assert_true(lay.regions["left"].is_ancestor_of(panels["a"]))
	assert_true(lay.regions["left"].is_ancestor_of(panels["b"]))
	assert_false(panels["c"].is_visible_in_tree(), "left out: kept, hidden")
	assert_true(host.is_ancestor_of(panels["c"]))
	lay.set_view("overworld")
	assert_false(lay.regions["left"].visible)
	lay.set_view("battle")
	assert_true(lay.regions["left"].visible)


func test_a_column_keeps_its_width_whatever_it_shows() -> void:
	# sw-7m6: a wide panel must not widen its column, or the stage shifts
	# under the cursor and a hover flickers on and off.
	var host := Control.new()
	add_child_autofree(host)
	var panels := _panels(["a"])
	var lay := UiLayout.build({"row": [
		{"id": "left", "kind": "column", "width": 100, "scroll": ["a"]},
		{"id": "stage", "kind": "stage", "layers": []}]}, panels, host)
	var col: Control = lay.regions["left"]
	var before := col.get_combined_minimum_size().x
	(panels["a"] as Label).custom_minimum_size.x = 600
	assert_eq(col.get_combined_minimum_size().x, before, "the column's width is the layout's, not its content's")


func test_the_battle_column_does_not_grow_for_a_squad_card() -> void:
	var w := _room()
	var col: Control = w.layout.regions["battle"]
	var before := col.get_combined_minimum_size().x
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	var q: Dictionary = s.observe(1)["squads"][0]
	w._battle_box.show_battle("T", s.observe(1), q, s.inspect(1, q["id"]), 1, 10)
	assert_eq(col.get_combined_minimum_size().x, before, "showing a card keeps the column's width")
	var widest := 0.0
	for c: Node in w._battle_box.find_children("*", "Control", true, false):
		widest = maxf(widest, (c as Control).get_combined_minimum_size().x)
	var room := (w._battle_box as Control).get_parent_control().size.x
	assert_true(room <= 0.0 or widest <= room + 0.5, "the card fits the column (widest %d, room %d)" % [widest, room])
