extends GutTest
## Squad footprints (sw-txnj.13, GDD 02 §2.14): friendly squads ordered to
## one point are given points one footprint (formation width) apart, the
## nearest free ring position first, then the one nearest the squad, then
## the lowest cell index. Orders go
## through BattleOrders.apply, which is where the spread happens.

const ONE := Fixed.ONE
const LANE := 80
const PX := 100
const PY := 80

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _state() -> BattleState:
	var r := BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	assert_eq(r.errors, PackedStringArray())
	return BattleState.new(1, r, 1)


func _place(s: BattleState, player: int, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index("rifle_squad"), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _move(sid: int, x: int, y: int, type: String = "move") -> Dictionary:
	return {"squad": sid, "type": type, "x": x * ONE, "y": y * ONE}


func _point(s: BattleState, sid: int) -> PackedInt64Array:
	var row := s.squads.row_of(sid)
	return PackedInt64Array([s.squads.tx[row], s.squads.ty[row]])


func _fp(s: BattleState, sid: int) -> int:
	return s.rules.sq_footprint[s.squads.tmpl[s.squads.row_of(sid)]]


func test_footprint_is_the_formation_width_from_the_ruleset() -> void:
	var s := _state()
	var sid := _place(s, 1, 20, LANE)
	var row := s.squads.row_of(sid)
	var rules := s.rules
	var half := Formation.half_width(rules.sq_shape[s.squads.tmpl[row]], rules.sq_members[s.squads.tmpl[row]].size(), rules.sq_spacing[s.squads.tmpl[row]])
	assert_eq(_fp(s, sid), maxi(2 * half, rules.sq_spacing[s.squads.tmpl[row]]))
	assert_true(_fp(s, sid) > 0)


func test_three_squads_on_one_point_stand_one_footprint_apart() -> void:
	var s := _state()
	var a := _place(s, 1, 60, PY)
	var b := _place(s, 1, 60, PY + 4)
	var c := _place(s, 1, 60, PY - 4)
	var fp := _fp(s, a)
	var errors := BattleOrders.apply(s, 1, [_move(a, PX, PY), _move(b, PX, PY), _move(c, PX, PY)])
	assert_eq(errors, PackedStringArray())
	# The first squad keeps the point. Ring 1's nearest points are the four
	# one footprint due west, north, south and east; the squads come from
	# the west, so b takes the west point (its approach side) and c, from
	# the north-west, the north point.
	assert_eq(_point(s, a), PackedInt64Array([PX * ONE, PY * ONE]), "first keeps its point")
	assert_eq(_point(s, b), PackedInt64Array([PX * ONE - fp, PY * ONE]), "second takes the ring point on its approach side")
	assert_eq(_point(s, c), PackedInt64Array([PX * ONE, PY * ONE - fp]), "third takes the nearest free ring point to it")
	# Each squad is a footprint from the first.
	for sid in [b, c]:
		var q := _point(s, sid)
		assert_true(absi(Fixed.distance(PX * ONE, PY * ONE, q[0], q[1]) - fp) <= 2, "one footprint from the first")


func test_spread_is_deterministic_for_the_same_orders() -> void:
	var out := []
	for _run in 2:
		var s := _state()
		var a := _place(s, 1, 60, PY)
		var b := _place(s, 1, 60, PY + 4)
		var c := _place(s, 1, 60, PY - 4)
		BattleOrders.apply(s, 1, [_move(a, PX, PY), _move(b, PX, PY), _move(c, PX, PY)])
		out.append([_point(s, a), _point(s, b), _point(s, c)])
	assert_eq(out[0], out[1])


func test_a_later_order_takes_a_free_ring_point_around_an_earlier_one() -> void:
	var s := _state()
	var a := _place(s, 1, 60, PY)
	var b := _place(s, 1, 60, PY + 4)
	BattleOrders.apply(s, 1, [_move(a, PX, PY)])
	assert_eq(_point(s, a), PackedInt64Array([PX * ONE, PY * ONE]))
	# Given its order in a later turn, b sees a already on the point.
	BattleOrders.apply(s, 1, [_move(b, PX, PY)])
	# b comes from the west: ring 1's west point, not a far corner.
	var fp := _fp(s, b)
	assert_eq(_point(s, b), PackedInt64Array([PX * ONE - fp, PY * ONE]), "b takes ring 1's west point")


func test_a_follower_from_the_far_side_stays_on_its_side() -> void:
	var s := _state()
	var a := _place(s, 1, 60, PY)
	var b := _place(s, 1, 140, PY)
	BattleOrders.apply(s, 1, [_move(a, PX, PY), _move(b, PX, PY)])
	var fp := _fp(s, b)
	assert_eq(_point(s, b), PackedInt64Array([PX * ONE + fp, PY * ONE]), "b, from the east, takes the east point")


func test_a_squad_keeps_its_own_point_when_reordered_there() -> void:
	var s := _state()
	var a := _place(s, 1, 60, PY)
	BattleOrders.apply(s, 1, [_move(a, PX, PY)])
	BattleOrders.apply(s, 1, [_move(a, PX, PY)])
	assert_eq(_point(s, a), PackedInt64Array([PX * ONE, PY * ONE]), "its own point is not taken by itself")


func test_other_players_squads_and_other_points_are_untouched() -> void:
	var s := _state()
	var mine := _place(s, 1, 60, PY)
	var theirs := _place(s, 2, 60, PY + 4)
	var far := _place(s, 1, 60, LANE + 30)
	BattleOrders.apply(s, 1, [_move(mine, PX, PY)])
	BattleOrders.apply(s, 2, [_move(theirs, PX, PY)])
	assert_eq(_point(s, mine), PackedInt64Array([PX * ONE, PY * ONE]), "an enemy on the point doesn't move ours")
	assert_eq(_point(s, theirs), PackedInt64Array([PX * ONE, PY * ONE]), "nor does ours move theirs")
	BattleOrders.apply(s, 1, [_move(far, PX + 40, PY)])
	assert_eq(_point(s, far), PackedInt64Array([(PX + 40) * ONE, PY * ONE]), "a free point is kept as ordered")


func test_hold_orders_do_not_take_part() -> void:
	var s := _state()
	var holder := _place(s, 1, 60, PY)
	var mover := _place(s, 1, 60, PY + 4)
	BattleOrders.apply(s, 1, [{"squad": holder, "type": "hold"}, _move(mover, 60, PY)])
	assert_eq(_point(s, mover), PackedInt64Array([60 * ONE, PY * ONE]), "a holding squad's spot is not a destination")


func test_attack_move_counts_like_move() -> void:
	var s := _state()
	var a := _place(s, 1, 60, PY)
	var b := _place(s, 1, 60, PY + 4)
	BattleOrders.apply(s, 1, [_move(a, PX, PY, "attack_move"), _move(b, PX, PY, "attack_move")])
	assert_ne(_point(s, b), _point(s, a), "attack-move squads are spread too")
