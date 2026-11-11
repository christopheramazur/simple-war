extends GutTest
## Stat registry and modifier engine: GDD 02 §2.13, E1Q3, E2Q1, E3Q4.
## Task sw-ps1.1.

const ONE := Fixed.ONE
const K := StatModifier.Kind

static var _reg: StatRegistry


func _r() -> StatRegistry:
	if _reg == null:
		_reg = StatRegistry.from_schema()
	return _reg


func _def(integral: bool = false) -> StatDef:
	var d := StatDef.new()
	d.id = "test.stat"
	d.integral = integral
	return d


func _mods(list: Array) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for e: Array in list:
		out.append(StatModifier.make("test.stat", e[0], e[1], e[2]))
	return out


# --- Registry ---------------------------------------------------------------

func test_registry_derives_numeric_fields_with_scope_and_bounds() -> void:
	var hp := _r().find("unit.hp")
	assert_not_null(hp)
	assert_eq(hp.scope, StatDef.SCOPE_UNIT)
	assert_true(hp.has_min)
	assert_eq(hp.min_value, ONE)
	var ev := _r().find("defense.evasion_pct")
	assert_eq(ev.unit, "%")
	assert_eq(ev.max_value, 100 * ONE)
	assert_eq(_r().find("squad.capture_rate").scope, StatDef.SCOPE_SQUAD)
	assert_false(_r().find("weapon.range").integral, "fixed fields are not rounded to whole numbers")
	assert_eq(_r().find("weapon.range").unit, "m")


func test_registry_expands_declared_keys_and_wildcards() -> void:
	for t in DataSchema.DAMAGE_TYPES:
		assert_true(_r().has("defense.resist_pct." + t), t)
	assert_true(_r().has("squad.pools.morale.capacity"))
	assert_eq(_r().find("weapon.modes.auto.accuracy").id, "weapon.modes.*.accuracy")
	assert_eq(_r().find("movement.terrain_cost_pct.ruins").id, "movement.terrain_cost_pct.*")
	assert_true(_r().has("ability.activation.costs.instinct"), "reaction cost is a registered stat (E3Q4)")
	assert_true(_r().has("squad.concealment_pct"))
	assert_true(_r().has("squad.detection_radius"))


func test_registry_skips_non_stats() -> void:
	assert_false(_r().has("squad.members.count"))
	assert_false(_r().has("squad.members.*.count"))
	assert_false(_r().has("ruleset.ticks_per_second"), "ruleset is not unit/squad scoped")
	assert_false(_r().has("unit.name"))
	assert_false(_r().has("defense.resist_pct.psychic"), "undeclared damage type")


func test_read_base_from_templates() -> void:
	var loader := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var t := loader.templates
	var carapace: Dictionary = {}
	for tid in t.ids():
		if t.kind_of(tid) == "defense" and (t.values_of(tid) as Dictionary).get("floor") != null:
			carapace = t.values_of(tid)
	assert_false(carapace.is_empty(), "core has a defense with a floor")
	var res := _r().find("defense.resist_pct.kinetic")
	assert_eq(_r().read_base(res, carapace), Fixed.from_int(int(carapace["resist_pct"]["kinetic"])))
	assert_eq(_r().read_base(_r().find("defense.resist_pct.energy"), carapace, PackedStringArray(), 7), 7, "missing -> default")
	var mv := _r().find("movement.terrain_cost_pct.*")
	assert_eq(_r().read_base(mv, {"terrain_cost_pct": {"ruins": 150}}, PackedStringArray(["ruins"])), 150 * ONE)
	var react := _r().find("ability.activation.costs.instinct")
	assert_eq(_r().read_base(react, {"activation": {"timing": "reaction", "costs": {"instinct": 5}}}), 5 * ONE)


func test_schema_rejects_undeclared_map_keys() -> void:
	var t := TemplateTable.build([{"id": "d", "kind": "defense", "values": {"resist_pct": {"psychic": 10}}}])
	var errs := DataSchema.validate(t)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "unknown key 'psychic'")


# --- Modifier engine ---------------------------------------------------------

func test_designer_hp_example() -> void:
	# E2Q2: 10 base, +5 base, +50% increased max -> 22.5.
	var r := StatCalc.with_trace(_def(), 10 * ONE, _mods([[K.FLAT, 5 * ONE, "item:plate"], [K.INCREASED, 50 * ONE, "status:hardy"]]))
	assert_eq(r["value"], 22 * ONE + ONE / 2)
	var steps := (r["trace"] as Array).map(func(s: Dictionary) -> String: return s["step"])
	assert_eq(steps, ["base", "flat", "increased", "result"])


func test_increased_sums_and_more_multiplies() -> void:
	var m := _mods([[K.INCREASED, 50 * ONE, "a"], [K.INCREASED, 50 * ONE, "b"], [K.MORE, 50 * ONE, "c"], [K.MORE, 50 * ONE, "d"]])
	# 100 * (1 + 0.5 + 0.5) * 1.5 * 1.5 = 450
	assert_eq(StatCalc.value(_def(), 100 * ONE, m), 450 * ONE)


func test_reduced_and_less_floor_at_zero() -> void:
	assert_eq(StatCalc.value(_def(), 10 * ONE, _mods([[K.INCREASED, -150 * ONE, "a"]])), 0)
	assert_eq(StatCalc.value(_def(), 10 * ONE, _mods([[K.MORE, -50 * ONE, "a"]])), 5 * ONE)


func test_order_independent() -> void:
	var list := [[K.MORE, 33 * ONE, "x"], [K.FLAT, 3 * ONE, "y"], [K.MORE, -17 * ONE, "a"], [K.INCREASED, 12 * ONE, "q"], [K.OVERRIDE, 4 * ONE, "o2"], [K.OVERRIDE, 9 * ONE, "o1"]]
	var fwd := StatCalc.with_trace(_def(), 7 * ONE, _mods(list))
	list.reverse()
	var rev := StatCalc.with_trace(_def(), 7 * ONE, _mods(list))
	assert_eq(fwd, rev)
	assert_eq(fwd["value"], 4 * ONE, "last override in canonical order (source o2) wins")


func test_clamp_then_one_rounding() -> void:
	var d := _def(true)
	d.has_min = true
	d.min_value = ONE
	d.has_max = true
	d.max_value = 95 * ONE
	# 10 * 1.25 = 12.5 -> rounds once, away from zero, to 13.
	var r := StatCalc.with_trace(d, 10 * ONE, _mods([[K.MORE, 25 * ONE, "a"]]))
	assert_eq(r["value"], 13 * ONE)
	assert_eq((r["trace"] as Array)[-2]["step"], "round")
	assert_eq(StatCalc.value(d, 90 * ONE, _mods([[K.FLAT, 20 * ONE, "a"]])), 95 * ONE)
	var low := StatCalc.with_trace(d, 3 * ONE, _mods([[K.MORE, -100 * ONE, "a"]]))
	assert_eq(low["value"], ONE)
	assert_eq((low["trace"] as Array)[-2]["step"], "clamp")


func test_no_modifiers_is_base() -> void:
	var r := StatCalc.with_trace(_def(), 7 * ONE, [] as Array[StatModifier])
	assert_eq(r["value"], 7 * ONE)
	assert_eq((r["trace"] as Array).size(), 2)
