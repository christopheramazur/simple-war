extends GutTest
## Drop-offs and detachments (GDD 02 §2.3, §2.9, R2Q1, R4Q13, R5Q9, R7Q8).
## Task sw-o1m.2.4. test_vale: plains cost 10, field_commander 60 MP with
## its own rifle squad + 2 rifle squads; battleforce cap 3 squads / 250
## strength, so a drop-off (own squad kept out) is both rifle squads.
## Bandit camp (11,3) guarded; depot (6,4) controllable; lakes (7,2), (8,2).

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_rules_cache = OverworldRules.compile(_l().templates, "test_vale", _l().data_hash)
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


func _of(events: Array, type: StringName) -> Array:
	return events.filter(func(e: Variant) -> bool:
		return (e.type if e is SimEvent else StringName(e["type"])) == type)


func _row0(n: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for i in range(1, n + 1):
		out.append(P(i, 0))
	return out


func test_drop_off_planning_checks() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	assert_eq(OverworldOrders.set_drop_off(s, 1, a, 0, P(1, 0)), "step 1 is not on the route")
	assert_eq(OverworldOrders.set_drop_off(s, 2, a, -1, P(0, 0)), "not your commander")
	assert_eq(OverworldOrders.set_drop_off(s, 1, a, -1, P(2, 0)), "a battleforce is dropped on the route or 1 hex off it")
	assert_eq(OverworldOrders.set_route(s, 1, a, _row0(6)), "")
	assert_eq(OverworldOrders.set_drop_off(s, 1, a, 5, P(6, 1)), "needs 70 movement points, has 60",
		"a hex off the route costs its movement")
	assert_eq(OverworldOrders.set_drop_off(s, 1, a, 5, P(6, 0)), "", "on the route it is free")
	# A shorter route that no longer reaches step 6 drops the plan.
	assert_eq(OverworldOrders.set_route(s, 1, a, _row0(3)), "")
	assert_false(s.drops.has(a))
	var b := Commanders.spawn(s, 1, "field_commander", P(7, 3))
	assert_eq(OverworldOrders.set_drop_off(s, 1, b, -1, P(7, 2)), "that hex is impassable")
	for id in OverworldArmies.of(s, b):
		if s.squads.get_value(id, &"own") == 0:
			s.squads.set_value(id, &"alive", 0)
	assert_eq(OverworldOrders.set_drop_off(s, 1, b, -1, P(7, 3)),
		"the battleforce has no squads to drop off (the commander's own squad stays)")


func test_drop_on_the_route_and_move_on() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	OverworldOrders.set_route(s, 1, a, _row0(3))
	assert_eq(OverworldOrders.set_drop_off(s, 1, a, 0, P(1, 1)), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"plot"), P(3, 0), "the commander moves on")
	assert_eq(s.drops, {}, "drop-offs are cleared with the turn")
	var dets := Detachments.at(s, P(1, 1))
	assert_eq(dets.size(), 1)
	var held := Detachments.squads_of(s, dets[0])
	assert_eq(held.size(), 2, "both rifle squads; the own squad stays")
	assert_eq(OverworldArmies.count(s, a), 0)
	assert_eq(OverworldArmies.of(s, a).size(), 1)
	assert_eq(s.engagements.count(), 0, "nothing to fight there")
	var types := ev.map(func(e: SimEvent) -> StringName: return e.type)
	var dropped := types.find(&"battleforce_dropped")
	assert_true(dropped > types.find(&"commander_moved") and dropped < types.rfind(&"commander_moved"),
		"dropped after step 1, before the later steps")


func test_drop_onto_guards_fights_without_the_commander() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	assert_eq(OverworldOrders.set_drop_off(s, 1, a, -1, P(11, 3)), "")
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	assert_ne(eid, -1, "the guard engages the detachment")
	assert_eq(s.commanders.get_value(a, &"engagement"), -1, "the commander stays free")
	var did := Detachments.at(s, P(11, 3))[0]
	assert_eq(s.detachments.get_value(did, &"engagement"), eid)
	assert_eq(OverworldBattleforce.deployed_in(s, eid), Detachments.squads_of(s, did))
	# A battle tile takes no drop-offs.
	var b := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	assert_eq(OverworldOrders.set_drop_off(s, 1, b, -1, P(11, 3)), "a battleforce cannot be dropped onto a battle")
	var errs := PackedStringArray()
	var battle := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_eq(errs, PackedStringArray())
	assert_eq(battle.state.players, PackedInt64Array([1, OverworldBattles.NEUTRAL]))
	battle.state.result = {"winner": 1, "reason": "annihilation", "turn": 3, "scores": {}, "survivors": {}}
	OverworldBattles.finish(s, battle)
	assert_true(s.guard_at(P(11, 3)).is_empty(), "the guard is cleared")
	assert_true(s.detachments.is_alive(did), "the detachment holds the hex")
	assert_eq(s.detachments.get_value(did, &"engagement"), -1)
	assert_eq(s.squads.get_value(Detachments.squads_of(s, did)[0], &"deployed"), -1)


func test_a_beaten_detachment_scatters() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	OverworldOrders.set_drop_off(s, 1, a, -1, P(11, 3))
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	var did := Detachments.at(s, P(11, 3))[0]
	var errs := PackedStringArray()
	var battle := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	battle.state.result = {"winner": OverworldBattles.NEUTRAL, "reason": "influence", "turn": 8, "scores": {}, "survivors": {}}
	s.events.drain()
	OverworldBattles.finish(s, battle)
	assert_false(s.detachments.is_alive(did))
	assert_eq(s.squads.count(), 1, "only the commander's own squad is left")
	assert_eq(_of(s.events.drain(), &"detachment_disbanded")[0].data["reason"], "defeated")
	assert_eq(s.guard_at(P(11, 3)).size(), 2)


func test_a_garrison_must_be_engaged_first() -> void:
	var s := _s()
	var depot := P(6, 4)
	var n := Hex.neighbours(depot, W, 12)
	var a := Commanders.spawn(s, 1, "field_commander", n[0])
	OverworldOrders.set_drop_off(s, 1, a, -1, depot)
	OverworldTurn.resolve(s)
	var did := Detachments.at(s, depot)[0]
	var f := s.features_at(depot)
	var owner_of := func() -> int:
		for row in s.features_at(depot):
			if s.rules.hf_controllable[s.features.tmpl[row]] == 1:
				return s.features.owner[row]
		return -1
	assert_eq(owner_of.call(), 0, "a detachment never takes features")
	assert_false(f.is_empty())
	var b := Commanders.spawn(s, 2, "field_commander", n[n.size() - 1])
	assert_eq(OverworldOrders.set_route(s, 2, b, PackedInt64Array([depot])), "")
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(depot)
	assert_ne(eid, -1)
	assert_eq(s.engagements.get_value(eid, &"kinds"), OverworldEngagements.DETACHMENTS)
	assert_eq(s.commanders.get_value(b, &"engagement"), eid)
	assert_eq(owner_of.call(), 0, "no capture before the engagement is won")
	var errs := PackedStringArray()
	var battle := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_eq(battle.state.players, PackedInt64Array([1, 2]))
	battle.state.result = {"winner": 2, "reason": "annihilation", "turn": 4, "scores": {}, "survivors": {}}
	OverworldBattles.finish(s, battle)
	assert_false(s.detachments.is_alive(did))
	assert_eq(owner_of.call(), 2, "the winner takes the depot")


func test_pick_up_from_a_detachment() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	OverworldOrders.set_drop_off(s, 1, a, -1, P(0, 0))
	OverworldTurn.resolve(s)
	var did := Detachments.at(s, P(0, 0))[0]
	var held := Detachments.squads_of(s, did)
	var c := Commanders.spawn(s, 1, "field_commander", P(1, 0))
	assert_eq(OverworldOrders.transfer_squad(s, 1, held[0], c), "the commander must be on the detachment's hex")
	assert_eq(OverworldOrders.transfer_squad(s, 2, held[0], a), "not your squad")
	assert_eq(OverworldOrders.transfer_squad(s, 1, held[0], a), "")
	assert_true(s.detachments.is_alive(did))
	assert_eq(OverworldOrders.transfer_squad(s, 1, held[1], a), "")
	assert_false(s.detachments.is_alive(did), "an empty detachment is gone")
	assert_eq(OverworldArmies.count(s, a), 2)
	var ev := s.events.drain()
	assert_eq(_of(ev, &"squad_picked_up").size(), 2)
	assert_eq(_of(ev, &"detachment_disbanded")[0].data["reason"], "picked_up")


func test_detachments_in_the_fog() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	OverworldOrders.set_route(s, 1, a, _row0(6))
	OverworldOrders.set_drop_off(s, 1, a, -1, P(0, 0))
	Commanders.spawn(s, 2, "outrider", P(3, 2))
	var ev := OverworldTurn.resolve(s)
	assert_eq(OverworldVision.sight(s, 1)[P(0, 1)], 1, "a detachment is a sight source")
	var mine: Array = OverworldVision.observe(s, 1)["detachments"]
	assert_eq(mine.size(), 1)
	assert_eq((mine[0]["squads"] as Array).size(), 2)
	var theirs: Array = OverworldVision.observe(s, 2)["detachments"]
	assert_eq(theirs.size(), 1)
	assert_false(theirs[0].has("squads"), "what a hostile detachment holds is hidden")
	var seen := _of(OverworldVision.filter_events(s, 2, ev), &"battleforce_dropped")
	assert_eq(seen.size(), 1)
	assert_eq(seen[0].data.keys(), ["detachment", "player", "plot"])
	var own := _of(OverworldVision.filter_events(s, 1, ev), &"battleforce_dropped")
	assert_true(own[0].data.has("squads"))


func test_session_drop_off_saves_and_replays() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var fc := -1
	for row in x.state.commanders.count():
		if x.state.commanders.player[row] == 1 and Commanders.name_of(x.state, row) == "Field commander":
			fc = x.state.commanders.id_at(row)
	var at := x.state.commanders.get_value(fc, &"plot")
	assert_eq(x.set_drop_off(1, fc, -1, at), "")
	x.ready(1)
	x.ready(2)
	assert_eq((x.observe(1)["detachments"] as Array).size(), 1)
	assert_eq(x.input_log.filter(func(i: Dictionary) -> bool: return i["kind"] == "drop").size(), 1)
	var loaded := OverworldSession.load_save(x.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.state_hash_hex(), x.state_hash_hex())
	assert_eq(loaded.state.detachments.count(), 1)
