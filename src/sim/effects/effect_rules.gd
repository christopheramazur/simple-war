class_name EffectRules
extends RefCounted
## Bundles compiled for the simulation (GDD 02 §2.13, 03 §3.4). Built once
## per battle from the template table; read-only afterwards.
##
## A compiled bundle is a Dictionary:
##   id, name, tags (PackedStringArray), effects (Array of compiled effects),
##   seconds_ticks (-1 = none), turns (0 = none), policy (String),
##   per_source (bool), max_stacks (int), acc (Dictionary or {}),
##   disguise (bundle index or -1), listens (PackedStringArray of hook events).
## A compiled effect is a Dictionary:
##   op, when (Strings), stat (StringName, "" if none), mod (StatModifier.Kind),
##   amount (fixed), dtype, pool, bundle (ints, -1 if none), target / per /
##   cond (Dictionaries, {} if none), every, cooldown (ticks, 0 if none),
##   restores (bool), source (String: "<bundle id>#<index>").

const OP_DEFAULT_WHEN: Dictionary = {"modify": "while"}

var bundles: Array[Dictionary] = []
var errors: PackedStringArray = PackedStringArray()
var _index: Dictionary = {}  # bundle template id -> index


static func compile(t: TemplateTable, registry: StatRegistry, tps: int) -> EffectRules:
	var fx := EffectRules.new()
	var ids: PackedStringArray = PackedStringArray()
	var tags := {}
	for tid in t.ids():
		if t.is_abstract(tid):
			continue
		if t.kind_of(tid) == "bundle":
			ids.append(tid)
		elif t.kind_of(tid) == "tag":
			tags[tid] = true
	ids.sort()
	for tid in ids:
		fx._index[tid] = fx.bundles.size()
		fx.bundles.append({})
	for tid in ids:
		fx.bundles[fx._index[tid]] = fx._compile_bundle(tid, t.values_of(tid), registry, tps, tags)
	return fx


func index_of(bundle_id: String) -> int:
	return _index.get(bundle_id, -1)


func size() -> int:
	return bundles.size()


func _compile_bundle(tid: String, v: Dictionary, registry: StatRegistry, tps: int, tags: Dictionary) -> Dictionary:
	var b := {
		"id": tid, "name": str(v.get("name", tid)), "tags": PackedStringArray(v.get("tags", [])),
		"effects": [], "seconds_ticks": -1, "turns": 0, "policy": "refresh", "per_source": false,
		"max_stacks": 1, "acc": {}, "disguise": -1, "listens": PackedStringArray(),
	}
	for tag: String in b["tags"]:
		if not tags.has(tag):
			errors.append("%s: unknown tag '%s'" % [tid, tag])
	var dur: Dictionary = v.get("duration", {})
	if dur.has("seconds"):
		b["seconds_ticks"] = maxi(Fixed.to_int_round(DataSchema.to_fixed(dur["seconds"]) * tps), 1)
	if dur.has("turns"):
		b["turns"] = int(dur["turns"])
	var st: Dictionary = v.get("stacking", {})
	b["policy"] = str(st.get("policy", "refresh"))
	b["per_source"] = st.get("per", "target") == "source"
	b["max_stacks"] = int(st.get("max_stacks", 1 if b["policy"] != "stack" else 99))
	if v.has("disguise"):
		b["disguise"] = _index.get(v["disguise"], -1)
	if v.has("accumulator"):
		var a: Dictionary = v["accumulator"]
		b["acc"] = {
			"event": str(a["event"]), "threshold": DataSchema.to_fixed(a["threshold"]),
			"step": DataSchema.to_fixed(a.get("step", 1)), "start": DataSchema.to_fixed(a.get("start", 0)),
			"reset_on": str(a.get("reset_on", "")),
			"reset_after": Fixed.to_int_round(DataSchema.to_fixed(a.get("reset_after_s", 0)) * tps),
		}
		if b["acc"]["event"] in DataSchema.HOOK_EVENTS:
			b["listens"].append(b["acc"]["event"])
		if b["acc"]["reset_on"] != "" and not b["listens"].has(b["acc"]["reset_on"]):
			b["listens"].append(b["acc"]["reset_on"])
	var list: Array = v.get("effects", [])
	for i in list.size():
		var e := _compile_effect("%s#%d" % [tid, i], list[i], b, registry, tps, tags)
		b["effects"].append(e)
		if e["when"] in DataSchema.HOOK_EVENTS and not b["listens"].has(e["when"]):
			b["listens"].append(e["when"])
	return b


func _compile_effect(src: String, v: Dictionary, b: Dictionary, registry: StatRegistry, tps: int, tags: Dictionary) -> Dictionary:
	var op := str(v["op"])
	var e := {
		"op": op, "when": str(v.get("when", OP_DEFAULT_WHEN.get(op, "apply"))),
		"stat": &"", "mod": StatModifier.Kind.FLAT, "amount": DataSchema.to_fixed(v.get("amount", 0)),
		"dtype": -1, "pool": -1, "bundle": -1, "target": _selector(v.get("target", {})),
		"per": {}, "cond": v.get("condition", {}), "every": 0, "cooldown": 0,
		"restores": bool(v.get("restores", false)), "source": src,
	}
	for tag: String in v.get("tags", []):
		if not tags.has(tag):
			errors.append("%s: unknown tag '%s'" % [src, tag])
	var need_amount := op != "apply_bundle"
	if need_amount and not v.has("amount"):
		errors.append("%s: '%s' needs an amount" % [src, op])
	match op:
		"modify":
			var def: StatDef = registry.find(str(v.get("stat", "")))
			if def == null:
				errors.append("%s: unknown stat '%s'" % [src, v.get("stat", "")])
			else:
				e["stat"] = StringName(def.id)
			e["mod"] = maxi(DataSchema.MOD_KINDS.find(str(v.get("mod", "flat"))), 0)
			if e["when"] != "while":
				errors.append("%s: modify effects act 'while' the bundle is active" % src)
		"damage":
			e["dtype"] = DataSchema.DAMAGE_TYPES.find(str(v.get("damage_type", "")))
			if e["dtype"] < 0:
				errors.append("%s: damage needs a damage_type" % src)
		"pool_flow":
			e["pool"] = DataSchema.SIMPL.find(str(v.get("pool", "")))
			if e["pool"] < 0:
				errors.append("%s: pool_flow needs a pool" % src)
		"apply_bundle":
			e["bundle"] = _index.get(v.get("bundle", ""), -1)
			if e["bundle"] < 0:
				errors.append("%s: apply_bundle needs a bundle" % src)
	if op != "modify" and e["when"] == "while":
		errors.append("%s: only modify effects act 'while'" % src)
	if e["when"] == "every":
		e["every"] = Fixed.to_int_round(DataSchema.to_fixed(v.get("every_s", 0)) * tps)
		if e["every"] <= 0:
			errors.append("%s: 'every' needs every_s > 0" % src)
	if e["when"] == "accumulator" and (b["acc"] as Dictionary).is_empty():
		errors.append("%s: 'accumulator' effects need the bundle to have an accumulator" % src)
	e["cooldown"] = Fixed.to_int_round(DataSchema.to_fixed(v.get("cooldown_s", 0)) * tps)
	if v.has("per"):
		var p: Dictionary = v["per"]
		e["per"] = {"source": str(p["source"]), "selector": _selector(p.get("selector", {})),
			"pool": DataSchema.SIMPL.find(str(p.get("pool", ""))),
			"each": DataSchema.to_fixed(p.get("each", 1))}
		if e["per"]["each"] <= 0:
			e["per"]["each"] = Fixed.ONE
		match e["per"]["source"]:
			"selector":
				if (e["per"]["selector"] as Dictionary).is_empty():
					errors.append("%s: per selector needs a selector" % src)
			"pool":
				if e["per"]["pool"] < 0:
					errors.append("%s: per pool needs a pool" % src)
			"accumulator":
				if (b["acc"] as Dictionary).is_empty():
					errors.append("%s: per accumulator needs the bundle to have an accumulator" % src)
	return e


static func _selector(v: Dictionary) -> Dictionary:
	if v.is_empty():
		return {}
	return {"select": str(v["select"]), "within": DataSchema.to_fixed(v.get("within"), -1),
		"tags": PackedStringArray(v.get("tags", [])), "max": int(v.get("max", 0))}
