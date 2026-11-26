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
