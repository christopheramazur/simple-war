extends GutTest
## War room readability (sw-ip8.7): the match log, the event feed, squads
## lost in battle, armies and garrisons in the panel, battle terrain, and
## orders drawn in a reaction window being queued instead of dropped.


func _skirmish(map: String = "skirmish_mirror", seed_value: int = 3) -> WarRoom:
	var w := MainMenu.skirmish_room("profile_utility", map, seed_value)
	add_child_autofree(w)
	return w


func _play_out(w: WarRoom, turns: int = 40) -> Array:
	var seen := []
	var guard := 0
	while w.session.state.outcome.is_empty() and guard < turns:
		guard += 1
		w.end_turn_requested.emit()
		for e in w.session.last_events:
			seen.append(e.to_dict())
	return seen


func test_event_text_reads_plainly() -> void:
	var r := OverworldRules.new()
	r.width = 20
	var lost := {"type": &"squads_lost", "data": {"player": 1, "plot": 45, "count": 2,
		"squads": PackedStringArray(["rifle_squad", "scout_squad"])}}
	assert_eq(EventText.describe(lost, r, 1), "You lost 2 squads in the battle at (5,2): Rifle squad, Scout squad.")
	assert_eq(EventText.describe(lost, r, 2), "Enemy (P1) lost 2 squads in the battle at (5,2): Rifle squad, Scout squad.")
	var fell := {"type": &"commander_defeated", "data": {"commander": 4294967297, "player": 2, "plot": 21, "scattered": 3}}
	assert_string_contains(EventText.describe(fell, r, 0), "P2 Commander 1 defeated at (1,1); its army of 3 squads scattered")
	assert_true(EventText.in_feed(&"squads_lost"))
	assert_false(EventText.in_feed(&"value_changed"))


func test_battles_report_losses_and_the_feed_shows_them() -> void:
	var w := _skirmish()
	var seen := _play_out(w)
	assert_false(w.session.state.outcome.is_empty(), "the AI beats an idle player")
	var types := seen.map(func(e: Dictionary) -> StringName: return e["type"])
	assert_has(types, &"squads_lost")
	var fell: Array = seen.filter(func(e: Dictionary) -> bool: return e["type"] == &"commander_defeated")
	assert_eq(fell.size(), 1)
	assert_true((fell[0]["data"] as Dictionary).has("scattered"))
	await get_tree().process_frame
	assert_true(Array(w.messages).any(func(m: String) -> bool: return m.contains("defeated")), str(w.messages))


func test_the_match_log_records_turns_and_a_replayable_save() -> void:
	var w := _skirmish()
	assert_not_null(w.match_log)
	assert_string_contains(w.messages[0], "Match log: ")
	var p := w.session.state.commanders.ids()[0]
	w.contexts.select_commander(p)
	w.route_to(Hex.plot(5, 4, w.session.rules.width))
	for i in 3:
		w.end_turn_requested.emit()
	var dir := w.match_log.dir
	assert_true(FileAccess.file_exists(dir + "/match.json"))
	var log_text := FileAccess.get_file_as_string(dir + "/log.md")
	assert_string_contains(log_text, "## Turn 3")
	assert_string_contains(log_text, "route Commander")
	assert_string_contains(log_text, "end turn")
	assert_string_contains(log_text, "**What happened**")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/match.json"))
	assert_eq(info["opponent"], "profile_utility")
	var restored := OverworldSession.load_save(FileAccess.get_file_as_bytes(dir + "/match.sav"), w.session.templates, w.session.data_hash)
	assert_not_null(restored, OverworldSession.last_error)
	assert_eq(restored.turns_resolved(), 3)


func test_army_panel_and_garrison_pick_up() -> void:
	var w := _skirmish()
	var s := w.session
	var cid: int = Array(s.state.commanders.ids()).filter(func(c: int) -> bool: return s.state.commanders.get_value(c, &"player") == 1)[0]
	var at: int = s.state.commanders.get_value(cid, &"plot")
	var did := s.state.detachments.spawn({&"player": 1, &"plot": at})
	var sq := s.rules.squad_ids.find("rifle_squad")
	var size := s.rules.sq_size[sq]
	s.state.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": sq, &"alive": size, &"size": size})
	var before := OverworldArmies.count(s.state, cid)
	w.contexts.select_commander(cid)
	await get_tree().process_frame
	var texts := w._commander_box.get_children().map(func(n: Node) -> String: return n.text if "text" in n else "")
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Pick up 1 squad")), str(texts))
	assert_eq(w.pick_up(did), "")
	assert_eq(OverworldArmies.count(s.state, cid), before + 1)


func test_terrain_is_drawn_from_the_battle_rules() -> void:
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.demo_view = "battle"
	w.record_match = false
	add_child_autofree(w)
	var rules := w._battle_rules(w.contexts.focus)
	assert_not_null(rules)
	var tex := w._main._terrain_texture(rules)
	assert_not_null(tex)
	assert_eq(tex.get_size(), Vector2(rules.width, rules.height))
	assert_same(w._main._terrain_texture(rules), tex, "built once per battle")


func test_orders_drawn_in_a_reaction_window_are_queued() -> void:
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.demo_view = "battle"
	add_child_autofree(w)
	var eid := w.contexts.focus
	var st: BattleState = (w.session.battles[eid] as OverworldBattle).state
	var sq := st.squads
	var g := -1
	for row in sq.count():
		if sq.player[row] != 1:
			g = row
	for row in sq.count():  # 20 m from the enemy: the turn has contacts
		if sq.player[row] != 1:
			continue
		var dist := maxi(Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[g], sq.cy[g]), 1)
		var mx := sq.cx[g] + (sq.cx[row] - sq.cx[g]) * Fixed.from_int(20) / dist - sq.cx[row]
		var my := sq.cy[g] + (sq.cy[row] - sq.cy[g]) * Fixed.from_int(20) / dist - sq.cy[row]
		for urow in st.units.count():
			if st.units.squad[urow] == sq.id_at(row):
				st.units.set_value(st.units.id_at(urow), &"x", st.units.x[urow] + mx)
				st.units.set_value(st.units.id_at(urow), &"y", st.units.y[urow] + my)
	Centroids.update(st)
	w.end_turn_requested.emit()
	assert_eq(w.session.clock.phase, PulseClock.Phase.REACTION)
	await get_tree().process_frame
	assert_true(w._phase_banner.visible, "the banner says moves are locked")
	var pl := w.planner(eid)
	pl.select(pl.own_squads())
	pl.move_to(pl.selection_centre() + Vector2(-30, 0), false)
	assert_true(w._pending.has(eid), "queued, not dropped")
	assert_false(pl.drafts.is_empty())
	w.end_turn_requested.emit()  # plays the turn; Planning is back
	assert_eq(w.session.clock.phase, PulseClock.Phase.PLANNING)
	assert_false(w._pending.has(eid), "sent once Planning returned")
	assert_false(pl.drafts.is_empty(), "the queued drafts survived the turn change")
	await get_tree().process_frame
	assert_false(w._phase_banner.visible)
