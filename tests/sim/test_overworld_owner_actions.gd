extends GutTest
## Owner actions: remote buys at owned features (U1Q24, GDD 02 §2.9).
## Task sw-63wt.9. test_vale: barracks (8,7) recruits assault squads and
## mortar teams for 7 (9 remote, 25% rounded up); depot (6,4) sells one camo
## netting for 8 (10 remote); player 1's village (1,6) recruits rifle squads
## for 6 (8) and scout teams for 4 (5); player 2's village is at (14,5).

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
	return events.filter(func(e: SimEvent) -> bool: return e.type == type)


func _feature(s: OverworldState, col: int, row: int, id: String) -> int:
	return s.features.id_at(s.feature_row(P(col, row), _rules().feature_index(id)))


## A feature given to `player`.
func _own(s: OverworldState, col: int, row: int, id: String, player: int = 1) -> int:
	var fid := _feature(s, col, row, id)
	s.features.set_value(fid, &"owner", player)
	return fid


func _spent(events: Array, player: int) -> int:
	var n := 0
	for e: SimEvent in _of(events, &"value_changed"):
		if e.data["source"] == &"owner_action" and e.data["player"] == player:
			n -= int(e.data["amount"])
	return n


func _cancel_reasons(events: Array) -> Array:
	return _of(events, &"owner_action_cancelled").map(func(e: SimEvent) -> String: return e.data["reason"])


func test_rules_compile_owner_actions() -> void:
	var r := _rules()
	var barracks := r.feature_index("hex_barracks")
	var depot := r.feature_index("hex_depot")
	assert_true(r.has_owner_action(barracks, "buy"))
	assert_true(r.has_owner_action(barracks, "output"))
	assert_true(r.has_owner_action(depot, "buy"))
	assert_false(r.has_owner_action(depot, "rally"))
	assert_false(r.has_owner_action(r.feature_index("hex_mine"), "buy"))
	assert_eq(r.hf_markup[barracks], 25)
	assert_eq(r.hf_buys[barracks], 1)
	assert_eq(Array(r.buy_option(depot, "camo_netting")), [-1, r.item_index("camo_netting"), 1, 10])
	assert_true(r.buy_option(depot, "rifle_squad").is_empty())


func test_markup_rounds_up() -> void:
	var r := _rules()
	var b := r.feature_index("hex_barracks")
	assert_eq(r.remote_price(b, 7), 9, "8.75 rounds up")
	assert_eq(r.remote_price(b, 8), 10, "exact")
	assert_eq(r.remote_price(b, 4), 5)
	assert_eq(r.remote_price(b, 1), 2, "1.25 rounds up")
	assert_eq(r.remote_price(b, 0), 0)


func test_buy_with_no_line_joins_the_garrison() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"squad_bought").size(), 1)
	assert_eq(_spent(ev, 1), 9, "7 plus 25%, rounded up")
	var dets := Detachments.at(s, P(8, 7))
	assert_eq(dets.size(), 1)
	var row := s.detachments.row_of(dets[0])
	assert_false(Convoys.is_convoy(s, row))
	assert_true(OverworldStats.is_garrison(s, row))
	var sq := Detachments.squads_of(s, dets[0])
	assert_eq(sq.size(), 1)
	assert_eq(s.squads.get_value(sq[0], &"tmpl"), _rules().squad_index("assault_squad"))
	assert_true(s.owner_orders.is_empty(), "orders are used up")


func test_buy_with_a_line_leaves_as_a_caravan() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	assert_eq(Convoys.set_line(s, 1, fid, P(0, 11), -1), "")
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "mortar_team"), "")
	OverworldTurn.resolve(s)
	var dets := Detachments.at(s, P(8, 7))
	assert_eq(dets.size(), 1, "it waits on the hex this turn")
	var row := s.detachments.row_of(dets[0])
	assert_true(Convoys.is_convoy(s, row))
	assert_eq(s.detachments.line[row], fid)
	assert_eq(s.detachments.dest_plot[row], P(0, 11))
	assert_eq(s.detachments.band[row], _rules().band_caravan)
	OverworldTurn.resolve(s)
	assert_true(Detachments.at(s, P(8, 7)).is_empty(), "and leaves next turn")


func test_items_go_into_the_garrison_chest() -> void:
	var s := _s()
	var fid := _own(s, 6, 4, "hex_depot")
	s.value[1] = 10
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "camo_netting"), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"item_bought").size(), 1)
	assert_eq(_spent(ev, 1), 10)
	var dets := Detachments.at(s, P(6, 4))
	assert_eq(dets.size(), 1)
	assert_eq(WarChest.count_of(s, _rules().item_index("camo_netting"), -1, dets[0], -1), 1)


func test_planning_refusals() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	var mine := _feature(s, 8, 9, "hex_mine")
	s.value[1] = 5
	assert_eq(OverworldOrders.set_owner_action(s, 2, fid, "buy", "assault_squad"), "not your feature")
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "trade", "x"), "unknown owner action 'trade'")
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "rifle_squad"), "this feature does not sell 'rifle_squad'")
	assert_string_contains(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "costs 9 Value, you have 5")
	s.features.set_value(mine, &"owner", 1)
	assert_eq(OverworldOrders.set_owner_action(s, 1, mine, "buy", "assault_squad"), "this feature does not allow buy")
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "output", "1"), "")
	assert_eq(s.features.get_value(fid, &"output"), 1, "output goes through Convoys.set_output")
	assert_true(s.owner_orders.is_empty())


func test_limit_one_buy_a_turn_per_feature() -> void:
	var s := _s()
	var barracks := _own(s, 8, 7, "hex_barracks")
	var depot := _own(s, 6, 4, "hex_depot")
	s.value[1] = 50
	assert_eq(OverworldOrders.set_owner_action(s, 1, barracks, "buy", "assault_squad"), "")
	assert_eq(OverworldOrders.set_owner_action(s, 1, barracks, "buy", "mortar_team"), "this feature takes 1 buy a turn")
	assert_eq(OverworldOrders.set_owner_action(s, 1, depot, "buy", "camo_netting"), "", "the limit is per feature")
	# Clearing frees the slot.
	assert_eq(OverworldOrders.set_owner_action(s, 1, barracks, "buy", ""), "")
	assert_eq(OverworldOrders.set_owner_action(s, 1, barracks, "buy", "mortar_team"), "")
	# The resolver holds the limit too, against orders that skip planning.
	s.owner_orders[barracks]["buys"] = PackedStringArray(["mortar_team", "assault_squad"])
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"squad_bought").size(), 1)
	assert_eq(_of(ev, &"item_bought").size(), 1)
	assert_eq(_cancel_reasons(ev), [OverworldOwnerActions.LIMIT])


func test_captured_during_movement_cancels() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	var enemy := Commanders.spawn(s, 2, "field_commander", P(9, 7))
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	assert_eq(OverworldOrders.set_route(s, 2, enemy, PackedInt64Array([P(8, 7)])), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.features.get_value(fid, &"owner"), 2)
	assert_eq(_of(ev, &"squad_bought").size(), 0)
	assert_eq(_cancel_reasons(ev), [OverworldOwnerActions.NOT_YOURS])
	assert_eq(_spent(ev, 1), 0, "nothing is paid")


func test_engaged_hex_cancels() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	s.engagements.spawn({&"plot": P(8, 7), &"kinds": OverworldEngagements.ACTIVITY, &"turn": s.turn})
	var ev := OverworldTurn.resolve(s)
	assert_eq(_cancel_reasons(ev), [OverworldOwnerActions.ENGAGED])
	assert_eq(_spent(ev, 1), 0)


func test_hostile_commander_on_the_hex_contests_it() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	var enemy := Commanders.spawn(s, 2, "outrider", P(8, 7))
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.engagement_at(P(8, 7)), -1, "no battle: the owner has no force there")
	assert_eq(_cancel_reasons(ev), [OverworldOwnerActions.CONTESTED])
	assert_eq(_spent(ev, 1), 0)
	# Fog-safe: the reason and the event name nothing that contests the hex.
	var seen := _of(OverworldVision.filter_events(s, 1, ev), &"owner_action_cancelled")
	assert_eq(seen.size(), 1)
	var data: Dictionary = seen[0].data
	assert_eq(data["reason"], "contested")
	for v: Variant in data.values():
		if v is int:
			assert_ne(v, enemy, "the enemy commander is not named")
	assert_eq(_of(OverworldVision.filter_events(s, 2, ev), &"owner_action_cancelled").size(), 0,
		"the enemy does not see the cancelled buy")


func test_hostile_band_with_squads_contests_the_hex() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	var did := s.detachments.spawn({&"player": 2, &"plot": P(8, 7)})
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	# An empty shell does not contest.
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"squad_bought").size(), 1)
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": _rules().squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	assert_true(OverworldOwnerActions.contested(s, 1, P(8, 7)))
	assert_true(OverworldOwnerActions.contested(s, 2, P(8, 7)), "player 1's bought garrison holds the hex too")
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	# Without a hostile force of the owner's there, no battle starts: the buy is cancelled.
	ev = OverworldTurn.resolve(s)
	assert_eq(_cancel_reasons(ev), [OverworldOwnerActions.ENGAGED if s.engagement_at(P(8, 7)) >= 0 else OverworldOwnerActions.CONTESTED])


## Players in seat order, each player's features by ascending ID; Value is
## paid as each buy resolves, so the later buys find it spent.
func test_resolution_order_with_buys_short_of_value() -> void:
	var s := _s()
	var village := _feature(s, 1, 6, "hex_village")
	var barracks := _own(s, 8, 7, "hex_barracks")
	var depot := _own(s, 6, 4, "hex_depot")
	var enemy_village := _feature(s, 14, 5, "hex_village")
	s.value[1] = 10
	s.value[2] = 10
	var cost := {village: 5, barracks: 9, depot: 10}
	assert_eq(OverworldOrders.set_owner_action(s, 1, depot, "buy", "camo_netting"), "")
	assert_eq(OverworldOrders.set_owner_action(s, 1, barracks, "buy", "assault_squad"), "")
	assert_eq(OverworldOrders.set_owner_action(s, 1, village, "buy", "scout_team"), "")
	assert_eq(OverworldOrders.set_owner_action(s, 2, enemy_village, "buy", "rifle_squad"), "")
	# The expected outcome: walk player 1's features by ascending ID.
	var fids := [village, barracks, depot]
	fids.sort()
	var left := 10
	var bought := []
	var cancelled := []
	for fid: int in fids:
		if left >= cost[fid]:
			left -= cost[fid]
			bought.append(fid)
		else:
			cancelled.append(fid)
	assert_false(cancelled.is_empty(), "the test needs some buys short of Value")
	var ev := OverworldTurn.resolve(s)
	var order := []
	for e: SimEvent in ev:
		if e.type in [&"squad_bought", &"item_bought", &"owner_action_cancelled"]:
			order.append([e.data["player"], e.data["feature"], e.type != &"owner_action_cancelled"])
	var want := []
	for fid: int in fids:
		want.append([1, fid, bought.has(fid)])
	want.append([2, enemy_village, true])
	assert_eq(order, want)
	assert_eq(_spent(ev, 1), 10 - left)
	assert_eq(_spent(ev, 2), 8)
	for e: SimEvent in _of(ev, &"owner_action_cancelled"):
		assert_eq(e.data["reason"], OverworldOwnerActions.NO_VALUE)


func test_owner_orders_saved_hashed_and_old_saves_load() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	var before := s.state_hash_hex()
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	assert_ne(s.state_hash_hex(), before, "planned buys are hashed")
	var snap := s.snapshot()
	var t := OverworldState.new(1, _rules(), 7)
	t.restore(snap)
	assert_eq(t.state_hash_hex(), s.state_hash_hex())
	assert_eq(Array(t.owner_orders[fid]["buys"]), ["assault_squad"])
	(snap["overworld"] as Dictionary).erase("owner_orders")
	var old := OverworldState.new(1, _rules(), 7)
	old.restore(snap)
	assert_eq(old.owner_orders, {}, "a save from before owner actions has none")


func test_observe_lists_own_owner_orders_only() -> void:
	var s := _s()
	var fid := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 20
	assert_eq(OverworldOrders.set_owner_action(s, 1, fid, "buy", "assault_squad"), "")
	assert_eq((OverworldVision.observe(s, 1)["owner_orders"] as Dictionary).keys(), [fid])
	assert_true((OverworldVision.observe(s, 2)["owner_orders"] as Dictionary).is_empty())


func test_session_buy_replays() -> void:
	var l := _l()
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var village := -1
	for f: Dictionary in s.inspect_plot(1, P(1, 6))["features"]:
		if f["name"] == "Village":
			village = f["id"]
	assert_true(village >= 0)
	for i in 20:
		if int(s.observe(1)["value"]) >= 5 and s.phase_name() == "PLANNING":
			break
		s.ready(1)
		s.ready(2)
	assert_eq(s.phase_name(), "PLANNING")
	assert_eq(s.set_owner_action(1, village, "buy", "scout_team"), "")
	assert_eq((s.observe(1)["owner_orders"] as Dictionary).keys(), [village])
	var turn := s.state.turn
	for i in 10:
		if s.state.turn > turn and s.phase_name() == "PLANNING":
			break
		s.ready(1)
		s.ready(2)
	assert_true(s.state.turn > turn)
	var scout := _rules().squad_index("scout_team")
	var found := false
	for did in Detachments.at(s.state, P(1, 6)):
		for q in Detachments.squads_of(s.state, did):
			found = found or s.state.squads.get_value(q, &"tmpl") == scout
	assert_true(found, "the scout team waits in the village garrison")
	var r := OverworldSession.rebuild(s.save(), l.templates, l.data_hash)
	assert_not_null(r, OverworldSession.last_error)
	assert_eq(r.state.state_hash_hex(), s.state.state_hash_hex())
