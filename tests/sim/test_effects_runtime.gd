extends GutTest
## Effects at runtime: bundles, stacking, durations, auras, stack sources,
## hooks, accumulators, max changes, rules text (GDD 02 §2.13). Task sw-ps1.4.

const ONE := Fixed.ONE
const ACC := &"weapon.modes.*.accuracy"

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


func _b(id: String) -> int:
	return _rules().fx.index_of(id)


func _state() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, x: int, y: int = 50) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index("rifle_squad"), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _row(s: BattleState, sid: int) -> int:
	return s.squads.row_of(sid)


func _unit(s: BattleState, sid: int, nth: int = 0) -> int:
	return Centroids.units_of(s, _row(s, sid))[nth]


## One tick of the effect-relevant systems.
func _tick(s: BattleState) -> void:
	EffectSystem.new().run(s)
	HealthSystem.new().run(s)
	s.commands.apply(s)
	Centroids.update(s)
	s.end_tick()


func _events(s: BattleState, type: StringName) -> Array:
	return s.turn_log.filter(func(e: SimEvent) -> bool: return e.type == type)


func test_core_bundles_compile() -> void:
	assert_true(_rules().is_valid(), str(_rules().errors))
	assert_gt(_rules().fx.size(), 5)


func test_compile_errors() -> void:
	var t := TemplateTable.build([
		{"id": "x", "kind": "bundle", "values": {"tags": ["nope"], "effects": [
			{"op": "modify", "stat": "unit.charisma", "amount": 1},
			{"op": "modify", "stat": "unit.hp", "amount": 1, "when": "apply"},
			{"op": "damage", "amount": 1},
			{"op": "heal", "amount": 1, "when": "accumulator"},
		]}},
	])
	var fx := EffectRules.compile(t, StatRegistry.from_schema(), 10)
	var text := "\n".join(fx.errors)
	assert_string_contains(text, "unknown tag 'nope'")
	assert_string_contains(text, "unknown stat 'unit.charisma'")
	assert_string_contains(text, "modify effects act 'while'")
	assert_string_contains(text, "damage needs a damage_type")
	assert_string_contains(text, "need the bundle to have an accumulator")


func test_status_modifies_and_expires() -> void:
	var s := _state()
	var sid := _place(s, 1, 40)
	var u := _unit(s, sid)
	var base := _rules().md_accuracy[0]
	var morale := Pools.value(s, _row(s, sid), BattleSquads.MORALE)
	Effects.apply(s, _b("inspired"), sid)
	assert_eq(Pools.value(s, _row(s, sid), BattleSquads.MORALE), morale + 5 * ONE, "on-apply pool flow")
	_tick(s)
	assert_eq(Stats.unit(s, u, ACC, base), Fixed.mul_ratio(base, 120, 100), "20% more accuracy")
	for _i in 10 * _rules().tps:
		_tick(s)
	assert_eq(s.effects.count(), 0, "expired after 10 s")
	assert_eq(Stats.unit(s, u, ACC, base), base)


func test_refresh_and_stack_policies() -> void:
	var s := _state()
	var sid := _place(s, 1, 40)
	var a := Effects.apply(s, _b("inspired"), sid)
	s.tick = 30
	assert_eq(Effects.apply(s, _b("inspired"), sid), a, "refresh keeps one instance")
	assert_eq(s.effects.get_value(a, &"expires"), 30 + 10 * _rules().tps)
	var bl := -1
	for _i in 5:
		bl = Effects.apply(s, _b("bleeding"), sid)
	assert_eq(s.effects.get_value(bl, &"stacks"), 3, "max 3 stacks")


func test_periodic_damage_scales_with_stacks() -> void:
	var s := _state()
	var sid := _place(s, 1, 40)
	var u := _unit(s, sid)
	var hp := s.units.hp[u]
	Effects.apply(s, _b("bleeding"), sid)
	Effects.apply(s, _b("bleeding"), sid)
	for _i in _rules().tps + 1:
		_tick(s)
	assert_eq(s.units.hp[_unit(s, sid)], hp - 2 * ONE, "2 stacks x 1 damage after 1 s")


func test_aura_on_allies_keeps_pool_ratio() -> void:
	var s := _state()
	var a := _place(s, 1, 40)
	var near := _place(s, 1, 50)
	var far := _place(s, 1, 80)
	var p := BattleSquads.MORALE
	var v := Pools.value(s, _row(s, near), p)
	var cap := Pools.capacity(s, _row(s, near), p)
	Effects.apply(s, _b("rally_banner"), a)
	_tick(s)
	assert_eq(Pools.capacity(s, _row(s, near), p), Fixed.mul_ratio(cap, 120, 100), "ally in range")
	assert_almost_eq(Pools.value(s, _row(s, near), p), Fixed.mul_ratio(v, 120, 100), 2, "ratio kept")
	assert_eq(Pools.capacity(s, _row(s, far), p), cap, "out of range")
	assert_eq(Pools.capacity(s, _row(s, a), p), cap, "allies excludes the holder")
	Effects.remove(s, s.effects.id_at(0), false)
	_tick(s)
	assert_eq(Pools.capacity(s, _row(s, near), p), cap, "back to base when the aura ends")


func test_per_selector_stacks() -> void:
	var s := _state()
	var a := _place(s, 1, 40)
	_place(s, 1, 45)
	_place(s, 1, 48)
	_place(s, 2, 44)
	Effects.apply(s, _b("safety_in_numbers"), a)
	_tick(s)
	var base := Fixed.from_int(5)
	assert_eq(Stats.unit(s, _unit(s, a), &"defense.evasion_pct", base), base + 10 * ONE, "+5 per ally, 2 allies, enemies ignored")


func test_max_hp_trait_keeps_ratio() -> void:
	var s := _state()
	var sid := _place(s, 1, 40)
	var urow := _unit(s, sid)
	var uid := s.units.id_at(urow)
	var full := s.units.hp_max[urow]
	s.units.set_value(uid, &"hp", full / 2)
	var eid := Effects.apply(s, _b("hardy"), sid, uid)
	_tick(s)
	urow = s.units.row_of(uid)
	assert_eq(s.units.hp_max[urow], Fixed.mul_ratio(full, 150, 100))
	assert_eq(s.units.hp[urow], Fixed.mul_ratio(full / 2, 150, 100))
	Effects.remove(s, eid, false)
	_tick(s)
	urow = s.units.row_of(uid)
	assert_eq(s.units.hp_max[urow], full)
	assert_eq(s.units.hp[urow], full / 2)


func test_hook_with_cooldown() -> void:
	var s := _state()
	var a := _place(s, 1, 40)
	var b := _place(s, 2, 50)
	Effects.apply(s, _b("vengeful"), a)
	for nth in 2:
		var u := _unit(s, a, 0)
		Health.queue(s, -1, b, s.units.id_at(u), a, 1000 * ONE, 0)
		_tick(s)
	assert_eq(_events(s, &"unit_killed").size(), 2)
	var inspired := 0
	for e: SimEvent in _events(s, &"effect_applied"):
		if e.data["bundle"] == "inspired":
			inspired += 1
	assert_eq(inspired, 1, "second casualty is inside the 5 s cooldown")


func test_accumulator_fires_and_resets() -> void:
	var s := _state()
	var a := _place(s, 1, 40)
	var eid := Effects.apply(s, _b("steady_aim"), a)
	var row := _row(s, a)
	var prowess := Pools.value(s, row, BattleSquads.PROWESS)
	_tick(s)
	for _i in 2:
		Effects.on_event(s, "hit", a, -1, -1, -1, ONE)
	assert_eq(s.effects.get_value(eid, &"acc"), 2 * ONE, "next in 1 hit")
	Effects.on_event(s, "damaged", a, -1, -1, -1, ONE)
	assert_eq(s.effects.get_value(eid, &"acc"), 0, "reset when damaged")
	for _i in 3:
		Effects.on_event(s, "hit", a, -1, -1, -1, ONE)
	assert_eq(Pools.value(s, row, BattleSquads.PROWESS), prowess + 2 * ONE)
	assert_eq(s.effects.get_value(eid, &"acc"), 0, "back to start")
	Effects.on_event(s, "hit", a, -1, -1, -1, ONE, 1)
	assert_eq(s.effects.get_value(eid, &"acc"), 0, "depth 1 counts nothing")


func test_hook_chains_stop_at_depth_one() -> void:
	var s := _state()
	var a := _place(s, 1, 40)
	var b := _place(s, 2, 50)
	Effects.apply(s, _b("thorns"), a)
	Effects.apply(s, _b("thorns"), b)
	_tick(s)
	var ua := s.units.id_at(_unit(s, a))
	var ub := s.units.id_at(_unit(s, b))
	var hp_a := s.units.get_value(ua, &"hp")
	var hp_b := s.units.get_value(ub, &"hp")
	Health.queue(s, ua, a, ub, b, 2 * ONE, 0)
	_tick(s)
	assert_lt(s.units.get_value(ub, &"hp"), hp_b, "B took the hit")
	assert_eq(hp_a - s.units.get_value(ua, &"hp"), ONE, "A took exactly one thorns hit; B's thorns didn't bounce back")


func test_rules_text() -> void:
	var r := _rules()
	var lines := RulesText.bundle_lines(r.fx, _b("inspired"), r.stats, r.tps)
	assert_eq(lines[0], "20% more Accuracy")
	assert_eq(lines[1], "On application: +5 Morale")
	assert_eq(lines[2], "Lasts 10 s.")
	assert_eq(RulesText.bundle_lines(r.fx, _b("bleeding"), r.stats, r.tps)[0], "Every 1 s: Deals 1 kinetic damage")
	assert_eq(RulesText.bundle_lines(r.fx, _b("rally_banner"), r.stats, r.tps)[0], "20% increased Morale Capacity to allies within 15 m")
	assert_eq(RulesText.bundle_lines(r.fx, _b("safety_in_numbers"), r.stats, r.tps)[0], "+5% Evasion per ally within 10 m")
	assert_eq(RulesText.bundle_lines(r.fx, _b("vengeful"), r.stats, r.tps)[0], "When the squad takes a casualty: Applies Inspired (at most once every 5 s)")
	assert_eq(RulesText.bundle_lines(r.fx, _b("steady_aim"), r.stats, r.tps)[0], "Every 3 hits: +2 Prowess")


func test_effects_are_deterministic_through_save() -> void:
	var s := _state()
	var a := _place(s, 1, 40)
	var b := _place(s, 2, 55)
	Effects.apply(s, _b("bleeding"), a, -1, b)
	Effects.apply(s, _b("rally_banner"), b)
	Effects.apply(s, _b("steady_aim"), b)
	var sim := BattleSim.new()
	for _i in 5:
		sim.runner.step(s)
	var copy := BattleState.new(1, _rules(), 1)
	copy.restore(s.snapshot())
	Centroids.update(copy)
	for _i in 30:
		sim.runner.step(s)
		sim.runner.step(copy)
	assert_eq(copy.state_hash_hex(), s.state_hash_hex())
