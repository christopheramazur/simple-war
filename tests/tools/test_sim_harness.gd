extends GutTest
## The game side of `hx sim` (GDD 05 §5.1-5.2, R4Q11, R7Q17): variants
## (SimVariant), the metrics library (SimMetrics) and per-system profiling.
## Task sw-884.1.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func test_variants_patch_content() -> void:
	var v := SimVariant.load_file("res://data/sim/variants/tough_angels.json")
	assert_eq(v.name, "tough_angels")
	assert_true(v.apply(_l()), "; ".join(v.errors))
	assert_eq(v.templates.values_of("seraph")["hp"], 18)
	assert_eq(_l().templates.values_of("seraph")["hp"], 12, "the shipped content is untouched")
	assert_ne(v.data_hash, _l().data_hash, "patched content has its own hash")
	assert_eq(v.turns(), 12)
	var base := SimVariant.load_file("")
	assert_true(base.apply(_l()))
	assert_eq(base.data_hash, _l().data_hash)
	var bad := SimVariant.new()
	bad.data = {"patches": {"no_such_unit": {"hp": 3}, "seraph": {"hp": "lots"}}}
	assert_false(bad.apply(_l()))
	assert_eq(bad.errors.size(), 2, "; ".join(bad.errors))


func test_controller_profiles() -> void:
	var v := SimVariant.load_file("res://data/sim/variants/cautious.json")
	var c: ZoneController = v.controller(1, "zone")
	assert_eq(c.fall_back_pct, 50)
	assert_true(SimVariant.load_file("res://data/sim/variants/idle_defender.json").controller(2, "zone") is SimVariant.IdleController)
	assert_true(SimVariant.new().controller(1, "expand") is ExpandController)


func _duel(measure: bool) -> Array:
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 2)
	var m := SimMetrics.new()
	if measure:
		m.watch_battle(s.state, s.sim)
	HeadlessDuel.play(s, {1: ZoneController.new(1), 2: ZoneController.new(2)}, 4)
	return [s, m]


func test_battle_metrics() -> void:
	var r := _duel(true)
	var s: BattleSession = r[0]
	var rows := (r[1] as SimMetrics).battle(s.state, s.sim)
	var names := {}
	for row: Dictionary in rows:
		names[row["metric"]] = true
	for m: String in ["vp", "value_destroyed", "value_lost", "units_lost", "squads_lost", "turns",
			"first_contact_tick", "first_casualty_tick", "first_capture_turn"]:
		assert_true(names.has(m), m)
	assert_true(names.keys().any(func(k: String) -> bool: return k.begins_with("band.morale.")), "time in pressure bands")
	assert_true(names.keys().any(func(k: String) -> bool: return k.begins_with("ledger.")), "the SIMPL ledger")
	assert_true(names.has("perf.CombatSystem_usec"), "per-system performance")
	assert_true(names.has("band_changes.morale") or names.has("band_changes.stamina"), "band crossings (Pressure Lab)")
	assert_true(names.has("first_break_tick"))
	var ticks := 0.0
	for row: Dictionary in rows:
		if String(row["metric"]).begins_with("band.stamina.") and row["player"] == 1:
			ticks += row["value"]
	assert_gt(ticks, 0.0)


func test_measuring_changes_nothing() -> void:
	var a: BattleSession = _duel(true)[0]
	var b: BattleSession = _duel(false)[0]
	assert_eq(a.state.state_hash(), b.state.state_hash(), "metrics and profiling are read-only")


func test_overworld_metrics() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 3)
	var ctl := {1: ExpandController.new(1), 2: ExpandController.new(2)}
	var events := []
	for t in 3:
		HeadlessOverworld.play(x, ctl, t + 1)
		for e in x.last_events:
			var d := e.to_dict()
			d["turn"] = x.turns_resolved()
			events.append(d)
	var rows := SimMetrics.new().overworld(x, events)
	var explored := rows.filter(func(r: Dictionary) -> bool: return r["metric"] == "hexes_explored" and r["player"] == 1)
	assert_gt(explored[0]["value"], 0.0)
	var turns := rows.filter(func(r: Dictionary) -> bool: return r["metric"] == "turns")
	assert_eq(turns[0]["value"], 3.0)
