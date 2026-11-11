class_name OverworldRules
extends RefCounted
## Read-only overworld data compiled once from flattened templates into flat
## arrays (GDD 02 §2.9, 03 §3.5): hex features and one map template.

const ACTIVITIES: Array[String] = DataSchema.HEX_ACTIVITIES
const INTERACTIONS: Array[String] = DataSchema.HEX_INTERACTIONS
const PASSES: Array[String] = DataSchema.MAP_PASSES
const DEFAULT_BASE_COST: int = 10

var errors: PackedStringArray = PackedStringArray()
var map_id: String = ""
var data_hash: String = ""

# --- hex features ---
var feature_ids: PackedStringArray = PackedStringArray()
var hf_names: PackedStringArray = PackedStringArray()
var hf_tags: Array[PackedStringArray] = []
var hf_move_cost: PackedInt64Array = PackedInt64Array()
var hf_impassable: PackedByteArray = PackedByteArray()
var hf_sight: PackedInt64Array = PackedInt64Array()
var hf_controllable: PackedByteArray = PackedByteArray()
## Index into INTERACTIONS.
var hf_interaction: PackedInt64Array = PackedInt64Array()
## Bit i set = ACTIVITIES[i] available.
var hf_activities: PackedInt64Array = PackedInt64Array()
var hf_value_per_turn: PackedInt64Array = PackedInt64Array()
var hf_cache_value: PackedInt64Array = PackedInt64Array()
## Guard squad template IDs (battles are built from them).
var hf_guard: Array[PackedStringArray] = []
## Value paid to perform an activity on the feature.
var hf_activity_cost: PackedInt64Array = PackedInt64Array()
## Feature index the "convert" activity turns it into, -1 = none.
var hf_converts_to: PackedInt64Array = PackedInt64Array()

# --- commanders ---
var commander_ids: PackedStringArray = PackedStringArray()
var cm_names: PackedStringArray = PackedStringArray()
var cm_mp: PackedInt64Array = PackedInt64Array()
var cm_sight: PackedInt64Array = PackedInt64Array()
## The commander's squad template ID ("" = none).
var cm_squad: PackedStringArray = PackedStringArray()

# --- map ---
var width: int = 0
var height: int = 0
var base_cost: int = DEFAULT_BASE_COST
## Compiled passes: {op (PASSES index), feature, col, row, w, h, to_col,
## to_row, count, spacing, avoid (PackedInt64Array), owner}.
var passes: Array[Dictionary] = []


static func compile(t: TemplateTable, map: String, hash_hex: String = "") -> OverworldRules:
	var r := OverworldRules.new()
	r.map_id = map
	r.data_hash = hash_hex
	r._compile(t, map)
	return r


func is_valid() -> bool:
	return errors.is_empty()


func feature_index(id: String) -> int:
	return feature_ids.find(id)


func plot_count() -> int:
	return width * height


func commander_index(id: String) -> int:
	return commander_ids.find(id)


func has_activity(feature: int, activity: String) -> bool:
	return hf_activities[feature] & (1 << ACTIVITIES.find(activity)) != 0


func _compile(t: TemplateTable, map: String) -> void:
	for tid in _of_kind(t, "hex_feature"):
		_compile_feature(tid, t.values_of(tid))
	for tid in feature_ids:
		var into := String(t.values_of(tid).get("converts_to", ""))
		var to := feature_index(into) if into != "" else -1
		hf_converts_to.append(to)
		if to < 0 and has_activity(feature_index(tid), "convert"):
			errors.append("%s: the convert activity needs 'converts_to'" % tid)
	for tid in _of_kind(t, "commander"):
		var v := t.values_of(tid)
		commander_ids.append(tid)
		cm_names.append(String(v.get("name", tid)))
		cm_mp.append(int(v["movement_points"]))
		cm_sight.append(int(v.get("sight", 2)))
		cm_squad.append(String(v.get("squad", "")))
	if not t.has(map) or t.kind_of(map) != "overworld_map":
		errors.append("unknown overworld map '%s'" % map)
		return
	var m := t.values_of(map)
	width = int(m["width"])
	height = int(m["height"])
	base_cost = int(m.get("base_move_cost", DEFAULT_BASE_COST))
	var passes_in: Array = m["passes"]
	for i in passes_in.size():
		_compile_pass(i, passes_in[i])


static func _of_kind(t: TemplateTable, kind: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for tid in t.ids():
		if not t.is_abstract(tid) and t.kind_of(tid) == kind:
			ids.append(tid)
	ids.sort()
	return ids


func _compile_feature(tid: String, v: Dictionary) -> void:
	feature_ids.append(tid)
	hf_names.append(String(v.get("name", tid)))
	hf_tags.append(PackedStringArray(v.get("tags", [])))
	hf_move_cost.append(int(v.get("move_cost", 0)))
	hf_impassable.append(1 if v.get("impassable", false) else 0)
	hf_sight.append(int(v.get("sight", 0)))
	hf_controllable.append(1 if v.get("controllable", false) else 0)
	hf_interaction.append(INTERACTIONS.find(String(v.get("interaction", "none"))))
	var bits := 0
	for a: String in v.get("activities", []):
		bits |= 1 << ACTIVITIES.find(a)
	hf_activities.append(bits)
	hf_value_per_turn.append(int(v.get("value_per_turn", 0)))
	hf_cache_value.append(int(v.get("cache_value", 0)))
	hf_guard.append(PackedStringArray(v.get("guard", [])))
	hf_activity_cost.append(int(v.get("activity_cost", 0)))


func _compile_pass(i: int, v: Dictionary) -> void:
	var where := "%s pass %d" % [map_id, i]
	var op := PASSES.find(String(v["op"]))
	var f := feature_index(String(v["feature"]))
	if f < 0:
		errors.append("%s: unknown hex feature '%s'" % [where, v["feature"]])
		return
	var p := {
		"op": op, "feature": f,
		"col": int(v.get("col", 0)), "row": int(v.get("row", 0)),
		"w": int(v.get("w", width - int(v.get("col", 0)))), "h": int(v.get("h", height - int(v.get("row", 0)))),
		"to_col": int(v.get("to_col", 0)), "to_row": int(v.get("to_row", 0)),
		"count": int(v.get("count", 1)), "spacing": int(v.get("spacing", 0)),
		"avoid": PackedInt64Array(), "owner": int(v.get("owner", 0)),
	}
	for a: String in v.get("avoid", []):
		p["avoid"].append(feature_index(a))
	match PASSES[op]:
		"rect", "place", "line":
			for k: String in ["col", "row"]:
				if not v.has(k):
					errors.append("%s: %s needs '%s'" % [where, PASSES[op], k])
					return
	if PASSES[op] == "line" and not (v.has("to_col") and v.has("to_row")):
		errors.append("%s: line needs 'to_col' and 'to_row'" % where)
		return
	if not Hex.in_bounds(p["col"], p["row"], width, height) \
			or not Hex.in_bounds(p["col"] + p["w"] - 1, p["row"] + p["h"] - 1, width, height) \
			or not Hex.in_bounds(p["to_col"], p["to_row"], width, height):
		errors.append("%s: outside the %dx%d map" % [where, width, height])
		return
	if p["owner"] > 0 and hf_controllable[f] == 0:
		errors.append("%s: '%s' is not controllable, so it cannot have an owner" % [where, feature_ids[f]])
		return
	passes.append(p)
