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
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
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


## A battle on a producing hex pauses production: progress is held and no
## squad appears on the battle hex. It resumes the turn after the battle ends
## (sw-63wt.12, GDD 02 §2.9).
func test_production_pauses_while_its_hex_is_engaged() -> void:
	var s := _s()
	var fid := _barracks(s)
	_turns(s, 1)
	assert_eq(s.features.get_value(fid, &"progress"), 1)
	var eid := s.engagements.spawn({&"plot": P(8, 7), &"kinds": OverworldEngagements.ACTIVITY, &"turn": s.turn})
	var ev := _turns(s, 3)
	assert_eq(s.features.get_value(fid, &"progress"), 1, "progress is held, not reset or advanced")
	assert_eq(_of(ev, &"squad_produced").size(), 0, "nothing is made while engaged")
	assert_true(Detachments.at(s, P(8, 7)).is_empty(), "no detachment appears on the battle hex")
	OverworldMovement.end_engagement(s, eid)
	ev = _turns(s, 1)
	assert_eq(s.features.get_value(fid, &"progress"), 2, "production resumes the turn after the battle")
	assert_eq(_of(ev, &"squad_produced").size(), 0)
	ev = _turns(s, 1)
	assert_eq(_of(ev, &"squad_produced").size(), 1, "and makes its squad when due")


func test_selecting_output() -> void:
	var s := _s()
	var fid := _barracks(s)
	assert_eq(Convoys.set_output(s, 2, fid, 1), "not your feature")
	assert_eq(Convoys.set_output(s, 1, fid, 5), "no such output")
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
	assert_eq(s.detachments.count(), 1, "the empty shell stays (sw-ll4.26.2)")
	var shell := Detachments.at(s, P(8, 4))[0]
	assert_true(Detachments.squads_of(s, shell).is_empty())
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(shell)), "no route left: it halts there")


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


## A convoy sent to a commander walks to where that commander's route ends,
## not to where it stood (sw-ll4.19).
func test_a_convoy_heads_for_where_its_commander_is_going() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(2, 9))
	var before := OverworldArmies.count(s, a)
	var did := s.detachments.spawn({&"player": 1, &"plot": P(1, 9), &"dest_commander": a})
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": _rules().squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	assert_eq(Convoys.aim(s, did), P(2, 9))
	assert_eq(OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(3, 9), P(4, 9)])), "")
	assert_eq(Convoys.aim(s, did), P(4, 9), "the end of the route it can afford")
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"plot"), P(4, 9))
	assert_true(s.detachments.is_alive(did), "the shell stays after delivery (sw-ll4.26.2)")
	assert_true(Detachments.squads_of(s, did).is_empty(), "it caught up and joined the army")
	assert_eq(s.detachments.get_value(did, &"plot"), P(4, 9))
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(did)), "no route left: it halts there")
	assert_eq(OverworldArmies.count(s, a), before + 1)
	assert_eq(_of(ev, &"convoy_delivered")[0].data["plot"], P(4, 9))


## A commander that walks through the hex of a convoy sent to it picks the
## convoy up there and carries on.
func test_a_commander_picks_up_its_convoy_on_the_way() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(1, 9))
	var before := OverworldArmies.count(s, a)
	var did := s.detachments.spawn({&"player": 1, &"plot": P(2, 9), &"dest_commander": a})
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": _rules().squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	var route := PackedInt64Array()
	var cost := 0
	for col in range(2, 16):
		var c := s.move_cost(P(col, 9))
		if c < 0 or cost + c > Commanders.budget(s, s.commanders.row_of(a)):
			break
		cost += c
		route.append(P(col, 9))
	assert_gt(cost, _rules().convoy_mp, "the commander goes further than a convoy walks in a turn")
	assert_eq(OverworldOrders.set_route(s, 1, a, route), "")
	var end := route[route.size() - 1]
	assert_eq(Convoys.aim(s, did), end)
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"plot"), end, "the commander finished its route")
	assert_true(s.detachments.is_alive(did), "the shell stays after the pickup (sw-ll4.26.2)")
	assert_true(Detachments.squads_of(s, did).is_empty())
	assert_eq(OverworldArmies.count(s, a), before + 1)
	var met: int = _of(ev, &"convoy_delivered")[0].data["plot"]
	assert_ne(met, end, "they met on the way, before the route's end")
	assert_true(route.has(met))
	assert_eq(s.detachments.get_value(did, &"plot"), met, "it halts where it was picked up")
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(did)))


## A delivered convoy with no route left halts on the hex as an empty shell:
## it cannot fight, and a hostile commander seizes its chest (sw-ll4.26.2).
func test_delivery_halts_the_empty_shell_on_the_hex() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(2, 9))
	var did := s.detachments.spawn({&"player": 1, &"plot": P(1, 9), &"dest_commander": a})
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": _rules().squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"convoy_delivered").size(), 1)
	assert_true(s.detachments.is_alive(did), "the shell stays")
	assert_true(Detachments.squads_of(s, did).is_empty())
	assert_eq(s.detachments.get_value(did, &"plot"), P(2, 9))
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(did)), "no route left: it halts")
	var halted := _of(ev, &"convoy_halted")
	assert_eq(halted.size(), 1)
	assert_eq(halted[0].data["reason"], "delivered")
	# The empty shell cannot fight; a hostile commander seizes its chest.
	WarChest.add(s, _rules().item_index("carapace_plates"), 1, -1, did, -1)
	assert_eq(OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(1, 9)])), "")
	var b := Commanders.spawn(s, 2, "field_commander", P(3, 9))
	assert_eq(OverworldOrders.set_route(s, 2, b, PackedInt64Array([P(2, 9)])), "")
	ev = OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"items_seized").size(), 1, "a chest without squads cannot fight")
	assert_eq(s.engagement_at(P(2, 9)), -1)
	assert_false(s.detachments.is_alive(did), "seized: the shell is disbanded")


## A delivered convoy with a steered route left keeps walking it
## (sw-ll4.26.2): delivery hands over the load, not the movement order.
func test_delivery_continues_a_steered_route() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(2, 9))
	var before := OverworldArmies.count(s, a)
	var did := s.detachments.spawn({&"player": 1, &"plot": P(1, 9), &"dest_commander": a})
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": _rules().squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	assert_eq(Convoys.set_route(s, 1, did, PackedInt64Array([P(2, 9), P(3, 9), P(4, 9)])), "")
	s.detachments.set_value(did, &"dest_commander", a)  # steered and sent to the commander
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"convoy_delivered").size(), 1)
	assert_eq(OverworldArmies.count(s, a), before + 1)
	assert_true(s.detachments.is_alive(did), "the shell stays")
	assert_true(Detachments.squads_of(s, did).is_empty())
	assert_eq(s.detachments.get_value(did, &"plot"), P(2, 9))
	assert_eq(s.detachments.get_value(did, &"dest_commander"), -1, "delivery done")
	assert_true(Convoys.is_convoy(s, s.detachments.row_of(did)), "the route left is its own order")
	assert_eq(s.convoy_routes[did], PackedInt64Array([P(3, 9), P(4, 9)]), "walked plots leave the route")
	ev = OverworldTurn.resolve(s)
	assert_gt(_of(ev, &"convoy_moved").size(), 0, "it walks on")
	assert_eq(s.detachments.get_value(did, &"plot"), P(4, 9))
	assert_eq(_of(ev, &"convoy_arrived").size(), 1)
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(did)), "route done: a garrison again")


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


# --- steering convoys by hand (sw-kys.8) -------------------------------------

## A player-1 garrison at (5,8): a field commander drops its battleforce.
func _garrison(s: OverworldState) -> int:
	var cid := Commanders.spawn(s, 1, "field_commander", P(5, 8))
	return Detachments.drop(s, cid, P(5, 8))


func _route_via(s: OverworldState, from: int, stops: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for to: int in stops:
		out.append_array(OverworldPath.find(s, from, to, 1))
		from = to
	return out


func test_a_steered_garrison_walks_its_route_and_takes_nothing() -> void:
	var s := _s()
	var did := _garrison(s)
	var barracks := s.features.id_at(s.feature_row(P(8, 7), _rules().feature_index("hex_barracks")))
	var mine := s.features.id_at(s.feature_row(P(8, 9), _rules().feature_index("hex_mine")))
	var route := _route_via(s, P(5, 8), [P(8, 7), P(8, 9)])
	assert_eq(Convoys.set_route(s, 1, did, route), "")
	assert_true(Convoys.is_convoy(s, s.detachments.row_of(did)), "routing a garrison makes it a convoy")
	_turns(s, 1)
	var row := s.detachments.row_of(did)
	assert_ne(s.detachments.plot[row], P(5, 8), "it moved")
	assert_lt((s.convoy_routes.get(did, PackedInt64Array()) as PackedInt64Array).size(), route.size(), "walked plots leave the route")
	_turns(s, 3)
	row = s.detachments.row_of(did)
	assert_eq(s.detachments.plot[row], P(8, 9), "through the waypoint to the end")
	assert_false(Convoys.is_convoy(s, row), "arrived: a garrison again")
	assert_false(s.convoy_routes.has(did))
	assert_eq(s.features.get_value(barracks, &"owner"), 0, "convoys take no features on the way")
	assert_eq(s.features.get_value(mine, &"owner"), 0, "nor where they stop")


func test_steering_checks_and_halts() -> void:
	var s := _s()
	var did := _garrison(s)
	assert_eq(Convoys.set_route(s, 2, did, PackedInt64Array([P(6, 8)])), "not your detachment")
	assert_eq(Convoys.set_route(s, 1, did, PackedInt64Array([P(9, 8)])), "the route must be a chain of neighbouring hexes")
	assert_eq(Convoys.set_route(s, 1, did, _route_via(s, P(5, 8), [P(9, 9)])), "")
	var snap := s.snapshot()
	var t := OverworldState.create(1, _rules(), 7)
	t.restore(snap)
	assert_eq(t.convoy_routes, s.convoy_routes, "saves keep steered routes")
	assert_eq(t.state_hash(), s.state_hash())
	assert_eq(Convoys.rally(s, 1, did, P(1, 6), -1), "")
	assert_false(s.convoy_routes.has(did), "a rally replaces the hand route")
	assert_eq(Convoys.set_route(s, 1, did, PackedInt64Array()), "")
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(did)), "an empty route halts it")
