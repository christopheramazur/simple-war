extends GutTest
## Battle rules end to end on the core Duel scenario. Tasks sw-eo8.1-6, sw-1jy.1-2.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _rules() -> BattleRules:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(_loader.templates, "duel_crossroads", _loader.data_hash)
	assert_true(r.is_valid(), "\n".join(r.errors))
	return r


func _battle(seed_value: int = 1) -> BattleState:
	return BattleSetup.create(1, _rules(), seed_value)


func _squads_of(state: BattleState, player: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for row in state.squads.count():
		if state.squads.player[row] == player and state.squads.is_active(row):
			out.append(state.squads.id_at(row))
	return out


func _all_attack_move(state: BattleState, player: int, x: int, y: int) -> void:
	var orders := []
	for sid in _squads_of(state, player):
		orders.append({"squad": sid, "type": "attack_move", "x": x * ONE, "y": y * ONE})
	var errors := BattleOrders.apply(state, player, orders)
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_rules_compile() -> void:
	var r := _rules()
	assert_eq(r.width, 200)
	assert_eq(r.sides.size(), 2)
	assert_eq(r.zone_ids.size(), 3)
	var rifle := r.squad_index("rifle_squad")
	assert_eq(r.sq_members[rifle].size(), 8)
	assert_eq(r.ut_leader[r.sq_members[rifle][0]], 1, "leader first")
	assert_eq(r.mv_walk[0] > 0, true)
	assert_eq(r.feature_ids[r.feature_at(50 * ONE, 20 * ONE)], "forest")
	assert_eq(r.feature_ids[r.feature_at(10 * ONE, 49 * ONE)], "road")


func test_deploy() -> void:
	var s := _battle()
	assert_eq(s.squads.count(), 10)
	var total_units := 0
	for row in s.squads.count():
		total_units += s.squads.alive[row]
	assert_eq(s.units.count(), total_units)
	for row in s.squads.count():
		var x := s.squads.cx[row]
		if s.squads.player[row] == 1:
			assert_true(x < 40 * ONE, "player 1 deploys west")
		else:
			assert_true(x > 160 * ONE, "player 2 deploys east")


func test_order_validation() -> void:
	var s := _battle()
	var mine := _squads_of(s, 1)
	var theirs := _squads_of(s, 2)
	var errs := BattleOrders.apply(s, 1, [
		{"squad": theirs[0], "type": "move", "x": 0, "y": 0},
		{"squad": mine[0], "type": "teleport"},
		{"squad": mine[0], "type": "move", "x": -5, "y": 0},
		{"squad": mine[0], "type": "attack", "target": theirs[0]},
		{"squad": mine[0], "type": "move", "x": 10 * ONE, "y": 10 * ONE, "abilities": [{"id": "scout_cloak", "on": true}]},
	])
	assert_eq(errs.size(), 5, "\n".join(errs))
	assert_string_contains(errs[0], "not your squad")
	assert_string_contains(errs[3], "target not visible")
	assert_string_contains(errs[4], "squad has no ability 'scout_cloak'")


func test_movement_closes_distance() -> void:
	var s := _battle()
	var sim := BattleSim.new()
	_all_attack_move(s, 1, 100, 50)
	var start := s.squads.cx[0]
	sim.execute_turn(s)
	assert_true(s.squads.cx[0] > start + 15 * ONE, "moved east")
	assert_eq(s.turn, 1)


func test_full_battle_resolves_and_is_deterministic() -> void:
	var hashes := []
	var results := []
	for _run in 2:
		var s := _battle(7)
		var sim := BattleSim.new()
		var turns := 0
		while not s.is_over() and turns < 12:
			_all_attack_move(s, 1, 100, 50)
			_all_attack_move(s, 2, 100, 50)
			sim.execute_turn(s)
			turns += 1
		hashes.append(s.state_hash().hex_encode())
		results.append(s.result)
	assert_eq(hashes[0], hashes[1])
	assert_false(results[0].is_empty(), "battle ended")
	assert_true(results[0]["reason"] in ["annihilation", "score_target", "turn_limit"], str(results[0]))


func test_fighting_happens_and_ledger_records() -> void:
	var s := _battle(3)
	var sim := BattleSim.new()
	var fired := 0
	var killed := 0
	for _t in 5:
		if s.is_over():
			break
		_all_attack_move(s, 1, 100, 50)
		_all_attack_move(s, 2, 100, 50)
		sim.execute_turn(s)
		for e in s.turn_log:
			if e.type == &"squad_fired":
				fired += 1
			elif e.type == &"unit_killed":
				killed += 1
	assert_gt(fired, 0, "squads fired")
	assert_gt(killed, 0, "units died")
	var sources := {}
	for k: String in s.ledger:
		sources[k.split("|")[2]] = true
	assert_true(sources.has("drift"), str(sources.keys()))
	assert_true(sources.has("morale_base"), str(sources.keys()))
	assert_true(sources.has("hp_lost"), str(sources.keys()))


func test_snapshot_restore_round_trip() -> void:
	var s := _battle(5)
	var sim := BattleSim.new()
	_all_attack_move(s, 1, 100, 50)
	_all_attack_move(s, 2, 100, 50)
	sim.execute_turn(s)
	var snap := s.snapshot()
	var copy := BattleState.new(1, s.rules)
	copy.restore(snap)
	assert_eq(copy.state_hash().hex_encode(), s.state_hash().hex_encode())
	for st: BattleState in [s, copy]:
		_all_attack_move(st, 1, 100, 50)
		_all_attack_move(st, 2, 100, 50)
		sim.execute_turn(st)
	assert_eq(copy.state_hash().hex_encode(), s.state_hash().hex_encode(), "continues identically")
