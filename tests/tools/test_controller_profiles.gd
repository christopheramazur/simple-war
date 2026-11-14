extends GutTest
## Controller profiles (GDD 05 §5.4, R7Q15, A2Q1, A2Q5, A2Q6, B1Q11):
## ProfileController composition, utility processes on both layers,
## scripted processes, fuzz, leader safety and faults. Task sw-884.3.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _profile(id: String) -> Dictionary:
	assert_eq(_l().templates.kind_of(id), "controller_profile", id)
	return _l().templates.values_of(id)


func test_shipped_profiles_compose_both_layers() -> void:
	for id in ["profile_utility", "profile_aggressor", "profile_turtle"]:
		var pc := ProfileController.new(1, _profile(id), 1)
		assert_true(pc.overworld_process() is UtilityOverworld, id)
		assert_true(pc.battle_process() is UtilityBattle, id)
	var empty := ProfileController.new(1, {}, 1)
	assert_true(empty.overworld_process() is UtilityOverworld, "a missing section gets its default")
	assert_true(ProfileController.default_mask().has("pressure"), "the default mask is the fitness shaping")
	var agg := ProfileController.new(1, _profile("profile_aggressor"), 1).overworld_process() as UtilityOverworld
	assert_almost_eq(agg.risk, 0.8, 1e-9, "decimal strings in package data become floats")


func _duel(p1: Dictionary, p2: Dictionary, seed_value: int) -> BattleSession:
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 2)
	HeadlessDuel.play(s, {1: ProfileController.new(1, p1, seed_value), 2: ProfileController.new(2, p2, seed_value)}, 50)
	return s


func test_utility_battle_plays_deterministically() -> void:
	var u := _profile("profile_utility")
	var a := _duel(u, u, 1)
	assert_true(a.is_over(), "the duel ends")
	assert_eq(_duel(u, u, 1).state.state_hash().hex_encode(), a.state.state_hash().hex_encode(), "same seed, same game")
	var fuzzy := u.duplicate(true)
	fuzzy["fuzz"] = 40
	var hashes := {}
	for seed_value in [1, 2, 3]:
		hashes[_duel(fuzzy, fuzzy, seed_value).state.state_hash().hex_encode()] = true
	assert_gt(hashes.size(), 1, "fuzz varies decisions with the match seed")


func test_utility_overworld_takes_spends_and_finishes() -> void:
	var u := _profile("profile_utility")
	var x := OverworldSession.create(_l().templates, _l().data_hash, "skirmish_seeded", 3)
	var ctl := {1: ProfileController.new(1, u, 3), 2: ProfileController.new(2, u, 3)}
	var kinds := {}
	for t in 20:
		HeadlessOverworld.play(x, ctl, t + 1)
		for e in x.last_events:
			kinds[e.type] = true
			if e.type == &"activity_performed":
				kinds["activity_" + String(e.data["activity"])] = true
		if not x.state.outcome.is_empty():
			break
	assert_true(kinds.has(&"feature_captured"), "takes features")
	assert_true(kinds.has("activity_convert") or kinds.has("activity_recruit"), "spends Value (A2Q4)")
	assert_true(kinds.has(&"battle_resolved"), "fights")
	for p in [1, 2]:
		assert_eq((ctl[p] as ProfileController).fault, "", "no faults")


func test_scripted_processes() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "skirmish_mirror", 1)
	var steps := [{"turn": 0, "commander": 0, "to": [4, 4]}]
	var pc := ProfileController.new(1, {"overworld": {"process": "scripted", "params": {"steps": steps}}}, 1)
	var plan := pc.plan(x.observe(1), x)
	assert_eq(plan.size(), 1)
	assert_eq(plan[0]["route"][plan[0]["route"].size() - 1], Hex.plot(4, 4, 20))
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 2)
	var b := ProfileController.new(1, {"battle": {"process": "scripted", "params": {"steps": [{"turn": 1, "squad": 0, "type": "hold"}]}}}, 1)
	var o := b.orders(s.observe(1))
	assert_eq(o.size(), 1)
	assert_eq(o[0]["type"], "hold")
	assert_eq(b.orders({"player": 1, "turn": 2, "squads": [], "zones": []}).size(), 0, "no step for turn 2")
	var opening := {"process": "scripted", "params": {"steps": [{"turn": 1, "squad": 0, "type": "hold"}],
		"then": {"process": "zone"}}}
	var h := ProfileController.new(1, {"battle": opening}, 1)
	assert_eq(h.orders(s.observe(1))[0]["type"], "hold", "the scripted opening")
	var later := s.observe(1)
	later["turn"] = 2
	assert_eq(h.orders(later)[0]["type"], "attack_move", "then the zone process takes over")


func _sq(id: int, player: int, x: int, hp_max: int = 100, hp_lost: int = 0) -> Dictionary:
	return {"id": id, "player": player, "template": "", "x": Fixed.from_int(x), "y": 0, "alive": 1,
		"destroyed": false, "withdrawn": false, "hp_max": hp_max, "hp_lost": hp_lost, "order": "hold"}


func test_leaders_stay_out_of_losing_fights() -> void:
	var ub := UtilityBattle.new(1, SimCriteria.Mask.new(ProfileController.default_mask()))
	ub.leaders = {1: true}
	var obs := {"player": 1, "turn": 3, "scores": {},
		"squads": [_sq(1, 1, 0), _sq(2, 1, 1), _sq(10, 2, 8), _sq(11, 2, 9)],
		"zones": [{"x": Fixed.from_int(5), "y": 0, "owner": 0, "amount": 0, "threshold": 10, "locked": false}]}
	var orders := {}
	for o: Dictionary in ub.orders(obs):
		orders[o["squad"]] = o["type"]
	assert_eq(orders[1], "fall_back", "the leader backs off from a stronger enemy")
	assert_eq(orders[2], "attack_move", "other squads still fight for the zone")
	ub.leaders = {}
	var free := {}
	for o: Dictionary in ub.orders(obs):
		free[o["squad"]] = o["type"]
	assert_eq(free[1], "attack_move", "without leaders every squad fights")


## A process that fails: returns null like a script error would.
class _Broken extends RefCounted:
	func plan(_obs: Dictionary, _session: OverworldSession) -> Variant:
		return null


func test_faults_forfeit() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "skirmish_mirror", 1)
	var crash := ProfileController.new(1, {"overworld": {"process": "idle"}}, 1)
	crash._overworld = _Broken.new()
	assert_eq(crash.plan(x.observe(1), x), [])
	assert_eq(crash.fault, "crash")
	var slow := ProfileController.new(2, {}, 1)
	slow.think_ms = 0
	slow.plan(x.observe(2), x)
	assert_eq(slow.fault, "think_time", "over the think-time limit")
	assert_eq(slow.plan(x.observe(2), x), [], "a faulted profile does nothing more")
	var m := SimMetrics.new()
	var report := {}
	assert_true(ProfileController.record_faults({1: crash, 2: slow}, m, report))
	var res := m._results(PackedInt64Array([1, 2]), 0, 1)
	var forfeited := res.filter(func(r: Dictionary) -> bool: return r["metric"] == "forfeited" and r["value"] > 0)
	assert_eq(forfeited.size(), 1, "the first fault forfeits")
	assert_true(report.has("fault"))
	assert_true(report["think_ms_max"].has("2"))
