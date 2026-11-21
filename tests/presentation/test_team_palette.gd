extends GutTest
## CVD-safe team colours (sw-ijp.5): one presentation source, presets in
## settings, AA text tones, a distinct neutral in every preset, and the four
## readers resolving from the source.

const SETTINGS := "user://test_settings_team_palette.cfg"
const PANEL := Color("1d2128")


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


func test_the_default_pair_is_okabe_ito() -> void:
	assert_eq(str(GameSettings.value("team_palette")), "okabe_ito")
	assert_eq(TeamPalette.color(1), Color.html("0072B2"))
	assert_eq(TeamPalette.color(2), Color.html("D55E00"))
	assert_eq(TeamPalette.ids()[0], TeamPalette.DEFAULT_ID)


func test_every_preset_carries_both_sides_and_a_distinct_neutral() -> void:
	for id in TeamPalette.ids():
		var colors: Dictionary = TeamPalette.preset(id)["colors"]
		assert_true(colors.has(1) and colors.has(2) and colors.has(TeamPalette.NEUTRAL_ID), id)
		var a := Color.html(str(colors[1]))
		var b := Color.html(str(colors[2]))
		var n := Color.html(str(colors[TeamPalette.NEUTRAL_ID]))
		assert_gt(_distance(a, b), 0.25, "%s: the sides differ" % id)
		assert_gt(_distance(a, n), 0.25, "%s: neutral differs from side 1" % id)
		assert_gt(_distance(b, n), 0.25, "%s: neutral differs from side 2" % id)
		# In greyscale the neutral stays apart from both sides.
		assert_gt(absf(TeamPalette.luminance(n) - TeamPalette.luminance(a)), 0.05, "%s: grey vs side 1" % id)
		assert_gt(absf(TeamPalette.luminance(n) - TeamPalette.luminance(b)), 0.05, "%s: grey vs side 2" % id)


func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func test_switching_the_preset_changes_fills_and_text() -> void:
	var fill := TeamPalette.color(1)
	var text := TeamPalette.text_color(1)
	assert_eq(GameSettings.set_value("team_palette", "tol_high_contrast"), "")
	assert_eq(TeamPalette.color(1), Color.html("004488"))
	assert_eq(TeamPalette.color(2), Color.html("DDAA33"))
	assert_ne(TeamPalette.color(1), fill)
	assert_ne(TeamPalette.text_color(1), text)


func test_the_preset_survives_a_reload() -> void:
	assert_eq(GameSettings.set_value("team_palette", "tol_high_contrast"), "")
	GameSettings.path = "user://test_settings_team_palette_else.cfg"
	assert_eq(str(GameSettings.value("team_palette")), "okabe_ito", "a fresh file starts at the default")
	GameSettings.path = SETTINGS
	assert_eq(str(GameSettings.value("team_palette")), "tol_high_contrast")
	assert_eq(TeamPalette.color(1), Color.html("004488"))


func test_text_tones_pass_aa_on_the_panel() -> void:
	# Raw Okabe-Ito blue fails AA on the dark panel; the derived tone passes.
	assert_lt(TeamPalette.contrast(Color.html("0072B2"), PANEL), TeamPalette.AA)
	for id in TeamPalette.ids():
		GameSettings.set_value("team_palette", id)
		for p: int in [1, 2, TeamPalette.NEUTRAL_ID]:
			var tone := TeamPalette.text_color(p, PANEL)
			assert_gte(TeamPalette.contrast(tone, PANEL), TeamPalette.AA, "%s side %d" % [id, p])
	# The default background is the current theme's panel colour.
	assert_eq(TeamPalette.text_color(1), TeamPalette.text_color(1, UiTheme.color(UiTheme.profile("default"), "panel")))


func test_text_tones_work_on_a_light_panel_too() -> void:
	var light := Color("f0f0f0")
	for p: int in [1, 2, TeamPalette.NEUTRAL_ID]:
		assert_gte(TeamPalette.contrast(TeamPalette.text_tone(TeamPalette.color(p), light), light), TeamPalette.AA)


func test_unlisted_ids_fall_back() -> void:
	assert_false(TeamPalette.has(0))
	assert_eq(TeamPalette.color(0), TeamPalette.color(TeamPalette.NEUTRAL_ID))
	assert_eq(TeamPalette.color(99, ContextView.TEXT), ContextView.TEXT)
	assert_eq(TeamPalette.preset("no_such_preset"), TeamPalette.preset(TeamPalette.DEFAULT_ID))


func test_the_four_readers_resolve_from_the_one_source() -> void:
	var readers: Array[String] = [
		"res://src/presentation/war_room/context_view.gd",
		"res://src/presentation/replay_viewer/replay_viewer.gd",
		"res://src/presentation/war_room/battle_panel.gd",
		"res://src/presentation/war_room/results_screen.gd",
	]
	for path in readers:
		var src := FileAccess.get_file_as_string(path)
		assert_string_contains(src, "TeamPalette.", path)
		assert_false(src.contains("PLAYER_COLORS"), "%s keeps no palette of its own" % path)
		assert_false(src.contains("NEUTRAL_COLOR"), path)


func test_battle_panel_labels_use_the_text_tone() -> void:
	var panel := BattlePanel.new()
	add_child_autofree(panel)
	var obs := {"turn": 2, "scores": {1: {"influence": 5, "value": 12}, 2: {"influence": 3, "value": 9}}, "zones": []}
	panel.show_battle("Crossroads", obs, {}, {}, 1, 10)
	var tones := _side_tones(panel)
	assert_eq(tones.get(1), TeamPalette.text_color(1))
	assert_eq(tones.get(2), TeamPalette.text_color(2))
	GameSettings.set_value("team_palette", "tol_high_contrast")
	panel.show_battle("Crossroads", obs, {}, {}, 1, 10)
	tones = _side_tones(panel)
	assert_eq(tones.get(1), TeamPalette.text_color(1), "the switch reaches the panel")
	assert_eq(tones.get(2), TeamPalette.text_color(2))


func _side_tones(panel: BattlePanel) -> Dictionary:
	var out := {}
	for c in panel.get_children():
		if c is Label and (c as Label).has_theme_color_override("font_color"):
			var l := c as Label
			if l.text.begins_with("You"):
				out[1] = l.get_theme_color("font_color")
			elif l.text.begins_with("Enemy"):
				out[2] = l.get_theme_color("font_color")
	return out


func test_results_screen_labels_use_the_text_tone() -> void:
	var r := ResultsScreen.new()
	add_child_autofree(r)
	r._build("won", "Every enemy commander is defeated.", {"turns": 4, "battles": 1, "players": {
		1: {"squads_lost": 0, "commanders_lost": 0, "features_taken": 2},
		2: {"squads_lost": 3, "commanders_lost": 1, "features_taken": 0}}}, 1, {})
	var grid: GridContainer = r.find_child("Stats", true, false)
	assert_not_null(grid)
	var who := grid.get_child(4) as Label  # first column of the first player row
	assert_true(who.has_theme_color_override("font_color"))
	assert_eq(who.get_theme_color("font_color"), TeamPalette.text_color(1))
	var foe := grid.get_child(8) as Label
	assert_eq(foe.get_theme_color("font_color"), TeamPalette.text_color(2))


func test_options_offers_the_presets_and_switches_live() -> void:
	var o := OptionsScreen.new()
	add_child_autofree(o)
	var pick: OptionButton = o.find_child("TeamPalette", true, false)
	assert_not_null(pick)
	assert_eq(pick.item_count, TeamPalette.ids().size())
	var seen: Array = []
	o.setting_changed.connect(func(key: String) -> void: seen.append(key))
	pick.item_selected.emit(1)
	assert_eq(str(GameSettings.value("team_palette")), TeamPalette.ids()[1])
	assert_has(seen, "team_palette")
	assert_eq(TeamPalette.color(1), Color.html("004488"))
