extends GutTest
## Weapon timers run in real time and concurrently (sw-ll4.27.1, GDD 02 §2.6):
## every living armed unit's reload and cooldown tick each tick, engaged or
## not, so a mortar's shot gap is max(reload, cooldown), not their sum, and a
## target lost and regained mid-turn does not silence the mortar.

const ONE := Fixed.ONE

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


## An empty battle (no deployment) to place squads by hand.
func _empty() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	return ScenarioBuilder.place(s, player, squad, x * ONE, y * ONE)


## The fixture mortar's shot gap: max(reload 30, cooldown 60) = 60 ticks.
func _mortar_gap(s: BattleState) -> int:
	var r := s.rules
	var w: int = r.weapon_index["mortar"]
	return maxi(r.wp_reload[w], r.md_cooldown[r.pick_mode(w, false)])


## A stationary enemy that cannot shoot back (disarmed) and cannot die
## (huge HP), so only the mortar's timing is under test.
func _target(s: BattleState, x: int, y: int) -> int:
	return ScenarioBuilder.target_dummy(s, 2, "rifle_squad", x * ONE, y * ONE)


func _toughen(s: BattleState, sid: int) -> void:
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"hp", 1000 * ONE)
		s.units.set_value(s.units.id_at(urow), &"hp_max", 1000 * ONE)


## Teleports a squad (anchor, order point and every unit by the same delta,
## so units stay in their formation slots). HOLD squads stand still after.
func _move_squad(s: BattleState, sid: int, nx: int, ny: int) -> void:
	ScenarioBuilder.move_squad(s, sid, nx * ONE, ny * ONE)


## Runs one tick; returns the tick number if squad `sid` fired, else -1.
func _step_fire_tick(s: BattleState, sim: BattleSim, sid: int) -> int:
	var before := s.shot_trace.size()
	var t := s.tick
	sim.runner.step(s)
	for o in range(before, s.shot_trace.size(), BattleState.SHOT_STRIDE):
		if s.units.squad[s.units.row_of(s.shot_trace[o + 1])] == sid:
			return t
	return -1


## (a) The mortar fires, has no target for 40 ticks, then re-engages in its
## 20-90 m band: it fires no later than max(reload,cooldown)-40 ticks after
## re-engaging, because the timers ran while it was disengaged.
func test_timers_run_while_the_mortar_has_no_target() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 85, 70)
	var sim := BattleSim.new()
	var gap := _mortar_gap(s)
	assert_eq(gap, 60, "fixture: reload 30, cooldown 60")
	var first := _step_fire_tick(s, sim, mortar)
	assert_eq(first, 0, "ready on engagement: fires the first tick")
	# No target for 40 ticks: out of reach and out of sight.
	_move_squad(s, enemy, 190, 70)
	for _t in 40:
		assert_eq(_step_fire_tick(s, sim, mortar), -1, "no target, no shot")
		assert_eq(s.squads.engaged[s.squads.row_of(mortar)], -1, "disengaged")
	# Re-engage in the band; the shot gap stays max(reload,cooldown).
	_move_squad(s, enemy, 85, 70)
	var reengaged := -1
	var again := -1
	for _t in gap - 40:
		var t := s.tick
		var ft := _step_fire_tick(s, sim, mortar)
		if reengaged < 0 and s.squads.engaged[s.squads.row_of(mortar)] >= 0:
			reengaged = t
		if ft >= 0:
			again = ft
			break
	assert_gte(again, 0, "fires within max(reload,cooldown)-40 ticks of re-engaging")
	assert_eq(again - first, gap, "the timers ran through the 40-tick gap")
	assert_lte(again - reengaged, gap - 40)


## (b) An engaged mortar fires every max(reload,cooldown) ticks, not
## reload + cooldown: each mortarman shots at 0, 60, 120, 180.
func test_engaged_mortar_fires_every_max_of_reload_and_cooldown() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	_target(s, 85, 70)
	var sim := BattleSim.new()
	var gap := _mortar_gap(s)
	for _t in 3 * gap + 1:
		sim.runner.step(s)
	var by_unit := {}
	for o in range(0, s.shot_trace.size(), BattleState.SHOT_STRIDE):
		var uid := s.shot_trace[o + 1]
		if s.units.squad[s.units.row_of(uid)] != mortar:
			continue
		if not by_unit.has(uid):
			by_unit[uid] = []
		by_unit[uid].append(s.shot_trace[o])
	assert_eq(by_unit.size(), 3, "all three mortarmen fired")
	for uid: int in by_unit:
		var ticks: Array = by_unit[uid]
		assert_eq(ticks.size(), 4, "shots at 0, gap, 2*gap, 3*gap")
		for i in range(1, ticks.size()):
			assert_eq(ticks[i] - ticks[i - 1], gap, "max(reload,cooldown), not reload+cooldown")


## (c) Playtest-equivalent: the mortar's target is spotted by an ally at 70 m
## (beyond the mortar team's own sight). The spotter leaves mid-turn and
## returns; the mortar loses then regains its target and fires within the turn.
func test_mortar_refires_within_the_turn_after_losing_and_regaining_its_spot() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	_target(s, 120, 70)
	var spotter := _place(s, 1, "scout_team", 110, 70)
	_toughen(s, spotter)
	var sim := BattleSim.new()
	var shots := []
	for t in s.rules.ticks_per_turn:
		if t == 40:
			_move_squad(s, spotter, 10, 10)
		if t == 70:
			_move_squad(s, spotter, 110, 70)
		var ft := _step_fire_tick(s, sim, mortar)
		if ft >= 0:
			shots.append(ft)
	assert_gte(shots.size(), 2, "fires before and after the spotting gap")
	assert_lt(shots[0], 40, "first shot while the target is spotted")
	assert_gte(shots[shots.size() - 1], 70, "the later shot follows re-spotting")
	assert_lt(shots[shots.size() - 1], s.rules.ticks_per_turn, "it fires within the turn")


## Timers tick even while the squad holds fire (FALL_BACK/WITHDRAW): a
## withdrawing mortar keeps reloading and cooling down in real time.
func test_timers_tick_while_holding_fire() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	_target(s, 85, 70)
	var sim := BattleSim.new()
	assert_eq(_step_fire_tick(s, sim, mortar), 0)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": mortar, "type": "withdraw"}]).size(), 0)
	var mrow := s.squads.row_of(mortar)
	var urow := Centroids.units_of(s, mrow)[0]
	var rl0 := s.units.reload[urow]
	var cd0 := s.units.cooldown[urow]
	assert_eq(rl0, 30, "magazine emptied: reload set")
	assert_eq(cd0, 60, "cooldown set at the same time")
	for _t in 10:
		assert_eq(_step_fire_tick(s, sim, mortar), -1, "withdrawing holds fire")
	assert_eq(s.squads.engaged[mrow], -1, "hold-fire squads do not engage")
	assert_eq(s.units.reload[urow], rl0 - 10, "reload ran while holding fire")
	assert_eq(s.units.cooldown[urow], cd0 - 10, "cooldown ran while holding fire")
