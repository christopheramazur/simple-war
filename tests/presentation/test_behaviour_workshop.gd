extends GutTest
## The behaviour workshop F6 scene (sw-tho3.8, U1 B8): WorkshopRun's
## playback and BattleCursor states, the scene's transport, probes and
## squad card, and that it leaves nothing behind.

const SCENE := "res://src/presentation/workshop/behaviour_workshop.tscn"
const SCENARIO := "res://data/sim/workshop/dps_orders.json"


func _run(variant: String = WorkshopScenario.BASE) -> WorkshopRun:
	var sc := WorkshopScenario.load_file(SCENARIO)
	return WorkshopRun.execute(sc, variant, true, true)


## Unit ID -> Vector2i(x, y) fixed, from a ReplayRecorder frame.
static func _rec_positions(f: PackedInt64Array) -> Dictionary:
	var out := {}
	for o in range(0, f.size(), ReplayRecorder.STRIDE):
		out[f[o + ReplayRecorder.F_ID]] = Vector2i(f[o + ReplayRecorder.F_X], f[o + ReplayRecorder.F_Y])
	return out


static func _state_positions(st: BattleState) -> Dictionary:
	var out := {}
	var u := st.units
	for row in u.count():
		out[u.id_at(row)] = Vector2i(u.x[row], u.y[row])
	return out


func test_debug_run_records_playback_and_cursors() -> void:
	var run := _run()
	assert_true(run.is_ok(), "\n".join(run.errors))
	assert_eq(run.playback_frames.size(), run.frame_turn.size(), "a playback frame per frame")
	assert_eq(run.cursor_records.size(), run.turns_run, "a cursor record per turn")
	var rec := run.playback()
	assert_eq((rec["frames"] as Array).size(), run.frame_turn.size())
	assert_gt((rec["volleys"] as Array).size(), 0, "the rifles' shots are there")


func test_a_plain_run_keeps_no_playback() -> void:
	var sc := WorkshopScenario.load_file(SCENARIO)
	var run := WorkshopRun.execute(sc)
	assert_true(run.playback_frames.is_empty())
	assert_true(run.playback().is_empty())


func test_debug_recording_leaves_the_hash_alone() -> void:
	var sc := WorkshopScenario.load_file(SCENARIO)
	assert_eq(WorkshopRun.execute(sc, "base", true, true).final_hash, WorkshopRun.execute(sc).final_hash)


func test_cursor_state_matches_every_headless_frame() -> void:
	var run := _run("move_then_attack")
	var fresh := _run("move_then_attack")
	var n := run.frame_turn.size()
	for f in [0, 1, 7, 33, run.frame_at(1, -1), run.frame_at(2, 0), run.frame_at(2, 19), n / 2, n - 2, n - 1]:
		var st := run.state_at(f)
		assert_not_null(st, "frame %d: %s" % [f, run.cursor_reason(f)])
		if st == null:
			continue
		assert_eq(_state_positions(st), _rec_positions(fresh.recorder.frames[f]), "frame %d positions" % f)
	# Backwards after forwards: the cursor restores from a keyframe.
	var back := run.state_at(5)
	assert_eq(_state_positions(back), _rec_positions(fresh.recorder.frames[5]), "seeking back")


# --- the scene -------------------------------------------------------------------

func _scene(variant: String = WorkshopScenario.BASE, path: String = SCENARIO) -> BehaviourWorkshop:
	var w: BehaviourWorkshop = (load(SCENE) as PackedScene).instantiate()
	w.scenario_path = path
	w.variant = variant
	add_child_autofree(w)
	return w


func _fire(w: BehaviourWorkshop, action: StringName) -> void:
	(w.keys.actions[action] as GUIDEAction).triggered.emit()


func test_scene_loads_the_scenario_and_its_probes() -> void:
	var w := _scene("hold")
	assert_eq(w.error, "", w.error)
	assert_not_null(w.run)
	assert_eq(w.variant, "hold")
	assert_eq(w.probe_count(), w.run.scenario.probes.size(), "a row per probe")
	assert_eq(w.current_frame(), 0)
	assert_false(w.playing, "opens paused")


func test_seeking_to_a_tick_shows_the_headless_frame() -> void:
	var w := _scene("attack_move")
	var fresh := _run("attack_move")
	for n in [0, 1, 12, 61, w.run.frame_at(1, -1), w.run.frame_at(2, 30), w.frame_count() - 1]:
		w.seek_frame(n)
		assert_eq(w.current_frame(), n)
		var want := {}
		var pos := _rec_positions(fresh.recorder.frames[n])
		for uid: int in pos:
			want[uid] = Vector2(pos[uid]) / float(Fixed.ONE)
		assert_eq(w.shown_positions(), want, "frame %d shows the headless positions" % n)
		assert_eq(w.overlay.frame(), fresh.debug_frames[n], "overlay frame %d" % n)


func test_transport_keys_step_ticks_turns_and_restart() -> void:
	var w := _scene()
	_fire(w, &"workshop_next_tick")
	_fire(w, &"workshop_next_tick")
	assert_eq(w.current_frame(), 2, "period steps a tick on")
	_fire(w, &"workshop_prev_tick")
	assert_eq(w.current_frame(), 1, "comma steps a tick back")
	_fire(w, &"replay_next_turn")
	assert_eq(w.current_turn(), 2, "Right: the next turn")
	assert_eq(w.run.frame_turn[w.current_frame() - 1], 1, "at its first frame")
	_fire(w, &"replay_prev_turn")
	assert_eq(w.current_turn(), 1)
	_fire(w, &"replay_faster")
	assert_eq(w.speed_index, 3)
	_fire(w, &"replay_toggle")
	assert_true(w.playing)
	w._process(0.5)
	assert_gt(w.current_frame(), w.run.frame_at(1, 0), "plays on")
	_fire(w, &"replay_restart")
	assert_eq(w.current_frame(), 0, "Home: the start")
	_fire(w, &"workshop_prev_tick")
	assert_eq(w.current_frame(), 0, "clamped at the start")
	assert_false(w.playing, "stepping pauses")


func test_probe_click_seeks_and_inspects_its_squad() -> void:
	var w := _scene("hold")
	var sc := w.run.scenario
	var row := 0
	var want := w.run.frames_over(sc.probes[row]["over"])[0]
	w.pick_probe(row)
	assert_eq(w.current_frame(), want, "seeks to the probe's first tick")
	assert_eq(w.inspected, int(w.run.sids[sc.probes[row]["squad"]]), "inspects the probe's squad")
	w.seek_frame(40)
	var card := w._card_box.get_child(0)
	assert_true(card is VBoxContainer, "a SquadCard shows (not a notice)")


func test_card_reads_the_cursor_state_at_the_frame() -> void:
	var w := _scene()
	w.inspect(int(w.run.sids["rifles"]))
	w.seek_frame(25)
	var st := w.run.state_at(25)
	assert_not_null(st)
	assert_eq(st.tick, w.run.frame_abs[25] + 1, "the state after that tick")


func test_mid_turn_orders_explain_the_missing_state() -> void:
	var w := _scene("retarget_mid", "res://data/sim/workshop/dps_retarget.json")
	assert_eq(w.error, "", w.error)
	w.inspect(int(w.run.sids["rifles"]))
	w.seek_frame(10)
	assert_null(w.run.state_at(10))
	assert_string_contains(w.run.cursor_reason(10), "mid-turn")
	var lbl := w._card_box.get_child(0) as Label
	assert_not_null(lbl)
	assert_string_contains(lbl.text, "mid-turn")


func test_f5_reloads_at_the_same_frame() -> void:
	var w := _scene()
	var before := w.run
	w.seek_frame(37)
	_fire(w, &"workshop_reload")
	assert_ne(w.run, before, "ran again")
	assert_eq(w.current_frame(), 37, "kept the frame")
	assert_eq(w.run.final_hash, before.final_hash, "same file, same run")


func test_args_and_a_bad_path_report_instead_of_crashing() -> void:
	var w := _scene(WorkshopScenario.BASE, "res://data/sim/workshop/no_such_scenario.json")
	assert_null(w.run)
	assert_ne(w.error, "")
	w.seek_frame(5)
	_fire(w, &"replay_toggle")
	assert_false(w.playing)


func test_keys_come_from_guide_only() -> void:
	var src := (load("res://src/presentation/workshop/behaviour_workshop.gd") as GDScript).source_code
	assert_false(src.contains("KEY_"), "no hard-coded keys")
	assert_false(src.contains("func _input") or src.contains("func _unhandled_input") or src.contains("func _unhandled_key_input"))
	var g := DefaultKeys.workshop()
	assert_eq((g.keys[&"workshop_next_tick"] as Array)[0].key, KEY_PERIOD)
	assert_eq((g.keys[&"workshop_prev_tick"] as Array)[0].key, KEY_COMMA)
	assert_eq((g.keys[&"workshop_reload"] as Array)[0].key, KEY_F5)
	assert_eq(g.actions.size(), DefaultKeys.replay().actions.size() + 3, "the replay transport plus three")


func test_no_orphans_after_freeing() -> void:
	var w: BehaviourWorkshop = (load(SCENE) as PackedScene).instantiate()
	w.scenario_path = SCENARIO
	add_child(w)
	w.inspect(int(w.run.sids["rifles"]))
	w.seek_frame(30)
	w.seek_frame(31)
	remove_child(w)
	w.free()
	await get_tree().process_frame
	assert_no_new_orphans()
