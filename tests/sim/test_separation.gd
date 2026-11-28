extends GutTest
## Separation between squads (sw-txnj.12, U1Q10; GDD 02 §2.14 Separation and
## coherency): units of different squads closer than the separation distance
## of their size class are pushed apart; units of one squad never are. Core
## package squads on Crossroads' open lane (y = 80), as
## test_behaviour_movement.

const ONE := Fixed.ONE
const LANE := 80

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


## Core rules with every unit template's separation radius set to the
## `size` class's ("" keeps the data's size classes).
func _rules(size: String = "") -> BattleRules:
	var r := BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	assert_eq(r.errors, PackedStringArray())
	if size != "":
		var rad: int = r.separation[size]
		for i in r.ut_sep.size():
			r.ut_sep[i] = rad
		r.sep_cell = maxi(2 * ONE, rad * Separation.CROWD_PCT / 100)
	return r


func _place(s: BattleState, player: int, x: int, y: int, facing: int = 0) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index("rifle_squad"), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid


func _order(s: BattleState, sid: int, order: int, x: int, y: int) -> void:
	BattleOrders.set_order(s, s.squads.row_of(sid), order, x * ONE, y * ONE, -1, 0)


func _run(s: BattleState, ticks: int) -> void:
	var sim := BattleSim.new()
	for _t in ticks:
		sim.runner.step(s)


func _rows(s: BattleState, sid: int) -> PackedInt64Array:
	return Centroids.units_of(s, s.squads.row_of(sid))


## Nearest distance between a living unit of squad a and one of squad b.
func _gap(s: BattleState, a: int, b: int) -> int:
	var u := s.units
	var best := -1
	for ra in _rows(s, a):
		for rb in _rows(s, b):
			if u.hp[ra] > 0 and u.hp[rb] > 0:
				var d := Fixed.distance(u.x[ra], u.y[ra], u.x[rb], u.y[rb])
				if best < 0 or d < best:
					best = d
	return best


func _put(s: BattleState, row: int, x: int, y: int, facing: int = 0) -> void:
	var id := s.units.id_at(row)
	s.units.set_value(id, &"x", x)
	s.units.set_value(id, &"y", y)
	s.units.set_value(id, &"facing", facing)


func test_radius_by_size_class_from_the_ruleset() -> void:
	var r := _rules()
	assert_eq(r.separation["small"], DataSchema.to_fixed("0.4"))
	assert_eq(r.separation["medium"], DataSchema.to_fixed("0.6"))
	assert_eq(r.separation["large"], DataSchema.to_fixed("1.2"))
	assert_eq(r.separation["huge"], DataSchema.to_fixed("2.4"))
	assert_eq(r.ut_sep[r.unit_ids.find("trooper")], r.separation["medium"], "troopers are medium")
	assert_true(r.sep_cell >= 2 * ONE)


func test_two_squads_on_one_point_end_apart_by_size_class() -> void:
	for size in ["small", "medium", "large"]:
		var r := _rules(size)
		var lim: int = r.separation[size]
		var s := BattleState.new(1, r, 1)
		var north := _place(s, 1, 20, LANE - 10)
		var south := _place(s, 1, 20, LANE + 10)
		_order(s, north, BattleSquads.Order.MOVE, 55, LANE)
		_order(s, south, BattleSquads.Order.MOVE, 55, LANE)
		_run(s, 300)
		var gap := _gap(s, north, south)
		assert_true(gap >= lim, "%s: nearest pair %.3f m, not under %.3f m" % [size, gap / float(ONE), lim / float(ONE)])
		assert_true(gap < lim + 2 * ONE, "%s: the squads share the point (%.3f m)" % [size, gap / float(ONE)])
		assert_true(Fixed.distance(s.squads.ax[s.squads.row_of(north)], s.squads.ay[s.squads.row_of(north)], 55 * ONE, LANE * ONE) <= ONE, "%s: north arrived" % size)


func test_units_of_one_squad_are_never_pushed() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, 50, LANE)
	var rows := _rows(s, sid)
	_put(s, rows[0], 50 * ONE, LANE * ONE)
	_put(s, rows[1], 50 * ONE, LANE * ONE)
	Separation.new().run(s)
	assert_eq(s.units.x[rows[0]], 50 * ONE)
	assert_eq(s.units.x[rows[1]], 50 * ONE)
	assert_eq(s.units.crowded[rows[0]], 0)


func test_pair_is_pushed_apart_half_each_and_marked_crowded() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _rows(s, _place(s, 1, 40, LANE))[0]
	var b := _rows(s, _place(s, 2, 70, LANE))[0]
	_put(s, a, 50 * ONE, LANE * ONE)
	_put(s, b, 50 * ONE + ONE * 2 / 10, LANE * ONE)
	var sep := Separation.new()
	sep.run(s)
	assert_eq(sep.pushes, 1)
	var u := s.units
	assert_true(u.x[b] - u.x[a] >= s.rules.separation["medium"], "0.6 m apart: %d" % (u.x[b] - u.x[a]))
	assert_eq(u.y[a], LANE * ONE, "along the line between them")
	assert_eq(50 * ONE - u.x[a], u.x[b] - (50 * ONE + ONE * 2 / 10), "half the overlap each")
	assert_eq(u.crowded[a], 1)
	assert_eq(u.crowded[b], 1)
	# Apart now: a second pass pushes nothing, but they are still crowded.
	sep.run(s)
	assert_eq(sep.pushes, 0)
	assert_eq(u.crowded[a], 1)


func test_same_point_pushes_along_the_lower_unit_ids_facing() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _rows(s, _place(s, 1, 40, LANE))[0]
	var b := _rows(s, _place(s, 2, 70, LANE))[0]
	var lo := a if s.units.id_at(a) < s.units.id_at(b) else b
	var hi := b if lo == a else a
	_put(s, lo, 50 * ONE, LANE * ONE, Fixed.ANGLE_QUARTER)  # facing south
	_put(s, hi, 50 * ONE, LANE * ONE, 0)
	Separation.new().run(s)
	var u := s.units
	var info := "lo %d (%d,%d) f%d hi %d (%d,%d)" % [lo, u.x[lo], u.y[lo], u.facing[lo], hi, u.x[hi], u.y[hi]]
	assert_eq(u.x[lo], 50 * ONE)
	assert_eq(u.x[hi], 50 * ONE)
	assert_true(u.y[lo] > LANE * ONE, "the lower ID steps forward (south) " + info)
	assert_true(u.y[hi] < LANE * ONE, "the other steps back " + info)
	assert_true(u.y[lo] - u.y[hi] >= s.rules.separation["medium"], "apart by 0.6 m " + info)


func test_push_is_capped_at_walk_speed_for_a_standing_unit() -> void:
	var r := _rules("huge")
	var s := BattleState.new(1, r, 1)
	var a := _rows(s, _place(s, 1, 40, LANE))[0]
	var b := _rows(s, _place(s, 2, 70, LANE))[0]
	_put(s, a, 50 * ONE, LANE * ONE)
	_put(s, b, 50 * ONE + ONE / 10, LANE * ONE)
	Separation.new().run(s)
	var walk := Fixed.round_div(r.mv_walk_s[r.ut_movement[s.units.tmpl[a]]], r.tps)
	assert_true(50 * ONE - s.units.x[a] <= walk, "capped: %d > %d" % [50 * ONE - s.units.x[a], walk])
	assert_true(50 * ONE - s.units.x[a] > 0)


func test_push_never_enters_a_cell_the_unit_cannot() -> void:
	var r := _rules()
	var wall := -1
	var profile := r.ut_movement[r.unit_ids.find("trooper")]
	for f in r.feature_count():
		if r.mv_cost[profile * r.feature_count() + f] <= 0:
			wall = f
			break
	if wall < 0:
		pending("no impassable feature in core")
		return
	r.terrain[LANE * r.width + 51] = wall
	var s := BattleState.new(1, r, 1)
	var a := _rows(s, _place(s, 1, 40, LANE))[0]
	var b := _rows(s, _place(s, 2, 70, LANE))[0]
	# a stands against the wall at x = 51; b just west pushes it east.
	_put(s, a, 51 * ONE - ONE / 20, LANE * ONE + ONE / 2)
	_put(s, b, 51 * ONE - ONE / 4, LANE * ONE + ONE / 2)
	Separation.new().run(s)
	assert_true(s.units.x[a] < 51 * ONE, "never into the wall: %d" % s.units.x[a])
	assert_true(s.units.x[b] < 51 * ONE - ONE / 4, "b still moves away")


func test_head_on_walkers_step_around_each_other() -> void:
	# Two single files walking straight at each other along the lane: the
	# pushes slide them sideways instead of locking them in place. Both are
	# player 1's, so no fire or morale decides whether they arrive.
	var s := BattleState.new(1, _rules(), 1)
	var west := _place(s, 1, 40, LANE)
	var east := _place(s, 1, 70, LANE, Fixed.ANGLE_HALF)
	_order(s, west, BattleSquads.Order.MOVE, 70, LANE)
	_order(s, east, BattleSquads.Order.MOVE, 40, LANE)
	_run(s, 300)
	var sq := s.squads
	for sid in [west, east]:
		var row := sq.row_of(sid)
		var tx := 70 * ONE if sid == west else 40 * ONE
		assert_true(Fixed.distance(sq.ax[row], sq.ay[row], tx, LANE * ONE) <= ONE, "anchor arrived")
		for urow in _rows(s, sid):
			var slot := MovementSystem.slot_point(s, urow, row)
			assert_true(Fixed.distance(s.units.x[urow], s.units.y[urow], slot[0], slot[1]) <= ONE,
				"unit reached its slot (%.2f m off)" % (Fixed.distance(s.units.x[urow], s.units.y[urow], slot[0], slot[1]) / float(ONE)))


func test_same_inputs_same_positions() -> void:
	var out := []
	for i in 2:
		var s := BattleState.new(1, _rules(), 7)
		var north := _place(s, 1, 20, LANE - 10)
		var south := _place(s, 1, 20, LANE + 10)
		_order(s, north, BattleSquads.Order.MOVE, 55, LANE)
		_order(s, south, BattleSquads.Order.MOVE, 55, LANE)
		_run(s, 200)
		out.append(s.state_hash())
	assert_eq(out[0], out[1])
