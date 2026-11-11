extends GutTest
## Commanders, routes, simultaneous movement, guards, meetings, control and
## movement banking on the overworld (GDD 02 §2.9, R4Q13, R6Q11, R7Q8).
## Task sw-o1m.1.2. Costs on test_vale: plains 10, road 5, forest 15,
## hills 20; field_commander has 60 movement points per turn.

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = OverworldRules.compile(_loader.templates, "test_vale", _loader.data_hash)
	return _rules_cache


func _s() -> OverworldState:
	return OverworldState.create(1, _rules(), 7)


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _route(cells: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for c: Vector2i in cells:
		out.append(P(c.x, c.y))
	return out


func _cmd(s: OverworldState, player: int, col: int, row: int, kind: String = "field_commander") -> int:
	return Commanders.spawn(s, player, kind, P(col, row))


func _plot(s: OverworldState, cid: int) -> int:
	return s.commanders.get_value(cid, &"plot")


func _types(events: Array[SimEvent]) -> Array:
	return events.map(func(e: SimEvent) -> String: return String(e.type))


func test_commanders_compile() -> void:
	var r := _rules()
	var f := r.commander_index("field_commander")
	assert_eq(r.cm_mp[f], 60)
	assert_eq(r.cm_sight[f], 3)
	assert_eq(r.cm_squad[f], "rifle_squad")


func test_route_validation() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 8)
	assert_eq(OverworldOrders.set_route(s, 2, a, _route([Vector2i(5, 8)])), "not your commander")
	assert_eq(OverworldOrders.set_route(s, 1, 999, _route([Vector2i(5, 8)])), "no such commander")
	assert_eq(OverworldOrders.set_route(s, 1, a, _route([Vector2i(6, 8)])), "step 1 is not next to the previous hex")
	var far := _route([Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8)])
	assert_eq(OverworldOrders.set_route(s, 1, a, far), "", "the hills are out of sight: they look like plains")
	OverworldVision.glimpse(s, 1, P(10, 8), 0)
	assert_eq(OverworldOrders.set_route(s, 1, a, far), "needs 70 movement points, has 60", "hills +10 on the last hex")
	var b := _cmd(s, 1, 6, 2)
	assert_eq(OverworldOrders.set_route(s, 1, b, _route([Vector2i(7, 2)])), "step 1 is impassable", "the lake")
	assert_eq(OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 8)])), "")
	assert_eq(s.routes[a], _route([Vector2i(5, 8)]))
	assert_eq(OverworldOrders.clear_route(s, 1, a), "")
	assert_false(s.routes.has(a))


func test_pathfinding() -> void:
	var s := _s()
	var path := OverworldPath.find(s, P(6, 2), P(9, 2))
	assert_false(path.is_empty())
	assert_eq(path[path.size() - 1], P(9, 2))
	assert_false(path.has(P(7, 2)) or path.has(P(8, 2)), "around the lake")
	assert_ne(OverworldPath.cost(s, P(6, 2), path), -1, "every step is legal")
	var road := OverworldPath.find(s, P(0, 6), P(15, 5))
	assert_eq(OverworldPath.cost(s, P(0, 6), road), 5 * road.size(), "follows the road")
	assert_eq(OverworldPath.find(s, P(6, 2), P(7, 2)), PackedInt64Array(), "the lake is unreachable")
	assert_eq(OverworldPath.find(s, P(6, 2), P(9, 2)), path, "deterministic")


func test_movement_follows_the_route() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 8)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8)]))
	var ev := OverworldTurn.resolve(s)
	assert_eq(_plot(s, a), P(7, 8))
	assert_eq(_types(ev).count("commander_moved"), 3)
	assert_eq(s.turn, 1)
	assert_true(s.routes.is_empty(), "routes are cleared")
	assert_eq(s.commanders.get_value(a, &"banked"), 0, "a finished route banks nothing")


func test_passing_through_captures() -> void:
	var s := _s()
	var mine := s.feature_row(P(8, 9), _rules().feature_index("hex_mine"))
	assert_eq(s.features.owner[mine], 0)
	var a := _cmd(s, 1, 6, 9)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9)]))
	var ev := OverworldTurn.resolve(s)
	mine = s.feature_row(P(8, 9), _rules().feature_index("hex_mine"))
	assert_eq(s.features.owner[mine], 1)
	var cap: Array = ev.filter(func(e: SimEvent) -> bool: return e.type == &"feature_captured")
	assert_eq(cap.size(), 1)
	assert_eq(cap[0].data["from"], 0)


func test_guard_stops_and_banks() -> void:
	var s := _s()
	var a := _cmd(s, 1, 9, 3)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(10, 3), Vector2i(11, 3), Vector2i(12, 3), Vector2i(13, 3)]))
	var ev := OverworldTurn.resolve(s)
	assert_eq(_plot(s, a), P(11, 3), "stopped at the bandit camp")
	var eid := s.engagement_at(P(11, 3))
	assert_ne(eid, -1)
	assert_eq(s.engagements.get_value(eid, &"kinds"), OverworldEngagements.GUARD)
	assert_eq(s.commanders.get_value(a, &"engagement"), eid)
	assert_true(_types(ev).has("engagement_started"))
	assert_eq(s.commanders.get_value(a, &"banked"), 20, "50% of the 40 unused")
	var row := s.commanders.row_of(a)
	assert_eq(Commanders.budget(s, row), 80, "usable next turn")
	OverworldMovement.end_engagement(s, eid)
	assert_eq(s.commanders.get_value(a, &"engagement"), -1)
	OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"banked"), 0, "the bank expires after one turn")


func test_bank_is_capped_at_one_turn() -> void:
	var s := _s()
	var a := _cmd(s, 1, 10, 3)
	s.commanders.set_value(a, &"banked", 60)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(11, 3), Vector2i(12, 3)]))
	OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"banked"), 55, "(120 - 10) / 2, under the 60 cap")
	s.commanders.set_value(a, &"engagement", -1)
	s.engagements.despawn(s.engagement_at(P(11, 3)))
	s.commanders.set_value(a, &"banked", 200)
	s.commanders.set_value(a, &"plot", P(10, 3))
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(11, 3), Vector2i(12, 3)]))
	OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(a, &"banked"), 60, "capped at one turn's points")


func test_hostile_commanders_meet_head_on() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 8)
	var b := _cmd(s, 2, 9, 8)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8)]))
	OverworldOrders.set_route(s, 2, b, _route([Vector2i(8, 8), Vector2i(7, 8), Vector2i(6, 8), Vector2i(5, 8)]))
	OverworldTurn.resolve(s)
	assert_eq(_plot(s, a), P(7, 8), "A walks into B at t=30")
	assert_eq(_plot(s, b), P(7, 8), "B was still there, about to leave")
	var eid := s.engagement_at(P(7, 8))
	assert_eq(s.engagements.get_value(eid, &"kinds"), OverworldEngagements.COMMANDERS)
	assert_eq(s.commanders.get_value(a, &"banked"), 15, "(60 - 30) / 2")
	assert_eq(s.commanders.get_value(b, &"banked"), 20, "(60 - 20) / 2")


func test_swapping_hexes_meets() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 10)
	var b := _cmd(s, 2, 5, 10)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 10)]))
	OverworldOrders.set_route(s, 2, b, _route([Vector2i(4, 10)]))
	OverworldTurn.resolve(s)
	assert_eq(_plot(s, a), P(5, 10))
	assert_eq(_plot(s, b), P(5, 10), "no passing through each other")
	assert_ne(s.engagement_at(P(5, 10)), -1)
	assert_eq(s.commanders.get_value(a, &"banked"), 0, "A arrived where it planned")
	assert_eq(s.commanders.get_value(b, &"banked"), 30, "B never left")


func test_ending_on_a_waiting_enemy() -> void:
	var s := _s()
	var a := _cmd(s, 1, 6, 10)
	var b := _cmd(s, 2, 8, 10)
	OverworldOrders.set_route(s, 2, b, _route([Vector2i(7, 10), Vector2i(6, 10), Vector2i(5, 10)]))
	OverworldTurn.resolve(s)
	assert_eq(_plot(s, b), P(6, 10), "intercepted by the waiting commander")
	assert_eq(s.commanders.get_value(a, &"engagement"), s.commanders.get_value(b, &"engagement"))
	assert_eq(s.commanders.get_value(a, &"banked"), 0, "A had no plan to cut")


func test_battle_tiles() -> void:
	var s := _s()
	var a := _cmd(s, 1, 10, 3)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(11, 3)]))
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	assert_eq(OverworldOrders.set_route(s, 1, a, _route([Vector2i(12, 3)])), "is in a battle: it cannot move until the battle ends")
	var b := _cmd(s, 1, 12, 4)
	assert_eq(OverworldOrders.set_route(s, 1, b, _route([Vector2i(11, 3), Vector2i(12, 3)])),
		"step 1 is a battle: a route onto a battle ends there")
	assert_eq(OverworldOrders.set_route(s, 1, b, _route([Vector2i(11, 3)])), "")
	OverworldTurn.resolve(s)
	assert_eq(s.commanders.get_value(b, &"engagement"), eid, "joined the battle")
	assert_true(OverworldPath.find(s, P(10, 3), P(12, 3)).find(P(11, 3)) < 0, "paths go around battles")


func test_determinism_and_snapshot() -> void:
	var hashes := []
	for _i in 2:
		var s := _s()
		var a := _cmd(s, 1, 4, 8)
		var b := _cmd(s, 2, 9, 8)
		OverworldOrders.set_route(s, 1, a, OverworldPath.find(s, P(4, 8), P(9, 9)))
		OverworldOrders.set_route(s, 2, b, OverworldPath.find(s, P(9, 8), P(4, 9)))
		var snap := s.snapshot()
		var t := OverworldState.new(1, _rules(), 0)
		t.restore(snap)
		assert_eq(t.state_hash_hex(), s.state_hash_hex(), "routes survive a snapshot")
		OverworldTurn.resolve(s)
		OverworldTurn.resolve(t)
		assert_eq(t.state_hash_hex(), s.state_hash_hex())
		hashes.append(s.state_hash_hex())
	assert_eq(hashes[0], hashes[1])
