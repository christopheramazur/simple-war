extends GutTest
## The behaviour workshop (sw-tho3.3, U1 B3): every scenario in
## data/sim/workshop runs here. Gate checks must pass; pending ones are
## reported and never fail the suite ("unexpected pass" when they start
## passing). Plus the format's own contract: determinism, readable errors,
## fixed-point quantization and variant merge rules.

const ONE := Fixed.ONE


## A small valid scenario to vary in the contract tests.
func _base() -> Dictionary:
	return {
		"id": "t", "component": "test", "status": "gate", "open": true, "turns": 1,
		"squads": [
			{"key": "rifles", "player": 1, "squad": "rifle_squad", "at": [50, 70]},
			{"key": "dummy", "player": 2, "squad": "rifle_squad", "at": [70, 70], "facing": 180,
				"dummy": {"armed": false, "hp": 1000, "stationary": true}, "patch": {"morale": 5, "ammo": 3}},
		],
		"script": {"1": [{"squad": "rifles", "type": "attack", "target": "dummy"}]},
		"probes": [{"id": "shots", "over": "t1", "squad": "rifles", "shots": {"min": 1}}],
	}


func test_every_gate_scenario_passes() -> void:
	var files := WorkshopScenario.list()
	assert_gt(files.size(), 0, "data/sim/workshop holds scenarios")
	for f in files:
		var rep := WorkshopReport.run(WorkshopScenario.load_file(f))
		for line in WorkshopReport.text(rep):
			if "unexpected pass" in line or "pending" in line:
				gut.p(line)
		assert_eq(rep["errors"], [], "%s loads and runs" % f)
		assert_eq(rep["result"], "pass", "%s:\n%s" % [f, "\n".join(WorkshopReport.text(rep))])


func test_two_runs_give_the_same_hash() -> void:
	var sc := WorkshopScenario.find("rifle_vs_dummy")
	var a := WorkshopRun.execute(sc)
	var b := WorkshopRun.execute(sc)
	assert_true(a.is_ok(), "; ".join(a.errors))
	assert_ne(a.final_hash, "")
	assert_eq(a.final_hash, b.final_hash)
	assert_eq(a.turn_hashes, b.turn_hashes)
	assert_eq(a.recorder.frames.size(), b.recorder.frames.size())
	assert_ne(WorkshopRun.execute(sc, "run_away").final_hash, a.final_hash, "a variant is another battle")


func test_bad_file_gives_path_and_field() -> void:
	var d := _base()
	d["status"] = "maybe"
	d["squads"][0]["at"] = [50]
	d["squads"][1]["dummy"]["hp"] = -3
	d["script"]["1"].append({"squad": "nobody", "type": "move", "x": 1, "y": 1})
	d["script"]["1"].append({"squad": "dummy", "type": "hold"})
	d["probes"].append({"id": "x", "at": "t9:4", "squad": "rifles", "activity": "ENGAGED"})
	d["probes"].append({"id": "y", "over": "t1", "squad": "rifles", "fire": "shot", "target": "dummy"})
	d["compare"] = [{"metric": "nope", "lhs": "base", "rhs": "base"}]
	var sc := WorkshopScenario.from_dict(d, "bad.json")
	assert_false(sc.is_valid())
	var all := "\n".join(sc.errors)
	for want in ["bad.json: status:", "bad.json: squads[0].at: must be [x, y] in metres",
			"squads[1].dummy.hp:", "script.1[1].squad:", "script.1[2].squad: 'dummy' is a stationary dummy",
			"probes.x.at:", "probes.y.over: 'fire' is read at one moment", "compare[0].metric:"]:
		assert_string_contains(all, want)
	var rep := WorkshopReport.run(sc)
	assert_eq(rep["result"], "error")
	var missing := WorkshopScenario.load_file("res://data/sim/workshop/no_such.json")
	assert_string_contains("\n".join(missing.errors), "no_such.json: no such file")


func test_quantization_is_one_rule() -> void:
	assert_eq(WorkshopScenario.milli(0.1), 100)
	assert_eq(WorkshopScenario.milli(2.0005), 2001, "ties away from zero")
	assert_eq(WorkshopScenario.milli(-2.0005), -2001)
	assert_eq(WorkshopScenario.to_fixed(1.5), 3 * ONE / 2)
	assert_eq(WorkshopScenario.to_fixed(0.1), Fixed.round_div(100 * ONE, 1000))
	assert_eq(WorkshopScenario.to_fixed(0.1), WorkshopScenario.to_fixed(0.1000001), "below a thousandth is dropped")
	assert_eq(WorkshopScenario.to_angle(180), Fixed.ANGLE_HALF)
	assert_eq(WorkshopScenario.to_angle(-90), 3 * Fixed.ANGLE_QUARTER)
	var d := _base()
	d["squads"][0]["at"] = [50.25, 70.0004]
	d["compare"] = [{"metric": "shots", "lhs": "base", "rhs": "base", "factor": 0.8}]
	var sc := WorkshopScenario.from_dict(d)
	assert_true(sc.is_valid(), "\n".join(sc.errors))
	assert_eq(sc.squads[0]["x"], 50 * ONE + ONE / 4)
	assert_eq(sc.squads[0]["y"], 70 * ONE, "70.0004 rounds to 70.000")
	assert_eq(sc.squads[1]["patch"]["morale"], 5 * ONE)
	assert_eq(sc.squads[1]["patch"]["ammo"], 3, "ammo stays a whole count")
	assert_eq(sc.compare[0]["factor"], 800)
	assert_eq(sc.probes[0]["expect"], {"min": 1000})


func test_variant_script_replaces_turn_and_patch_merges_shallowly() -> void:
	var d := _base()
	d["turns"] = 2
	d["script"]["2"] = [{"squad": "rifles", "type": "hold"}]
	d["variants"] = {"v": {
		"script": {"1": [{"squad": "rifles", "type": "move", "x": 20, "y": 70}]},
		"patch": {"dummy": {"morale": 9}, "rifles": {"hp": 50}}}}
	var sc := WorkshopScenario.from_dict(d)
	assert_true(sc.is_valid(), "\n".join(sc.errors))
	var base := sc.resolved("base")
	var v := sc.resolved("v")
	assert_eq(base["script"][1][0]["type"], "attack")
	assert_eq(v["script"][1].size(), 1, "turn 1 replaced, not appended")
	assert_eq(v["script"][1][0]["type"], "move")
	assert_eq(v["script"][2][0]["type"], "hold", "turns the variant does not name stay")
	assert_eq(v["squads"][1]["patch"], {"morale": 9 * ONE, "ammo": 3}, "stat by stat over the base patch")
	assert_eq(v["squads"][0]["patch"], {"hp": 50 * ONE})
	assert_eq(base["squads"][1]["patch"]["morale"], 5 * ONE, "the base is untouched")
	assert_eq(sc.resolved("nope"), {})
	var run := WorkshopRun.execute(sc, "v", false)
	assert_true(run.is_ok(), "; ".join(run.errors))
	var srow := run.state.squads.row_of(run.sids["dummy"])
	assert_eq(run.state.squads.p_morale[srow], 9 * ONE)
	var urow: int = Centroids.units_of(run.state, run.state.squads.row_of(run.sids["rifles"]))[0]
	assert_eq(run.state.units.hp_max[urow], 50 * ONE)


func test_pending_never_fails_and_unexpected_pass_is_reported() -> void:
	var d := _base()
	d["probes"] = [
		{"id": "miss", "over": "t1", "squad": "rifles", "shots": {"min": 100000}, "pending": true},
		{"id": "hit", "over": "t1", "squad": "rifles", "shots": {"min": 1}, "pending": true},
	]
	var rep := WorkshopReport.run(WorkshopScenario.from_dict(d))
	assert_eq(rep["result"], "pass", "pending checks never fail the scenario")
	assert_eq(rep["gate_failures"], 0)
	assert_eq(rep["pending"], 1)
	assert_eq(rep["unexpected_passes"], 1)
	assert_string_contains("\n".join(WorkshopReport.text(rep)), "unexpected pass [base] hit")
	d["status"] = "pending"
	d["probes"][0].erase("pending")
	assert_eq(WorkshopReport.run(WorkshopScenario.from_dict(d))["result"], "pass", "a pending scenario never fails")
	d["status"] = "gate"
	var gate := WorkshopReport.run(WorkshopScenario.from_dict(d))
	assert_eq(gate["result"], "fail", "the same miss in a gate scenario fails")
	assert_eq(gate["gate_failures"], 1)
	var all := WorkshopReport.run_all(PackedStringArray(["res://data/sim/workshop/no_such.json"]))
	assert_false(all["ok"], "--all is not ok when a file cannot load")


func test_strided_snapshots_and_manifest() -> void:
	var d := _base()
	d["probe_stride"] = 25
	d["probes"].append({"id": "act", "at": "t1:33", "squad": "rifles", "activity": null})
	var run := WorkshopRun.execute(WorkshopScenario.from_dict(d))
	assert_true(run.is_ok(), "; ".join(run.errors))
	var ticks := run.rules.ticks_per_turn
	# start + ticks 0, 25, 50, 75 + tick 33 (an at probe) + the resolved turn
	assert_eq(run.snapshots.size(), 1 + ceili(ticks / 25.0) + 1 + 1)
	assert_true(run.snapshots.has(run.frame_at(1, 33)))
	assert_eq(run.recorder.frames.size(), 1 + ticks + 1, "playback frames stay per tick")
	var rep := WorkshopReport.run(WorkshopScenario.from_dict(d))
	assert_eq(rep["schema"], WorkshopReport.SCHEMA)
	assert_eq(rep["data_hash"], WorkshopRun.loader_for("rules-fixture").data_hash)
	assert_ne(rep["data_hash"], "")
	for k in ["scenario", "status", "package", "engine", "seed", "variants", "compare", "result"]:
		assert_true(rep.has(k), "manifest carries %s" % k)
