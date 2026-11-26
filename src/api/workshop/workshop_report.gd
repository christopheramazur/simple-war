class_name WorkshopReport
extends RefCounted
## Runs a workshop scenario's variants, grades its probes and comparisons,
## and builds the report (sw-tho3.3, U1 B3). The report is the frozen
## `--json` schema in data/sim/workshop/README.md; bump SCHEMA on any change.
##
## Grading: a probe or comparison is a gate check when the scenario's status
## is gate and it is not marked pending. Gate checks pass or fail. Others
## never fail: "pending" when they miss, "unexpected_pass" when they meet
## their expectation (time to promote them). A probe without an expectation,
## or in a variant its expectation does not cover, is "report". A scenario
## fails only on a gate check; it is "error" when it cannot load or run.

const SCHEMA: int = 1


## The report for one scenario; `only` runs just that variant (comparisons
## that need another variant are skipped).
static func run(sc: WorkshopScenario, only: String = "") -> Dictionary:
	var rep := {
		"schema": SCHEMA, "scenario": sc.id if sc.id != "" else sc.path.get_file().get_basename(),
		"path": sc.path, "component": sc.component, "status": sc.status, "doc": sc.doc,
		"package": sc.package, "data_hash": "", "engine": Engine.get_version_info()["string"],
		"map": sc.map, "open": sc.open, "seed": sc.seed_value, "turns": sc.turns,
		"probe_stride": sc.probe_stride, "variants": [], "compare": [], "errors": [],
		"result": "pass", "gate_failures": 0, "pending": 0, "unexpected_passes": 0,
	}
	if not sc.is_valid():
		rep["errors"] = Array(sc.errors)
		rep["result"] = "error"
		return rep
	var names := sc.variant_names()
	if only != "":
		if not only in names:
			rep["errors"] = ["%s: no variant '%s' (%s)" % [sc.path, only, ", ".join(names)]]
			rep["result"] = "error"
			return rep
		names = PackedStringArray([only])
	var gate := sc.status == "gate"
	var values := {}
	for v in names:
		var r := WorkshopRun.execute(sc, v)
		rep["data_hash"] = r.data_hash
		var vr := {"name": v, "hash": r.final_hash, "turn_hashes": Array(r.turn_hashes),
			"turns_run": r.turns_run, "frames": r.frame_turn.size(), "errors": Array(r.errors), "probes": []}
		rep["variants"].append(vr)
		if not r.is_ok():
			(rep["errors"] as Array).append_array(r.errors)
			continue
		values[v] = {}
		for p: Dictionary in sc.probes:
			var m := WorkshopProbes.measure(r, p)
			values[v][p["id"]] = m["value"]
			var applies: bool = v in (p["variants"] as PackedStringArray) and p["expect"] != null
			var res := "report"
			if m["error"] != "":
				res = "error"
			elif applies:
				res = "pass" if WorkshopProbes.check(p["kind"], p["expect"], m["value"]) else "fail"
			var pr := {"id": p["id"], "kind": p["kind"], "squad": p["squad"], "target": p["target"],
				"when": _when(p), "value": WorkshopProbes.to_json(p["kind"], m["value"]),
				"expect": _expect_json(p["kind"], p["expect"]) if applies else null,
				"result": _grade(rep, res, gate and not p["pending"]), "error": m["error"]}
			vr["probes"].append(pr)
	for c: Dictionary in sc.compare:
		if not values.has(c["lhs"]) or not values.has(c["rhs"]):
			continue
		var lv: Variant = _num(values[c["lhs"]].get(c["probe"]), c["sub"])
		var rv: Variant = _num(values[c["rhs"]].get(c["probe"]), c["sub"])
		var res := "error"
		if lv != null and rv != null:
			res = "pass" if _rel(int(lv) * 1000, c["rel"], int(c["factor"]) * int(rv)) else "fail"
		rep["compare"].append({"metric": c["metric"], "lhs": c["lhs"], "rhs": c["rhs"], "rel": c["rel"],
			"factor": WorkshopProbes.decimal(c["factor"]),
			"lhs_value": WorkshopProbes.decimal(lv) if lv != null else null,
			"rhs_value": WorkshopProbes.decimal(rv) if rv != null else null,
			"result": _grade(rep, res, gate and not c["pending"])})
	if not (rep["errors"] as Array).is_empty():
		rep["result"] = "error"
	elif rep["gate_failures"] > 0:
		rep["result"] = "fail"
	return rep


## Every scenario in `dir` (or the given paths): {"schema", "ok", "scenarios"}.
## ok is false only when a scenario failed a gate check or errored.
static func run_all(paths: PackedStringArray, only: String = "") -> Dictionary:
	var out: Array = []
	var ok := true
	for f in paths:
		var rep := run(WorkshopScenario.load_file(f), only)
		ok = ok and rep["result"] == "pass"
		out.append(rep)
	return {"schema": SCHEMA, "ok": ok, "scenarios": out}


static func _grade(rep: Dictionary, res: String, is_gate: bool) -> String:
	if res == "report":
		return res
	if is_gate:
		if res != "pass":
			rep["gate_failures"] += 1
			return "fail" if res == "fail" else "error"
		return res
	if res == "pass":
		rep["unexpected_passes"] += 1
		return "unexpected_pass"
	rep["pending"] += 1
	return "pending"


static func _num(v: Variant, sub: String) -> Variant:
	if v == null:
		return null
	if sub != "":
		return (v as Dictionary).get(sub)
	return v if typeof(v) == TYPE_INT else null


static func _rel(a: int, rel: String, b: int) -> bool:
	match rel:
		">=": return a >= b
		"<=": return a <= b
		">": return a > b
		"<": return a < b
	return a == b


static func _expect_json(kind: String, e: Variant) -> Variant:
	if e == null or kind == "within":
		return e
	if e is PackedStringArray:
		return Array(e)
	if kind == "victims":
		var out := {}
		for k: String in e:
			out[k] = _range_json(e[k])
		return out
	return _range_json(e)


static func _range_json(r: Variant) -> Variant:
	if r == null:
		return null
	var out := {}
	for k: String in r:
		out[k] = WorkshopProbes.decimal(r[k])
	return out


static func _when(p: Dictionary) -> String:
	if p.has("at"):
		return "at " + WorkshopProbes._at_text(p["at"])
	return "over " + WorkshopProbes._over_text(p["over"])


## Compact text: one header line per scenario, then one line per probe or
## comparison that is not a plain pass (all of them when `verbose`).
static func text(rep: Dictionary, verbose: bool = false) -> PackedStringArray:
	var out := PackedStringArray()
	var hashes := PackedStringArray()
	for v: Dictionary in rep["variants"]:
		hashes.append("%s %s" % [v["name"], String(v["hash"]).left(12)])
	out.append("%s %s [%s] %s" % [String(rep["result"]).to_upper(), rep["scenario"], rep["status"], ", ".join(hashes)])
	for e: String in rep["errors"]:
		out.append("  error: " + e)
	for v: Dictionary in rep["variants"]:
		for p: Dictionary in v["probes"]:
			if verbose or not p["result"] in ["pass", "report"]:
				out.append("  %s [%s] %s %s %s = %s%s%s" % [_label(p["result"]), v["name"], p["id"], p["kind"], p["when"],
					JSON.stringify(p["value"]), (" expect " + JSON.stringify(p["expect"])) if p["expect"] != null else "",
					(" (" + p["error"] + ")") if p["error"] != "" else ""])
	for c: Dictionary in rep["compare"]:
		if verbose or c["result"] != "pass":
			out.append("  %s compare %s: %s %s %s x %s (%s vs %s)" % [_label(c["result"]), c["metric"], c["lhs"], c["rel"],
				c["rhs"], c["factor"], c["lhs_value"], c["rhs_value"]])
	return out


static func _label(res: String) -> String:
	return "unexpected pass" if res == "unexpected_pass" else res
