extends GutTest
## The opt-in shot trace behind readable playback (sw-aba), and BattleFx's
## timing: projectiles land when the hit is applied, misses fly past.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _battle(seed_value: int) -> BattleState:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return BattleSetup.create(1, BattleRules.compile(_loader.templates, "duel_crossroads", _loader.data_hash), seed_value)


func _fight(s: BattleState, turns: int) -> void:
	var sim := BattleSim.new()
	for _t in turns:
		if s.is_over():
			return
		for p in [1, 2]:
			var orders := []
			for row in s.squads.count():
				if s.squads.player[row] == p and s.squads.is_active(row):
					orders.append({"squad": s.squads.id_at(row), "type": "attack_move", "x": 100 * ONE, "y": 50 * ONE})
			BattleOrders.apply(s, p, orders)
		sim.execute_turn(s)


func test_trace_records_shots_and_hits_without_changing_the_battle() -> void:
	var plain := _battle(3)
	_fight(plain, 4)
	assert_eq(plain.shot_trace.size(), 0, "off by default")
	var traced := _battle(3)
	traced.trace_shots = true
	_fight(traced, 4)
	assert_eq(traced.state_hash(), plain.state_hash(), "tracing never changes the outcome")
	var st := traced.shot_trace
	assert_gt(st.size(), 0, "shots traced")
	assert_eq(st.size() % BattleState.SHOT_STRIDE, 0)
	var hit := 0
	var miss := 0
	for o in range(0, st.size(), BattleState.SHOT_STRIDE):
		if st[o + 3] == 1:
			hit += 1
		else:
			miss += 1
	assert_gt(hit, 0, "some shots hit")
	assert_gt(miss, 0, "some miss")
	assert_gt(traced.hit_trace.size(), 0, "hits applied are traced with their damage")


## Shooter at (0, 0), victim at (30, 0): a hit landing at frame 15 and a
## miss passing at frame 40; the victim is killed by a hit at frame 65.
func _rec() -> Dictionary:
	var frames := []
	for i in 66:
		var f := {1: {"player": 1, "facing": 0, "ids": [10], "units": [Vector2(0, 0)], "tmpls": ["trooper"], "hp": [1.0], "acts": [0]}}
		if i < 65:
			f[2] = {"player": 2, "facing": 0, "ids": [20], "units": [Vector2(30, 0)], "tmpls": ["trooper"], "hp": [1.0], "acts": [0]}
		frames.append(f)
	return {"frames": frames, "volleys": [[15, 10, 20, true], [40, 10, 20, false], [65, 10, 20, true]],
		"hits": [[15, 20, 3 * ONE, 10], [65, 20, 5 * ONE, 10]]}


func test_a_hit_lands_on_its_frame_with_flash_and_number() -> void:
	var fx := BattleFx.from_playback(_rec())
	var flight := 30.0 / BattleFx.SPEED
	assert_eq(fx.projectiles(15.0 - flight - 0.5).size(), 0, "not launched yet")
	var mid := fx.projectiles(15.0 - flight * 0.5)
	assert_eq(mid.size(), 1, "in flight")
	assert_almost_eq((mid[0]["at"] as Vector2).x, 15.0, 0.5, "halfway there halfway through")
	assert_eq(fx.projectiles(15.0).size(), 0, "gone once it lands")
	assert_lt(float(fx.recoil(15.0 - flight + 0.5).get(10, 0.0)), 0.0, "shooter tilts back, away from a target on its right")
	assert_false(fx.flashes(14.9).has(20), "no flash before it lands")
	assert_gt(float(fx.flashes(15.0).get(20, 0.0)), 0.9, "flash as it lands")
	var texts := fx.floaters(15.5)
	assert_eq(texts.size(), 1)
	assert_eq(texts[0]["text"], "3")
	assert_almost_eq((texts[0]["at"] as Vector2).x, 30.0, 0.01, "over the unit hit")


func test_a_miss_flies_past_and_floats_over_the_shooter() -> void:
	var fx := BattleFx.from_playback(_rec())
	var after := fx.projectiles(41.0)
	assert_eq(after.size(), 1, "still flying after passing the target")
	assert_gt((after[0]["at"] as Vector2).x, 30.0, "behind the target")
	assert_lt(float(after[0]["alpha"]), 1.0, "fading")
	var texts := fx.floaters(40.5).filter(func(t: Dictionary) -> bool: return t["miss"])
	assert_eq(texts.size(), 1)
	assert_eq(texts[0]["text"], "miss")
	assert_almost_eq((texts[0]["at"] as Vector2).x, 0.0, 0.01, "over the shooter")
	assert_false(fx.flashes(40.5).has(20), "a miss never flashes the target")


func test_a_killed_unit_topples_where_it_stood() -> void:
	var fx := BattleFx.from_playback(_rec())
	var d := fx.dying(65.5)
	assert_eq(d.size(), 1)
	assert_eq(d[0]["pos"], Vector2(30, 0))
	assert_eq(fx.floaters(65.5)[0]["text"], "5", "its damage still floats")
