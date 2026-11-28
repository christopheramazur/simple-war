extends GutTest
## AI remote buys (sw-63wt.11, U1 E10): OwnerBuys plans the buy a human makes
## from anywhere, from the observation alone. test_vale: player 1's village
## (1,6) recruits rifle squads for 6 (8 remote), scouts for 4 (5) and engineers
## for 5 (7 rounded up); barracks (8,7) recruits assault squads for 7 (9).

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_rules_cache = OverworldRules.compile(_l().templates, "test_vale", _l().data_hash)
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


func _feature(s: OverworldState, col: int, row: int, id: String) -> int:
	return s.features.id_at(s.feature_row(P(col, row), _rules().feature_index(id)))


func _own(s: OverworldState, col: int, row: int, id: String, player: int = 1) -> int:
	var fid := _feature(s, col, row, id)
	s.features.set_value(fid, &"owner", player)
	return fid


func _options_of(plan: Array, fid: int) -> Array:
	return plan.filter(func(b: Dictionary) -> bool: return b["feature"] == fid).map(func(b: Dictionary) -> String: return b["option"])


func test_plans_a_buy_at_an_owned_village() -> void:
	var s := _s()
	var village := _own(s, 1, 6, "hex_village")
	s.value[1] = 20
	var plan := OwnerBuys.plan(OverworldVision.observe(s, 1), _rules())
	assert_false(plan.is_empty(), "with Value to spare the AI buys")
	for b: Dictionary in plan:
		assert_eq(b["feature"], village, "only its owned village sells")
		assert_true(_rules().squad_ids.has(b["option"]), "a squad, not an item")


func test_no_plan_without_value() -> void:
	var s := _s()
	_own(s, 1, 6, "hex_village")
	s.value[1] = 3
	assert_true(OwnerBuys.plan(OverworldVision.observe(s, 1), _rules()).is_empty(), "the cheapest squad costs 5")


func test_plan_is_affordable_as_a_whole() -> void:
	var s := _s()
	_own(s, 1, 6, "hex_village")
	_own(s, 8, 7, "hex_barracks")
	s.value[1] = 12
	var plan := OwnerBuys.plan(OverworldVision.observe(s, 1), _rules())
	var spent := 0
	for b: Dictionary in plan:
		var t := _rules().feature_index("hex_village") if b["feature"] == _feature(s, 1, 6, "hex_village") else _rules().feature_index("hex_barracks")
		spent += _rules().buy_option(t, b["option"])[3]
	assert_true(spent <= 12, "the plan spends no more than the Value held (%d)" % spent)


func test_limit_one_buy_a_turn_per_feature() -> void:
	var s := _s()
	var barracks := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 100
	var plan := OwnerBuys.plan(OverworldVision.observe(s, 1), _rules())
	assert_eq(_options_of(plan, barracks).size(), 1, "barracks take one buy a turn")


func test_already_planned_buys_count_against_the_limit() -> void:
	var s := _s()
	var barracks := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 100
	assert_eq(OverworldOrders.set_owner_action(s, 1, barracks, "buy", "assault_squad"), "")
	var plan := OwnerBuys.plan(OverworldVision.observe(s, 1), _rules())
	assert_true(_options_of(plan, barracks).is_empty(), "its one buy is planned already")


func test_no_buy_on_a_hex_with_a_hostile_commander() -> void:
	var s := _s()
	var barracks := _own(s, 8, 7, "hex_barracks")
	s.value[1] = 100
	Commanders.spawn(s, 2, "outrider", P(8, 7))
	assert_true(_options_of(OwnerBuys.plan(OverworldVision.observe(s, 1), _rules()), barracks).is_empty(),
		"the resolver would cancel it as contested")


func test_plans_apply_as_planned() -> void:
	var s := _s()
	_own(s, 1, 6, "hex_village")
	_own(s, 8, 7, "hex_barracks")
	s.value[1] = 30
	var plan := OwnerBuys.plan(OverworldVision.observe(s, 1), _rules())
	assert_false(plan.is_empty())
	for b: Dictionary in plan:
		assert_eq(OverworldOrders.set_owner_action(s, 1, b["feature"], "buy", b["option"]), "",
			"every planned buy is accepted by the planning API")


func test_expand_controller_buys_through_economy() -> void:
	var l := _l()
	var x := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var village := -1
	for f: Dictionary in x.inspect_plot(1, P(1, 6))["features"]:
		if f["name"] == "Village":
			village = f["id"]
	assert_true(village >= 0)
	x.state.value[1] = 20
	var out := ExpandController.new(1).economy(x.observe(1), x)
	assert_false(out.is_empty(), "the expand process buys too")
	for e: Dictionary in out:
		assert_eq(e["feature"], village)
		assert_true(e.has("buy"))
		assert_false(e.has("output") or e.has("commander"), "buys only")


func test_headless_overworld_applies_buys() -> void:
	var l := _l()
	var x := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var village := -1
	for f: Dictionary in x.inspect_plot(1, P(1, 6))["features"]:
		if f["name"] == "Village":
			village = f["id"]
	x.state.value[1] = 20
	var c := ExpandController.new(1)
	HeadlessOverworld.plan_for(x, 1, c)
	assert_eq((x.observe(1)["owner_orders"] as Dictionary).keys(), [village], "the buy is planned")
	var logged := x.input_log.filter(func(e: Dictionary) -> bool: return e["kind"] == "owner_action")
	assert_eq(logged.size(), 1, "and logged for replay")


func test_a_buy_keeps_at_least_half_the_value() -> void:
	var s := _s()
	var village := _own(s, 1, 6, "hex_village")
	s.value[1] = 12
	var plan := OwnerBuys.plan(OverworldVision.observe(s, 1), _rules())
	var t := _rules().feature_index("hex_village")
	for b: Dictionary in plan:
		assert_true(_rules().buy_option(t, b["option"])[3] * 2 <= 12, "%s leaves half the Value" % b["option"])
	assert_eq(_options_of(plan, village), ["scout_team"], "rifle squads (8) are over the reserve, scouts (5) are not")
