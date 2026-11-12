extends GutTest
## Production, supply lines and convoys (GDD 02 §2.9, R5Q10, R6Q13, R8Q3).
## Task sw-o1m.2.5. test_vale: barracks (8,7) produces a rifle squad every
## 3 turns for 2 Value, or a scout team every 2 turns for 1; convoys move
## 40 points a turn; plains cost 10; bandit camp (11,3) is guarded.

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


## The barracks, given to player 1 with Value to spend.
func _barracks(s: OverworldState) -> int:
	var row := s.feature_row(P(8, 7), _rules().feature_index("hex_barracks"))
	var fid := s.features.id_at(row)
	s.features.set_value(fid, &"owner", 1)
	s.add_value(1, 20, &"test")
	return fid


func _turns(s: OverworldState, n: int) -> Array:
	var ev := []
	for i in n:
		ev.append_array(OverworldTurn.resolve(s))
	return ev


func test_production_fills_a_garrison() -> void:
	var s := _s()
	var fid := _barracks(s)
	var before := s.value_of(1)
	_turns(s, 2)
	assert_eq(s.features.get_value(fid, &"progress"), 2)
	assert_true(Detachments.at(s, P(8, 7)).is_empty())
	var ev := _turns(s, 1)
	assert_eq(_of(ev, &"squad_produced").size(), 1)
	var dets := Detachments.at(s, P(8, 7))
	assert_eq(dets.size(), 1, "with no supply line it holds the barracks")
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(dets[0])))
	assert_eq(s.features.get_value(fid, &"progress"), 0)
	var paid := _of(ev, &"value_changed").filter(func(e: SimEvent) -> bool: return e.data["amount"] == -2)
	assert_eq(paid.size(), 1, "the squad costs 2 Value")
	assert_true(s.value_of(1) >= before - 2)
	# Without the Value it waits, ready to go.
	for id in s.features.ids():
		if id != fid:
			s.features.set_value(id, &"owner", 0)
	s.value[1] = 0
	_turns(s, 4)
	assert_eq(Detachments.squads_of(s, dets[0]).size(), 1)
	assert_eq(s.features.get_value(fid, &"progress"), 3)


func test_selecting_output() -> void:
	var s := _s()
	var fid := _barracks(s)
	assert_eq(Convoys.set_output(s, 2, fid, 1), "not your feature")
	assert_eq(Convoys.set_output(s, 1, fid, 3), "no such output")
	var depot := s.features.id_at(s.feature_row(P(6, 4), _rules().feature_index("hex_depot")))
	s.features.set_value(depot, &"owner", 1)
	assert_eq(Convoys.set_output(s, 1, depot, 0), "this feature produces nothing")
	assert_eq(Convoys.set_output(s, 1, fid, 1), "")
	_turns(s, 2)
	var held := Detachments.squads_of(s, Detachments.at(s, P(8, 7))[0])
	assert_eq(s.squads.get_value(held[0], &"tmpl"), _rules().squad_index("scout_team"))


func test_supply_line_to_a_plot() -> void:
	var s := _s()
	var fid := _barracks(s)
	assert_eq(Convoys.set_line(s, 1, fid, P(8, 4), -1), "")
	var ev := _turns(s, 3)
	var convoys := Convoys.ids(s)
	assert_eq(convoys.size(), 1, "the squad leaves as a convoy")
	assert_eq(s.detachments.get_value(convoys[0], &"line"), fid)
	ev = _turns(s, 1)
	assert_gt(_of(ev, &"convoy_moved").size(), 0)
	assert_eq(_of(ev, &"convoy_arrived").size(), 1)
	assert_eq(Convoys.ids(s).size(), 0)
	assert_eq(Detachments.at(s, P(8, 4)).size(), 1, "it holds its destination")


func test_supply_line_to_a_commander() -> void:
	var s := _s()
	var fid := _barracks(s)
	var a := Commanders.spawn(s, 1, "field_commander", P(8, 4))
	assert_eq(Convoys.set_line(s, 2, fid, -1, a), "not your feature")
	assert_eq(Convoys.set_line(s, 1, fid, -1, a), "")
	var ev := _turns(s, 4)
	var got := _of(ev, &"convoy_delivered")
	assert_eq(got.size(), 1)
	assert_eq(OverworldArmies.count(s, a), 3, "two rifle squads plus the delivered one")
	assert_eq(s.detachments.count(), 0)


func test_convoys_route_around_known_guards() -> void:
	var s := _s()
	Commanders.spawn(s, 1, "field_commander", P(12, 3))
	OverworldVision.update(s)
	var mask := Convoys.guarded_mask(s, 1)
	assert_eq(mask[P(11, 3)], 1)
	var path := OverworldPath.find(s, P(10, 3), P(12, 3), 1, mask)
	assert_false(path.has(P(11, 3)))
	assert_eq(OverworldPath.find(s, P(10, 3), P(12, 3), 1).size(), 2, "commanders still walk through")


func test_a_convoy_is_intercepted() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	OverworldOrders.set_drop_off(s, 1, a, -1, P(0, 0))
	OverworldTurn.resolve(s)
	var did := Detachments.at(s, P(0, 0))[0]
	var b := Commanders.spawn(s, 2, "field_commander", P(2, 0))
	assert_eq(Convoys.rally(s, 2, did, P(3, 0), -1), "not your detachment")
	assert_eq(Convoys.rally(s, 1, did, P(3, 0), -1), "")
	OverworldTurn.resolve(s)
	assert_eq(s.detachments.get_value(did, &"plot"), P(2, 0), "stopped where it met the enemy")
	var eid := s.engagement_at(P(2, 0))
	assert_ne(eid, -1)
	assert_eq(s.detachments.get_value(did, &"engagement"), eid)
	assert_eq(s.commanders.get_value(b, &"engagement"), eid)
	assert_eq(Convoys.rally(s, 1, did, P(4, 0), -1), "is in a battle")


func test_convoys_on_one_line_merge() -> void:
	var s := _s()
	var fid := _barracks(s)
	var rifle := _rules().squad_index("rifle_squad")
	var ids := []
	for i in 2:
		var did := s.detachments.spawn({&"player": 1, &"plot": P(5, 5), &"dest_plot": P(0, 11), &"line": fid})
		s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": rifle, &"alive": 8, &"size": 8})
		ids.append(did)
	Convoys.settle(s)
	assert_eq(Convoys.ids(s), PackedInt64Array([ids[0]]))
	assert_eq(Detachments.squads_of(s, ids[0]).size(), 2)
	assert_eq(_of(s.events.drain(), &"convoys_merged").size(), 1)


func test_survivors_of_a_commander_that_left_rally_to_it() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	OverworldBattleforce.set_plan(s, 1, c, "", PackedInt64Array(), false)
	OverworldOrders.set_route(s, 1, c, PackedInt64Array([P(11, 3)]))
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	var errs := PackedStringArray()
	var b := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_eq(OverworldOrders.leave_battle(s, 1, c), "")
	OverworldOrders.set_route(s, 1, c, PackedInt64Array([P(12, 4)]))
	OverworldTurn.resolve(s)
	b.state.result = {"winner": 1, "reason": "annihilation", "turn": 3, "scores": {}, "survivors": {}}
	OverworldBattles.finish(s, b)
	var convoys := Convoys.ids(s)
	assert_eq(convoys.size(), 1)
	assert_eq(s.detachments.get_value(convoys[0], &"dest_commander"), c)
	assert_eq(s.detachments.get_value(convoys[0], &"plot"), P(11, 3))
	assert_eq(OverworldArmies.count(s, c), 0)
	OverworldTurn.resolve(s)
	assert_eq(OverworldArmies.count(s, c), 2, "the convoy reached it")


func test_capture_resets_production_and_the_line() -> void:
	var s := _s()
	var fid := _barracks(s)
	Convoys.set_output(s, 1, fid, 1)
	Convoys.set_line(s, 1, fid, P(8, 4), -1)
	OverworldTurn.resolve(s)
	var b := Commanders.spawn(s, 2, "field_commander", P(9, 7))
	OverworldOrders.set_route(s, 2, b, PackedInt64Array([P(8, 7)]))
	OverworldTurn.resolve(s)
	assert_eq(s.features.get_value(fid, &"owner"), 2)
	assert_false(s.supply_lines.has(fid))
	assert_eq(s.features.get_value(fid, &"output"), 0)
	assert_eq(s.features.get_value(fid, &"progress"), 1, "it starts over for its new owner")


func test_fog_and_session() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var fid := _barracks(x.state)
	assert_eq(x.set_output(1, fid, 1), "")
	assert_eq(x.set_supply_line(1, fid, P(8, 4)), "")
	for i in 3:
		x.ready(1)
		x.ready(2)
	var o := x.observe(1)
	assert_true((o["production"] as Dictionary).has(fid))
	assert_eq((o["supply_lines"] as Dictionary)[fid]["plot"], P(8, 4))
	assert_eq(x.observe(2)["production"], {}, "only the owner sees its production")
	var dets: Array = o["detachments"]
	assert_gt(dets.size(), 0)
	var loaded := OverworldSession.load_save(x.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.state_hash_hex(), x.state_hash_hex())
	var kinds := x.input_log.map(func(i: Dictionary) -> String: return i["kind"])
	assert_true(kinds.has("output") and kinds.has("supply"))
