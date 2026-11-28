extends GutTest
## Targeting policies (sw-pd2l.4, GDD 02 §2.6 Fire distribution): the ruleset's
## fire.policy, the squad override, and the focus policy's kill priority, best
## fit and area plan. The fire-range workshop scenarios gate the outcomes
## (fire_range_*, fire_duel_rifle_mirror, variants focus*); these pin the
## rules one pick at a time.

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


func _ruleset_defs(fire: Variant) -> Array:
	var defs := _l().defs.duplicate(true)
	for d: Dictionary in defs:
		if d.get("kind", "") == "ruleset":
			d["values"]["fire"] = fire
	return defs


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _units(s: BattleState, sid: int) -> PackedInt64Array:
	return Centroids.units_of(s, s.squads.row_of(sid))


## The first armed unit of the squad and its weapon and first fire mode.
func _shooter(s: BattleState, sid: int) -> Array:
	for urow in _units(s, sid):
		var w := s.units.weapon[urow]
		if w >= 0:
			return [urow, w, CombatSystem.fire_mode(s, urow, false)]
	return []


func test_default_policy_is_nearest() -> void:
	assert_eq(_rules().fire_policy, TargetPolicy.NEAREST)
	assert_eq(DataSchema.FIRE_POLICIES[TargetPolicy.NEAREST], "nearest")
	assert_eq(DataSchema.FIRE_POLICIES[TargetPolicy.FOCUS], "focus")


func test_ruleset_fire_policy_compiles() -> void:
	var t := TemplateTable.build(_ruleset_defs({"policy": "focus"}))
	assert_eq(DataSchema.validate(t), PackedStringArray())
	var r := BattleRules.compile(t, "duel_crossroads", "x")
	assert_eq(r.fire_policy, TargetPolicy.FOCUS)


func test_unknown_fire_policy_fails_validation() -> void:
	for bad: Variant in [{"policy": "sniper"}, {"policy": 3}, {"polcy": "focus"}]:
		var errs := DataSchema.validate(TemplateTable.build(_ruleset_defs(bad)))
		assert_false(errs.is_empty(), "fire %s is rejected" % [bad])


func test_squad_override_beats_the_ruleset() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var row := s.squads.row_of(sid)
	assert_eq(s.squads.fire_policy[row], -1, "no override by default")
	assert_eq(TargetPolicy.squad_policy(s, row), TargetPolicy.NEAREST)
	s.squads.set_value(sid, &"fire_policy", TargetPolicy.FOCUS)
	assert_eq(TargetPolicy.squad_policy(s, row), TargetPolicy.FOCUS)


## Kill priority: lowest remaining HP first, then lowest unit ID, whatever
## the distance; nearest takes the nearest.
func test_focus_takes_the_lowest_remaining_hp_not_the_nearest() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	var near := TargetPolicy.nearest(s, sh[0], targets, sh[1], sh[2], {})
	assert_gte(near, 0)
	# Wound the farthest target in reach: focus goes there.
	var far := -1
	var far_d := -1
	for t in targets:
		var d := Fixed.distance(s.units.x[sh[0]], s.units.y[sh[0]], s.units.x[t], s.units.y[t])
		if d > far_d and CombatSystem.shot_gate(s, sh[0], t, sh[1], sh[2], d) == CombatSystem.GATE_OK:
			far_d = d
			far = t
	assert_ne(far, near)
	var pending := {far: 4 * ONE}
	var v := TargetPolicy.Volley.new()
	v.policy = TargetPolicy.FOCUS
	assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], pending, v), far, "least remaining first")
	# Unwounded: the lowest HP (the 12 HP sergeant last), ties to the lowest
	# unit ID, the same for every shooter.
	var lowest := targets[0]
	for t in targets:
		var hp_t := s.units.hp[t]
		var hp_l := s.units.hp[lowest]
		if hp_t < hp_l or (hp_t == hp_l and s.units.id_at(t) < s.units.id_at(lowest)):
			lowest = t
	assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], {}, v), lowest)


## Best fit: a hit that can finish a unit takes the one it overshoots least,
## and a finishing hit beats a merely wounding one.
func test_focus_best_fit_prefers_the_smallest_overshoot() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	var e := TargetPolicy.hit_damage(s, sh[0], sh[2])
	var t0 := targets[1]
	var t1 := targets[2]
	var t2 := targets[3]
	# t0: one hit leaves it alive at 1; t1: finished with overshoot e - 1;
	# t2: finished exactly. Remaining = hp - pending.
	var pending := {t0: s.units.hp[t0] - e - ONE, t1: s.units.hp[t1] - 1 * ONE, t2: s.units.hp[t2] - e}
	var v := TargetPolicy.Volley.new()
	v.policy = TargetPolicy.FOCUS
	assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], pending, v), t2)
	pending.erase(t2)
	assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], pending, v), t1, "a finishing hit beats lower HP left")


## With every target covered, focus falls back to nearest's covered pick.
func test_focus_falls_back_to_nearest_when_all_are_covered() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 20, 40)
	var b := _place(s, 2, "bare_rifle_squad", 45, 40)
	var sh := _shooter(s, a)
	var targets := _units(s, b)
	var pending := {}
	for t in targets:
		pending[t] = s.units.hp[t]
	var v := TargetPolicy.Volley.new()
	v.policy = TargetPolicy.FOCUS
	assert_eq(TargetPolicy.pick(s, sh[0], targets, sh[1], sh[2], pending, v),
		TargetPolicy.nearest(s, sh[0], targets, sh[1], sh[2], pending))


## The mortar team's area plan covers the whole line in one salvo, the
## 12 HP sergeant included (two splashes), where greedy kills-first strands
## it: every target ends covered by the planned splashes.
func test_area_plan_covers_the_line() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "mortar_team", 50, 80)
	var b := _place(s, 2, "bare_rifle_squad", 86, 80)
	s.squads.set_value(a, &"fire_policy", TargetPolicy.FOCUS)
	var targets := _units(s, b)
	var v := TargetPolicy.begin_volley(s, s.squads.row_of(a), targets)
	assert_eq(v.policy, TargetPolicy.FOCUS)
	assert_eq(v.plan.size(), 3, "three ready mortars planned")
	var r := s.rules
	var pending := {}
	for urow: int in v.plan:
		var m := CombatSystem.fire_mode(s, urow, false)
		var w := s.units.weapon[urow]
		var victim := TargetPolicy.pick(s, urow, targets, w, m, pending, v)
		assert_eq(victim, v.plan[urow], "pick follows the plan")
		for o in targets:
			if o == victim or Fixed.distance(s.units.x[victim], s.units.y[victim], s.units.x[o], s.units.y[o]) <= r.md_aoe[m]:
				pending[o] = int(pending.get(o, 0)) + DamagePipeline.preview(s, o, r.md_damage[m], r.wp_type[w])
	for t in targets:
		assert_true(TargetPolicy.covered(s.units, t, pending), "unit %d covered" % t)


func test_nearest_policy_builds_no_plan() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "mortar_team", 50, 80)
	var b := _place(s, 2, "bare_rifle_squad", 86, 80)
	var v := TargetPolicy.begin_volley(s, s.squads.row_of(a), _units(s, b))
	assert_eq(v.policy, TargetPolicy.NEAREST)
	assert_true(v.plan.is_empty())
