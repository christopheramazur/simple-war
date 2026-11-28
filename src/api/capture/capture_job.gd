class_name CaptureJob
extends RefCounted
## What a capture shows and the truth behind it (sw-tho3.9, U1 B9, GDD 05
## §5.6 proposal), without drawing anything: the capture runner
## (src/presentation/capture/capture_runner.gd) renders the plan; tests and
## `--no-render` use it headless.
##
## A source is re-simulated through the Game API on a CaptureSim, twice:
##   pass 1 records the battle's playback and finds its stages
##          (CaptureStages);
##   pass 2 runs it again and takes the truth (BattleProbe with each
##          viewer's fog, the observation, the WorkshopDebug frame) at exactly
##          the frames the shots show.
## Both passes must end on the same state hash, and a source that recorded
## hashes (a battle save, a match log) must reproduce them, so the picture is
## always of the recorded battle; otherwise the job has errors and no shots.
## The source itself is only read: a save or match file is never written, a
## live session never touched (it is captured from its save bytes).
##
## Sources (Dictionary, as in the manifest):
##   {"kind": "workshop", "id": <scenario id or path> | "scenario": <dict>,
##    "variant": "base"}
##   {"kind": "duel", "scenario": <battle scenario>, "seed": n,
##    "controller": "zone" (SimVariant builtin), "turns": 50}
##   {"kind": "save", "path": <battle .sav>} or {"kind": "save", "bytes": ...}
##   {"kind": "match", "path": <match log folder>, "battle": <state id>}
##     (default: the battle with the most turns, lowest ID on a tie)
##
## Options: "views" (viewers; 0 = all-seeing), "kinds" (KINDS), "forms"
## ("still", "strip"), "stages" (a subset of CaptureStages.ORDER),
## "strip_frames", "strip_stride", "size" ([w, h] of a still).
##
## FX determinism: BattleFx is a pure function of the playback record and
## the frame, and the runner shows every frame exactly
## (ContextView.show_playback_frame), so the effects in a capture are a
## function of the tick alone. Nothing depends on wall time.

const VERSION: int = 1
## game: what the player sees; control: the same frame with the debug
## overlay and large labels; the colour-vision kinds are the game render
## through CvdSim.
const KINDS: PackedStringArray = ["game", "control", "greyscale", "protan", "deutan"]
const RENDERED: PackedStringArray = ["game", "control"]
const FORMS: PackedStringArray = ["still", "strip"]
## A strip is kept to about this many vision tokens (28 x 28 px patches).
const STRIP_TOKENS: int = 1024
const PATCH: int = 28
const DEFAULTS: Dictionary = {
	"views": [0], "kinds": ["game", "control"], "forms": ["still", "strip"], "stages": [],
	"strip_frames": 5, "strip_stride": 2, "size": [960, 640],
}

var source: Dictionary = {}
var options: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()
var data_hash: String = ""
var state_hash: String = ""
var turn_hashes: PackedStringArray = PackedStringArray()
## The battle captured (BattleState.id) and its players.
var battle: int = -1
var players: PackedInt64Array = PackedInt64Array()
## The battle's CaptureSim turn records (pass 2) and its truth.
var turns: Array = []
var truth: Dictionary = {}
var stages: Dictionary = {}
var missing: Dictionary = {}
## Views asked for but skipped (a viewer not in the battle): viewer -> why.
var skipped: Dictionary = {}
var shots: Array[Dictionary] = []


## Runs both passes and plans the shots. Never null: check `errors`.
static func prepare(src: Dictionary, opts: Dictionary = {}) -> CaptureJob:
	var job := CaptureJob.new()
	job.source = src.duplicate(true)
	job.source.erase("bytes")
	job.options = DEFAULTS.duplicate(true)
	job.options.merge(opts, true)
	if not job._check_options():
		return job
	var first := CaptureSim.new()
	var one := job._play(src, first)
	if not job.errors.is_empty():
		return job
	job.battle = job._pick_battle(first)
	if job.battle < 0:
		job.state_hash = one["hash"]
		job.turn_hashes = one["turn_hashes"]
		job.missing = CaptureStages.find([])["missing"]
		return job
	var found := CaptureStages.find(first.turns[job.battle])
	job.stages = found["stages"]
	job.missing = found["missing"]
	job.turns = first.turns[job.battle]
	job._plan()
	var second := CaptureSim.new()
	second.want = {job.battle: job._wanted()}
	second.viewers = PackedInt64Array(job.options["views"])
	second.debug = (job.options["kinds"] as Array).has("control")
	var two := job._play(src, second)
	if not job.errors.is_empty():
		return job
	if two["hash"] != one["hash"]:
		job._fail("the second pass ended on a different state hash (%s, not %s)" % [two["hash"], one["hash"]])
		return job
	job.state_hash = two["hash"]
	job.turn_hashes = two["turn_hashes"]
	job.turns = second.turns.get(job.battle, [])
	job.truth = second.truth.get(job.battle, {})
	return job


func is_ok() -> bool:
	return errors.is_empty()


func _fail(msg: String) -> void:
	errors.append(msg)
	shots = []
	stages = {}


func _check_options() -> bool:
	for k: String in options["kinds"]:
		if not KINDS.has(k):
			errors.append("kinds: unknown kind '%s' (%s)" % [k, ", ".join(KINDS)])
	for f: String in options["forms"]:
		if not FORMS.has(f):
			errors.append("forms: unknown form '%s' (%s)" % [f, ", ".join(FORMS)])
	for s: String in options["stages"]:
		if not CaptureStages.ORDER.has(s):
			errors.append("stages: unknown stage '%s' (%s)" % [s, ", ".join(CaptureStages.ORDER)])
	if int(options["strip_frames"]) < 2 or int(options["strip_stride"]) < 1:
		errors.append("strip_frames must be at least 2 and strip_stride at least 1")
	var views := PackedInt64Array()
	for v: Variant in options["views"]:
		views.append(int(v))
	options["views"] = Array(views)
	return errors.is_empty()


# --- sources ---------------------------------------------------------------

## Plays the source on `sim`: {"hash", "turn_hashes"} (errors on failure).
func _play(src: Dictionary, sim: CaptureSim) -> Dictionary:
	match String(src.get("kind", "")):
		"workshop":
			return _play_workshop(src, sim)
		"duel":
			return _play_duel(src, sim)
		"save":
			return _play_save(src, sim)
		"match":
			return _play_match(src, sim)
	errors.append("source: unknown kind '%s' (workshop, duel, save, match)" % src.get("kind", ""))
	return {}


func _play_workshop(src: Dictionary, sim: CaptureSim) -> Dictionary:
	var sc: WorkshopScenario
	if src.has("scenario"):
		sc = WorkshopScenario.from_dict(src["scenario"], String((src["scenario"] as Dictionary).get("id", "<scenario>")))
	else:
		sc = WorkshopScenario.find(String(src.get("id", "")))
	if sc == null:
		errors.append("workshop: no scenario '%s'" % src.get("id", ""))
		return {}
	var run := WorkshopRun.execute(sc, String(src.get("variant", WorkshopScenario.BASE)), true, false, sim)
	if not run.is_ok():
		errors.append_array(run.errors)
		return {}
	data_hash = run.data_hash
	return {"hash": run.final_hash, "turn_hashes": run.turn_hashes}


static func _core() -> PackageLoader:
	return WorkshopRun.loader_for("core")


func _play_duel(src: Dictionary, sim: CaptureSim) -> Dictionary:
	var l := _core()
	var seed_value := int(src.get("seed", 1))
	var s := BattleSession.create(l.templates, l.data_hash, String(src.get("scenario", "")), seed_value)
	if s == null or not s.rules.is_valid():
		errors.append("duel: cannot build battle scenario '%s'" % src.get("scenario", ""))
		return {}
	data_hash = l.data_hash
	_use_sim(s, sim)
	var name := String(src.get("controller", "zone"))
	var controllers := {}
	for p in s.players():
		controllers[p] = ProfileController.new(p, SimVariant.builtin(name), seed_value)
	HeadlessDuel.play(s, controllers, int(src.get("turns", 50)))
	return {"hash": s.state.state_hash_hex(), "turn_hashes": _end_hashes(sim)}


func _play_save(src: Dictionary, sim: CaptureSim) -> Dictionary:
	var bytes: PackedByteArray = src["bytes"] if src.has("bytes") else FileAccess.get_file_as_bytes(String(src.get("path", "")))
	var data: Variant = BattleSession._decode(bytes) if not bytes.is_empty() else null
	if typeof(data) != TYPE_DICTIONARY or not data.has("inputs"):
		errors.append("save: unreadable battle save '%s'" % src.get("path", "<bytes>"))
		return {}
	var l := _core()
	if data.get("data_hash") != l.data_hash:
		errors.append("save: the game's content has changed since this battle was saved")
		return {}
	data_hash = l.data_hash
	var s := BattleSession.create(l.templates, l.data_hash, data["scenario"], data["seed"],
		BattleSession._config_from(data["clock_config"]), int(data.get("jitter", 0)))
	_use_sim(s, sim)
	s.replay_inputs(data["inputs"])
	var h := s.state.state_hash_hex()
	if h != String(data.get("hash", "")):
		errors.append("save: re-execution did not reproduce the saved state hash")
		return {}
	return {"hash": h, "turn_hashes": _end_hashes(sim)}


## Puts `sim` in the session's place, keeping the session's tick hook.
static func _use_sim(s: BattleSession, sim: CaptureSim) -> void:
	sim.tick_hook = s.sim.tick_hook
	s.sim = sim


## The state hash after every turn of the source's battle (record seal).
static func _end_hashes(sim: CaptureSim) -> PackedStringArray:
	var out := PackedStringArray()
	if sim.turns.size() == 1:
		for rec: Dictionary in sim.turns.values()[0]:
			out.append(String((rec["start"] as Dictionary).get("end_hash", "")))
	return out


func _play_match(src: Dictionary, sim: CaptureSim) -> Dictionary:
	var r := MatchReplay.open(String(src.get("path", "")))
	if r == null:
		errors.append("match: %s" % MatchReplay.last_error)
		return {}
	data_hash = String(r._data_hash)
	r.session.keep_playback = false
	sim.tick_hook = r.session._battle_sim.tick_hook
	r.session._battle_sim = sim
	while r.step():
		pass
	if r.diverged_turn >= 0:
		errors.append("match: turn %d did not reproduce its recorded hash" % r.diverged_turn)
		return {}
	return {"hash": r.session.state_hash_hex(), "turn_hashes": r.session.turn_hashes.duplicate()}


func _pick_battle(sim: CaptureSim) -> int:
	if source.has("battle"):
		var want := int(source["battle"])
		if sim.turns.has(want):
			return want
		errors.append("battle: no battle %d in the source (%s)" % [want, sim.turns.keys()])
		return -1
	if sim.turns.is_empty():
		return -1
	var ids: Array = sim.turns.keys()
	ids.sort()
	var best := -1
	for id: int in ids:
		if best < 0 or (sim.turns[id] as Array).size() > (sim.turns[best] as Array).size():
			best = id
	return best


# --- the plan --------------------------------------------------------------

static func view_name(viewer: int) -> String:
	return "all" if viewer <= 0 else "p%d" % viewer


## The frames a strip around `frame` shows: strip_frames frames strip_stride
## apart, centred on it and shifted to stay inside the turn's 0..last.
static func strip_frames(frame: int, last: int, n: int, stride: int) -> PackedInt64Array:
	var span := (n - 1) * stride
	var lo := clampi(frame - span / 2, 0, maxi(last - span, 0))
	var out := PackedInt64Array()
	for i in n:
		var f := lo + i * stride
		if f > last:
			break
		out.append(f)
	return out


## Pixel size of one strip cell for `n` cells beside each other: the still's
## aspect, kept to STRIP_TOKENS patches in all (whole patches per cell).
static func strip_cell(still: Vector2i, n: int) -> Vector2i:
	var aspect := float(still.x) / float(maxi(still.y, 1))
	var per := float(STRIP_TOKENS) / float(maxi(n, 1))
	var rows := maxi(int(floor(sqrt(per / aspect))), 1)
	var cols := maxi(int(floor(per / rows)), 1)
	return Vector2i(mini(cols * PATCH, still.x), mini(rows * PATCH, still.y))


func _plan() -> void:
	shots = []
	var wanted_stages: Array = options["stages"]
	var size := Vector2i(int(options["size"][0]), int(options["size"][1]))
	for v: int in options["views"]:
		if v > 0 and not _battle_players().has(v):
			skipped[view_name(v)] = "player %d does not fight in battle %d" % [v, battle]
	for stage in CaptureStages.ORDER:
		if not stages.has(stage) or (not wanted_stages.is_empty() and not wanted_stages.has(stage)):
			continue
		var at: Dictionary = stages[stage]
		var ti := int(at["turn"]) - 1
		var last := (turns[ti]["frames"] as Array).size() - 1
		var first := int(turns[ti]["first_tick"])
		for v: int in options["views"]:
			if skipped.has(view_name(v)):
				continue
			for form: String in options["forms"]:
				var frames := PackedInt64Array([at["frame"]]) if form == "still" else \
					strip_frames(int(at["frame"]), last, int(options["strip_frames"]), int(options["strip_stride"]))
				var ticks := []
				for f in frames:
					ticks.append(first + f)
				var id := "%s_%s_%s" % [stage, view_name(v), form]
				var images := {}
				var layout := {}
				for kind: String in options["kinds"]:
					images[kind] = "%s_%s.png" % [id, kind]
					if RENDERED.has(kind):
						layout[kind] = "layout/%s_%s.json" % [id, kind]
				var cell := size if form == "still" else strip_cell(size, frames.size())
				shots.append({"id": id, "stage": stage, "view": view_name(v), "viewer": v, "form": form,
					"turn": at["turn"], "frames": Array(frames), "ticks": ticks, "truth": "truth/%s.json" % id,
					"cell": [cell.x, cell.y], "image_size": [cell.x * frames.size(), cell.y],
					"images": images, "layout": layout})


func _battle_players() -> PackedInt64Array:
	if turns.is_empty():
		return PackedInt64Array()
	return turns[0]["players"]


func _wanted() -> Dictionary:
	var out := {}
	for s: Dictionary in shots:
		for f: int in s["frames"]:
			out[Vector2i(int(s["turn"]) - 1, f)] = true
	return out


## One frame's recorded truth: {"probe": {viewer: snapshot}, "obs", "debug"}.
func truth_at(turn: int, frame: int) -> Dictionary:
	return truth.get(Vector2i(turn - 1, frame), {})


## The playback record of a turn (1-based) as `viewer` saw it
## (OverworldSession.playback_entry); {} when the viewer did not fight in it.
func playback(turn: int, viewer: int) -> Dictionary:
	var rec: Dictionary = turns[turn - 1]
	if viewer > 0 and not (rec["players"] as PackedInt64Array).has(viewer):
		return {}
	return OverworldSession.playback_entry(rec, viewer)


## truth/<shot>.json: the shot and a BattleProbe snapshot per frame, with
## the viewer's fog.
func shot_truth(shot: Dictionary) -> Dictionary:
	var frames := []
	for i in (shot["frames"] as Array).size():
		var f: int = shot["frames"][i]
		var t := truth_at(int(shot["turn"]), f)
		frames.append({"frame": f, "tick": shot["ticks"][i],
			"probe": (t.get("probe", {}) as Dictionary).get(int(shot["viewer"]), {})})
	return {"version": VERSION, "shot": shot["id"], "stage": shot["stage"], "view": shot["view"],
		"viewer": shot["viewer"], "battle": battle, "turn": shot["turn"], "frames": frames}


func manifest() -> Dictionary:
	return {
		"version": VERSION, "source": source, "data_hash": data_hash,
		"engine": str(Engine.get_version_info().get("string", "")),
		"state_hash": state_hash, "turn_hashes": Array(turn_hashes), "battle": battle,
		"players": Array(_battle_players()), "turns": turns.size(),
		"options": options, "skipped_views": skipped,
		"fx": "BattleFx is a pure function of the playback frame; every frame is shown exactly",
		"stages": stages, "missing": missing, "shots": shots, "errors": Array(errors),
	}


## Deterministic JSON (sorted keys, tabs).
static func to_json(d: Variant) -> String:
	return JSON.stringify(d, "\t", true) + "\n"


## Writes truth/<shot>.json for every shot and manifest.json under `dir`
## (created). Images and layout are the runner's.
func write(dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir.path_join("truth"))
	if err != OK:
		return err
	for s: Dictionary in shots:
		err = _write_text(dir.path_join(s["truth"]), to_json(shot_truth(s)))
		if err != OK:
			return err
	return _write_text(dir.path_join("manifest.json"), to_json(manifest()))


static func _write_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK
