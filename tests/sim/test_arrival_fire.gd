extends GutTest
## The arrival tick (U1Q28, sw-txnj.17): a unit under an attack order that
## reaches its firing position this tick stands on it and fires in standing
## mode, not a moving volley. Walking units with a moving mode still fire on
## the move. Built on the core package's draft 01 table B rifle squad.

const ONE := Fixed.ONE
const LANE := 80

static var _rules: BattleRules


func _r() -> BattleRules:
	if _rules == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules


func _place(s: BattleState, player: int, squad: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _r().squad_index(squad), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid


## An unarmed, 1000-HP squad that stands still.
func _dummy(s: BattleState, x: int, y: int) -> int:
	var sid := _place(s, 2, "rifle_squad", x, y, Fixed.ANGLE_HALF)
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		var id := s.units.id_at(urow)
		s.units.set_value(id, &"weapon", -1)
		s.units.set_value(id, &"hp", 1000 * ONE)
		s.units.set_value(id, &"hp_max", 1000 * ONE)
	return sid


func _run(s: BattleState, ticks: int, hook: Callable = Callable()) -> void:
	var sim := BattleSim.new()
	for _t in ticks:
		sim.runner.step(s)
		if hook.is_valid():
			hook.call(s)


## Within arrival distance of its firing position (the fix snaps onto it;
## without the fix the unit stops up to ARRIVE short).
func _on_fpos(s: BattleState, urow: int) -> bool:
	var u := s.units
	return u.fpos[urow] == FiringPositions.HAS and Fixed.distance(u.x[urow], u.y[urow], u.fx[urow], u.fy[urow]) <= MovementSystem.ARRIVE


## A unit that reaches its firing position and fires on that same tick must
## have stood (moving flag 0) and must have fired in standing mode.
func test_arrival_tick_fires_standing_not_moving() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 30, LANE, 0)
	_dummy(s, 80, LANE + 10)
	BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK_MOVE, 80 * ONE, (LANE + 10) * ONE, -1, 0)
	var row := s.squads.row_of(me)
	var was_on := {}
	var arrivals := [0]
	var moving_on_arrival := [0]
	_run(s, 200, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			var on := _on_fpos(st, urow)
			if on and not was_on.get(urow, false) and st.units.fired_tick[urow] == st.tick - 1:
				arrivals[0] += 1
				if st.units.moving[urow] == 1:
					moving_on_arrival[0] += 1
			was_on[urow] = on)
	assert_true(arrivals[0] >= 1, "some unit fires on its arrival tick: %d" % arrivals[0])
	assert_eq(moving_on_arrival[0], 0, "no arrival-tick volley is a moving volley")


## A walking unit without a firing position keeps its moving mode: some shot
## is fired on the move while the squad closes (no position is held yet).
func test_walking_unit_still_fires_on_the_move() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	_dummy(s, 90, LANE)
	BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK_MOVE, 90 * ONE, LANE * ONE, -1, 0)
	var row := s.squads.row_of(me)
	var on_move := [0]
	_run(s, 200, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fired_tick[urow] == st.tick - 1 and st.units.moving[urow] == 1:
				on_move[0] += 1)
	assert_true(on_move[0] >= 1, "a walking unit fires on the move: %d shots" % on_move[0])
