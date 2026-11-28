extends GutTest
## The capture runner's headless half (sw-tho3.9): CaptureSim, CaptureJob.

const FIGHT: Dictionary = {
	"id": "capture_fight", "component": "capture", "doc": "Capture test.", "status": "pending",
	"package": "core", "map": "duel_crossroads", "seed": 3, "turns": 2,
	"squads": [
		{"key": "gunners", "player": 1, "squad": "rifle_squad", "at": [78, 50], "facing": 0},
		{"key": "enemy", "player": 2, "squad": "rifle_squad", "at": [98, 52], "facing": 180},
	],
	"script": {"1": [{"squad": "gunners", "type": "attack_move", "x": 100, "y": 52}]},
	"probes": [],
}


func _quiet() -> Dictionary:
	var d := FIGHT.duplicate(true)
	d["id"] = "capture_quiet"
	d["squads"] = [
		{"key": "a", "player": 1, "squad": "rifle_squad", "at": [10, 10], "facing": 0},
		{"key": "b", "player": 2, "squad": "rifle_squad", "at": [180, 90], "facing": 180},
	]
	d["script"] = {}
	return d


func _src(d: Dictionary = FIGHT) -> Dictionary:
	return {"kind": "workshop", "scenario": d}


func test_workshop_source_finds_stages_and_plans_shots() -> void:
	var job := CaptureJob.prepare(_src(), {"views": [0, 1], "kinds": ["game", "control", "greyscale"]})
	assert_true(job.is_ok(), str(job.errors))
	assert_true(job.stages.has("deploy") and job.stages.has("contact") and job.stages.has("end"), str(job.stages))
	assert_eq(job.stages["deploy"], {"turn": 1, "frame": 0, "tick": 0})
	assert_false(job.shots.is_empty())
	var s: Dictionary = job.shots[0]
	assert_eq(s["id"], "deploy_all_still")
	assert_eq((s["images"] as Dictionary).keys(), ["game", "control", "greyscale"])
	assert_false((s["layout"] as Dictionary).has("greyscale"), "CVD kinds reuse the game render's layout")
	for shot: Dictionary in job.shots:
		var t := job.shot_truth(shot)
		for fr: Dictionary in t["frames"]:
			assert_false((fr["probe"] as Dictionary).is_empty(), "truth at %s frame %d" % [shot["id"], fr["frame"]])
		var entry := job.truth_at(int(shot["turn"]), int(shot["frames"][0]))
		assert_true(entry.has("debug"), "control kind takes a debug frame")


func test_two_captures_give_identical_truth_and_manifest() -> void:
	var a := CaptureJob.prepare(_src())
	var b := CaptureJob.prepare(_src())
	assert_true(a.is_ok(), str(a.errors))
	assert_eq(CaptureJob.to_json(a.manifest()), CaptureJob.to_json(b.manifest()))
	for i in a.shots.size():
		assert_eq(CaptureJob.to_json(a.shot_truth(a.shots[i])), CaptureJob.to_json(b.shot_truth(b.shots[i])))


func test_manifest_carries_identity_and_stage_ticks() -> void:
	var job := CaptureJob.prepare(_src())
	var m := job.manifest()
	for k in ["source", "data_hash", "engine", "state_hash", "stages", "missing", "shots"]:
		assert_true(m.has(k), k)
	assert_eq(m["data_hash"], WorkshopRun.loader_for("core").data_hash)
	assert_eq(m["engine"], Engine.get_version_info()["string"])
	assert_eq(m["state_hash"], WorkshopRun.execute(WorkshopScenario.from_dict(FIGHT)).final_hash)
	for st: String in m["stages"]:
		assert_true((m["stages"][st] as Dictionary).has("tick"))
	assert_false(m["source"].has("bytes"))


func test_recording_does_not_change_the_battle() -> void:
	var sc := WorkshopScenario.from_dict(FIGHT)
	var plain := WorkshopRun.execute(sc)
	var sim := CaptureSim.new()
	sim.want = {1: {Vector2i(0, 3): true, Vector2i(1, 7): true}}
	sim.viewers = PackedInt64Array([0, 1, 2])
	sim.debug = true
	var rec := WorkshopRun.execute(sc, WorkshopScenario.BASE, true, false, sim)
	assert_eq(rec.final_hash, plain.final_hash)
	assert_eq(rec.turn_hashes, plain.turn_hashes)
	assert_eq((sim.turns[1] as Array).size(), 2)
	assert_eq((sim.truth[1] as Dictionary).size(), 2)
	# The record seals each turn with the same hash the run saw.
	assert_eq(String(sim.turns[1][1]["start"]["end_hash"]), plain.turn_hashes[1])


func test_no_contact_gives_an_empty_manifest() -> void:
	var job := CaptureJob.prepare(_src(_quiet()))
	assert_true(job.is_ok(), str(job.errors))
	assert_true(job.shots.is_empty())
	assert_true(job.stages.is_empty())
	assert_eq(job.missing.get("contact"), "no contact")
	assert_eq((job.manifest()["shots"] as Array).size(), 0)


func test_missing_stage_is_reported_not_an_error() -> void:
	var job := CaptureJob.prepare(_src())
	assert_true(job.is_ok())
	for n in CaptureStages.ORDER:
		assert_true(job.stages.has(n) != job.missing.has(n), n)


func test_fog_view_truth_hides_enemy_internals() -> void:
	var job := CaptureJob.prepare(_src(), {"views": [1], "forms": ["still"], "kinds": ["game"]})
	assert_true(job.is_ok(), str(job.errors))
	var t := job.shot_truth(job.shots[0])
	var probe: Dictionary = t["frames"][0]["probe"]
	assert_eq(probe["viewer"], 1)
	for sq: Dictionary in probe["squads"]:
		assert_eq(sq.has("order"), sq["player"] == 1, "only own squads show orders")


func test_view_for_a_player_not_in_the_battle_is_skipped() -> void:
	var job := CaptureJob.prepare(_src(), {"views": [0, 7], "forms": ["still"]})
	assert_true(job.is_ok())
	assert_true(job.skipped.has("p7"))
	for s: Dictionary in job.shots:
		assert_eq(s["viewer"], 0)


func test_bad_options_are_errors() -> void:
	assert_false(CaptureJob.prepare(_src(), {"kinds": ["sepia"]}).is_ok())
	assert_false(CaptureJob.prepare(_src(), {"stages": ["lunch"]}).is_ok())
	assert_false(CaptureJob.prepare({"kind": "nope"}).is_ok())
	assert_false(CaptureJob.prepare({"kind": "workshop", "id": "no_such_scenario_xyz"}).is_ok())


func test_save_source_is_hash_checked_and_never_written() -> void:
	var l := WorkshopRun.loader_for("core")
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 4)
	var controllers := {}
	for p in s.players():
		controllers[p] = ProfileController.new(p, SimVariant.builtin("zone"), 4)
	HeadlessDuel.play(s, controllers, 50, 4)
	var before := s.state.state_hash_hex()
	var inputs := s.input_log.size()
	var bytes := s.save()
	var path := "user://test_capture_job.sav"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var job := CaptureJob.prepare({"kind": "save", "path": path})
	assert_true(job.is_ok(), str(job.errors))
	assert_eq(job.state_hash, before)
	assert_eq(s.state.state_hash_hex(), before, "the live session is untouched")
	assert_eq(s.input_log.size(), inputs)
	assert_eq(FileAccess.get_file_as_bytes(path), bytes, "the save file is untouched")
	var from_bytes := CaptureJob.prepare({"kind": "save", "bytes": bytes})
	assert_eq(CaptureJob.to_json(from_bytes.manifest()["stages"]), CaptureJob.to_json(job.manifest()["stages"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_tampered_save_is_refused() -> void:
	var l := WorkshopRun.loader_for("core")
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 4)
	var data: Dictionary = BattleSession._decode(s.save())
	data["hash"] = "0000"
	var bad := var_to_bytes(data).compress(FileAccess.COMPRESSION_GZIP)
	var job := CaptureJob.prepare({"kind": "save", "bytes": bad})
	assert_false(job.is_ok())
	assert_true(job.shots.is_empty())


func test_fx_are_a_function_of_the_frame() -> void:
	var job := CaptureJob.prepare(_src(), {"forms": ["strip"]})
	assert_true(job.is_ok())
	var shot: Dictionary = job.shots[0]
	for s: Dictionary in job.shots:
		if s["stage"] == "mid":
			shot = s
	var a := BattleFx.from_playback(job.playback(int(shot["turn"]), 0))
	var b := BattleFx.from_playback(job.playback(int(shot["turn"]), 0))
	for f: int in shot["frames"]:
		assert_eq(str(a.projectiles(f)), str(b.projectiles(f)))
		assert_eq(str(a.flashes(f)), str(b.flashes(f)))
		assert_eq(str(a.floaters(f)), str(b.floaters(f)))
	var v := ContextView.new()
	add_child_autofree(v)
	var rec := job.playback(int(shot["turn"]), 0)
	var n := (rec["frames"] as Array).size() - 1
	for f in range(0, n + 1):
		v.show_playback_frame(rec, f)
		assert_eq(v._frame_f(), float(f))


func test_strip_helpers() -> void:
	assert_eq(CaptureJob.strip_frames(10, 30, 5, 2), PackedInt64Array([6, 8, 10, 12, 14]))
	assert_eq(CaptureJob.strip_frames(0, 30, 5, 2), PackedInt64Array([0, 2, 4, 6, 8]))
	assert_eq(CaptureJob.strip_frames(30, 30, 5, 2), PackedInt64Array([22, 24, 26, 28, 30]))
	assert_eq(CaptureJob.strip_frames(2, 3, 5, 2), PackedInt64Array([0, 2]))
	var cell := CaptureJob.strip_cell(Vector2i(960, 640), 5)
	var patches := (cell.x / CaptureJob.PATCH) * (cell.y / CaptureJob.PATCH) * 5
	assert_true(patches <= CaptureJob.STRIP_TOKENS, str(cell))
	assert_true(patches > CaptureJob.STRIP_TOKENS * 0.8, str(cell))


func test_match_source_replays_hash_checked_and_reads_only() -> void:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 5)
	add_child_autofree(w)
	for i in 12:
		w.end_turn_requested.emit()
	var dir: String = w.match_log.dir
	var bytes := FileAccess.get_file_as_bytes(dir + "/match.sav")
	var played := w.session.state_hash_hex()
	var job := CaptureJob.prepare({"kind": "match", "path": dir})
	assert_true(job.is_ok(), str(job.errors))
	assert_eq(job.state_hash, played, "the capture replays the recorded match")
	assert_eq(FileAccess.get_file_as_bytes(dir + "/match.sav"), bytes, "the match log is untouched")
	for n in CaptureStages.ORDER:
		assert_true(job.stages.has(n) != job.missing.has(n), n)
	var again := CaptureJob.prepare({"kind": "match", "path": dir})
	assert_eq(CaptureJob.to_json(again.manifest()), CaptureJob.to_json(job.manifest()))
	assert_false(CaptureJob.prepare({"kind": "match", "path": dir, "battle": 99999}).is_ok())


func test_frame_camera_frames_the_points_and_is_pure() -> void:
	var field := Vector2(1000, 600)
	var view := Vector2(960, 640)
	var pts := [Vector2(400, 300), Vector2(430, 320), Vector2(410, 280)]
	var a := CaptureJob.frame_camera(pts, field, view)
	assert_eq(a, CaptureJob.frame_camera(pts, field, view), "same points, same camera")
	var z := float(a["zoom"])
	assert_true(z >= CaptureJob.ZOOM_MIN and z <= CaptureJob.ZOOM_MAX, str(a))
	assert_eq(CaptureJob.ZOOM_MAX, ViewContexts.BATTLE_ZOOM_MAX, "the camera's zoom range is the battle view's")
	# The view's visible half-widths (ContextView: fit, zoom, PAD of 16 px).
	var k := minf((view.x - 32.0) / field.x, (view.y - 32.0) / field.y) * z
	var c := Vector2(float(a["centre"][0]), float(a["centre"][1]))
	var half := Vector2((view.x / 2.0 - 16.0) / k, (view.y / 2.0 - 16.0) / k)
	for p: Vector2 in pts:
		assert_true(absf(p.x - c.x) <= half.x and absf(p.y - c.y) <= half.y, "%s in the window at %s" % [p, c])
	# A lone squad is not blown up to fill the view (the minimum framed span caps the zoom).
	var lone := CaptureJob.frame_camera([Vector2(500, 300)], field, view)
	assert_true(float(lone["zoom"]) < CaptureJob.ZOOM_MAX, str(lone))
	var none := CaptureJob.frame_camera([], field, view)
	assert_eq(float(none["zoom"]), 1.0)
	assert_eq(none["centre"], [-1.0, -1.0], "no squads: the whole field")


func test_shot_camera_holds_its_visible_squads_in_the_view() -> void:
	var job := CaptureJob.prepare(_src(), {"views": [0, 1], "forms": ["still", "strip"]})
	assert_true(job.is_ok(), str(job.errors))
	assert_false(job.shots.is_empty())
	var checked := 0
	for shot: Dictionary in job.shots:
		assert_true(shot.has("camera"), shot["id"])
		var cam: Dictionary = shot["camera"]
		var viewer := int(shot["viewer"])
		var turn := int(shot["turn"])
		var cell: Array = shot["cell"]
		var v := ContextView.new()
		v.size = Vector2(cell[0], cell[1])
		var rec := job.playback(turn, viewer)
		v.set_camera(float(cam["zoom"]), Vector2(float(cam["centre"][0]), float(cam["centre"][1])))
		var rect := Rect2(Vector2.ZERO, v.size)
		for f: int in shot["frames"]:
			var at := job.truth_at(turn, f)
			var obs: Dictionary = (at.get("obs", {}) as Dictionary).get(viewer, {})
			v.show_playback_frame(rec, f, obs)
			var probe: Dictionary = (at.get("probe", {}) as Dictionary).get(viewer, {})
			for d: Dictionary in probe.get("squads", []):
				if int(d["alive"]) <= 0 or d["destroyed"] or d["withdrawn"]:
					continue
				var p := v.to_view(Vector2(float(d["x"]), float(d["y"])) / float(Fixed.ONE))
				assert_true(rect.has_point(p), "%s frame %d squad %d at %s" % [shot["id"], f, d["id"], p])
				checked += 1
		v.free()
	assert_true(checked > 0, "some squads were framed")


func test_shot_manifest_records_the_camera() -> void:
	var job := CaptureJob.prepare(_src())
	assert_true(job.is_ok(), str(job.errors))
	for shot: Dictionary in job.manifest()["shots"]:
		assert_true((shot["camera"] as Dictionary).has("zoom"), shot["id"])
		assert_eq((shot["camera"]["centre"] as Array).size(), 2, shot["id"])
