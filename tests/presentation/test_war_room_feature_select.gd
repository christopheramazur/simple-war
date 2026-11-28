extends GutTest
## Per-feature selection in the war room (sw-63wt.7, U1Q23): a click on a
## site or its panel row selects it, hover links row and map both ways, and
## with a producing own site selected a right click sets its rally point.
## On angelfall_frontier, whose frontier town (1,4) is the player's and makes
## squads.

const W := 12


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _room() -> WarRoom:
	var w: WarRoom = load("res://src/presentation/angelfall/angelfall.tscn").instantiate()
	w.use_settings = false
	add_child_autofree(w)
	return w


func _town(w: WarRoom) -> int:
	return w.session.state.features.id_at(w.session.state.feature_row(P(1, 4), w.session.rules.feature_index("hex_frontier_town")))


func test_clicking_a_site_selects_it_on_the_map_and_in_the_panel() -> void:
	var w := _room()
	var town := _town(w)
	assert_true((w.session.observe(1)["production"] as Dictionary).has(town), "the town is a producing own site")
	var jeff: int = w.session.state.commanders.ids()[0]
	w.contexts.select_commander(jeff)
	w._on_hex_clicked(P(1, 4), MOUSE_BUTTON_LEFT, false, town)
	assert_eq(w.contexts.selected_feature, town)
	assert_eq(w.contexts.selected_plot, P(1, 4))
	assert_eq(w.contexts.selected, -1, "the panel shows the site")
	w._refresh()
	assert_eq(w._main._selected_feature, town, "the map rings it")
	var row: Button = w._commander_box._rows[town]
	assert_true(row.button_pressed, "its row is the selected one")
	var on_row := row.get_parent().get_children().map(func(c: Node) -> String: return (c as Button).text)
	assert_has(on_row, "Set rally point…", "the rally button sits on the feature's row")
	# Its row selects it too.
	w.contexts.deselect_all()
	assert_eq(w.contexts.selected_feature, -1, "deselect-all clears it")
	w._refresh()
	assert_false(w._commander_box._rows.has(town))
	w.contexts.select_hex(P(1, 4))
	w._refresh()
	(w._commander_box._rows[town] as Button).pressed.emit()
	assert_eq(w.contexts.selected_feature, town)


func test_a_token_click_still_selects_the_commander() -> void:
	var w := _room()
	var jeff: int = w.session.state.commanders.ids()[0]
	var at: int = w.session.state.commanders.get_value(jeff, &"plot")
	w._on_hex_clicked(at, MOUSE_BUTTON_LEFT, false, -1)
	assert_eq(w.contexts.selected, jeff, "no site picked: the hex's commander as before")
	assert_eq(w.contexts.selected_feature, -1)


func test_hover_links_row_and_map_both_ways() -> void:
	var w := _room()
	var town := _town(w)
	w.contexts.select_hex(P(1, 4))
	w._refresh()
	w._main.feature_hovered.emit(town)
	assert_true(w._commander_box.row_hovered(town), "a site hovered on the map lights its row")
	w._main.feature_hovered.emit(-1)
	assert_false(w._commander_box.row_hovered(town))
	w._commander_box.feature_hovered.emit(town)
	assert_eq(w._main._hover_feature, town, "a row hovered rings its site")
	w._commander_box.feature_hovered.emit(-1)
	assert_eq(w._main._hover_feature, -1)


func test_right_click_sets_the_selected_sites_rally_point() -> void:
	var w := _room()
	var town := _town(w)
	var jeff: int = w.session.state.commanders.ids()[0]
	w.select_feature(town, P(1, 4))
	w._on_hex_clicked(w.session.state.commanders.get_value(jeff, &"plot"), MOUSE_BUTTON_RIGHT)
	var line: Dictionary = (w.session.observe(1)["supply_lines"] as Dictionary).get(town, {})
	assert_eq(int(line.get("commander", -1)), jeff, "a right click on a commander's hex supplies it")
	assert_eq(w.contexts.selected_feature, town, "the site stays selected")
	assert_true((w.session.observe(1).get("routes", {}) as Dictionary).is_empty(), "no commander was routed")
	# Without a producing site selected the right click is the commander's again.
	w.contexts.select_commander(jeff)
	assert_eq(w._rally_feature(), -1)


func test_panel_rows_stay_selectable_while_locked() -> void:
	var w := _room()
	var town := _town(w)
	w.select_feature(town, P(1, 4))
	var box: CommandPanel = w._commander_box
	box.locked_reason = WarRoom.PLANNING_ONLY_NOTE
	box.show_selection(w.session, 1, -1, P(1, 4), -1, town)
	var row: Button = box._rows[town]
	assert_false(row.disabled, "selecting is inspection, not an order")
	for c: Node in row.get_parent().get_children():
		if c != row:
			assert_true((c as Button).disabled, "the rally buttons are orders")
	box.locked_reason = ""


func test_selected_site_lists_what_it_does() -> void:
	var w := _room()
	var town := _town(w)
	w.select_feature(town, P(1, 4))
	w._refresh()
	var texts := []
	for c: Node in w._commander_box.get_children():
		if c is Label:
			texts.append((c as Label).text)
	var all := "\n".join(texts)
	assert_string_contains(all, "every", "its production, from HexCard.feature_lines")
	assert_string_contains(all, "Right click a hex", "how to set its rally point")


func test_selection_notes_say_last_seen_and_enemy() -> void:
	var notes := HexCard.selection_notes({"visible": false, "turn": 2, "owner": 2}, 1, 5)
	assert_eq(notes[0][0], "Last seen 3 turns ago: not in sight now.")
	assert_eq(notes[1][0], "An enemy site: selected to inspect only.")
	assert_eq(HexCard.selection_notes({"visible": true, "owner": 1}, 1, 5), [])
