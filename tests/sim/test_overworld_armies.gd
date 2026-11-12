extends GutTest
## Commanders' armies: own squad, starting armies, caps, recruit, refit and
## trading on a shared hex (GDD 02 §2.3, §2.9, R2Q1, R7Q9). Task sw-o1m.2.1.
## test_vale: village (1,6) of player 1 recruits rifle_squad (6) and
## scout_team (4); supply depot at (6,4) refits for 1 Value per unit.
## field_commander: own rifle_squad + 2 rifle squads, cap 6; outrider: own
## scout_team + 1 scout team, cap 2.

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = OverworldRules.compile(_loader.templates, "test_vale", _loader.data_hash)
	return _rules_cache


func _s() -> OverworldState:
	var s := OverworldState.create(1, _rules(), 7)
	var cache := _rules().feature_index("hex_supply_cache")
	for id in s.features.ids():
		if s.features.get_value(id, &"tmpl") == cache:
			s.remove_feature(id)
	return s


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _of(events: Array[SimEvent], type: StringName) -> Array:
	return events.filter(func(e: SimEvent) -> bool: return e.type == type)


func _sq(id: String) -> int:
	return _rules().squad_index(id)


func test_rules_compile() -> void:
	var r := _rules()
	assert_true(r.is_valid(), "; ".join(r.errors))
	assert_eq(r.sq_size[_sq("rifle_squad")], 8)
	assert_eq(r.sq_size[_sq("scout_team")], 4)
	var fc := r.commander_index("field_commander")
	assert_eq(r.cm_own_squad[fc], _sq("rifle_squad"))
	assert_eq(r.cm_army[fc], PackedInt64Array([_sq("rifle_squad"), _sq("rifle_squad")]))
	assert_eq(r.cm_army_cap[r.commander_index("outrider")], 2)
	var village := r.feature_index("hex_village")
	assert_eq(r.recruit_cost(village, _sq("scout_team")), 4)
	assert_eq(r.recruit_cost(village, _sq("marksman_team")), -1)
	assert_eq(r.hf_refit_cost[r.feature_index("hex_depot")], 1)


func test_commanders_muster_with_their_army() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(4, 8))
	var army := OverworldArmies.view(s, a)
	assert_eq(army.size(), 3)
	assert_true(army[0]["own"], "own squad first")
	assert_eq(army.map(func(q: Dictionary) -> int: return q["alive"]), [8, 8, 8])
	assert_eq(OverworldArmies.count(s, a), 2, "the own squad does not count")
	assert_eq(OverworldArmies.cap(s, a), 6)


func test_recruit_checks() -> void:
	var s := _s()
	var o := Commanders.spawn(s, 1, "outrider", P(1, 6))
	assert_eq(OverworldOrders.set_activity(s, 1, o, "recruit", "marksman_team"), "this hex does not recruit 'marksman_team'")
	assert_eq(OverworldOrders.set_activity(s, 1, o, "recruit", "scout_team"), "recruit costs 4 Value, you have 0")
	s.value[1] = 20
	assert_eq(OverworldOrders.set_activity(s, 1, o, "recruit", "scout_team"), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"squad_recruited").size(), 1)
	assert_eq(OverworldArmies.count(s, o), 2)
	assert_eq(s.value_of(1), 20 - 4 + 2, "paid; the village produced")
	assert_eq(OverworldOrders.set_activity(s, 1, o, "recruit", "scout_team"), "the army is full (2 squads)")


func test_recruit_cancelled_when_the_army_fills_first() -> void:
	var s := _s()
	var o := Commanders.spawn(s, 1, "outrider", P(1, 6))
	var a := Commanders.spawn(s, 1, "field_commander", P(1, 6))
	s.value[1] = 20
	assert_eq(OverworldOrders.set_activity(s, 1, o, "recruit", "scout_team"), "")
	assert_eq(OverworldOrders.transfer_squad(s, 1, OverworldArmies.of(s, a)[1], o), "")
	var ev := OverworldTurn.resolve(s)
	var cancel: Array = _of(ev, &"activity_cancelled")
	assert_eq(cancel.size(), 1)
	assert_eq(cancel[0].data["reason"], "the army is full")
	assert_eq(s.value_of(1), 20 + 2, "nothing paid")


func test_refit() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(6, 5))
	OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(6, 4)]))
	assert_eq(OverworldOrders.set_activity(s, 1, a, "refit"), "the army has no losses to refit")
	var ids := OverworldArmies.of(s, a)
	s.squads.set_value(ids[0], &"alive", 6)
	s.squads.set_value(ids[2], &"alive", 7)
	assert_eq(OverworldArmies.losses(s, a), 3)
	assert_eq(OverworldOrders.set_activity(s, 1, a, "refit"), "refit costs 3 Value, you have 0")
	s.value[1] = 5
	assert_eq(OverworldOrders.set_activity(s, 1, a, "refit"), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"army_refitted")[0].data["units"], 3)
	assert_eq(OverworldArmies.losses(s, a), 0)
	assert_eq(s.value_of(1), 5 - 3 + 2, "paid 3; the village produced")


func test_trading_on_a_shared_hex() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(4, 8))
	var o := Commanders.spawn(s, 1, "outrider", P(4, 8))
	var far := Commanders.spawn(s, 1, "outrider", P(9, 8))
	var e := Commanders.spawn(s, 2, "field_commander", P(4, 8))
	var ids := OverworldArmies.of(s, a)
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[0], o), "a commander's own squad stays with it")
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[1], far), "the commanders must share a hex")
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[1], e), "not your commander")
	assert_eq(OverworldOrders.transfer_squad(s, 2, ids[1], o), "not your squad")
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[1], a), "already in that army")
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[1], o), "")
	assert_eq(OverworldArmies.count(s, o), 2)
	assert_eq(OverworldArmies.count(s, a), 1)
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[2], o), "the receiving army is full (2 squads)")
	assert_eq(OverworldOrders.transfer_squad(s, 1, ids[1], a), "", "and back")


func test_enemy_armies_stay_hidden() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(4, 8))
	var e := Commanders.spawn(s, 2, "field_commander", P(6, 8))
	var obs := OverworldVision.observe(s, 1)
	for c: Dictionary in obs["commanders"]:
		if c["id"] == a:
			assert_eq((c["army"] as Array).size(), 3)
		if c["id"] == e:
			assert_false(c.has("army"), "what a hostile army holds is never shown")
	s.value[2] = 10
	OverworldOrders.set_route(s, 2, e, PackedInt64Array())
	var o := Commanders.spawn(s, 2, "outrider", P(14, 5))
	OverworldOrders.set_activity(s, 2, o, "recruit", "scout_team")
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"squad_recruited").size(), 1)
	assert_eq(_of(OverworldVision.filter_events(s, 1, ev), &"squad_recruited").size(), 0)


func test_session_replays_army_orders() -> void:
	var l := _loader
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var mine := (s.observe(1)["commanders"] as Array).filter(func(c: Dictionary) -> bool: return c["player"] == 1)
	var fc: int = mine[0]["id"]
	var orr: int = mine[1]["id"]
	assert_eq(s.set_route(1, orr, s.path(1, orr, P(2, 6))), "")
	s.ready(1)
	s.ready(2)
	s.ready(1)
	s.ready(2)
	assert_eq(s.phase_name(), "PLANNING")
	var army: Array = (s.observe(1)["commanders"] as Array).filter(func(c: Dictionary) -> bool: return c["id"] == fc)[0]["army"]
	assert_eq(s.transfer_squad(1, army[1]["id"], orr), "")
	s.ready(1)
	s.ready(2)
	assert_eq(OverworldArmies.count(s.state, orr), 2)
	var r := OverworldSession.rebuild(s.save(), l.templates, l.data_hash)
	assert_not_null(r, OverworldSession.last_error)
	assert_eq(r.state.state_hash_hex(), s.state.state_hash_hex())
