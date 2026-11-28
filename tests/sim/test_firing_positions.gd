extends GutTest
## Per-unit firing positions under attack orders (GDD 02 §2.15 Closing to
## fire, U1Q28, U1Q29, sw-txnj.5), on the core package's draft 01 table B
## squads along Crossroads' open lane (y = 80). DPS by order is gated by the
## workshop scenarios table_b_* and mixed_range_orders.

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


func _order(s: BattleState, sid: int, order: int, x: int, y: int, target: int = -1) -> void:
	BattleOrders.set_order(s, s.squads.row_of(sid), order, x * ONE, y * ONE, target, 0)


## Runs `ticks` ticks, calling hook(state) after each.
func _run(s: BattleState, ticks: int, hook: Callable = Callable()) -> void:
	var sim := BattleSim.new()
	for _t in ticks:
		sim.runner.step(s)
		if hook.is_valid():
			hook.call(s)


func test_hold_never_leaves_slots() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "assault_squad", 20, LANE, 0)
	_dummy(s, 50, LANE)
	_order(s, me, BattleSquads.Order.HOLD, 20, LANE)
	var row := s.squads.row_of(me)
	var worst := [0]
	_run(s, 100, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			assert_eq(st.units.fpos[urow], FiringPositions.NONE)
			var slot := MovementSystem.slot_point(st, urow, row)
			worst[0] = maxi(worst[0], Fixed.distance(st.units.x[urow], st.units.y[urow], slot[0], slot[1])))
	assert_true(s.squads.fired_tick[row] >= 0, "the rifle fires from its slot")
	assert_true(worst[0] <= MovementSystem.ARRIVE, "no unit leaves its slot: %d" % worst[0])


func test_assault_attack_move_walks_its_shotguns_in_within_coherency() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "assault_squad", 20, LANE, 0)
	var foe := _dummy(s, 80, LANE)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 80, LANE)
	var row := s.squads.row_of(me)
	var radius := MovementSystem.coherency_m(s, row)
	var shooters := {}
	var outside := [0]
	_run(s, 300, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fired_tick[urow] != st.tick - 1:
				continue
			shooters[urow] = true
			if Fixed.distance(st.units.x[urow], st.units.y[urow], st.squads.ax[row], st.squads.ay[row]) > radius:
				outside[0] += 1)
	assert_eq(shooters.size(), 5, "the rifle and all four shotguns fire")
	assert_eq(outside[0], 0, "no unit fires from outside the coherency radius")
	var frow := s.squads.row_of(foe)
	assert_true(Fixed.distance(s.squads.cx[row], s.squads.cy[row], s.squads.cx[frow], s.squads.cy[frow]) < 25 * ONE, "closed to shotgun range")


func test_attack_move_keeps_its_leash_past_the_point() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "assault_squad", 20, LANE, 0)
	_dummy(s, 80, LANE)
	# A disarmed friendly spotter keeps the dummy seen.
	var spotter := _place(s, 1, "rifle_squad", 75, LANE + 12, 0)
	for urow in Centroids.units_of(s, s.squads.row_of(spotter)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
	_order(s, spotter, BattleSquads.Order.HOLD, 75, LANE + 12)
	# The point is 35 m short of the dummy (the rifle reaches it from there);
	# the shotguns would need 20 m more, past the 15 m leash.
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 45, LANE)
	var row := s.squads.row_of(me)
	var worst := [0]
	_run(s, 300, func(st: BattleState) -> void:
		if st.squads.ax[row] > 45 * ONE:
			worst[0] = maxi(worst[0], Fixed.distance(st.squads.ax[row], st.squads.ay[row], 45 * ONE, LANE * ONE)))
	assert_eq(_r().chase_leash, 15 * ONE, "default leash from the ruleset data")
	assert_true(s.squads.ax[row] > 55 * ONE, "it chases past the point: %d" % s.squads.ax[row])
	assert_true(worst[0] <= _r().chase_leash + MovementSystem.ARRIVE, "never more than the leash past the point: %d" % worst[0])


func test_attack_has_no_leash() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "assault_squad", 30, LANE, 0)
	var foe := _dummy(s, 85, LANE)
	_order(s, me, BattleSquads.Order.ATTACK, 30, LANE, foe)
	var row := s.squads.row_of(me)
	_run(s, 300)
	var frow := s.squads.row_of(foe)
	assert_true(Fixed.distance(s.squads.ax[row], s.squads.ay[row], s.squads.cx[frow], s.squads.cy[frow]) < 25 * ONE, "follows its target all the way")


func test_mortar_inside_min_range_backs_out_to_the_band() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "mortar_team", 20, LANE, 0)
	var foe := _dummy(s, 34, LANE)
	_order(s, me, BattleSquads.Order.ATTACK, 20, LANE, foe)
	var row := s.squads.row_of(me)
	var ax0 := s.squads.ax[row]
	var ay0 := s.squads.ay[row]
	var frow := s.squads.row_of(foe)
	var closest := [1 << 62]
	_run(s, 50, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			for t in Centroids.units_of(st, frow):
				closest[0] = mini(closest[0], Fixed.distance(st.units.x[urow], st.units.y[urow], st.units.x[t], st.units.y[t]))
	)
	# keep_distance min_m 25 (min_range 20 + 5): the team backs out to the band
	# and stands there (sw-txnj.11), instead of walking in.
	var d := Fixed.distance(s.squads.ax[row], s.squads.ay[row], s.squads.cx[frow], s.squads.cy[frow])
	assert_true(d >= 24 * ONE, "backed out to about 25 m: %d" % d)
	assert_true(Fixed.distance(s.squads.ax[row], s.squads.ay[row], ax0, ay0) > 5 * ONE, "the anchor walked out from 14 m: %d" % d)
	assert_true(closest[0] > 10 * ONE, "no mortar walks onto its target: %d" % closest[0])


func test_mortar_attack_move_never_comes_inside_20_m() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "mortar_team", 20, LANE, 0)
	var foe := _dummy(s, 120, LANE)
	# A disarmed spotter 25 m short of the target, as draft 01 table C.
	var spotter := _place(s, 1, "rifle_squad", 95, LANE + 5, 0)
	for urow in Centroids.units_of(s, s.squads.row_of(spotter)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 120, LANE)
	_order(s, spotter, BattleSquads.Order.HOLD, 95, LANE + 5)
	var row := s.squads.row_of(me)
	var frow := s.squads.row_of(foe)
	var closest := [1 << 62]
	_run(s, 300, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			for t in Centroids.units_of(st, frow):
				closest[0] = mini(closest[0], Fixed.distance(st.units.x[urow], st.units.y[urow], st.units.x[t], st.units.y[t])))
	assert_true(s.squads.fired_tick[row] >= 0, "the mortars fire")
	assert_true(closest[0] >= 20 * ONE, "never inside 20 m: %d" % closest[0])


## U1Q28: a homogeneous squad walking into range opens fire unit by unit,
## and no unit with a ready weapon and a shot waits for a squad-mate.
func test_staggered_opening_and_no_unit_waits() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 30, LANE, 0)
	_dummy(s, 80, LANE + 10)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 80, LANE + 10)
	var row := s.squads.row_of(me)
	var first := {}
	var waited := [0]
	_run(s, 200, func(st: BattleState) -> void:
		for urow in Centroids.units_of(st, row):
			if st.units.fired_tick[urow] == st.tick - 1:
				if not first.has(urow):
					first[urow] = st.tick - 1
			elif st.squads.engaged[row] >= 0 and BattleActivity.hold(st, urow) == BattleActivity.Hold.NONE:
				waited[0] += 1)
	assert_eq(first.size(), 8, "every rifle fires")
	var ticks := {}
	for urow: int in first:
		ticks[first[urow]] = true
	assert_true(ticks.size() >= 2, "staggered first shots: %s" % [first.values()])
	assert_eq(waited[0], 0, "no ready unit with a shot holds fire")


## Hysteresis (U1Q29): a stopped anchor moves again only after a unit has
## lacked a position for at least 1 s.
func test_hysteresis_restarts_only_after_one_second() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	var foe := _dummy(s, 55, LANE)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 55, LANE)
	var row := s.squads.row_of(me)
	_run(s, 20)
	assert_eq(s.squads.fp_stop[row], 1, "in range from the start: stands")
	var trow := s.squads.row_of(foe)
	var urow: int = Centroids.units_of(s, row)[0]
	var targets := {row: trow}
	var tps := _r().tps
	for i in tps + 1:
		var col: PackedByteArray = s.units.take_column(&"fpos")
		col[urow] = FiringPositions.LACKS
		s.units.put_column(&"fpos", col)
		FiringPositions._anchors(s, targets)
		if i < tps:
			assert_eq(s.squads.fp_stop[row], 1, "still standing %d ticks into the lack" % i)
		s.tick += 1
	assert_eq(s.squads.fp_stop[row], 0, "moves after 1 s without a position")


## A line-of-fire flicker (a unit losing its position for a few ticks) never
## restarts the anchor.
func test_flicker_does_not_restart_the_anchor() -> void:
	var s := BattleState.new(1, _r(), 1)
	var me := _place(s, 1, "rifle_squad", 20, LANE, 0)
	_dummy(s, 55, LANE)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 55, LANE)
	var row := s.squads.row_of(me)
	_run(s, 20)
	assert_eq(s.squads.fp_stop[row], 1)
	var ax := s.squads.ax[row]
	var urow: int = Centroids.units_of(s, row)[2]
	var moved := [0]
	_run(s, 60, func(st: BattleState) -> void:
		if st.squads.moving[row] == 1:
			moved[0] += 1
		# Every 7 ticks the unit loses its position (as a blocked line would);
		# its next re-evaluation, at most 5 ticks later, finds it again.
		if st.tick % 7 == 0:
			var col: PackedByteArray = st.units.take_column(&"fpos")
			col[urow] = FiringPositions.LACKS
			st.units.put_column(&"fpos", col))
	assert_eq(moved[0], 0, "the anchor never moved")
	assert_eq(s.squads.ax[row], ax)


## sw-0jm5: the batched engaging pass agrees with engaging() for every squad
## on every tick of a mixed fight (two squads per side, attack and
## attack-move, one squad on Move).
func test_engaging_rows_matches_engaging() -> void:
	var s := BattleState.new(1, _r(), 1)
	var a := _place(s, 1, "rifle_squad", 20, LANE, 0)
	var b := _place(s, 1, "assault_squad", 22, LANE + 12, 0)
	var c := _place(s, 2, "rifle_squad", 70, LANE, Fixed.ANGLE_HALF)
	var d := _place(s, 2, "rifle_squad", 72, LANE - 12, Fixed.ANGLE_HALF)
	_order(s, a, BattleSquads.Order.ATTACK_MOVE, 70, LANE)
	_order(s, b, BattleSquads.Order.ATTACK, 70, LANE, c)
	_order(s, c, BattleSquads.Order.ATTACK_MOVE, 20, LANE)
	_order(s, d, BattleSquads.Order.MOVE, 20, LANE - 12)
	var engaged := [0]
	_run(s, 150, func(st: BattleState) -> void:
		var rows := FiringPositions._engaging_rows(st)
		assert_eq(rows.size(), st.squads.count())
		for row in st.squads.count():
			assert_eq(rows[row], FiringPositions.engaging(st, row), "row %d tick %d" % [row, st.tick])
			if rows[row] >= 0:
				engaged[0] += 1)
	assert_true(engaged[0] > 0, "some squad engages for positions")


## sw-0jm5: SoaTable.rows_of resolves a batch exactly as row_of does,
## including -1, dead and stale IDs.
func test_rows_of_matches_row_of() -> void:
	var s := BattleState.new(1, _r(), 1)
	var a := _place(s, 1, "rifle_squad", 20, LANE, 0)
	var b := _place(s, 2, "rifle_squad", 70, LANE, Fixed.ANGLE_HALF)
	var ids := PackedInt64Array([a, b, -1, b + (1 << 32), 12345])
	var rows := s.squads.rows_of(ids)
	for i in ids.size():
		assert_eq(rows[i], s.squads.row_of(ids[i]), "id %d" % ids[i])

