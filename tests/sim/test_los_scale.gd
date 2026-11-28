extends GutTest
## Line of sight at scale (sw-arse): the jump walk over the blocker distance
## field and the bounded answer cache must answer exactly what the reference
## blocker walk (BattleRules._walk_los) answers, for every pair of cells, so
## no battle changes. Checked on painted maps from empty to nearly solid, on
## the core Crossroads map, exhaustively around a point, and through a whole
## battle against rules that trace with the reference walk.

const ONE := Fixed.ONE


## Reference rules: los() is the awareness test plus the plain blocker walk,
## with no field and no cache (the rule before sw-arse, minus its memo).
class WalkRules extends BattleRules:
	func los(ax: int, ay: int, bx: int, by: int) -> bool:
		var ex := bx - ax
		var ey := by - ay
		if ex * ex + ey * ey <= AWARENESS_SQ_LIMIT:
			return true
		return _walk_los(clampi(ax >> Fixed.FRAC_BITS, 0, width - 1), clampi(ay >> Fixed.FRAC_BITS, 0, height - 1),
			clampi(bx >> Fixed.FRAC_BITS, 0, width - 1), clampi(by >> Fixed.FRAC_BITS, 0, height - 1))


static var _core: PackageLoader


func _loader() -> PackageLoader:
	if _core == null:
		_core = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _core


func _crossroads() -> BattleRules:
	return BattleRules.compile(_loader().templates, "duel_crossroads", _loader().data_hash)


func _blocker(r: BattleRules) -> int:
	for f in r.f_blocks_los.size():
		if r.f_blocks_los[f] == 1:
			return f
	return -1


## Paints about `pct` percent of the cells with a blocker (a fixed LCG, so
## every run paints the same map), in clumps and singles.
func _paint(r: BattleRules, pct: int, seed_in: int) -> void:
	var blocker := _blocker(r)
	var open := r.feature_ids.find("open")
	var seed := seed_in
	for c in r.terrain.size():
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		r.terrain[c] = blocker if seed % 100 < pct else open
	r.clear_los_memo()


func _rand(seed: int) -> int:
	return (seed * 1103515245 + 12345) & 0x7FFFFFFF


## Mismatches between _jump_los and _walk_los over `n` random cell pairs of
## any length on the map; the first few are listed in `bad`.
func _compare_random(r: BattleRules, n: int, seed_in: int, bad: Array) -> int:
	var wrong := 0
	var seed := seed_in
	for i in n:
		seed = _rand(seed)
		var x0 := seed % r.width
		seed = _rand(seed)
		var y0 := seed % r.height
		seed = _rand(seed)
		var x1 := seed % r.width
		seed = _rand(seed)
		var y1 := seed % r.height
		if i % 3 == 0:
			# A third of the pairs within weapon range, where most traces are.
			seed = _rand(seed)
			x1 = clampi(x0 + seed % 81 - 40, 0, r.width - 1)
			seed = _rand(seed)
			y1 = clampi(y0 + seed % 81 - 40, 0, r.height - 1)
		if r._jump_los(x0, y0, x1, y1) != r._walk_los(x0, y0, x1, y1):
			wrong += 1
			if bad.size() < 5:
				bad.append([x0, y0, x1, y1])
	return wrong


## The walk visits cell i of a line at a closed form (the jump relies on it):
## every direction and every offset up to 48 cells, against the walk itself.
func test_walk_cells_have_a_closed_form() -> void:
	var wrong := 0
	for a in range(0, 49):
		for b in range(0, 49):
			if a == 0 and b == 0:
				continue
			for sgn in 4:
				var sx := 1 if sgn & 1 == 0 else -1
				var sy := 1 if sgn & 2 == 0 else -1
				var cells := _walk_cells(0, 0, sx * a, sy * b)
				var n := maxi(a, b)
				if cells.size() != 2 * (n + 1):
					wrong += 1
					continue
				for i in n + 1:
					var x := sx * i if a >= b else sx * ((2 * a * i + b) / (2 * b))
					var y := sy * ((2 * b * i + a) / (2 * a)) if a >= b else sy * i
					if cells[2 * i] != x or cells[2 * i + 1] != y:
						wrong += 1
						break
	assert_eq(wrong, 0, "every walk cell matches the closed form")


## The cells _walk_los visits, as x, y pairs (its loop, without terrain).
func _walk_cells(x0: int, y0: int, x1: int, y1: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		out.append_array([x, y])
		if x == x1 and y == y1:
			return out
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return out


## The jump walk answers like the walk on maps from empty to nearly solid.
func test_jump_los_answers_like_the_walk() -> void:
	var r := _crossroads()
	var total := 0
	var blocked := 0
	for pct in [0, 2, 6, 15, 30, 50, 80, 97]:
		_paint(r, pct, 1000 + pct)
		var bad := []
		var wrong := _compare_random(r, 3000, 77 + pct, bad)
		assert_eq(wrong, 0, "%d%% blockers: mismatches at %s" % [pct, bad])
		total += 3000
	# How many of the sampled lines were blocked, so the sample covers both.
	_paint(r, 15, 1015)
	var seed := 9
	for i in 2000:
		seed = _rand(seed)
		var x0 := seed % r.width
		seed = _rand(seed)
		var y0 := seed % r.height
		seed = _rand(seed)
		if not r._walk_los(x0, y0, seed % r.width, (seed >> 8) % r.height):
			blocked += 1
	assert_gt(blocked, 100, "the 15% sample includes blocked lines")
	assert_lt(blocked, 1990, "and clear ones")
	assert_eq(total, 24000)


## Every cell within 30 of a point, from points in the open, in a forest
## clump and at a map corner, on Crossroads as authored.
func test_jump_los_exhaustive_around_points_on_crossroads() -> void:
	var r := _crossroads()
	r.los_ready()
	var wrong := 0
	var bad := []
	for p in [[100, 50], [30, 20], [0, 0], [199, 99], [150, 70]]:
		for dy in range(-30, 31):
			for dx in range(-30, 31):
				var x1 := clampi(p[0] + dx, 0, r.width - 1)
				var y1 := clampi(p[1] + dy, 0, r.height - 1)
				if r._jump_los(p[0], p[1], x1, y1) != r._walk_los(p[0], p[1], x1, y1):
					wrong += 1
					if bad.size() < 5:
						bad.append([p[0], p[1], x1, y1])
	assert_eq(wrong, 0, "mismatches at %s" % [bad])
	var bad2 := []
	assert_eq(_compare_random(r, 20000, 4242, bad2), 0, "random pairs: %s" % [bad2])


## los() (awareness, clamping, the cache) answers like the reference on
## fixed-point points, including repeats served from the cache and points
## off the map.
func test_los_answers_like_the_reference() -> void:
	var r := _crossroads()
	_paint(r, 12, 5)
	var ref := WalkRules.new()
	for p in r.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			ref.set(p.name, r.get(p.name))
	var seed := 31337
	var wrong := 0
	for i in 6000:
		seed = _rand(seed)
		var ax := (seed % (r.width * 2 + 20) - 10) * ONE / 2 + (seed & 0x3FF)
		seed = _rand(seed)
		var ay := (seed % (r.height * 2 + 20) - 10) * ONE / 2 + (seed & 0x3FF)
		seed = _rand(seed)
		var bx := ax + (seed % 121 - 60) * ONE + (seed & 0xFFF)
		seed = _rand(seed)
		var by := ay + (seed % 121 - 60) * ONE + (seed & 0xFFF)
		var want := ref.los(ax, ay, bx, by)
		if r.los(ax, ay, bx, by) != want or r.los(ax, ay, bx, by) != want:
			wrong += 1
	assert_eq(wrong, 0, "los() agrees with the reference, first time and cached")
	assert_eq(r.los_cache.size(), BattleRules.LOS_CACHE_SLOTS, "the cache stays its fixed size")
	assert_eq(r.los_dist.size(), r.width * r.height, "one distance byte per cell")


## clear_los_memo rebuilds the field: a wall painted after a trace blocks.
func test_clear_los_memo_sees_new_terrain() -> void:
	var r := _crossroads()
	var open := r.feature_ids.find("open")
	r.terrain.fill(open)
	r.clear_los_memo()
	assert_true(r.los(10 * ONE, 10 * ONE, 40 * ONE, 10 * ONE), "open ground: clear")
	var wall := r.feature_ids.find("wall")
	for x in [20, 21, 22]:
		r.terrain[10 * r.width + x] = wall
	r.clear_los_memo()
	assert_false(r.los(10 * ONE, 10 * ONE, 40 * ONE, 10 * ONE), "three wall cells between: blocked")


func test_forecast_copy_shares_the_field_and_has_its_own_cache() -> void:
	var r := _crossroads()
	r.clear_los_memo()
	r.los(0, 0, 60 * ONE, 60 * ONE)
	var c := r.forecast_copy()
	assert_eq(c.los_dist, r.los_dist, "the copy reads the same field")
	assert_eq(c.los_cache.count(-1), BattleRules.LOS_CACHE_SLOTS, "a copy starts with an empty cache")
	var filled := r.los_cache.count(-1)
	c.los(0, 0, 60 * ONE, 60 * ONE)
	c.los(5 * ONE, 0, 60 * ONE, 70 * ONE)
	assert_lt(c.los_cache.count(-1), BattleRules.LOS_CACHE_SLOTS, "the copy caches on its own")
	assert_eq(r.los_cache.count(-1), filled, "the original's cache is untouched")


## A whole battle (both sides attack-moving across Crossroads, 300 ticks)
## ends in the same state hash as with rules that trace with the plain walk:
## the field and the cache never change an answer the sim reads.
func test_battle_hash_matches_the_plain_walk() -> void:
	var fast := _crossroads()
	var slow := WalkRules.new()
	for p in fast.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			slow.set(p.name, fast.get(p.name))
	slow.routes = BattleRoute.new()
	var hashes := []
	for r: BattleRules in [fast, slow]:
		Stats.warm(r)
		r.routes.warm(r)
		var s := _attack_moving(r, 16)
		var sim := BattleSim.new()
		s.begin_turn()
		for t in 300:
			if t > 0 and t % r.ticks_per_turn == 0:
				s.begin_turn()
			sim.runner.step(s)
		hashes.append(s.state_hash().hex_encode())
	assert_eq(hashes[0], hashes[1], "same state hash")


## n squads, half per side, 60 m apart across Crossroads, each attack-moving
## at its mirror (the docs/design/u1/scripts/fp fixture).
func _attack_moving(r: BattleRules, n: int) -> BattleState:
	var mix := ["rifle_squad", "rifle_squad", "heavy_weapons_team", "marksman_team", "scout_team"]
	var s := BattleState.new(1, r, 1)
	for i in n / 2:
		var y := 50 - 21 + (i / 4) * 14
		var st := r.squad_index(mix[i % mix.size()])
		var a := BattleSetup.spawn_squad(s, 1, st, (70 - (i % 4) * 7) * ONE, y * ONE, 0)
		var b := BattleSetup.spawn_squad(s, 2, st, (130 + (i % 4) * 7) * ONE, y * ONE, Fixed.ANGLE_HALF)
		Centroids.update(s)
		var ra := s.squads.row_of(a)
		var rb := s.squads.row_of(b)
		BattleOrders.set_order(s, ra, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[rb], s.squads.cy[rb], -1, 0)
		BattleOrders.set_order(s, rb, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[ra], s.squads.cy[ra], -1, 0)
	Centroids.update(s)
	return s


## VisionSystem's grid and per-tick observer columns (sw-arse) give the
## seen_by masks the old pair-by-pair loop gives, with concealment and
## detection in play, at several ticks of a closing battle.
func test_vision_grid_matches_the_pair_rule() -> void:
	var r := _crossroads()
	Stats.warm(r)
	r.routes.warm(r)
	# Concealed scouts and marksmen, detecting heavy weapons, so every branch
	# of the reach rule runs.
	r.sq_concealment[r.squad_index("scout_team")] = 45
	r.sq_concealment[r.squad_index("marksman_team")] = 20
	r.sq_detection[r.squad_index("heavy_weapons_team")] = 30 * ONE
	var s := _attack_moving(r, 24)
	var sim := BattleSim.new()
	var vs := VisionSystem.new()
	var wrong := 0
	var seen_some := false
	s.begin_turn()
	for t in 240:
		if t > 0 and t % r.ticks_per_turn == 0:
			s.begin_turn()
		sim.runner.step(s)
		if t % 20 != 0:
			continue
		var want := _pair_seen(s, vs)
		vs.run(s)
		for row in s.squads.count():
			if s.squads.seen_by[row] != want[row]:
				wrong += 1
			if s.squads.seen_by[row] != BattleSquads.bit(s.squads.player[row]):
				seen_some = true
	assert_eq(wrong, 0, "same seen_by as the pair rule")
	assert_true(seen_some, "squads saw enemies")


## The pre-sw-arse loop: every pair of squads through VisionSystem._sees.
func _pair_seen(state: BattleState, vs: VisionSystem) -> PackedInt64Array:
	var sq := state.squads
	var n := sq.count()
	var out := PackedInt64Array()
	out.resize(n)
	for t in n:
		if not sq.is_active(t):
			continue
		var mask := BattleSquads.bit(sq.player[t])
		var ct := vs.concealment_pct(state, t)
		for o in n:
			if o == t or not sq.is_active(o) or sq.alive[o] == 0 or sq.player[o] == sq.player[t]:
				continue
			if vs._sees(state, o, t, ct):
				mask |= BattleSquads.bit(sq.player[o])
		out[t] = mask | vs._revealed(state, t)
	return out


## fp_search_scale_squads (sw-arse, proposed): off by default, so the
## per-battle firing-position budgets stay fixed; set to N, a battle gets
## ceil(living squads / N) times them, so up to N squads nothing changes.
func test_firing_position_budget_scales_only_when_set() -> void:
	var r := _crossroads()
	assert_eq(r.fp_search_scale, 0, "core data leaves it off")
	var s := _attack_moving(r, 24)
	assert_eq(FiringPositions.budget_scale(s), 1, "off: one budget")
	r.fp_search_scale = 24
	assert_eq(FiringPositions.budget_scale(s), 1, "24 squads, one per 24: one budget")
	r.fp_search_scale = 10
	assert_eq(FiringPositions.budget_scale(s), 3, "24 squads, one per 10: three")
	r.fp_search_scale = 0
