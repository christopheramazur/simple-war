extends GutTest
## The prowess targeting policy (sw-pd2l.5, GDD 02 §2.8 Prowess): fire
## discipline and coordination scaled by Prowess efficacy, the K-width pick
## and its acc_focus, the coordination accumulator, pinned pools, and that a
## prowess battle is deterministic and survives a save mid-battle. The
## workshop gates the outcomes (fire_duel_rifle_mirror prowess_* variants,
## fire_range_* prowess_surging, fire_prowess_coordination).

const ONE := Fixed.ONE

static var _loader: PackageLoader
static var _rules_cache: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _rules() -> BattleRules:
	if _rules_cache == null:
		_rules_cache = BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	return _rules_cache


func _defs_with_fire(fire: Dictionary) -> Array:
	var defs := _l().defs.duplicate(true)
	for d: Dictionary in defs:
		if d.get("kind", "") == "ruleset":
			d["values"]["fire"] = fire
	return defs


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _units(s: BattleState, sid: int) -> PackedInt64Array:
	return Centroids.units_of(s, s.squads.row_of(sid))


func _shooter(s: BattleState, sid: int) -> Array:
	for urow in _units(s, sid):
		var w := s.units.weapon[urow]
		if w >= 0:
			return [urow, w, CombatSystem.fire_mode(s, urow, false)]
	return []


func _set_prowess(s: BattleState, sid: int, pct: int) -> void:
	s.squads.set_value(sid, &"p_prowess", Fixed.from_int(pct))


func _volley(s: BattleState, sid: int, targets: PackedInt64Array) -> TargetPolicy.Volley:
	s.squads.set_value(sid, &"fire_policy", TargetPolicy.PROWESS)
	return TargetPolicy.begin_volley(s, s.squads.row_of(sid), targets)


func test_defaults_and_content_compile() -> void:
	var r := _rules()
	assert_eq(DataSchema.FIRE_POLICIES[TargetPolicy.PROWESS], "prowess")
	assert_eq(r.fire_discipline_pct, 58)
	assert_eq(r.fire_coordination_pct, 70)
	var rifle := r.squad_index("rifle_squad")
	assert_eq(r.sq_fire_discipline[rifle], Fixed.from_int(58))
	assert_eq(r.sq_fire_coordination[rifle], Fixed.from_int(70))
	assert_eq(r.sq_fire_datalink[rifle], 0)
	var militia := r.squad_index("hf_militia")
	assert_eq(r.sq_fire_discipline[militia], Fixed.from_int(30), "militia spreads its fire")
	var cr0 := r.squad_index("cr0_patrol")
	assert_eq(r.sq_fire_coordination[cr0], Fixed.from_int(100))
	assert_eq(r.sq_fire_datalink[cr0], 1, "CR-0 is datalinked")
	assert_true(r.stats.has("squad.fire.discipline_pct"))
	assert_true(r.stats.has("squad.fire.coordination_pct"))


func test_ruleset_fire_block_compiles_and_validates() -> void:
	var t := TemplateTable.build(_defs_with_fire({"policy": "prowess", "discipline_pct": 40, "coordination_pct": 90}))
	assert_eq(DataSchema.validate(t), PackedStringArray())
	var r := BattleRules.compile(t, "duel_crossroads", "x")
	assert_eq(r.fire_policy, TargetPolicy.PROWESS)
	assert_eq(r.sq_fire_discipline[r.squad_index("rifle_squad")], Fixed.from_int(40), "templates take the ruleset default")
	assert_eq(r.sq_fire_discipline[r.squad_index("hf_militia")], Fixed.from_int(30), "a template override wins")
	for bad: Dictionary in [{"discipline_pct": 101}, {"coordination_pct": -1}, {"discipline": 50}]:
		assert_false(DataSchema.validate(TemplateTable.build(_defs_with_fire(bad))).is_empty(), "fire %s is rejected" % [bad])


func test_efficacy_rises_above_one_up_to_capacity_over_neutral() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var row := s.squads.row_of(sid)
	assert_eq(Pools.headroom(s, row, BattleSquads.PROWESS), Fixed.div(Fixed.from_int(100), Fixed.from_int(52)))
	_set_prowess(s, sid, 100)
	assert_eq(TargetPolicy.prowess_efficacy(s, row), Pools.headroom(s, row, BattleSquads.PROWESS))
	_set_prowess(s, sid, 26)
	assert_eq(TargetPolicy.prowess_efficacy(s, row), ONE / 2)


func test_quality_and_coordination_by_band() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var row := s.squads.row_of(sid)
	_set_prowess(s, sid, 52)
	assert_almost_eq(TargetPolicy.focus_quality(s, row), 58 * ONE / 100, 1, "Neutral: q = discipline")
	assert_almost_eq(TargetPolicy.coordination(s, row), Fixed.from_int(70), 1, "Neutral: c = coordination")
	_set_prowess(s, sid, 90)
	assert_eq(TargetPolicy.focus_quality(s, row), ONE, "the Surging floor already gives full focus")
	assert_eq(TargetPolicy.coordination(s, row), Fixed.from_int(100))
	_set_prowess(s, sid, 0)
	assert_eq(TargetPolicy.focus_quality(s, row), 0)
	assert_eq(TargetPolicy.coordination(s, row), 0)
	var cr0 := _place(s, 2, "cr0_patrol", 60, 20)
	_set_prowess(s, cr0, 0)
	assert_eq(TargetPolicy.coordination(s, s.squads.row_of(cr0)), Fixed.from_int(100), "datalink ignores efficacy")


## q = 1 is the focus policy, pick for pick.
func test_full_quality_picks_as_focus() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	_set_prowess(s, a, 95)
	var pv := _volley(s, a, targets)
	assert_eq(pv.q, ONE)
	var fv := TargetPolicy.Volley.new()
	fv.policy = TargetPolicy.FOCUS
	for pending: Dictionary in [{}, {targets[3]: 4 * ONE}, {targets[0]: s.units.hp[targets[0]], targets[5]: ONE}]:
		assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], pending, pv),
			TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], pending, fv))
	assert_eq(s.units.acc_focus[sh[0]], 0, "no fraction to carry at q = 1")


## q = 0 is the nearest candidate: K covers them all.
func test_zero_quality_picks_the_nearest() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	_set_prowess(s, a, 0)
	var v := _volley(s, a, targets)
	assert_eq(v.q, 0)
	assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], {}, v),
		TargetPolicy.nearest(s, sh[0], targets, sh[1], sh[2], {}))


## K = 1 + (1 - q)(N - 1); its fraction accumulates in acc_focus, only with a
## volley (a read model's pick leaves it alone).
func test_focus_width_fraction_is_carried() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	var n := 0
	for t in targets:
		var d := Fixed.distance(s.units.x[sh[0]], s.units.y[sh[0]], s.units.x[t], s.units.y[t])
		if CombatSystem.shot_gate(s, sh[0], t, sh[1], sh[2], d) == CombatSystem.GATE_OK:
			n += 1
	assert_gt(n, 2, "several candidates in reach")
	_set_prowess(s, a, 52)
	var v := _volley(s, a, targets)
	var frac := (ONE + (ONE - v.q) * (n - 1)) % ONE
	assert_gt(frac, 0)
	TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], {}, null)
	assert_eq(s.units.acc_focus[sh[0]], 0, "a read-model pick does not advance it")
	TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], {}, v)
	assert_eq(s.units.acc_focus[sh[0]], frac)
	TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], {}, v)
	assert_eq(s.units.acc_focus[sh[0]], (2 * frac) % ONE)


## Each unit volley adds c to acc_coord; at 100 the unit sees the squad's
## queued hits. Other policies always see them.
func test_coordination_accumulator_gates_the_view() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	var pending := {targets[0]: ONE}
	_set_prowess(s, a, 52)
	var v := _volley(s, a, targets)
	var seen: Array[bool] = []
	for i in 4:
		seen.append(not TargetPolicy.view(s, sh[0], pending, v).is_empty())
	assert_eq(seen, [false, true, true, false] as Array[bool], "c = 70: 70, 140, 110, 80")
	assert_almost_eq(s.units.acc_coord[sh[0]], Fixed.from_int(80), 4)
	var fv := TargetPolicy.Volley.new()
	fv.policy = TargetPolicy.FOCUS
	var before := s.units.acc_coord[sh[0]]
	assert_eq(TargetPolicy.view(s, sh[0], pending, fv), pending)
	assert_eq(s.units.acc_coord[sh[0]], before)


func test_a_pinned_pool_ignores_flows() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var row := s.squads.row_of(sid)
	_set_prowess(s, sid, 95)
	s.squads.set_value(sid, &"pinned", 1 << BattleSquads.PROWESS)
	assert_eq(Pools.flow(s, row, BattleSquads.PROWESS, -Fixed.from_int(10), &"test"), 0)
	assert_eq(Pools.value(s, row, BattleSquads.PROWESS), Fixed.from_int(95))
	assert_ne(Pools.flow(s, row, BattleSquads.MORALE, -Fixed.from_int(10), &"test"), 0, "other pools still flow")


## A rifle duel on the prowess policy at Neutral: both runs agree hash for
## hash, and a save after turn 1 continues identically.
func _duel() -> BattleState:
	var r := BattleRules.compile(TemplateTable.build(_defs_with_fire({"policy": "prowess"})), "duel_crossroads", "x")
	var s := BattleState.new(1, r, 1)
	_place(s, 1, "rifle_squad", 50, 50)
	_place(s, 2, "rifle_squad", 80, 50)
	return s


func test_prowess_battle_is_deterministic_and_round_trips() -> void:
	var sim := BattleSim.new()
	var s1 := _duel()
	var s2 := _duel()
	sim.execute_turn(s1)
	sim.execute_turn(s2)
	assert_eq(s1.state_hash().hex_encode(), s2.state_hash().hex_encode(), "identical runs, identical hashes")
	var used := false
	for urow in s1.units.count():
		used = used or s1.units.acc_coord[urow] != 0 or s1.units.acc_focus[urow] != 0
	assert_true(used, "the accumulators moved")
	var copy := BattleState.new(1, s1.rules)
	copy.restore(s1.snapshot())
	assert_eq(copy.state_hash().hex_encode(), s1.state_hash().hex_encode())
	for st: BattleState in [s1, copy]:
		sim.execute_turn(st)
	assert_eq(copy.state_hash().hex_encode(), s1.state_hash().hex_encode(), "continues identically after a save")
