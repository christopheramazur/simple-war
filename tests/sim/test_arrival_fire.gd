extends GutTest
## The arrival tick (U1Q28, sw-txnj.6): a unit under an attack order that
## reaches its firing position this tick stands and fires in standing mode,
## not a moving volley. Walking units with no firing position keep their
## moving mode. Built on the core package's draft 01 table B rifle squad.

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


func _attack_move(s: BattleState, sid: int, x: int, y: int) -> void:
	BattleOrders.set_order(s, s.squads.row_of(sid), BattleSquads.Order.ATTACK_MOVE, x * ONE, y * ONE, -1, 0)


func _run(s: BattleState, ticks: int, hook: Callable = Callable()) -> void:
	var sim := BattleSim.new()
	for _t in ticks:
		sim.runner.step(s)
		if hook.is_valid():
			hook.call(s)


## Within arrival distance of its firing position (the movement pass snaps
## onto it; without the snap the unit stops up to ARRIVE short).
func _on_fpos(s: BattleState, urow: int) -> bool:
	var u := s.units
	return u.fpos[urow] == FiringPositions.HAS and Fixed.distance(u.x[urow], u.y[urow], u.fx[urow], u.fy[urow]) <= MovementSystem.ARRIVE


## A unit that reaches its firing position and fires on that same tick fires
## in standing mode (its arrival volley is not a moving one).
func test_arrival_tick_fires_standing_not_moving() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 30, LANE, 0)
	_dummy(s, 80, LANE + 10)
	_attack_move(s, me, 80, LANE + 10)
	var row := s.squads.row_of(me)
	var was_on := {}
	var arrivals := [0]
	var moving_on_arrival := [0]
	_run(s, 200, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			var on := _on_fpos(st, urow)
			if on and not was_on.get(urow, false) and st.units.fired_tick[urow] == st.tick - 1:
				arrivals[0] += 1
				if CombatSystem.fires_moving(st, urow):
					moving_on_arrival[0] += 1
			was_on[urow] = on)
	assert_true(arrivals[0] >= 1, "some unit fires on its arrival tick: %d" % arrivals[0])
	assert_eq(moving_on_arrival[0], 0, "no arrival-tick volley is a moving volley")


## A rifle attack-moving into its 40 m range (the 44 m duel of draft 01 table
## D) fires its first shot standing, on the tick it comes into range.
func test_coming_into_range_fires_first_shot_standing() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	_dummy(s, 64, LANE)
	_attack_move(s, me, 64, LANE)
	var row := s.squads.row_of(me)
	var first := {}
	_run(s, 120, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fired_tick[urow] == st.tick - 1 and not first.has(urow):
				first[urow] = CombatSystem.fires_moving(st, urow))
	assert_eq(first.size(), 8, "every rifle fires")
	var moving_firsts := 0
	for urow in first:
		if first[urow]:
			moving_firsts += 1
	assert_eq(moving_firsts, 0, "no first volley is a moving volley")


## A unit walking on a Move order has no firing position (only attack orders
## take one), so a shot it fires while walking is still a moving volley.
func test_walking_unit_still_fires_on_the_move() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	_dummy(s, 64, LANE)
	BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.MOVE, 90 * ONE, LANE * ONE, -1, 0)
	var row := s.squads.row_of(me)
	var on_move := [0]
	_run(s, 200, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fired_tick[urow] == st.tick - 1 and CombatSystem.fires_moving(st, urow):
				on_move[0] += 1)
	assert_true(on_move[0] >= 1, "a walking unit fires on the move: %d shots" % on_move[0])
