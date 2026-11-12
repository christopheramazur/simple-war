extends GutTest
## Planning UI: the RTS command set (BattlePlanner), intent ghosts
## (IntentForecast), GUIDE actions (PlanningInput) and the war room's
## planning and reaction window. GDD 01 Input and UI, 02 §2.2, R1Q4, R3Q4,
## R4Q3. Task sw-ip8.3.

const ONE := Fixed.ONE


func _sq(id: int, player: int, template: String, x: int, y: int, abilities: Array = []) -> Dictionary:
	return {"id": id, "player": player, "template": template, "x": x * ONE, "y": y * ONE, "alive": 8,
		"abilities": abilities}


func _toggle(id: String, on: bool = false) -> Dictionary:
	return {"id": id, "name": id.capitalize(), "toggle": true, "reaction": false, "on": on}


func _obs() -> Dictionary:
	return {"width": 200, "height": 100, "squads": [
		_sq(1, 1, "rifle_squad", 10, 10, [_toggle("auspex"), {"id": "halt", "name": "Halt", "reaction": true}]),
		_sq(2, 1, "rifle_squad", 20, 10, [_toggle("auspex", true)]),
		_sq(3, 1, "scout_team", 30, 50, [_toggle("scout_cloak")]),
		_sq(9, 2, "rifle_squad", 150, 50),
	]}


func _planner() -> BattlePlanner:
	var p := BattlePlanner.new(1)
	p.sync(_obs())
	return p


func test_selection_commands() -> void:
	var p := _planner()
	p.select([1, 9])
	assert_eq(p.selection, [1] as Array[int], "only own squads")
	p.select([2], true)
	assert_eq(p.selection, [1, 2] as Array[int])
	p.select([1], false, true)
	assert_eq(p.selection, [2] as Array[int], "ctrl toggles")
	p.select_box(Rect2(0, 0, 25, 25))
	assert_eq(p.selection, [1, 2] as Array[int])
	p.select_type(3)
	assert_eq(p.selection, [3] as Array[int], "select by type")
	p.select_type(1, Rect2(0, 0, 15, 15))
	assert_eq(p.selection, [1] as Array[int], "by type on screen")


func test_control_groups() -> void:
	var p := _planner()
	p.select([1, 2])
	p.assign_group(1)
	p.select([3])
	p.assign_group(1, true)
	p.deselect()
	p.recall_group(1)
	assert_eq(p.selection, [1, 2, 3] as Array[int])
	var gone := _obs()
	(gone["squads"] as Array).remove_at(1)
	p.sync(gone)
	assert_eq(p.groups[1], [1, 3], "squads that left drop out")


func test_moves_keep_or_make_formations() -> void:
	var p := _planner()
	p.select([1, 2])
	p.move_to(Vector2(100, 10))
	var o := p.orders()
	assert_eq(o.size(), 2)
	assert_eq(o[0], {"squad": 1, "type": "move", "x": 95 * ONE, "y": 10 * ONE})
	assert_eq(o[1]["x"], 105 * ONE, "kept their places around the centre")
	p.move_to(Vector2(100, 50), true, true)
	o = p.orders()
	assert_eq(o[0]["type"], "attack_move")
	var gap := Vector2(o[1]["x"] - o[0]["x"], o[1]["y"] - o[0]["y"]).length()
	assert_almost_eq(gap, float(BattlePlanner.FORMATION_SPACING), 2.0, "a new line, one spacing apart")
	var travel := Vector2(100, 50) - Vector2(15, 10)
	assert_almost_eq(Vector2(o[1]["x"] - o[0]["x"], o[1]["y"] - o[0]["y"]).dot(travel), 0.0, 2.0 * ONE * travel.length(), "across the direction of travel")
	p.move_to(Vector2(500, -5))
	assert_eq(p.orders()[0]["y"], 0, "kept on the battlefield")


func test_attack_hold_and_run() -> void:
	var p := _planner()
	p.select([1, 2])
	p.attack(9)
	assert_eq(p.orders()[0], {"squad": 1, "type": "attack", "target": 9})
	p.attack(3)
	assert_eq(p.orders()[0]["target"], 9, "only visible enemies")
	p.toggle_run()
	p.order("hold")
	assert_eq(p.orders()[1], {"squad": 2, "type": "hold", "run": true}, "run survives a new order")


func test_one_ability_menu_across_the_selection() -> void:
	var p := _planner()
	p.select([1, 2, 3])
	var menu := p.ability_menu()
	assert_eq(menu.size(), 2, "reactions stay out")
	assert_eq(menu[0]["id"], "auspex")
	assert_eq(menu[0]["squads"], [1, 2])
	assert_false(menu[0]["on"], "not on for all")
	p.use_ability("auspex")
	assert_eq(p.orders()[0]["abilities"], [{"id": "auspex", "on": true}])
	assert_true(p.ability_menu()[0]["on"])
	p.use_ability("auspex")
	assert_eq(p.orders()[1]["abilities"], [{"id": "auspex", "on": false}], "all on -> off")


# --- through the sessions ------------------------------------------------------

func test_intent_forecast_is_read_only_and_fog_safe() -> void:
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	add_child_autofree(w)
	var s := w.session
	var eid: int = w.contexts.battles()[0]
	var obs := s.observe_battle(1, eid)
	var mine: Array = (obs["squads"] as Array).filter(func(q: Dictionary) -> bool: return q["player"] == 1)
	var before := s.state_hash_hex()
	var o := [{"squad": mine[0]["id"], "type": "move", "x": mine[0]["x"] + 30 * ONE, "y": mine[0]["y"]}]
	var fc := s.forecast_battle(1, eid, o)
	assert_eq(s.state_hash_hex(), before, "nothing changed")
	assert_true((fc["ghosts"] as Dictionary).has(mine[0]["id"]))
	var pts: PackedInt64Array = fc["ghosts"][mine[0]["id"]]
	assert_eq(pts.size(), IntentForecast.SAMPLES * 2)
	assert_gt(pts[pts.size() - 2], mine[0]["x"], "the ghost moved toward the order")
	for k: int in fc["ghosts"]:
		var row := (s.battles[eid] as OverworldBattle).state.squads.row_of(k)
		assert_eq((s.battles[eid] as OverworldBattle).state.squads.player[row], 1, "ghosts are own squads only")
	assert_eq(s.forecast_battle(2, eid, []), {}, "not player 2's battle")


func test_war_room_planning_submits_drafts() -> void:
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.demo_view = "battle"
	add_child_autofree(w)
	var eid := w.contexts.focus
	var pl := w.planner(eid)
	var id: int = pl.own_squads()[0]
	pl.select([id])
	w._on_command(&"hold", 0)
	assert_eq((w.session.battles[eid] as OverworldBattle).orders[1], [{"squad": id, "type": "hold"}], "submitted at once")
	assert_true(w._forecasts.has(eid), "and forecast")
	w._on_command(&"assign_group", 4)
	pl.deselect()
	w._on_command(&"recall_group", 4)
	assert_eq(pl.selection, [id] as Array[int])
	w._on_command(&"set_bookmark", 1)
	w.contexts.exit()
	w._on_command(&"recall_bookmark", 1)
	assert_eq(w.contexts.focus, eid, "the bookmark returns to the battle")


func test_guide_actions_are_remappable() -> void:
	var input := PlanningInput.new()
	add_child_autofree(input)
	assert_eq(input.actions.size(), 6 + 30 + 8)
	for a: GUIDEAction in input.actions.values():
		assert_true(a.is_remappable)
	assert_eq(PlanningInput.command_of(&"assign_group_3"), &"assign_group")
	var got := []
	input.command.connect(func(n: StringName, arg: int) -> void: got.append([n, arg]))
	(input.actions[&"add_group_7"] as GUIDEAction).triggered.emit()
	assert_eq(got, [[&"add_group", 7]])


func test_war_room_reaction_window() -> void:
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.demo_view = "battle"
	add_child_autofree(w)
	var eid := w.contexts.focus
	# Bring player 1's squads to 20 m from the enemy so the turn has contacts.
	var st: BattleState = (w.session.battles[eid] as OverworldBattle).state
	var sq := st.squads
	var g := -1
	for row in sq.count():
		if sq.player[row] != 1:
			g = row
	for row in sq.count():
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
	assert_eq(w.session.clock.phase, PulseClock.Phase.REACTION, "stopped at the window")
	var opps := w.session.reaction_opportunities(1)
	assert_gt(opps.size(), 0)
	await get_tree().process_frame
	assert_gt(w._reactions_box.get_child_count(), 1, "the queue lists the opportunities")
	var o: Dictionary = opps[0]
	assert_eq(w._reactable(o["engagement"]).get(o["squad"]), "")
	w._react(o, o["reactions"][0])
	assert_eq(w._reactable(o["engagement"])[o["squad"]], o["reactions"][0], "marked as queued")
	assert_true(w.session.input_log.any(func(i: Dictionary) -> bool: return i["kind"] == "reaction"))
