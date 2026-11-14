extends GutTest
## Criteria library v1, decision side (GDD 05 §5.4, Round B1): SimCriteria's
## decision-time forms, schedule gates and masks. Task sw-884.7.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


static func _json(path: String) -> Dictionary:
	var j := JSON.new()
	assert(j.parse(FileAccess.get_file_as_string(path)) == OK)
	return j.data


func test_gate_cases_shared_with_the_harness() -> void:
	var cases := _json("res://data/sim/fitness/gate_cases.json")
	var s := SimCriteria.Schedule.new(cases["entry"], int(cases["hold_turns"]))
	for step: Dictionary in cases["turns"]:
		assert_almost_eq(s.weight(step["conditions"], int(step["turn"])), float(step["weight"]), 1e-6, str(step))


func test_curve_and_utility() -> void:
	var pts := [[0, 1.0], [10, 3.0]]
	assert_eq(SimCriteria.curve(pts, -1), 1.0)
	assert_eq(SimCriteria.curve(pts, 5), 2.0)
	assert_eq(SimCriteria.curve(pts, 50), 3.0)
	assert_almost_eq(SimCriteria.utility({"a": 1.0, "b": 0.0}, {"a": 3.0, "b": 1.0}), 0.75, 1e-9)
	assert_eq(SimCriteria.utility({"a": 1.0}, {}), 0.0, "a fully hidden view weighs nothing")
	assert_true(SimCriteria.library()["criteria"].has("pressure"))


func _in_range(values: Dictionary) -> void:
	for c: String in values:
		var lo := -1.0 if c == "margin" else 0.0
		assert_between(float(values[c]), lo, 1.0, c)


func test_overworld_forms() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 3)
	var v := SimCriteria.overworld(x.observe(1), x.rules)
	assert_eq(v.keys().size(), 6)
	_in_range(v)
	assert_eq(v["force_ratio"], 1.0, "no enemy in sight at the start")
	assert_eq(v["commander_safety"], 1.0)
	var mask := SimCriteria.Mask.new({"exploration": {"base": 1.0, "gates": [{"condition": "since_contact", "points": [[-1, 1.0], [0, 1.0], [3, 0.0]]}]},
		"force_ratio": {"base": 2.0}})
	var ctl := {1: ExpandController.new(1), 2: ExpandController.new(2)}
	var seen := -1
	for t in 6:
		HeadlessOverworld.play(x, ctl, t + 1)
		var d := mask.overworld(x.observe(1), x.rules)
		_in_range(d["values"])
		assert_eq(d["weights"].keys().size(), 2, "hidden criteria carry no weight")
		assert_between(float(d["utility"]), 0.0, 1.0)
		if mask.contact_turn >= 0 and seen < 0:
			seen = mask.contact_turn
	assert_gt(SimCriteria.overworld(x.observe(1), x.rules)["exploration"], v["exploration"], "exploring raises exploration")


func test_battle_forms() -> void:
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 2)
	var v := SimCriteria.battle(s.observe(1), s.state.rules)
	_in_range(v)
	assert_eq(v["value_efficiency"], 0.5, "no fighting yet is neutral")
	var spec := _json("res://data/sim/fitness/default.json")
	var mask := SimCriteria.Mask.new(spec["shaping"], int(spec["hold_turns"]))
	var ctl := {1: ZoneController.new(1), 2: ZoneController.new(2)}
	var d := {}
	for t in range(2, 7):
		HeadlessDuel.play(s, ctl, 50, t)
		d = mask.battle(s.observe(1), s.state.rules)
		_in_range(d["values"])
		assert_between(float(d["utility"]), 0.0, 1.0)
	assert_ne(d["values"]["value_efficiency"], 0.5, "fighting moved the exchange")
	assert_gte(mask.contact_turn, 1, "first contact is remembered")
	assert_eq(d["conditions"]["contact"], 1.0, "contact stays latched")


func test_decision_forms_are_read_only() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 3)
	var before := x.state_hash_hex()
	SimCriteria.Mask.new({"economy": {}}).overworld(x.observe(2), x.rules)
	assert_eq(x.state_hash_hex(), before)
