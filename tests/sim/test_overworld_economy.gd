extends GutTest
## Cache pickups, activities, production and uncertain-outcome offers on the
## overworld (GDD 02 §2.9, R4Q12, R5Q10, R6Q14). Task sw-o1m.1.3.
## test_vale: villages at (1,6) for player 1 and (14,5) for player 2 (2 Value
## each per turn), mine at (8,9) (3), ore deposit at (2,10) (convert for 5
## Value into a mine), shrine at (3,7) (uncertain; battle), bandit camp at
## (11,3) (guarded).

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = OverworldRules.compile(_loader.templates, "test_vale", _loader.data_hash)
	return _rules_cache


## A fresh map without its seeded caches, so routes pick up only what a
## test places.
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


func test_cache_picked_up_on_the_way() -> void:
	var s := _s()
	s.add_feature(P(5, 8), _f("hex_supply_cache"))
	var a := _cmd(s, 1, 4, 8)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(5, 8), Vector2i(6, 8)]))
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.feature_row(P(5, 8), _f("hex_supply_cache")), -1, "taken")
	assert_eq(_of(ev, &"cache_picked").size(), 1)
	assert_eq(s.value_of(1), 5 + 2, "cache plus the village's production")


func test_guarded_cache_stays() -> void:
	var s := _s()
	s.add_feature(P(11, 3), _f("hex_supply_cache"))
	var a := _cmd(s, 1, 10, 3)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(11, 3)]))
	OverworldTurn.resolve(s)
	assert_ne(s.feature_row(P(11, 3), _f("hex_supply_cache")), -1, "the guards fight first")


func test_production() -> void:
	var s := _s()
	var ev := OverworldTurn.resolve(s)
	assert_eq([s.value_of(1), s.value_of(2)], [2, 2], "each starting village")
	var vc: Array = _of(ev, &"value_changed")
	assert_eq(vc.size(), 2)
	assert_eq(vc[0].data["source"], &"production")
	var a := _cmd(s, 1, 7, 9)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(8, 9)]))
	OverworldTurn.resolve(s)
	assert_eq(s.value_of(1), 2 + 2 + 3, "the mine pays the turn it is taken")


func test_convert() -> void:
	var s := _s()
	var a := _cmd(s, 1, 3, 10)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(2, 10)]))
	assert_eq(OverworldOrders.set_activity(s, 1, a, "convert"), "convert costs 5 Value, you have 0")
	s.value[1] = 10
	assert_eq(OverworldOrders.set_activity(s, 1, a, "convert"), "")
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.feature_row(P(2, 10), _f("hex_ore_deposit")), -1)
	var mine := s.feature_row(P(2, 10), _f("hex_mine"))
	assert_ne(mine, -1)
	assert_eq(s.features.owner[mine], 1)
	assert_eq(_of(ev, &"feature_converted").size(), 1)
	assert_eq(s.value_of(1), 10 - 5 + 2 + 3, "paid 5; the village and the new mine produce")


func test_activity_needs_the_route_to_end_there() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 8)
	assert_eq(OverworldOrders.set_activity(s, 1, a, "recruit"), "the route must end on a hex offering recruit")
	assert_eq(OverworldOrders.set_activity(s, 1, a, "dance"), "unknown activity 'dance'")
	assert_eq(OverworldOrders.set_activity(s, 2, a, "recruit"), "not your commander")
	var b := _cmd(s, 1, 3, 10)
	s.value[1] = 10
	OverworldOrders.set_route(s, 1, b, _route([Vector2i(2, 10)]))
	OverworldOrders.set_activity(s, 1, b, "convert")
	OverworldOrders.set_route(s, 1, b, _route([Vector2i(4, 10)]))
	var ev := OverworldTurn.resolve(s)
	var cancel: Array = _of(ev, &"activity_cancelled")
	assert_eq(cancel.size(), 1)
	assert_eq(cancel[0].data["reason"], "did not reach the hex")
	assert_ne(s.feature_row(P(2, 10), _f("hex_ore_deposit")), -1)
	assert_true(s.activities.is_empty(), "activities last one turn")


func test_recruit_is_performed() -> void:
	var s := _s()
	var a := _cmd(s, 1, 2, 6)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(1, 6)]))
	s.value[1] = 4
	assert_eq(OverworldOrders.set_activity(s, 1, a, "recruit", "scout_team"), "")
	var ev := OverworldTurn.resolve(s)
	var done: Array = _of(ev, &"activity_performed")
	assert_eq(done.size(), 1)
	assert_eq(done[0].data["activity"], "recruit")
	assert_eq(_of(ev, &"squad_recruited").size(), 1)
	assert_eq(OverworldArmies.count(s, a), 3, "two starting rifle squads and the new scouts")


func test_battle_activity_starts_an_engagement() -> void:
	var s := _s()
	var a := _cmd(s, 1, 3, 7)
	assert_eq(OverworldOrders.set_activity(s, 1, a, "battle"), "", "no route: the commander's own hex")
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(3, 7))
	assert_ne(eid, -1)
	assert_eq(s.engagements.get_value(eid, &"kinds"), OverworldEngagements.ACTIVITY)
	assert_eq(s.commanders.get_value(a, &"engagement"), eid)
	assert_true(s.offers.is_empty(), "an engaged commander is not offered the shrine")


func test_uncertain_features_are_offered_uncontested() -> void:
	var s := _s()
	var a := _cmd(s, 1, 4, 7)
	OverworldOrders.set_route(s, 1, a, _route([Vector2i(3, 7)]))
	var ev := OverworldTurn.resolve(s)
	assert_eq(s.offers.size(), 1)
	var o: Dictionary = s.offers[0]
	assert_eq(o["plot"], P(3, 7))
	assert_eq(o["player"], 1)
	assert_eq(s.features.get_value(o["feature"], &"tmpl"), _f("hex_shrine"))
	assert_eq(_of(ev, &"interaction_offered").size(), 1)
	_cmd(s, 2, 3, 7)
	OverworldTurn.resolve(s)
	assert_true(s.offers.is_empty(), "contested: no offer")


func test_snapshot_keeps_value_activities_offers() -> void:
	var s := _s()
	var a := _cmd(s, 1, 3, 7)
	OverworldTurn.resolve(s)
	s.value[1] = 9
	OverworldOrders.set_activity(s, 1, a, "battle")
	var t := OverworldState.new(1, _rules(), 0)
	t.restore(s.snapshot())
	assert_eq(t.state_hash_hex(), s.state_hash_hex())
	assert_eq(t.value_of(1), 9)
	assert_eq(t.offers.size(), 1)
	assert_eq(t.activities[a]["activity"], "battle")
	t.value[1] = 8
	assert_ne(t.state_hash_hex(), s.state_hash_hex(), "Value is hashed")
