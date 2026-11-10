extends GutTest
## Replay recording and the viewer. Task sw-ip8.1.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _controllers() -> Dictionary:
	return {1: ZoneController.new(1), 2: ZoneController.new(2, {"fall_back_pct": 60})}


func test_recorder_captures_every_tick() -> void:
	var rec := ReplayRecorder.from_duel(_l().templates, _l().data_hash, "duel_crossroads", 7, _controllers())
	var turns: int = rec.result["turn"]
	# One initial frame, ticks_per_turn per turn, plus one after each turn's resolution.
	assert_eq(rec.frames.size(), 1 + turns * (rec.rules.ticks_per_turn + 1))
	assert_eq(rec.events.size(), rec.frames.size())
	var fired := 0
	for evs: Array in rec.events:
		for e: Dictionary in evs:
			if e["type"] == &"squad_fired":
				fired += 1
	assert_gt(fired, 0)


func test_save_replays_to_the_same_frames() -> void:
	var live := ReplayRecorder.from_duel(_l().templates, _l().data_hash, "duel_crossroads", 3, _controllers())
	var again := ReplayRecorder.from_save(live.save_bytes, _l().templates, _l().data_hash)
	assert_not_null(again)
	assert_eq(again.frames.size(), live.frames.size())
	assert_eq(again.frames[-1], live.frames[-1])
	assert_eq(again.result, live.result)


func test_viewer_plays_and_seeks() -> void:
	var viewer: ReplayViewer = load("res://src/presentation/replay_viewer/replay_viewer.tscn").instantiate()
	add_child_autofree(viewer)
	assert_not_null(viewer.recorder, "demo recorded")
	viewer.advance(1.0)
	assert_almost_eq(viewer.position_ticks, float(viewer.recorder.rules.tps), 0.001, "1 s at 1x = tps ticks")
	viewer.seek_turn(3)
	assert_eq(viewer.current_turn(), 3)
	viewer.seek_frame(999999)
	assert_eq(int(viewer.position_ticks), viewer.recorder.frames.size() - 1)
	viewer._update_hud()
	assert_string_contains(viewer._hud.text, "Result:")
