extends GutTest
## The declarative trigger layer (GDD 03 §3.5, 02 §2.9 offers, §2.11
## Angels, R3Q9, R6Q14, R6Q17). Task sw-cgl.2. trigger_vale is test_vale
## with triggers: Angels gather before the mine (8,8) on turn 2, accepting
## the shrine's (3,7) offer grants 5 Value, and taking player 2's village
## (14,5) rewards player 1 once. hangar_drill is duel_crossroads with a
## locked "hangar" zone that opens on turn 3.

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _s() -> OverworldState:
	var r := OverworldRules.compile(_l().templates, "trigger_vale", _l().data_hash)
	assert_true(r.is_valid(), "; ".join(r.errors))
	return OverworldState.create(1, r, 7)


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _of(events: Array, type: StringName) -> Array:
	return events.filter(func(e: Variant) -> bool:
		return (e.type if e is SimEvent else StringName(e["type"])) == type)


func test_validation() -> void:
	var r := OverworldRules.compile(_l().templates, "trigger_vale", _l().data_hash)
	var bad := TriggerRules.compile(_l().templates, PackedStringArray(["drill_hangar_opens", "nope"]), "overworld", r.feature_ids)
	assert_eq(bad.errors.size(), 2)
	assert_string_contains(bad.errors[0], "action 'unlock_zone' is not available in overworld triggers")
	var t := TemplateTable.build([
		{"id": "x", "kind": "trigger", "values": {"on": "turn_resolved", "if": [{"check": "zone_owner", "zone": "moon"}, {"check": "var", "op": "~"}],
			"do": [{"do": "add_feature", "feature": "hex_nowhere"}, {"do": "set_var"}]}}])
	var errs := TriggerRules.compile(t, PackedStringArray(["x"]), "overworld", r.feature_ids).errors
	assert_eq(errs.size(), 4, "; ".join(errs))


func test_angels_gather_once() -> void:
	var s := _s()
	var host := s.rules.feature_index("hex_angel_host")
	OverworldTurn.resolve(s)
	assert_eq(s.feature_row(P(8, 8), host), -1)
	var ev := OverworldTurn.resolve(s)
	assert_ne(s.feature_row(P(8, 8), host), -1, "behaviour data placed the Angels")
	assert_eq(s.vars["angels"], 1)
	assert_eq(_of(ev, &"feature_added").size(), 1)
	var msgs := _of(ev, &"trigger_message")
	assert_eq(msgs.map(func(e: SimEvent) -> int: return e.data["player"]), [1, 2], "a message for every player")
	ev = OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"feature_added").size(), 0, "max_fires 1")
	assert_eq(s.fired["vale_angels_gather"], 1)


func test_answering_an_offer() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(3, 7))
	OverworldTurn.resolve(s)
	var shrine := s.features.id_at(s.feature_row(P(3, 7), s.rules.feature_index("hex_shrine")))
	assert_eq(s.offers.size(), 1, "the shrine is offered")
	assert_eq(OverworldTurn.answer(s, 2, shrine, "accept"), "no such offer")
	assert_eq(OverworldTurn.answer(s, 1, shrine, "pray"), "no such choice")
	assert_eq(OverworldTurn.answer(s, 1, shrine, "accept"), "")
	assert_eq(OverworldTurn.answer(s, 1, shrine, "accept"), "no such offer", "answered once")
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.fired.get("vale_shrine_blessing", 0), 1)
	var msg := _of(ev, &"trigger_message").filter(func(e: SimEvent) -> bool: return e.data["rule"] == "vale_shrine_blessing")
	assert_eq(msg.size(), 1)
	assert_eq(msg[0].data["player"], 1, "$player: the one who answered")
	assert_true(_of(ev, &"value_changed").any(func(e: SimEvent) -> bool: return e.data["amount"] == 5))
	assert_ne(c, -1)


func test_capture_with_where_on_a_hex() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(13, 5))
	OverworldOrders.set_route(s, 1, c, PackedInt64Array([P(14, 5)]))
	OverworldTurn.resolve(s)
	assert_eq(s.vars.get("village_taken", 0), 1)
	assert_eq(s.fired["vale_village_taken"], 1)


func test_session_answer_save_and_replay() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "trigger_vale", 7)
	for i in 2:
		x.ready(1)
		x.ready(2)
	assert_eq(x.state.vars.get("angels", 0), 0)
	for i in 2:
		x.ready(1)
		x.ready(2)
	assert_eq(x.state.vars["angels"], 1)
	var o1 := x.observe(1)
	assert_true((o1["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == &"trigger_message"))
	var loaded := OverworldSession.load_save(x.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.state.vars, x.state.vars)
	var rebuilt := OverworldSession.rebuild(x.save(), _l().templates, _l().data_hash)
	assert_not_null(rebuilt, OverworldSession.last_error)
	assert_eq(x.answer_offer(1, 12345, "accept"), "no such offer")


func test_battle_triggers_unlock_a_zone() -> void:
	var s := BattleSession.create(_l().templates, _l().data_hash, "hangar_drill", 3)
	assert_not_null(s)
	var z := s.state.rules.zone_ids.find("hangar")
	assert_eq(s.state.zone_locked[z], 1)
	for t in 2:
		s.ready(1)
		s.ready(2)
		s.ready(1)
		s.ready(2)
		while s.clock.phase == PulseClock.Phase.REACTION:
			s.ready(1)
			s.ready(2)
	assert_eq(s.state.zone_amount[z], 0, "a locked zone accrues nothing")
	var guard := 0
	while s.state.turn < 3 and guard < 20:
		guard += 1
		s.ready(1)
		s.ready(2)
	assert_eq(s.state.zone_locked[z], 0, "opened on turn 3")
	var seen := (s.observe(2)["events"] as Array).filter(func(e: Dictionary) -> bool: return e["type"] == &"trigger_message")
	assert_eq(seen.size(), 1, "a message to all players")
	var loaded := BattleSession.load_save(s.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded)
	assert_eq(loaded.state.zone_locked[z], 0)
	assert_eq(loaded.state.state_hash(), s.state.state_hash())


func test_end_battle_action() -> void:
	var t := _l().templates
	var defs := [
		{"id": "end_now", "kind": "trigger", "values": {"on": "turn_resolved", "do": [{"do": "end_battle", "winner": 2, "reason": "scripted"}]}}]
	var tt := TemplateTable.build(defs)
	var s := BattleSession.create(t, _l().data_hash, "hangar_drill", 3)
	s.state.rules.triggers = TriggerRules.compile(tt, PackedStringArray(["end_now"]), "battle", s.state.rules.zone_ids)
	var guard := 0
	while not s.is_over() and guard < 10:
		guard += 1
		s.ready(1)
		s.ready(2)
	assert_true(s.is_over())
	assert_eq(s.state.result["winner"], 2)
	assert_eq(s.state.result["reason"], "scripted")


func _battle_with(defs: Array, ids: Array) -> BattleSession:
	var s := BattleSession.create(_l().templates, _l().data_hash, "hangar_drill", 3)
	var tt := TemplateTable.build(_l().defs + defs)
	s.state.rules.triggers = TriggerRules.compile(tt, PackedStringArray(ids), "battle", s.state.rules.zone_ids)
	assert_eq(s.state.rules.triggers.errors.size(), 0, "; ".join(s.state.rules.triggers.errors))
	return s


func _step(s: BattleSession, turns: int) -> void:
	var target := s.state.turn + turns
	var guard := 0
	while s.state.turn < target and not s.is_over() and guard < 40:
		guard += 1
		s.ready(1)
		s.ready(2)


func _live(s: BattleSession, player: int, tid: String) -> int:
	var n := 0
	var st := s.state.rules.squad_index(tid)
	for row in s.state.squads.count():
		if s.state.squads.tmpl[row] == st and s.state.squads.player[row] == player and s.state.squads.is_active(row):
			n += 1
	return n


func test_battle_vocabulary_spawn_remove_score_and_checks() -> void:
	var defs := [
		{"id": "sp", "kind": "trigger", "values": {"on": "turn_resolved", "do": [
			{"do": "spawn_squad", "squad": "scout_team", "player": 1, "x": 10, "y": 30},
			{"do": "add_score", "player": 1, "amount": 7},
			{"do": "add_score", "player": 2, "amount": 3, "score": "influence"}]}},
		{"id": "rm", "kind": "trigger", "values": {"on": "turn_resolved", "if": [{"check": "turn", "value": 2}, {"check": "squad_alive", "squad": "marksman_team", "player": 2, "value": 1}, {"check": "strength", "player": 2, "value": 5}],
			"do": [{"do": "remove_squad", "squad": "marksman_team", "player": 2}, {"do": "set_var", "name": "removed", "value": 1}]}}]
	var s := _battle_with(defs, ["sp", "rm"])
	var before := _live(s, 1, "scout_team")
	_step(s, 1)
	assert_eq(_live(s, 1, "scout_team"), before + 1, "spawned")
	assert_eq(s.state.value_score[1], 7)
	assert_eq(s.state.influence[2], 3)
	_step(s, 1)
	assert_eq(s.state.vars.get("removed", 0), 1)
	assert_eq(_live(s, 2, "marksman_team"), 0)


func test_order_squad_and_squads_in_zone() -> void:
	var defs := [
		{"id": "go", "kind": "trigger", "values": {"on": "turn_resolved", "do": [
			{"do": "order_squad", "squad": "scout_team", "player": 1, "type": "move", "x": 100, "y": 50}]}},
		{"id": "near", "kind": "trigger", "values": {"on": "turn_resolved", "max_fires": 0, "if": [{"check": "squads_in_zone", "zone": "hangar", "player": 1}],
			"do": [{"do": "set_var", "name": "arrived", "value": 1}]}}]
	var s := _battle_with(defs, ["go", "near"])
	_step(s, 1)
	var row := s.state.squads.row_of(s.state.squads.ids()[0])
	var found := false
	for r in s.state.squads.count():
		if s.state.squads.tmpl[r] == s.state.rules.squad_index("scout_team") and s.state.squads.player[r] == 1:
			assert_eq(s.state.squads.order[r], BattleSquads.Order.MOVE)
			found = true
	assert_true(found)
	assert_gt(row, -1)


func test_after_turns_delays_actions_and_saves() -> void:
	var defs := [{"id": "late", "kind": "trigger", "values": {"on": "turn_resolved", "after_turns": 2, "do": [{"do": "set_var", "name": "late", "value": 1}]}}]
	var s := _battle_with(defs, ["late"])
	_step(s, 1)
	assert_false(s.state.vars.has("late"), "not yet")
	assert_eq(s.state.vars.keys().filter(func(k: String) -> bool: return k.begins_with("~due.")).size(), 1)
	var loaded := BattleSession.load_save(s.save(), _l().templates, _l().data_hash)
	assert_eq(loaded.state.vars, s.state.vars)
	_step(s, 3)
	assert_eq(s.state.vars.get("late", 0), 1)
	assert_eq(s.state.vars.keys().filter(func(k: String) -> bool: return k.begins_with("~due.")).size(), 0)


func test_new_action_validation() -> void:
	var t_defs := ([
		{"id": "x", "kind": "trigger", "values": {"on": "turn_resolved", "after_turns": -1, "if": [{"check": "squad_alive", "squad": "nope"}],
			"do": [{"do": "spawn_squad", "squad": "nope"}, {"do": "add_score", "score": "gold"}, {"do": "order_squad", "squad": "nope", "type": "dance"}]}}])
	var errs := TriggerRules.compile(TemplateTable.build(_l().defs + t_defs), PackedStringArray(["x"]), "battle", PackedStringArray()).errors
	assert_eq(errs.size(), 6, "; ".join(errs))
