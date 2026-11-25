extends SceneTree
## Runs behaviour-workshop scenarios headless (sw-tho3.3, U1 B3):
##
##   Godot_console --headless --path . -s res://src/api/workshop/workshop_cli.gd -- \
##       --scenario <id|path|all> [--variant <name>] [--json] [--verbose]
##
## Text: one header line per scenario, then each probe or comparison that is
## not a plain pass (all with --verbose). --json prints one JSON document
## ({"schema", "ok", "scenarios": [report]}, data/sim/workshop/README.md)
## between the lines WORKSHOP_JSON_BEGIN and WORKSHOP_JSON_END.
## Exit code: 0 when every scenario passed its gate checks; 1 when a gate
## check failed or a scenario could not load or run (pending checks never
## fail); 2 on bad arguments.


func _initialize() -> void:
	var args := _args()
	var which: String = args.get("scenario", "")
	if which == "":
		printerr("workshop_cli: --scenario <id|path|all> is required")
		quit(2)
		return
	var paths := WorkshopScenario.list() if which == "all" else PackedStringArray([_path(which)])
	var out := WorkshopReport.run_all(paths, args.get("variant", ""))
	if args.has("json"):
		print("WORKSHOP_JSON_BEGIN")
		print(JSON.stringify(out, "", false))
		print("WORKSHOP_JSON_END")
	else:
		for rep: Dictionary in out["scenarios"]:
			for line in WorkshopReport.text(rep, args.has("verbose")):
				print(line)
	quit(0 if out["ok"] else 1)


static func _path(which: String) -> String:
	if which.ends_with(".json"):
		return which
	return WorkshopScenario.DIR.path_join(which + ".json")


static func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := a[i]
		if k.begins_with("--"):
			k = k.substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				out[k] = a[i + 1]
				i += 1
			else:
				out[k] = true
		i += 1
	return out
