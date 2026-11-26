extends GutTest
## The deployment step: placements validated, hidden, applied at Reveal
## (sw-bafi.10, GDD 02 §2.4 Deployment, U1Q30).

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## A duel_crossroads session; `mod` may change the compiled rules first.
func _make(mod: Callable = Callable(), seed_value: int = 11) -> BattleSession:
	var r := BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	if mod.is_valid():
		mod.call(r)
	var s := BattleSession.new()
	s._setup(r, "duel_crossroads", seed_value, _l().data_hash, null)
	s.clock.start()
	s._pump()
	return s


func _ids(s: BattleSession, player: int) -> Array:
	var out := []
	for row in s.state.squads.count():
		if s.state.squads.player[row] == player:
			out.append(s.state.squads.id_at(row))
	return out


func _f(v: float) -> int:
	return int(round(v * Fixed.ONE))


## Runs turn 1 to the next Planning with no orders.
func _finish_turn(s: BattleSession) -> void:
	s.ready(1)
	s.ready(2)
	if s.phase_name() == "REACTION":
		s.ready(1)
		s.ready(2)


## Player 2's area moved next to player 1's, so the sides can deploy in sight.
func _near(r: BattleRules) -> void:
	r.sides[1]["deploy"] = PackedInt64Array([_f(30), _f(15), _f(25), _f(70)])


func _fixed(r: BattleRules) -> void:
	r.deployment_open = false


func test_open_by_default_and_fixed_by_scenario() -> void:
	assert_true(_make().state.deploying)
	assert_false(_make(_fixed).state.deploying)


func test_same_placements_and_seed_give_the_same_hash() -> void:
	var hashes := []
	for x: float in [10.0, 10.0, 20.0]:
		var s := _make()
		var sid: int = _ids(s, 1)[0]
		assert_eq(s.submit_deployment(1, [{"squad": sid, "x": _f(x), "y": _f(30.5), "facing": 4096}]).size(), 0)
		_finish_turn(s)
		assert_false(s.state.deploying, "cleared at Reveal")
		hashes.append(s.state.state_hash().hex_encode())
	assert_eq(hashes[0], hashes[1])
	assert_ne(hashes[0], hashes[2])


func test_placement_moves_anchor_units_and_facing() -> void:
	var s := _make()
	var sid: int = _ids(s, 1)[1]
	s.submit_deployment(1, [{"squad": sid, "x": _f(12.5), "y": _f(70.5), "facing": 8192}])
	s.ready(1)
	s.ready(2)
	var sq := s.state.squads
	var row := sq.row_of(sid)
	var want := BattleDeploy.open_point_in(s.rules, sq.tmpl[row], _f(12.5), _f(70.5), BattleDeploy.area(s.state, 1))
	assert_eq(sq.ax[row], want[0])
	assert_eq(sq.ay[row], want[1])
	assert_eq(sq.facing[row], 8192)
	var u := s.state.units
	for urow in u.count():
		if u.squad[urow] == sid:
			assert_eq(u.facing[urow], 8192)
			assert_lt(absi(u.x[urow] - want[0]), _f(8.0), "units laid out around the new anchor")


func test_refused_outside_enemy_and_duplicate() -> void:
	var s := _make()
	var mine: int = _ids(s, 1)[0]
	var theirs: int = _ids(s, 2)[0]
	var errs := s.submit_deployment(1, [
		{"squad": mine, "x": _f(100), "y": _f(30), "facing": 0},
		{"squad": theirs, "x": _f(10), "y": _f(30), "facing": 0},
		{"squad": mine, "x": _f(10), "y": _f(30), "facing": 0},
		{"squad": mine, "x": _f(12), "y": _f(30), "facing": 0},
		{"squad": mine, "x": 10.5, "y": _f(30), "facing": 0},
	])
	assert_eq(errs.size(), 4, str(errs))
	assert_string_contains(errs[0], "outside the deployment area")
	assert_string_contains(errs[1], "not your squad")
	assert_string_contains(errs[2], "squad placed twice")
	assert_string_contains(errs[3], "must be an int")
	assert_eq((s._deploys[1] as Array).size(), 1)


func test_refused_when_not_deploying() -> void:
	var s := _make(_fixed)
	var errs := s.submit_deployment(1, [{"squad": _ids(s, 1)[0], "x": _f(10), "y": _f(30), "facing": 0}])
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "deploying")


## The first feature the squad template can't enter, or -1.
func _wall(r: BattleRules, st: int) -> int:
	var costs: PackedInt32Array = r.rt_cost[r.sq_route_class[st]]
	for f in costs.size():
		if costs[f] <= 0:
			return f
	return -1


func test_impassable_placement_snaps_inside_the_area() -> void:
	var probe := _make()
	var st := probe.state.squads.tmpl[0]
	var wall := _wall(probe.rules, st)
	if wall < 0:
		pending("no impassable feature in the fixture")
		return
	# A wall on cells (5..7, 40..42): the corner of player 1's area.
	var s := _make(func(r: BattleRules) -> void:
		for y in range(40, 43):
			for x in range(5, 8):
				r.terrain[y * r.width + x] = wall)
	var sid: int = _ids(s, 1)[0]
	assert_eq(s.submit_deployment(1, [{"squad": sid, "x": _f(5.5), "y": _f(41.5), "facing": 0}]).size(), 0)
	s.ready(1)
	s.ready(2)
	var row := s.state.squads.row_of(sid)
	var ax := s.state.squads.ax[row]
	var ay := s.state.squads.ay[row]
	assert_eq(ax, _f(5.5), "snapped along the area's edge, not out of it")
	assert_true(ay == _f(39.5) or ay == _f(43.5), "nearest open cell: %d" % ay)


func test_area_with_no_enterable_cell_is_refused() -> void:
	var probe := _make()
	var wall := _wall(probe.rules, probe.state.squads.tmpl[0])
	if wall < 0:
		pending("no impassable feature in the fixture")
		return
	var s := _make(func(r: BattleRules) -> void:
		for y in range(14, 86):
			for x in range(4, 31):
				r.terrain[y * r.width + x] = wall)
	var errs := s.submit_deployment(1, [{"squad": _ids(s, 1)[0], "x": _f(10), "y": _f(30), "facing": 0}])
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "no cell")


func test_no_enemy_in_observation_while_deploying_even_in_sight() -> void:
	var s := _make(_near)
	var theirs: int = _ids(s, 2)[0]
	var sq := s.state.squads
	var row := sq.row_of(theirs)
	sq.set_value(theirs, &"seen_by", sq.seen_by[row] | BattleSquads.bit(1))
	for d: Dictionary in s.observe(1)["squads"]:
		assert_eq(d["player"], 1, "no enemy squad while deploying")
	assert_eq(s.inspect(1, theirs), {})
	for e: Dictionary in s.observe(1)["events"]:
		assert_ne(e["type"], "squad_revealed")
	var errs := s.submit_orders(1, [{"squad": _ids(s, 1)[0], "type": "attack", "target": theirs}])
	assert_string_contains(errs[0], "target not visible")
	assert_true(BattleDeploy.hides(s.state, 1, row))
	assert_false(BattleDeploy.hides(s.state, 1, row, PackedInt64Array([2])), "allies stay visible")
	assert_false(BattleDeploy.hides(s.state, 2, row), "own squads stay visible")
	s.state.deploying = false
	var seen := false
	for d: Dictionary in s.observe(1)["squads"]:
		seen = seen or d["id"] == theirs
	assert_true(seen, "the same squad shows once deployment is over")


func test_forecast_leaves_out_enemies_while_deploying() -> void:
	var s := _make(_near)
	var theirs: int = _ids(s, 2)[0]
	var sq := s.state.squads
	sq.set_value(theirs, &"seen_by", sq.seen_by[sq.row_of(theirs)] | BattleSquads.bit(1))
	var fc := s.forecast(1, [])
	for c: Dictionary in fc["contacts"]:
		assert_ne(c["target"], theirs)
	assert_true(s.state.deploying, "the forecast changes nothing")


func test_enemy_revealed_by_deployment_is_a_valid_trigger() -> void:
	var s := _make(_near)
	var mine: int = _ids(s, 1)[0]
	var theirs: int = _ids(s, 2)[0]
	s.submit_deployment(1, [{"squad": mine, "x": _f(29), "y": _f(50.5), "facing": 0}])
	s.submit_deployment(2, [{"squad": theirs, "x": _f(31), "y": _f(50.5), "facing": 32768}])
	s.ready(1)
	s.ready(2)
	assert_false(s.state.deploying)
	assert_true(Reactions.sees_at_reveal(s.state, 1, theirs), "seen once placements apply at Reveal")
	assert_true(Reactions.sees_at_reveal(s.state, 2, mine))
	var listed := false
	for d: Dictionary in s.observe(1)["squads"]:
		listed = listed or d["id"] == theirs
	assert_true(listed)


func test_no_placement_input_hashes_as_a_fixed_battle() -> void:
	var open := _make()
	var fixed := _make(_fixed)
	assert_ne(open.state.state_hash(), fixed.state.state_hash(), "deploying is hashed while set")
	_finish_turn(open)
	_finish_turn(fixed)
	assert_eq(open.state.state_hash(), fixed.state.state_hash())
	assert_eq(open.state.snapshot(), fixed.state.snapshot())


func test_save_rebuild_with_placements() -> void:
	var s := _make()
	var sid: int = _ids(s, 1)[2]
	s.submit_deployment(1, [{"squad": sid, "x": _f(20.5), "y": _f(60.5), "facing": 0}])
	var mid := BattleSession.load_save(s.save(), _l().templates, _l().data_hash)
	assert_not_null(mid)
	assert_true(mid.state.deploying)
	assert_eq((mid._deploys[1] as Array).size(), 1, "drafts saved")
	_finish_turn(s)
	var r := BattleSession.rebuild(s.save(), _l().templates, _l().data_hash)
	assert_not_null(r, BattleSession.last_error)
