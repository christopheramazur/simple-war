extends GutTest
## Hiring commanders (GDD 02 §2.5: Value recruits commanders) and the
## vertical-slice squads (sw-kys.1, sw-kys.2). test_vale: village (1,6) of
## player 1 hires an outrider (10) or a field commander (18).

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
		_rules_cache = OverworldRules.compile(_loader.templates, "test_vale", _loader.data_hash)
	return _rules_cache


func _s() -> OverworldState:
	var s := OverworldState.create(1, _rules(), 7)
	var cache := _rules().feature_index("hex_supply_cache")
	for id in s.features.ids():
		if s.features.get_value(id, &"tmpl") == cache:
			s.remove_feature(id)
	return s


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _of(events: Array[SimEvent], type: StringName) -> Array:
	return events.filter(func(e: SimEvent) -> bool: return e.type == type)


func _mine(s: OverworldState, player: int) -> int:
	var n := 0
	for row in s.commanders.count():
		if s.commanders.player[row] == player:
			n += 1
	return n


func test_rules_compile_hires_and_new_squads() -> void:
	var r := _rules()
	assert_true(r.is_valid(), "; ".join(r.errors))
	var village := r.feature_index("hex_village")
	assert_true(r.has_activity(village, "hire"))
	assert_eq(r.hire_cost(village, r.commander_index("outrider")), 10)
	assert_eq(r.hire_cost(village, r.commander_index("siege_captain")), -1)
	assert_eq(r.hire_cost(r.feature_index("hex_barracks"), r.commander_index("siege_captain")), 16)
	assert_eq(r.sq_size[r.squad_index("assault_squad")], 5)
	assert_eq(r.sq_size[r.squad_index("engineer_team")], 4)
	assert_eq(r.sq_size[r.squad_index("mortar_team")], 3)
	assert_eq(r.recruit_cost(village, r.squad_index("engineer_team")), 5)


func test_hire_checks_and_spawns_a_commander_with_its_army() -> void:
	var s := _s()
	var o := Commanders.spawn(s, 1, "outrider", P(1, 6))
	var before := _mine(s, 1)
	assert_eq(OverworldOrders.set_activity(s, 1, o, "hire", "siege_captain"), "this hex does not hire 'siege_captain'")
	assert_eq(OverworldOrders.set_activity(s, 1, o, "hire", "outrider"), "hire costs 10 Value, you have 0")
	s.value[1] = 25
	assert_eq(OverworldOrders.set_activity(s, 1, o, "hire", "field_commander"), "")
	var ev := OverworldTurn.resolve(s)
	var hired := _of(ev, &"commander_hired")
	assert_eq(hired.size(), 1)
	assert_eq(_mine(s, 1), before + 1)
	var nid: int = hired[0].data["commander"]
	var row := s.commanders.row_of(nid)
	assert_eq(s.commanders.plot[row], P(1, 6), "arrives on the hiring hex")
	assert_eq(OverworldArmies.view(s, nid).size(), 3, "own squad + starting army")
	assert_eq(s.value_of(1), 25 - 18 + 2, "paid; the village produced")
	assert_true(EventText.describe({"type": hired[0].type, "data": hired[0].data}, _rules(), 1).contains("field commander"))


func test_hire_cancelled_without_value() -> void:
	var s := _s()
	var o := Commanders.spawn(s, 1, "outrider", P(1, 6))
	s.value[1] = 10
	assert_eq(OverworldOrders.set_activity(s, 1, o, "hire", "outrider"), "")
	s.value[1] = 3
	var ev := OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"commander_hired").size(), 0)
	assert_eq(_of(ev, &"activity_cancelled").size(), 1)
