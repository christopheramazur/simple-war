extends GutTest
## Fixed-point HP and pools with ratio-keeping: GDD 02 §2.13, E3Q1, E3Q2.
## Task sw-ps1.2.

const ONE := Fixed.ONE

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


func _squad(s: BattleState) -> int:
	var sid := BattleSetup.spawn_squad(s, 1, _rules().squad_index("rifle_squad"), 20 * ONE, 20 * ONE, 0)
	Centroids.update(s)
	return s.squads.row_of(sid)


func test_designer_ratio_example() -> void:
	# E2Q2: 17.5/22.5, the +50% wears off -> 11.66/15.
	var hp := MaxChange.rescale(35 * ONE / 2, 45 * ONE / 2, 15 * ONE)
	assert_eq(Fixed.to_display(hp), "11.7")
	assert_almost_eq(float(hp) / ONE, 11.6667, 0.0001)
	# And back up: the ratio holds, so it returns to 17.5.
	assert_eq(Fixed.to_display(MaxChange.rescale(hp, 15 * ONE, 45 * ONE / 2)), "17.5")


func test_restores_adds_the_increase() -> void:
	assert_eq(MaxChange.rescale(5 * ONE, 10 * ONE, 15 * ONE, true), 10 * ONE)
	assert_eq(MaxChange.rescale(9 * ONE, 10 * ONE, 15 * ONE, true), 14 * ONE)
	# A falling max keeps the ratio even when restoring.
	assert_eq(MaxChange.rescale(5 * ONE, 10 * ONE, 4 * ONE, true), 2 * ONE)
	assert_eq(MaxChange.rescale(5 * ONE, 10 * ONE, 0), 0)


func test_display_shows_one_decimal_only_when_fractional() -> void:
	assert_eq(Fixed.to_display(15 * ONE), "15")
	assert_eq(Fixed.to_display(45 * ONE / 2), "22.5")
	assert_eq(Fixed.to_display(-3 * ONE / 2), "-1.5")
	assert_eq(Fixed.to_display(ONE * 1001 / 1000), "1", "rounds to one decimal first")


func test_unit_max_hp_change_keeps_ratio() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var row := _squad(s)
	var urow := Centroids.units_of(s, row)[0]
	var u := s.units
	var full := u.hp_max[urow]
	assert_eq(u.hp[urow], full, "spawns at full HP")
	u.set_value(u.id_at(urow), &"hp", full / 2)
	Health.set_max(s, urow, full * 2)
	assert_eq(u.hp_max[urow], full * 2)
	assert_eq(u.hp[urow], full, "half stays half")
	Health.set_max(s, urow, full * 3, true)
	assert_eq(u.hp[urow], full * 2, "restores adds the increase")


func test_pool_capacity_change_keeps_ratio_and_scales_neutral() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var row := _squad(s)
	var p := BattleSquads.MORALE
	var cap := Pools.capacity(s, row, p)
	var v := Pools.value(s, row, p)
	var n := Pools.neutral(s, row, p)
	var band := Pools.band(s, row, p)
	Pools.set_capacity(s, row, p, cap * 2, false, &"test")
	assert_eq(Pools.capacity(s, row, p), cap * 2)
	assert_eq(Pools.value(s, row, p), v * 2)
	assert_eq(Pools.neutral(s, row, p), n * 2)
	assert_eq(Pools.band(s, row, p), band, "same ratio, same band")


func test_hp_and_damage_accept_decimals() -> void:
	var t := TemplateTable.build([
		{"id": "d", "kind": "defense", "values": {"flat": "0.5", "floor": {"kinetic": "0.25"}}},
		{"id": "m", "kind": "movement", "values": {"walk": 1, "run": 2}},
		{"id": "u", "kind": "unit", "values": {"hp": "2.5", "defense": "d", "movement": "m"}},
		{"id": "bad", "kind": "unit", "values": {"hp": "0.5", "defense": "d", "movement": "m"}},
	])
	var errs := DataSchema.validate(t)
	assert_eq(errs.size(), 1, str(errs))
	assert_string_contains(errs[0], "bad: 'hp' below minimum 1")
