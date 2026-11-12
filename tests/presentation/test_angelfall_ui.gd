extends GutTest
## The playable Angelfall scene (sw-cf6): the war room on angelfall_frontier
## with overworld orders (routes, battleforce, supply lines), the message
## log and the mission banner.

const W := 12


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _room() -> WarRoom:
	var w: WarRoom = load("res://src/presentation/angelfall/angelfall.tscn").instantiate()
	add_child_autofree(w)
	return w


func test_jeff_disperses_the_blockade_from_the_ui() -> void:
	var w := _room()
	assert_eq(w.session.map_id, "angelfall_frontier")
	var jeff: int = w.session.state.commanders.ids()[0]
	w.contexts.select_commander(jeff)
	assert_eq(w.set_battleforce(OverworldBattleforce.NONE, false), "")
	var start: int = w.session.state.commanders.get_value(jeff, &"plot")
	assert_eq(w.route_to(P(7, 3)), "")
	assert_false((w.session.observe(1)["routes"] as Dictionary).is_empty(), "the route is planned")
	var guard := 0
	while w.session.state.vars.get("angels_dispersed", 0) == 0 and guard < 4:
		guard += 1
		if w.session.state.commanders.get_value(jeff, &"plot") != P(7, 3):
			w.route_to(P(7, 3))
		w.end_turn_requested.emit()
	assert_ne(w.session.state.commanders.get_value(jeff, &"plot"), start)
	assert_eq(w.session.state.vars.get("angels_dispersed", 0), 1)
	await get_tree().process_frame
	assert_true(Array(w.messages).any(func(m: String) -> bool: return m.contains("They scatter")), str(w.messages))
	assert_false(w._banner.visible)


func test_supply_lines_and_the_banner() -> void:
	var w := _room()
	var jeff: int = w.session.state.commanders.ids()[0]
	w.contexts.select_commander(jeff)
	await get_tree().process_frame
	assert_gt(w._commander_box.get_child_count(), 3, "battleforce and supply line controls")
	var town := w.session.state.features.id_at(w.session.state.feature_row(P(1, 4), w.session.rules.feature_index("hex_frontier_town")))
	assert_eq(w.session.set_supply_line(1, town, -1, jeff), "")
	w.session.state.outcome = {"outcome": "won", "key": "", "text": "Done.", "turn": 1}
	w._refresh()
	assert_true(w._banner.visible)
	assert_string_contains(w._banner_text.text, "Mission won")
