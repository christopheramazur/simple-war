extends GutTest
## Movement and fire read the squad's behaviour (GDD 02 §2.15 Squad
## behaviours, sw-txnj.10): a squad template naming a behaviour for an order
## changes what its squads do under it. The defaults reproduce the built
## closing to fire (sw-txnj.5) byte for byte (test_determinism, harness
## hashes). Core package squads on Crossroads' open lane (y = 80), as
## test_firing_positions.

const ONE := Fixed.ONE
const LANE := 80

static var _loader: PackageLoader
static var _base: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _default_rules() -> BattleRules:
	if _base == null:
		_base = BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	return _base


## Core rules with a behaviour `b` made of `components`, which `squad` names
## for `order` (a DataSchema.BATTLE_ORDERS name).
func _rules_with(squad: String, order: String, components: Array) -> BattleRules:
	var defs := _l().defs.duplicate(true)
	defs.append({"id": "b", "kind": "behaviour", "values": {"components": components}})
	for d: Dictionary in defs:
		if d["id"] == squad:
			var by: Dictionary = d["values"].get("behaviours", {}).duplicate()
			by[order] = "b"
			d["values"]["behaviours"] = by
	var t := TemplateTable.build(defs)
	assert_eq(DataSchema.validate(t), PackedStringArray())
	var r := BattleRules.compile(t, "duel_crossroads")
	assert_eq(r.errors, PackedStringArray())
	return r


func _place(s: BattleState, player: int, squad: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index(squad), x * ONE, y * ONE, facing)
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


## A disarmed friendly squad holding at (x, y): keeps the enemy seen.
func _spotter(s: BattleState, x: int, y: int) -> void:
	var sid := _place(s, 1, "rifle_squad", x, y, 0)
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
	_order(s, sid, BattleSquads.Order.HOLD, x, y)


func _order(s: BattleState, sid: int, order: int, x: int, y: int, target: int = -1) -> void:
	BattleOrders.set_order(s, s.squads.row_of(sid), order, x * ONE, y * ONE, target, 0)


func _run(s: BattleState, ticks: int, hook: Callable = Callable()) -> void:
	var sim := BattleSim.new()
	for _t in ticks:
		sim.runner.step(s)
		if hook.is_valid():
			hook.call(s)


## The assault squad attack-moves to a point 35 m short of a dummy; how far
## past the point its anchor gets in 300 ticks, and the most it ever was.
func _leash_run(r: BattleRules) -> Array:
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "assault_squad", 20, LANE, 0)
	_dummy(s, 80, LANE)
	_spotter(s, 75, LANE + 12)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 45, LANE)
	var row := s.squads.row_of(me)
	var worst := [0]
	_run(s, 300, func(st: BattleState) -> void:
		if st.squads.ax[row] > 45 * ONE:
			worst[0] = maxi(worst[0], Fixed.distance(st.squads.ax[row], st.squads.ay[row], 45 * ONE, LANE * ONE)))
	return [s.squads.ax[row] - 45 * ONE, worst[0]]


func test_defaults_are_the_built_constants() -> void:
	var r := _default_rules()
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "assault_squad", 20, LANE, 0)
	var row := s.squads.row_of(me)
	for o in BattleRules.BH_ORDERS:
		_order(s, me, o, 20, LANE)
		assert_eq(MovementSystem.coherency_m(s, row), r.sq_coherency[s.squads.tmpl[row]])
		var i := FiringPositions.bh(s, row)
		assert_eq(r.bh_leash[i], r.chase_leash if o == BattleSquads.Order.ATTACK_MOVE else -1)


func test_leash_5_m_stops_5_m_past_the_point() -> void:
	var r := _rules_with("assault_squad", "attack_move", [{"c": "leash", "chase_m": 5}])
	var got := _leash_run(r)
	assert_true(got[1] <= 5 * ONE + MovementSystem.ARRIVE, "never more than 5 m past the point: %d" % got[1])
	assert_true(got[0] > 4 * ONE, "it closes up to the 5 m leash: %d" % got[0])
	var base := _leash_run(_default_rules())
	assert_true(base[0] > 10 * ONE, "the default 15 m leash goes farther: %d" % base[0])


func test_coherency_from_the_behaviour() -> void:
	var r := _rules_with("assault_squad", "attack_move", [{"c": "firing_position", "coherency_m": 3}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "assault_squad", 20, LANE, 0)
	var foe := _dummy(s, 80, LANE)
	var row := s.squads.row_of(me)
	_order(s, me, BattleSquads.Order.HOLD, 20, LANE)
	assert_eq(MovementSystem.coherency_m(s, row), r.sq_coherency[s.squads.tmpl[row]], "Hold keeps the formation's radius")
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 80, LANE)
	assert_eq(MovementSystem.coherency_m(s, row), 3 * ONE)
	var outside := [0]
	var fired := [0]
	_run(s, 300, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fired_tick[urow] != st.tick - 1:
				continue
			fired[0] += 1
			if Fixed.distance(st.units.x[urow], st.units.y[urow], st.squads.ax[row], st.squads.ay[row]) > 3 * ONE + MovementSystem.ARRIVE:
				outside[0] += 1)
	assert_true(fired[0] > 0, "it fires")
	assert_eq(outside[0], 0, "no unit fires from beyond the 3 m radius")
	var frow := s.squads.row_of(foe)
	assert_true(Fixed.distance(s.squads.cx[row], s.squads.cy[row], s.squads.cx[frow], s.squads.cy[frow]) < 25 * ONE, "the anchor closed to shotgun range")


func test_stand_off_from_the_behaviour() -> void:
	# The mortar's 20 m minimum range plus a 15 m stand-off: no position
	# within 35 m of the target.
	var r := _rules_with("mortar_team", "attack", [{"c": "firing_position", "stand_off_m": 15}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "mortar_team", 20, LANE, 0)
	var foe := _dummy(s, 50, LANE)
	_order(s, me, BattleSquads.Order.ATTACK, 20, LANE, foe)
	var row := s.squads.row_of(me)
	_run(s, 30)
	for urow in Centroids.units_of(s, row):
		assert_eq(s.units.fpos[urow], FiringPositions.UNACHIEVABLE, "30 m is inside 20 + 15 m")
	var d := BattleState.new(1, _default_rules(), 1)
	var me2 := _place(d, 1, "mortar_team", 20, LANE, 0)
	var foe2 := _dummy(d, 50, LANE)
	_order(d, me2, BattleSquads.Order.ATTACK, 20, LANE, foe2)
	_run(d, 30)
	for urow in Centroids.units_of(d, d.squads.row_of(me2)):
		assert_eq(d.units.fpos[urow], FiringPositions.HAS, "the default 5 m stand-off has a position at 30 m")


func test_cadence_and_hysteresis_from_the_behaviour() -> void:
	var r := _rules_with("rifle_squad", "attack_move", [{"c": "firing_position", "cadence_ticks": 7, "hysteresis_s": 3}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	var foe := _dummy(s, 55, LANE)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 55, LANE)
	var row := s.squads.row_of(me)
	var i := FiringPositions.bh(s, row)
	assert_eq(r.bh_cadence[i], 7)
	assert_eq(r.bh_hysteresis[i], 3 * r.tps)
	_run(s, 20)
	assert_eq(s.squads.fp_stop[row], 1)
	var urow: int = Centroids.units_of(s, row)[0]
	var targets := {row: s.squads.row_of(foe)}
	for k in 3 * r.tps + 1:
		var col: PackedByteArray = s.units.take_column(&"fpos")
		col[urow] = FiringPositions.LACKS
		s.units.put_column(&"fpos", col)
		FiringPositions._anchors(s, targets)
		if k < 3 * r.tps:
			assert_eq(s.squads.fp_stop[row], 1, "still standing %d ticks into the lack" % k)
		s.tick += 1
	assert_eq(s.squads.fp_stop[row], 0, "moves after 3 s without a position")


func test_fire_on_move_false_forbids_moving_modes() -> void:
	var r := _rules_with("rifle_squad", "move", [{"c": "fire_on_move", "allow": false}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	var row := s.squads.row_of(me)
	var urow: int = Centroids.units_of(s, row)[0]
	var w := s.units.weapon[urow]
	assert_true(r.pick_mode(w, true) >= 0, "the rifle has a moving mode")
	_order(s, me, BattleSquads.Order.MOVE, 60, LANE)
	assert_eq(CombatSystem.fire_mode(s, urow, true), -1, "no moving fire under Move")
	assert_eq(CombatSystem.fire_mode(s, urow, false), r.pick_mode(w, false), "standing fire is unchanged")
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 60, LANE)
	assert_eq(CombatSystem.fire_mode(s, urow, true), r.pick_mode(w, true), "attack-move keeps the default")


func test_fire_on_move_false_holds_fire_while_walking() -> void:
	# Walking past a dummy under Move: the default fires on the move, the
	# behaviour never does.
	for allow in [true, false]:
		var r := _rules_with("rifle_squad", "move", [{"c": "fire_on_move", "allow": allow}])
		var s := BattleState.new(1, r, 1)
		var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
		_dummy(s, 60, LANE + 10)
		_order(s, me, BattleSquads.Order.MOVE, 100, LANE)
		_run(s, 200)
		var fired := s.squads.fired_tick[s.squads.row_of(me)] >= 0
		assert_eq(fired, allow, "fire_on_move %s" % allow)


func test_stand_while_firing_false_takes_no_positions() -> void:
	var r := _rules_with("rifle_squad", "attack_move", [{"c": "stand_while", "firing": false}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	_dummy(s, 55, LANE)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 55, LANE)
	var row := s.squads.row_of(me)
	var held := [0]
	_run(s, 60, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fpos[urow] != FiringPositions.NONE:
				held[0] += 1)
	assert_eq(held[0], 0, "no unit takes a firing position")
	assert_eq(s.squads.fp_stop[row], 0)
	assert_true(s.squads.fired_tick[row] >= 0, "it fires on the move")
	assert_true(s.squads.ax[row] > 30 * ONE, "the anchor keeps walking: %d" % s.squads.ax[row])


func test_stand_while_reloading_holds_the_anchor() -> void:
	for stand in [false, true]:
		var comps: Array = [{"c": "stand_while", "firing": true, "reloading": stand}]
		var r := _rules_with("rifle_squad", "attack", comps)
		var s := BattleState.new(1, r, 1)
		var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
		var foe := _dummy(s, 55, LANE)
		_order(s, me, BattleSquads.Order.ATTACK, 20, LANE, foe)
		var row := s.squads.row_of(me)
		_run(s, 20)
		assert_eq(FiringPositions.engaging(s, row), s.squads.row_of(foe))
		# Force the anchor to want to move, then reload one unit.
		var stop: PackedByteArray = s.squads.take_column(&"fp_stop")
		stop[row] = 0
		s.squads.put_column(&"fp_stop", stop)
		var urow: int = Centroids.units_of(s, row)[0]
		s.units.set_value(s.units.id_at(urow), &"reload", 10)
		var dest := MovementSystem.new()._destination(s, row)
		assert_eq(dest.is_empty(), stand, "stand_while reloading %s" % stand)


func test_keep_distance_min_backs_away() -> void:
	var r := _rules_with("rifle_squad", "attack", [{"c": "keep_distance", "min_m": 30}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "rifle_squad", 40, LANE, 0)
	var foe := _dummy(s, 55, LANE)
	_order(s, me, BattleSquads.Order.ATTACK, 40, LANE, foe)
	var row := s.squads.row_of(me)
	var frow := s.squads.row_of(foe)
	_run(s, 300)
	var d := Fixed.distance(s.squads.ax[row], s.squads.ay[row], s.squads.cx[frow], s.squads.cy[frow])
	assert_true(d >= 29 * ONE, "backed off to the 30 m band: %d" % d)
	assert_true(d <= 32 * ONE, "and no farther: %d" % d)


func test_keep_distance_max_closes_past_firing_positions() -> void:
	# The rifle has a shot at 35 m and would stand; max_m 20 closes it in.
	var r := _rules_with("rifle_squad", "attack_move", [{"c": "keep_distance", "max_m": 20}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	var foe := _dummy(s, 55, LANE)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 55, LANE)
	var row := s.squads.row_of(me)
	var frow := s.squads.row_of(foe)
	_run(s, 300)
	var d := Fixed.distance(s.squads.ax[row], s.squads.ay[row], s.squads.cx[frow], s.squads.cy[frow])
	assert_true(d <= 20 * ONE + MovementSystem.ARRIVE, "inside max_m: %d" % d)
	assert_true(d >= 15 * ONE, "stands once inside the band: %d" % d)


## Forecast ghosts run the same behaviours: the forecast's end point equals
## where the turn really ends (enemy seen, enemy orders unchanged).
func test_forecast_ghost_matches_execution_under_a_behaviour() -> void:
	var r := _rules_with("assault_squad", "attack_move", [{"c": "leash", "chase_m": 5}, {"c": "firing_position", "extra_m": 3}])
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "assault_squad", 30, LANE, 0)
	_dummy(s, 70, LANE)
	_spotter(s, 65, LANE + 12)
	_run(s, 1)
	var orders := [{"squad": me, "type": "attack_move", "x": 45 * ONE, "y": LANE * ONE}]
	var f := IntentForecast.run(s, BattleSim.new(), 1, orders)
	assert_eq(f["errors"], PackedStringArray())
	var pts: PackedInt64Array = f["ghosts"][me]
	BattleOrders.apply(s, 1, orders)
	s.begin_turn()
	_run(s, r.ticks_per_turn)
	var row := s.squads.row_of(me)
	assert_eq(pts[pts.size() - 2], s.squads.cx[row], "ghost end x")
	assert_eq(pts[pts.size() - 1], s.squads.cy[row], "ghost end y")
	assert_true(s.squads.cx[row] > 45 * ONE, "it closed past the point")
