extends GutTest
## The deployment heuristic (UtilityDeploy, sw-bafi.16, U1 C15): squads are
## placed by role; the default profile keeps the automatic places.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _make(mod: Callable = Callable(), seed_value: int = 11) -> BattleSession:
	var r := BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	if mod.is_valid():
		mod.call(r)
	var s := BattleSession.new()
	s._setup(r, "duel_crossroads", seed_value, _l().data_hash, null)
	s.clock.start()
	s._pump()
	return s


func _f(v: float) -> int:
	return int(round(v * Fixed.ONE))


func _role_pc(s: BattleSession, player: int, params: Dictionary = {}) -> ProfileController:
	var pc := ProfileController.new(player, {"deploy": {"process": "role", "params": params},
		"battle": {"process": "zone"}, "overworld": {"process": "expand"}}, 1)
	pc.set_battle_rules(s.state.rules)
	return pc


func _squad(s: BattleSession, player: int, template: String) -> Dictionary:
	for d: Dictionary in s.observe(player)["squads"]:
		if int(d["player"]) == player and d["template"] == template:
			return d
	return {}


func _by_squad(placements: Array) -> Dictionary:
	var out := {}
	for p: Dictionary in placements:
		out[int(p["squad"])] = p
	return out


## Forest over the middle of player 1's area (x 5-30, y 15-85).
func _forest(r: BattleRules) -> void:
	var f := r.feature_ids.find("forest")
	for y in range(40, 70):
		for x in range(10, 20):
			r.terrain[y * r.width + x] = f


## The heavy weapons team's LMG (its longest weapon; its troopers carry the
## rifles the rifle squads do) fires indirect.
func _indirect_heavy(r: BattleRules) -> void:
	var st := r.squad_ids.find("heavy_weapons_team")
	var w := -1
	for ut: int in r.sq_members[st]:
		var uw := int(r.ut_weapon[ut])
		if uw >= 0 and (w < 0 or r.wp_range[uw] > r.wp_range[w]):
			w = uw
	for m in range(r.wp_mode_start[w], r.wp_mode_start[w] + r.wp_mode_count[w]):
		r.md_indirect[m] = 1


func test_default_profile_keeps_automatic_places() -> void:
	var s := _make()
	var pc := ProfileController.new(1, {"battle": {"process": "zone"}}, 1)
	pc.set_battle_rules(s.state.rules)
	assert_eq(pc.deploy(s.observe(1)), [])


func test_roles() -> void:
	var s := _make(_indirect_heavy)
	var r := s.state.rules
	var d := UtilityDeploy.new()
	assert_eq(d.role(r, r.squad_ids.find("heavy_weapons_team")), "indirect")
	assert_eq(d.role(r, r.squad_ids.find("marksman_team")), "concealed")
	assert_eq(d.role(r, r.squad_ids.find("rifle_squad")), "")
	# Assault squad: a rifle sergeant, four shotgun breachers -> short.
	assert_eq(UtilityDeploy.main_range(r, r.squad_ids.find("assault_squad")), _f(15))
	assert_eq(d.role(r, r.squad_ids.find("assault_squad")), "short")
	assert_eq(UtilityDeploy.new({"short_range": 40}).role(r, r.squad_ids.find("rifle_squad")), "short")


func test_short_range_forward_keeping_lateral_place() -> void:
	var s := _make()
	# 40 m counts as short here, so the rifle squads (40 m) and the heavy
	# weapons team (two LMGs, two rifles: a tie goes to the shorter) move;
	# the scout (concealed, no cover in the area) keeps its automatic place.
	var pl := _by_squad(_role_pc(s, 1, {"short_range": 40}).deploy(s.observe(1)))
	assert_eq(pl.size(), 3)
	assert_false(pl.has(int(_squad(s, 1, "scout_team")["id"])))
	var rifle := _squad(s, 1, "rifle_squad")
	var p: Dictionary = pl[int(rifle["id"])]
	# Player 1 faces +x: area x 5..30, the anchor 3 cells inside the front edge.
	assert_eq(int(p["x"]), _f(27))
	assert_eq(int(p["y"]), int(rifle["y"]))
	assert_eq(int(p["facing"]), int(rifle["facing"]))
	# Player 2 faces -x: its front edge is the area's west side (170 + 3).
	var rifle2 := _squad(s, 2, "rifle_squad")
	var p2: Dictionary = _by_squad(_role_pc(s, 2, {"short_range": 40}).deploy(s.observe(2)))[int(rifle2["id"])]
	assert_eq(int(p2["x"]), _f(173))


func test_concealed_without_cover_keeps_its_place() -> void:
	var s := _make()
	assert_eq(_role_pc(s, 1).deploy(s.observe(1)), [])


func test_indirect_fire_at_the_back_edge() -> void:
	var s := _make(_indirect_heavy)
	var hw := _squad(s, 1, "heavy_weapons_team")
	var p: Dictionary = _by_squad(_role_pc(s, 1).deploy(s.observe(1)))[int(hw["id"])]
	assert_eq(int(p["x"]), _f(8))
	assert_eq(int(p["y"]), int(hw["y"]))


func test_concealed_squads_take_separate_cover_cells() -> void:
	var s := _make(_forest)
	var r := s.state.rules
	var pl := _by_squad(_role_pc(s, 1).deploy(s.observe(1)))
	var cells := {}
	for t in ["marksman_team", "scout_team"]:
		var p: Dictionary = pl[int(_squad(s, 1, t)["id"])]
		assert_eq(r.feature_ids[r.feature_at(int(p["x"]), int(p["y"]))], "forest", t)
		cells[[Fixed.to_int_floor(int(p["x"])), Fixed.to_int_floor(int(p["y"]))]] = true
	assert_eq(cells.size(), 2)


func test_placements_are_valid_and_applied() -> void:
	var s := _make(_forest)
	var placements := _role_pc(s, 1).deploy(s.observe(1))
	assert_eq(s.submit_deployment(1, placements), PackedStringArray())
	var scout := int(_squad(s, 1, "scout_team")["id"])
	s.ready(1)
	s.ready(2)
	var want: Dictionary = _by_squad(placements)[scout]
	var row := s.state.squads.row_of(scout)
	assert_eq(s.state.squads.ax[row], int(want["x"]))
	assert_eq(s.state.squads.ay[row], int(want["y"]))


func test_locked_squads_are_left_alone() -> void:
	var s := _make()
	var scout := int(_squad(s, 1, "scout_team")["id"])
	s.state.pinned[scout] = true
	assert_true(_squad(s, 1, "scout_team")["locked"])
	assert_eq(_role_pc(s, 1).deploy(s.observe(1)), [])


func test_nothing_when_not_deploying() -> void:
	var s := _make(func(r: BattleRules) -> void: r.deployment_open = false)
	assert_eq(_role_pc(s, 1).deploy(s.observe(1)), [])


func test_forward_from_facing_without_enemy_area() -> void:
	var obs := {"area": [0, 0, _f(10), _f(10)], "areas": [{"player": 1, "facing": Fixed.ANGLE_HALF, "deploy": [0, 0, _f(10), _f(10)]}]}
	assert_eq(UtilityDeploy.forward(obs, 1), Vector2i(-1, 0))
	obs["areas"][0]["facing"] = 0
	assert_eq(UtilityDeploy.forward(obs, 1), Vector2i(1, 0))
	obs["areas"][0]["facing"] = Fixed.ANGLE_HALF >> 1
	assert_eq(UtilityDeploy.forward(obs, 1), Vector2i(0, 1))


func test_deterministic_per_seed() -> void:
	var a := _role_pc(_make(_forest, 5), 1).deploy(_make(_forest, 5).observe(1))
	var b := _role_pc(_make(_forest, 5), 1).deploy(_make(_forest, 5).observe(1))
	assert_eq(a, b)
	assert_false(a.is_empty())


func test_headless_duel_logs_the_deployment_and_repeats() -> void:
	var runs := []
	for i in 2:
		var s := _make(_forest, 7)
		var c := {1: _role_pc(s, 1), 2: ProfileController.new(2, {"battle": {"process": "zone"}}, 7)}
		HeadlessDuel.play(s, c, 3)
		var deploys := s.input_log.filter(func(e: Dictionary) -> bool: return e["kind"] == "battle_deploy")
		assert_eq(deploys.size(), 1)
		assert_eq(int(deploys[0]["player"]), 1)
		runs.append([deploys, s.state.state_hash()])
	assert_eq(runs[0], runs[1])


func test_variant_deploy_spec() -> void:
	var v := SimVariant.new()
	v.data = {"controllers": {"1": {"deploy": "role"}}}
	var s := _make(_forest)
	var pc: ProfileController = v.controller(1, "zone", 1)
	pc.set_battle_rules(s.state.rules)
	assert_false(pc.deploy(s.observe(1)).is_empty())
	var auto: ProfileController = v.controller(2, "zone", 1)
	auto.set_battle_rules(s.state.rules)
	assert_eq(auto.deploy(s.observe(2)), [])
