extends GutTest
## The moving-fire Instinct sink (sw-txnj.8, U1 A8): a squad pays
## instinct_fire_moving_per_s per second, once per tick, while any of its
## units fires on the move. It used to pay per unit volley, so an 8-unit
## squad decayed 8x faster than a 1-unit one. Built on the core package's
## draft 01 table B rifle squad.

const ONE := Fixed.ONE
const LANE := 80

static var _rules: BattleRules


func _r() -> BattleRules:
	if _rules == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules


## A rifle squad of `size` units (the squad template's full strength when 0).
func _place(s: BattleState, player: int, x: int, y: int, size: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _r().squad_index("rifle_squad"), x * ONE, y * ONE, 0, size)
	Centroids.update(s)
	return sid


## An unarmed, 1000-HP squad that stands still in the enemy's reach.
func _dummy(s: BattleState, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, 2, _r().squad_index("rifle_squad"), x * ONE, y * ONE, Fixed.ANGLE_HALF)
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		var id := s.units.id_at(urow)
		s.units.set_value(id, &"weapon", -1)
		s.units.set_value(id, &"hp", 1000 * ONE)
		s.units.set_value(id, &"hp_max", 1000 * ONE)
	Centroids.update(s)
	return sid


## Runs `ticks` ticks. Returns [ticks with a moving-fire sink, the sink
## total in fixed point]: a tick counts when the squad's ledger shows the
## moving-fire sink that tick (read per step, so no drift in the count).
## `lowest` keeps the lowest Instinct seen.
func _run_counting(s: BattleState, sid: int, ticks: int, lowest: Array) -> Array:
	var sim := BattleSim.new()
	var row := s.squads.row_of(sid)
	var moving_ticks := 0
	var total := 0
	for _t in ticks:
		var before := _fire_moving_sink(s, sid)
		sim.runner.step(s)
		var delta := _fire_moving_sink(s, sid) - before
		if delta != 0:
			moving_ticks += 1
			total += delta
		lowest[0] = mini(lowest[0], Pools.value(s, row, BattleSquads.INSTINCT))
	return [moving_ticks, total]


## The moving-fire sink booked so far for squad `sid` (negative: a sink).
func _fire_moving_sink(s: BattleState, sid: int) -> int:
	for entry: Dictionary in s.ledger_of(sid, BattleSquads.INSTINCT):
		if entry["source"] == "fire_moving":
			return int(entry["amount"])
	return 0


## An 8-unit squad walking and firing at a dummy in reach for 10 s keeps its
## Instinct at or above the Fraying band's lower bound.
func test_eight_units_moving_fire_for_ten_seconds_stays_fraying_or_better() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, 20, LANE, 8)
	_dummy(s, 50, LANE + 10)
	BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.MOVE, 80 * ONE, LANE * ONE, -1, 0)
	var row := s.squads.row_of(me)
	var lowest := [Pools.value(s, row, BattleSquads.INSTINCT)]
	var res := _run_counting(s, me, 100, lowest)
	var cap := Pools.capacity(s, row, BattleSquads.INSTINCT)
	var fraying_floor := Fixed.round_div(cap * _r().band_floor_pct[1], 100)
	assert_true(res[0] >= 90, "moving fire on at least 90 of 100 ticks: %d" % res[0])
	assert_true(lowest[0] >= fraying_floor, "Instinct %d stays >= Fraying floor %d" % [lowest[0], fraying_floor])
	assert_eq(res[1], -res[0] * Fixed.round_div(2 * ONE, _r().tps),
		"the sink is 2 Instinct per second, once per tick of moving fire")


## The sink does not depend on squad size: a 2-unit and an 8-unit squad pay
## the same Instinct per tick of moving fire.
func test_moving_sink_is_per_tick_whatever_the_squad_size() -> void:
	var per_tick := {}
	for size in [2, 8]:
		var s := BattleState.new(1, _r(), 1)
		var me := _place(s, 1, 20, LANE, size)
		_dummy(s, 50, LANE + 10)
		BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.MOVE, 80 * ONE, LANE * ONE, -1, 0)
		var lowest := [Pools.value(s, s.squads.row_of(me), BattleSquads.INSTINCT)]
		var res := _run_counting(s, me, 100, lowest)
		assert_true(res[0] > 0, "%d-unit squad pays the moving-fire sink" % size)
		per_tick[size] = res[1] / res[0]
	assert_eq(per_tick[2], per_tick[8], "2 and 8 units pay the same Instinct per moving tick")
	assert_eq(per_tick[8], -Fixed.round_div(2 * ONE, _r().tps), "per tick is 2 Instinct per second over the tick rate")


## A squad on hold fire at the same range pays no moving-fire sink.
func test_standing_fire_pays_no_moving_sink() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, 20, LANE, 8)
	_dummy(s, 50, LANE + 10)
	BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.HOLD, 0, 0, -1, 0)
	var lowest := [Pools.value(s, s.squads.row_of(me), BattleSquads.INSTINCT)]
	var res := _run_counting(s, me, 60, lowest)
	assert_eq(res[0], 0, "a squad on hold never pays the moving-fire sink")
