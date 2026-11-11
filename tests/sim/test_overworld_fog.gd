extends GutTest
## Fog of war on the overworld (GDD 02 §2.9, R8Q4). Task sw-o1m.1.4.
## test_vale: field commanders see 3 hexes; villages (sight 2) at (1,6) for
## player 1 and (14,5) for player 2; lakes at (7,2) and (8,2); ore deposit
## at (2,10); bandit camp (guarded) at (11,3).

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = OverworldRules.compile(_loader.templates, "test_vale", _loader.data_hash)
	return _rules_cache


## A fresh map without its seeded caches.
func _s() -> OverworldState:
	var s := OverworldState.create(1, _rules(), 7)
	var cache := _f("hex_supply_cache")
	for id in s.features.ids():
		if s.features.get_value(id, &"tmpl") == cache:
			s.remove_feature(id)
	return s


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _f(id: String) -> int:
	return _rules().feature_index(id)


func _route(cells: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for c: Vector2i in cells:
		out.append(P(c.x, c.y))
	return out


func _cmd(s: OverworldState, player: int, col: int, row: int) -> int:
	return Commanders.spawn(s, player, "field_commander", P(col, row))


func _of(events: Array[SimEvent], type: StringName) -> Array:
	return events.filter(func(e: SimEvent) -> bool: return e.type == type)


func _types(events: Array[SimEvent]) -> Dictionary:
	var out := {}
	for e in events:
		out[e.type] = true
	return out


func test_sight_from_commanders_and_controlled_features() -> void:
	var s := _s()
	_cmd(s, 1, 4, 8)
	var m := OverworldVision.sight(s, 1)
	var wrong := []
	for p in s.rules.plot_count():
		var want := Hex.plot_distance(P(4, 8), p, W) <= 3 or Hex.plot_distance(P(1, 6), p, W) <= 2
		if (m[p] == 1) != want:
			wrong.append(p)
	assert_eq(wrong, [], "commander radius 3 plus the village's radius 2, nothing else")
	var m2 := OverworldVision.sight(s, 2)
	assert_eq(m2[P(14, 5)], 1, "player 2's village")
	assert_eq(m2[P(4, 8)], 0)
	assert_eq(m2[P(8, 9)], 0, "an unowned mine is no sight source")


func test_enemy_commanders_only_in_sight() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 8)
	var far := _cmd(s, 2, 12, 8)
	var ids := (OverworldVision.observe(s, 1)["commanders"] as Array).map(func(c: Dictionary) -> int: return c["id"])
	assert_eq(ids, [a], "the enemy is in the fog")
	var near := _cmd(s, 2, 6, 8)
	ids = (OverworldVision.observe(s, 1)["commanders"] as Array).map(func(c: Dictionary) -> int: return c["id"])
	assert_eq(ids, [a, near])
	assert_false(ids.has(far))


func test_allies_share_vision() -> void:
	var s := _s()
	_cmd(s, 1, 4, 8)
	var b := _cmd(s, 2, 12, 8)
	assert_eq(OverworldVision.sight(s, 1)[P(14, 5)], 0)
	s.teams[2] = 1
	assert_false(s.hostile(1, 2))
	var m := OverworldVision.sight(s, 1)
	assert_eq(m[P(14, 5)], 1, "the ally's village")
	assert_eq(m[P(12, 8)], 1, "the ally's commander")
	var ids := (OverworldVision.observe(s, 1)["commanders"] as Array).map(func(c: Dictionary) -> int: return c["id"])
	assert_true(ids.has(b))


func test_memory_keeps_the_last_seen_state() -> void:
	var s := _s()
	var cache := s.add_feature(P(7, 8), _f("hex_supply_cache"))
	var a := _cmd(s, 1, 6, 8)
	var before := OverworldVision.sight(s, 1)
	assert_false(OverworldVision.explored(s, 1, P(7, 1)))
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8),
		Vector2i(2, 8), Vector2i(1, 8), Vector2i(0, 8)]))
	OverworldTurn.resolve(s)
	var after := OverworldVision.sight(s, 1)
	assert_eq(after[P(7, 8)], 0, "walked out of sight")
	s.remove_feature(cache)  # taken by someone else, unseen
	var plot: Dictionary = OverworldVision.observe(s, 1)["plots"][P(7, 8)]
	assert_false(plot["visible"])
	assert_eq(plot["turn"], 0)
	assert_has((plot["features"] as Array).map(func(f: Dictionary) -> int: return f["tmpl"]),
		_f("hex_supply_cache"), "remembered as last seen")
	assert_eq(OverworldVision.last_seen(s, 1, P(7, 8)), 0)
	var glimpsed := 0
	for p: int in s.memory[1]:
		if before[p] == 0 and after[p] == 0:
			glimpsed += 1
	assert_gt(glimpsed, 0, "hexes seen only on the way are explored")
	assert_false(OverworldVision.observe(s, 1)["plots"].has(P(15, 0)), "unexplored hexes are not observed")


func test_orders_use_what_the_player_knows() -> void:
	var s := _s()
	var a := _cmd(s, 1, 7, 6)
	assert_false(OverworldVision.explored(s, 1, P(7, 2)), "the lake is out of sight")
	assert_eq(OverworldPath.find(s, P(7, 6), P(7, 2)), PackedInt64Array(), "the truth: a lake")
	assert_ne(OverworldPath.find(s, P(7, 6), P(7, 2), 1), PackedInt64Array(), "player 1 does not know that")
	assert_eq(OverworldOrders.set_route(s, 1, a, _route([Vector2i(7, 5), Vector2i(7, 4),
		Vector2i(7, 3), Vector2i(7, 2)])), "", "unexplored hexes look passable")
	OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"plot"), P(7, 3), "movement stops at the real lake")
	assert_eq(s.commanders.get_value(a, &"banked"), 0)
	assert_eq(OverworldOrders.set_route(s, 1, a, _route([Vector2i(7, 2)])), "step 1 is impassable", "now it knows")
	var b := _cmd(s, 1, 6, 10)
	s.value[1] = 10
	OverworldOrders.set_route(s, 1, b, _route([Vector2i(5, 10), Vector2i(4, 10), Vector2i(3, 10), Vector2i(2, 10)]))
	assert_eq(OverworldOrders.set_activity(s, 1, b, "convert"), "the route must end on a hex offering convert",
		"the ore deposit has not been seen")


func test_battle_tiles_are_public_their_contents_are_not() -> void:
	var s := _s()
	var a := _cmd(s, 1, 12, 4)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(11, 3)]))
	var ev := OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	assert_ne(eid, -1)
	var o2 := OverworldVision.observe(s, 2)
	assert_eq(o2["battles"], [{"engagement": eid, "plot": P(11, 3)}], "where, not what")
	assert_true((o2["commanders"] as Array).is_empty())
	var b1: Dictionary = OverworldVision.observe(s, 1)["battles"][0]
	assert_eq(b1["kinds"], OverworldEngagements.GUARD)
	var seen2 := OverworldVision.filter_events(s, 2, ev)
	assert_eq(_types(seen2).keys(), [&"engagement_started", &"value_changed"])
	var started: SimEvent = _of(seen2, &"engagement_started")[0]
	assert_false(started.data.has("kinds"))
	assert_eq(_of(seen2, &"value_changed")[0].data["player"], 2, "only its own Value")
	var seen1 := OverworldVision.filter_events(s, 1, ev)
	assert_eq(_of(seen1, &"engagement_started")[0].data["kinds"], OverworldEngagements.GUARD)
	assert_eq(_of(seen1, &"commander_engaged").size(), 1)
	OverworldMovement.end_engagement(s, eid)
	var ended := OverworldVision.filter_events(s, 2, s.events.drain(), s.turn)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].data, {"engagement": eid, "plot": P(11, 3)})


func test_enemy_moves_seen_only_in_sight() -> void:
	var s := _s()
	_cmd(s, 1, 4, 8)
	var b := _cmd(s, 2, 9, 8)
	OverworldOrders.set_route(s, 2, b, _route([Vector2i(8, 8), Vector2i(7, 8)]))
	var ev := OverworldTurn.resolve(s)
	var moves: Array = _of(OverworldVision.filter_events(s, 1, ev), &"commander_moved")
	assert_eq(moves.size(), 1, "the step out of the fog")
	assert_eq(moves[0].data["to"], P(7, 8))
	assert_eq(_of(OverworldVision.filter_events(s, 2, ev), &"commander_moved").size(), 2)


func test_snapshot_keeps_memory_and_teams() -> void:
	var s := _s()
	var a := _cmd(s, 1, 6, 8)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 8), Vector2i(4, 8)]))
	OverworldTurn.resolve(s)
	s.teams[3] = 1
	var t := OverworldState.new(1, _rules(), 0)
	t.restore(s.snapshot())
	assert_eq(t.state_hash_hex(), s.state_hash_hex())
	assert_eq(t.memory, s.memory)
	assert_false(t.hostile(1, 3))
	(t.memory[1] as Dictionary).erase(P(6, 8))
	assert_ne(t.state_hash_hex(), s.state_hash_hex(), "memory is hashed")
