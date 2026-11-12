extends GutTest
## Battles from engagements: building them with losses carried, running them
## on the shared pulse, results back into armies, guards cleared, commanders
## defeated, reinforcements and leaving (GDD 02 §2.2-2.4, R2Q1, R3Q3).
## Task sw-o1m.2.3. test_vale: bandit camp (11,3) guarded by 2 rifle squads;
## shrine (3,7) offers a battle with no guard; battles on ow_field.
## field_commander: own rifle squad + 2 rifle squads; its battleforce under
## the 3-squad / 250-strength cap is the own squad and one rifle squad.

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


## Player 1's field commander attacks the bandit camp; returns [s, cid, eid].
func _attack(weaken: int = -1) -> Array:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	if weaken >= 0:
		s.squads.set_value(OverworldArmies.of(s, a)[1], &"alive", weaken)
	OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(11, 3)]))
	OverworldTurn.resolve(s)
	return [s, a, s.engagement_at(P(11, 3))]


func _build(s: OverworldState, eid: int) -> OverworldBattle:
	var errs := PackedStringArray()
	var b := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_eq(errs, PackedStringArray())
	return b


func _units_of(b: OverworldBattle, bid: int) -> int:
	var n := 0
	for row in b.state.units.count():
		if b.state.units.squad[row] == bid:
			n += 1
	return n


func _bid_of(b: OverworldBattle, ow: int) -> int:
	for bid: int in b.links:
		if b.links[bid] == ow:
			return bid
	return -1


func test_build_carries_losses_and_neutral_guards() -> void:
	var x := _attack(3)
	var s: OverworldState = x[0]
	var b := _build(s, x[2])
	assert_not_null(b)
	assert_eq(b.scenario, "ow_field")
	assert_eq(b.state.players, PackedInt64Array([1, OverworldBattles.NEUTRAL]))
	var mine := OverworldBattleforce.deployed_in(s, x[2])
	assert_eq(mine.size(), 3, "own 100 + rifles 100 + the weakened rifles 37 fit 250")
	assert_eq(_units_of(b, _bid_of(b, mine[0])), 8)
	assert_eq(_units_of(b, _bid_of(b, mine[1])), 3, "losses carried into battle")
	assert_eq(b.links.values().count(-1), 2, "two guard squads")


func test_win_clears_the_guard_and_returns_survivors() -> void:
	var x := _attack()
	var s: OverworldState = x[0]
	var eid: int = x[2]
	var b := _build(s, eid)
	var mine := OverworldBattleforce.deployed_in(s, eid)
	var bid := _bid_of(b, mine[1])
	b.state.squads.set_value(bid, &"alive", 5)
	b.state.result = {"winner": 1, "reason": "annihilation", "turn": 3, "scores": {}, "survivors": {}}
	OverworldBattles.finish(s, b)
	assert_eq(s.engagement_at(P(11, 3)), -1)
	assert_eq(s.commanders.get_value(x[1], &"engagement"), -1, "free to move")
	assert_eq(s.squads.get_value(mine[1], &"alive"), 5, "losses come back")
	assert_eq(s.squads.get_value(mine[1], &"deployed"), -1)
	assert_true(s.guard_at(P(11, 3)).is_empty(), "the guard is cleared for good")
	var ev := s.events.drain()
	assert_eq(_of(ev, &"guard_cleared").size(), 1)
	assert_eq(_of(ev, &"battle_resolved")[0].data["winner"], 1)


func test_loss_defeats_a_leading_commander() -> void:
	var x := _attack()
	var s: OverworldState = x[0]
	var b := _build(s, x[2])
	for bid: int in b.links:
		if b.links[bid] >= 0:
			b.state.squads.set_value(bid, &"destroyed", 1)
	b.state.result = {"winner": OverworldBattles.NEUTRAL, "reason": "annihilation", "turn": 3, "scores": {}, "survivors": {}}
	OverworldBattles.finish(s, b)
	assert_false(s.commanders.is_alive(x[1]), "its own squad fell: defeated")
	assert_eq(s.squads.count(), 0, "the rest of the army scattered")
	assert_eq(s.guard_at(P(11, 3)).size(), 2, "the guard holds")
	var ev := s.events.drain()
	assert_eq(_of(ev, &"commander_defeated").size(), 1)
	assert_eq(_of(ev, &"battle_resolved")[0].data["winner"], 0, "neutral")


func test_unopposed_battle_ends_at_once() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(3, 7))
	OverworldOrders.set_activity(s, 1, a, "battle")
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(3, 7))
	assert_null(_build(s, eid), "nobody to fight")
	OverworldBattles.finish_unopposed(s, eid)
	assert_eq(s.engagement_at(P(3, 7)), -1)
	assert_eq(_of(s.events.drain(), &"battle_resolved")[0].data["reason"], "unopposed")


func test_reinforce_and_leave() -> void:
	var x := _attack()
	var s: OverworldState = x[0]
	var a: int = x[1]
	var eid: int = x[2]
	var b := _build(s, eid)
	var spare := OverworldArmies.of(s, a)[2]
	assert_eq(OverworldOrders.leave_battle(s, 1, a), "its own squad is fighting: it cannot leave")
	assert_eq(OverworldOrders.reinforce(s, 1, a, spare, 3), "the battleforce cap is 3 squads")
	assert_eq(OverworldOrders.reinforce(s, 1, a, spare, 2), "")
	assert_eq(OverworldOrders.reinforce(s, 1, a, spare, 2), "that squad is already in a battle")
	OverworldBattles.reinforce(s, b)
	var bid := _bid_of(b, spare)
	assert_ne(bid, -1, "joined the battle")
	assert_eq(_units_of(b, bid), 8)
	# A commander that stays out of the fight can leave it.
	var y := _s()
	var c := Commanders.spawn(y, 1, "field_commander", P(12, 4))
	OverworldBattleforce.set_plan(y, 1, c, "", PackedInt64Array(), false)
	OverworldOrders.set_route(y, 1, c, PackedInt64Array([P(11, 3)]))
	OverworldTurn.resolve(y)
	var e2 := y.engagement_at(P(11, 3))
	assert_eq(OverworldOrders.reinforce(y, 1, c, OverworldArmies.of(y, c)[0], 0),
		"only a commander staying in the battle brings reinforcements")
	assert_eq(OverworldOrders.leave_battle(y, 1, c), "")
	assert_eq(y.commanders.get_value(c, &"engagement"), -1)
	assert_eq(OverworldBattleforce.deployed_in(y, e2).size(), 2, "its battleforce fights on")


## Through the session: player 1's field commander walks into the bandit
## camp and fights it out with a ZoneController.
func _session_battle() -> OverworldSession:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var a := Commanders.spawn(s.state, 1, "field_commander", P(12, 4))
	assert_eq(s.set_route(1, a, PackedInt64Array([P(11, 3)])), "")
	s.ready(1)
	s.ready(2)
	return s


func test_session_runs_battles_on_the_shared_pulse() -> void:
	var s := _session_battle()
	assert_eq(s.battles.size(), 1, "the battle begins at the start of the next turn")
	var eid: int = s.battles.keys()[0]
	assert_eq(_of(s.observe(1)["events"], &"battle_started").size(), 1)
	var bt: Dictionary = (s.observe(2)["battles"] as Array)[0]
	assert_true(bt["battle"])
	assert_true(bt.has("kinds"), "player 2's outrider sees the hex")
	assert_eq(s.observe_battle(2, eid), {})
	var bo := s.observe_battle(1, eid)
	assert_eq((bo["links"] as Dictionary).size(), 2)
	s.ready(1)
	s.ready(2)
	assert_eq(s.submit_battle_orders(2, eid, []), PackedStringArray(["not in that battle"]))
	var fighter := ZoneController.new(1)
	var guard := 0
	while not s.battles.is_empty() and guard < 12:
		guard += 1
		assert_eq(s.submit_battle_orders(1, eid, fighter.orders(s.observe_battle(1, eid))), PackedStringArray())
		s.ready(1)
		s.ready(2)
		s.ready(1)
		s.ready(2)
	assert_true(s.battles.is_empty(), "the battle ended within its turn limit")
	assert_eq(s.state.engagement_at(P(11, 3)), -1)
	assert_eq(_of(s.last_events, &"battle_resolved").size(), 1)


func test_battles_save_load_and_replay() -> void:
	var full := _session_battle()
	var half := _session_battle()
	for t in 2:
		for x in [full, half]:
			x.ready(1)
			x.ready(2)
			x.ready(1)
			x.ready(2)
	assert_eq(half.battles.size(), 1, "mid-battle")
	var loaded := OverworldSession.load_save(half.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.state_hash_hex(), half.state_hash_hex())
	for x in [full, loaded]:
		for t in 8:
			x.ready(1)
			x.ready(2)
	assert_eq(loaded.turn_hashes, full.turn_hashes)
	assert_eq(loaded.state_hash_hex(), full.state_hash_hex())
