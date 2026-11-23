extends GutTest
## Seeded deployment jitter (sw-884.5): off by default, deterministic, varies by seed.

var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules() -> BattleRules:
	return BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)


func _anchors(s: BattleState) -> Array:
	var out := []
	for sid in s.squads.ids():
		out.append([s.squads.get_value(sid, "ax"), s.squads.get_value(sid, "ay")])
	return out


func test_zero_jitter_is_unchanged() -> void:
	var r := _rules()
	assert_eq(_anchors(BattleSetup.create(1, r, 1)), _anchors(BattleSetup.create(1, r, 99)), "no jitter: seed irrelevant")
	assert_eq(_anchors(BattleSetup.create(1, r, 1)), _anchors(BattleSetup.create(1, r, 1, 0)))


func test_same_seed_same_deployment_and_seeds_differ() -> void:
	var r := _rules()
	assert_eq(_anchors(BattleSetup.create(1, r, 5, 2)), _anchors(BattleSetup.create(1, r, 5, 2)))
	var keys := {}
	for sd in [1, 2, 3, 4, 5, 6]:
		keys[str(_anchors(BattleSetup.create(1, r, sd, 2)))] = true
	assert_gt(keys.size(), 3, "seeds give different deployments")


func test_anchors_stay_in_deploy_rect() -> void:
	var r := _rules()
	for sd in [1, 2, 3, 4, 5, 6, 7, 8]:
		var s := BattleSetup.create(1, r, sd, 3)
		for side in r.sides:
			var d: PackedInt64Array = side["deploy"]
			for sid in s.squads.ids():
				if s.squads.get_value(sid, "player") != side["player"]:
					continue
				var x: int = s.squads.get_value(sid, "ax")
				var y: int = s.squads.get_value(sid, "ay")
				# open_point may nudge off an impassable cell by a few cells.
				assert_true(x >= d[0] - Fixed.from_int(3) and x <= d[0] + d[2] + Fixed.from_int(3), "x in rect (seed %d)" % sd)
				assert_true(y >= d[1] - Fixed.from_int(3) and y <= d[1] + d[3] + Fixed.from_int(3), "y in rect (seed %d)" % sd)
