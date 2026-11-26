extends GutTest
## The workshop debug frames and overlay (sw-tho3.6, U1 B6): frames are plain
## data that leave the battle untouched, and the overlay draws from them
## alone, holding no sim object.

const SCENARIO := "res://data/sim/workshop/rifle_vs_dummy.json"


func _run(variant: String = WorkshopScenario.BASE, debug: bool = true, play: bool = true) -> WorkshopRun:
	var run := WorkshopRun.execute(WorkshopScenario.load_file(SCENARIO), variant, play, debug)
	assert_true(run.is_ok(), "\n".join(run.errors))
	return run


## Every Object reachable from `v` through Dictionaries and Arrays.
static func _objects(v: Variant, out: Array = []) -> Array:
	match typeof(v):
		TYPE_OBJECT:
			if v != null:
				out.append(v)
		TYPE_DICTIONARY:
			for k: Variant in v:
				_objects(k, out)
				_objects(v[k], out)
		TYPE_ARRAY:
			for e: Variant in v:
				_objects(e, out)
	return out


func test_debug_frames_leave_the_battle_unchanged() -> void:
	var plain := _run(WorkshopScenario.BASE, false)
	var dbg := _run(WorkshopScenario.BASE, true)
	assert_eq(dbg.final_hash, plain.final_hash, "capturing debug frames must not change the battle")
	assert_eq(dbg.turn_hashes, plain.turn_hashes)
	assert_true(plain.debug_frames.is_empty())
	assert_eq(dbg.debug_frames.size(), dbg.frame_turn.size(), "one debug frame per frame")


func test_frames_are_plain_data() -> void:
	var run := _run()
	for f: int in run.debug_frames:
		assert_eq(_objects(run.debug_frames[f]), [], "frame %d holds an object" % f)


func test_frame_holds_fire_victims_and_ranges() -> void:
	var run := _run()
	var fr: Dictionary = run.debug_frames[run.frame_at(1, 10)]
	var rifles: int = run.sids["rifles"]
	var dummy: int = run.sids["dummy"]
	var shot: Array = fr["fire"].filter(func(p: Dictionary) -> bool: return p["from"] == rifles and p["to"] == dummy)
	assert_eq(shot.size(), 1)
	assert_eq(shot[0]["los"], "shot")
	var sq: Dictionary = fr["squads"].filter(func(s: Dictionary) -> bool: return s["id"] == rifles)[0]
	assert_gt(float(sq["range"]), 15.0, "rifle range in metres")
	assert_typeof(sq["activity"], TYPE_STRING)
	var victims := 0
	for u: Dictionary in fr["units"]:
		if u["squad"] == rifles and u["victim"] >= 0:
			victims += 1
	assert_gt(victims, 0, "rifles have victims")


func test_a_moving_squad_shows_its_route() -> void:
	var run := _run("run_away")
	var fr: Dictionary = run.debug_frames[run.frame_at(1, 2)]
	var rifles: int = run.sids["rifles"]
	var rt: Array = fr["routes"].filter(func(r: Dictionary) -> bool: return r["squad"] == rifles)
	assert_eq(rt.size(), 1)
	var pts: PackedVector2Array = rt[0]["points"]
	assert_gte(pts.size(), 2)
	assert_true(rt[0]["final"])
	assert_almost_eq(pts[pts.size() - 1].x, 10.0, 1.0, "ends at the ordered point (10, 70)")


func test_units_on_top_of_each_other_are_a_spacing_violation() -> void:
	var run := _run(WorkshopScenario.BASE, true, false)
	var st := run.state
	var row := st.squads.row_of(run.sids["rifles"])
	var urows := Centroids.units_of(st, row)
	var a := st.units.id_at(urows[0])
	var b := st.units.id_at(urows[1])
	st.units.set_value(b, &"x", st.units.x[urows[0]])
	st.units.set_value(b, &"y", st.units.y[urows[0]])
	var fr := WorkshopDebug.capture(st, BattleRoute.new())
	var hit: Array = fr["spacing"].filter(func(v: Dictionary) -> bool: return v["a"] in [a, b] and v["b"] in [a, b])
	assert_eq(hit.size(), 1)
	assert_almost_eq(float(hit[0]["gap"]), 0.0, 0.01)


func test_overlay_holds_no_sim_object_and_drawing_changes_nothing() -> void:
	var run := _run()
	var before := run.state.state_hash_hex()
	var view := ContextView.new()
	view.size = Vector2(800, 500)
	add_child_autofree(view)
	view.show_battle(BattleSession.observe_state(run.state, 0), {})
	var o := DebugOverlay.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.add_child(o)
	o.attach(view)
	o.set_layer("labels", true)
	o.show_frame(run.debug_frames[run.frame_turn.size() - 1])
	await wait_frames(3)
	assert_gt(o.draws, 0, "the overlay drew")
	assert_eq(run.state.state_hash_hex(), before, "drawing must not touch the battle")
	for p: Dictionary in o.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		for obj: Object in _objects(o.get(p["name"])):
			assert_true(obj == view, "%s holds %s" % [p["name"], obj])


func test_overlay_frame_is_a_copy() -> void:
	var run := _run()
	var fr: Dictionary = run.debug_frames[0]
	var o := DebugOverlay.new()
	autofree(o)
	o.show_frame(fr)
	(fr["squads"] as Array).clear()
	assert_false((o.frame()["squads"] as Array).is_empty())


func test_layers_switch() -> void:
	var o := DebugOverlay.new()
	autofree(o)
	watch_signals(o)
	o.set_layer("ranges", false)
	assert_false(o.is_layer_on("ranges"))
	assert_signal_emit_count(o, "layers_changed", 1)
	o.set_layer("ranges", false)
	o.set_layer("nonsense", true)
	assert_signal_emit_count(o, "layers_changed", 1, "no change, no signal")
	assert_false(o.is_layer_on("nonsense"))
	assert_eq(o.mouse_filter, Control.MOUSE_FILTER_IGNORE)
