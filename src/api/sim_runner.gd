extends SceneTree
## One headless harness run (GDD 05 §5.1): a scenario (a battle scenario
## or an overworld map) under a configuration variant and a seed, played
## at full speed through the Game API, measured by SimMetrics. Driven by
## `hx sim run`, one Godot process per run:
##
##   Godot_console --headless --path . -s res://src/api/sim_runner.gd -- \
##       --scenario duel_crossroads --seed 3 --out <dir> --run-id <id> \
##       [--variant <variant.json>]
##
## Writes <dir>/<run-id>.json ({"run": {...}, "metrics": [rows]}) and the
## replay <dir>/<run-id>.sav (BattleSession / OverworldSession save). Exit
## code 0 on a finished run, 1 on a setup error (reported in the JSON).

const CORE := "res://data/packages/core"


func _initialize() -> void:
	var args := _args()
	var out_dir: String = args.get("out", "user://sim")
	var run_id: String = args.get("run-id", "run")
	var report := {"run_id": run_id, "scenario": args.get("scenario", ""), "seed": int(args.get("seed", "1")),
		"variant": "baseline", "status": "error", "error": ""}
	var t0 := Time.get_ticks_msec()
	var metrics: Array = []
	DirAccess.make_dir_recursive_absolute(out_dir)
	var loader := PackageLoader.load_dirs(PackedStringArray([CORE]))
	var variant := SimVariant.load_file(args.get("variant", ""))
	report["variant"] = variant.name
	if not loader.is_valid():
		report["error"] = "content: " + "; ".join(loader.errors)
	elif not variant.apply(loader):
		report["error"] = "variant: " + "; ".join(variant.errors)
	else:
		var t := variant.templates
		var sid: String = report["scenario"]
		if not t.has(sid):
			report["error"] = "unknown scenario '%s'" % sid
		elif t.kind_of(sid) == "scenario":
			metrics = _battle(t, variant, sid, report, out_dir.path_join(run_id + ".sav"))
		elif t.kind_of(sid) == "overworld_map":
			metrics = _overworld(t, variant, sid, report, out_dir.path_join(run_id + ".sav"))
		else:
			report["error"] = "'%s' is a %s, not a scenario or overworld map" % [sid, t.kind_of(sid)]
	report["wall_ms"] = Time.get_ticks_msec() - t0
	var f := FileAccess.open(out_dir.path_join(run_id + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"run": report, "metrics": metrics}))
	f.close()
	print("sim_runner: %s %s" % [run_id, report["status"]])
	quit(0 if report["status"] == "ok" else 1)


func _battle(t: TemplateTable, v: SimVariant, sid: String, report: Dictionary, replay: String) -> Array:
	var s := BattleSession.create(t, v.data_hash, sid, report["seed"])
	if s == null:
		report["error"] = BattleSession.last_error
		return []
	var m := SimMetrics.new()
	m.watch_battle(s.state, s.sim)
	var controllers := {}
	for p in s.players():
		controllers[p] = v.controller(p, "zone")
	HeadlessDuel.play(s, controllers)
	_save(replay, s.save())
	report["kind"] = "battle"
	report["status"] = "ok"
	report["turns"] = s.state.turn
	report["winner"] = int(s.state.result.get("winner", 0))
	report["reason"] = String(s.state.result.get("reason", ""))
	report["state_hash"] = s.state.state_hash().hex_encode()
	return m.battle(s.state, s.sim)


func _overworld(t: TemplateTable, v: SimVariant, sid: String, report: Dictionary, replay: String) -> Array:
	var x := OverworldSession.create(t, v.data_hash, sid, report["seed"])
	if x == null:
		report["error"] = OverworldSession.last_error
		return []
	var controllers := {}
	for p in x.players():
		controllers[p] = v.controller(p, "expand")
	var events: Array = []
	var guard := 0
	while x.turns_resolved() < v.turns() and x.state.outcome.is_empty() and guard < v.turns() * 6:
		guard += 1
		var before := x.turns_resolved()
		HeadlessOverworld.play(x, controllers, before + 1)
		for e in x.last_events:
			var d := e.to_dict()
			d["turn"] = x.turns_resolved()
			events.append(d)
	_save(replay, x.save())
	report["kind"] = "overworld"
	report["status"] = "ok"
	report["turns"] = x.turns_resolved()
	report["outcome"] = String(x.state.outcome.get("outcome", ""))
	report["state_hash"] = x.state_hash_hex()
	return SimMetrics.new().overworld(x, events)


static func _save(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


static func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
