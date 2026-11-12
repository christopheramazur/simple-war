class_name OverworldRules
extends RefCounted
## Read-only overworld data compiled once from flattened templates into flat
## arrays (GDD 02 §2.9, 03 §3.5): hex features and one map template.

const ACTIVITIES: Array[String] = DataSchema.HEX_ACTIVITIES
const INTERACTIONS: Array[String] = DataSchema.HEX_INTERACTIONS
const PASSES: Array[String] = DataSchema.MAP_PASSES
const DEFAULT_BASE_COST: int = 10
const DEFAULT_ARMY_CAP: int = 6
const DEFAULT_BATTLEFORCE_SQUADS: int = 4
const DEFAULT_DETACHMENT_SIGHT: int = 1
const DEFAULT_CONVOY_MOVEMENT: int = 40
## Item slots: a unit carries at most one item per slot.
const SLOT_WEAPON: int = 0
const SLOT_DEFENSE: int = 1
const SLOT_KIT: int = 2
## Values per production option in hf_produces.
const PRODUCTION_STRIDE: int = 5

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
## Item caches: [item, count] pairs picked up by the first commander through.
var hf_items: Array[PackedInt64Array] = []
## Guard squad template IDs (battles are built from them).
var hf_guard: Array[PackedStringArray] = []
## Value paid to perform an activity on the feature.
var hf_activity_cost: PackedInt64Array = PackedInt64Array()
## Feature index the "convert" activity turns it into, -1 = none.
var hf_converts_to: PackedInt64Array = PackedInt64Array()
## Recruit options: [squad index, cost, squad index, cost, ...].
var hf_recruits: Array[PackedInt64Array] = []
## Production options: [squad (-1 = item), turns, cost, item (-1), count]
## per option (PRODUCTION_STRIDE values).
var hf_produces: Array[PackedInt64Array] = []
## Value per lost unit restored by refitting here.
var hf_refit_cost: PackedInt64Array = PackedInt64Array()
## Scenario ID of the feature's battlefield ("" = the map's).
var hf_battlefield: PackedStringArray = PackedStringArray()
## Answers an uncertain feature's offer accepts (default accept, decline).
var hf_choices: Array[PackedStringArray] = []
## Turns a guard stays dispersed by a commander with no battleforce (0 =
## it can't be).
var hf_dispersal: PackedInt64Array = PackedInt64Array()

# --- squads (what armies hold; battles compile their own) ---
var squad_ids: PackedStringArray = PackedStringArray()
var sq_names: PackedStringArray = PackedStringArray()
## Battle value (R6Q15).
var sq_value: PackedInt64Array = PackedInt64Array()
## Units at full strength: the members' counts summed.
var sq_size: PackedInt64Array = PackedInt64Array()
var sq_tags: Array[PackedStringArray] = []
## Per member slot (leaders first, then template order, as battles spawn
## them): the keys an item's `fits` matches (unit ID, unit tags, faction).
var sq_member_keys: Array[Array] = []

# --- items (War Chest, R4Q10) ---
var item_ids: PackedStringArray = PackedStringArray()
var it_names: PackedStringArray = PackedStringArray()
var it_icons: PackedStringArray = PackedStringArray()
var it_tags: Array[PackedStringArray] = []
var it_value: PackedInt64Array = PackedInt64Array()
var it_slot: PackedInt64Array = PackedInt64Array()
## Weapon / defense template IDs ("" = none) and bundle IDs.
var it_weapon: PackedStringArray = PackedStringArray()
var it_defense: PackedStringArray = PackedStringArray()
var it_bundles: Array[PackedStringArray] = []
var it_fits: Array[PackedStringArray] = []

# --- commanders ---
var commander_ids: PackedStringArray = PackedStringArray()
var cm_names: PackedStringArray = PackedStringArray()
var cm_mp: PackedInt64Array = PackedInt64Array()
var cm_sight: PackedInt64Array = PackedInt64Array()
## The commander's squad template ID ("" = none).
var cm_squad: PackedStringArray = PackedStringArray()
## The commander's own squad as a squad index, -1 = none.
var cm_own_squad: PackedInt64Array = PackedInt64Array()
## Starting squads besides its own (squad indices).
var cm_army: Array[PackedInt64Array] = []
var cm_army_cap: PackedInt64Array = PackedInt64Array()

# --- map ---
var width: int = 0
var height: int = 0
var base_cost: int = DEFAULT_BASE_COST
## Compiled passes: {op (PASSES index), feature, col, row, w, h, to_col,
## to_row, count, spacing, avoid (PackedInt64Array), owner}.
var passes: Array[Dictionary] = []
## Starting commanders: {player, commander (index), plot}.
var starts: Array[Dictionary] = []
## Battleforce caps: squads, and total strength (0 = no limit).
var bf_cap_squads: int = DEFAULT_BATTLEFORCE_SQUADS
var bf_cap_value: int = 0
## Scenario ID engagements are fought on by default.
var battle_scenario: String = ""
## Sight radius of a detachment, in hexes.
var detachment_sight: int = DEFAULT_DETACHMENT_SIGHT
## Movement points a convoy spends each turn.
var convoy_mp: int = DEFAULT_CONVOY_MOVEMENT

## Campaign scripting (TriggerRules, overworld context).
var triggers: TriggerRules

# --- battleforce presets ---
var preset_ids: PackedStringArray = PackedStringArray()
var pr_prefer: Array[PackedStringArray] = []
var pr_avoid: Array[PackedStringArray] = []


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


func squad_index(id: String) -> int:
	return squad_ids.find(id)


## Production options of feature f.
func production_count(f: int) -> int:
	return hf_produces[f].size() / PRODUCTION_STRIDE


func item_index(id: String) -> int:
	return item_ids.find(id)


## Whether item `it` may be carried by member slot `slot` of squad `sq`.
func item_fits(it: int, sq: int, slot: int) -> bool:
	if it_fits[it].is_empty():
		return true
	var keys: PackedStringArray = sq_member_keys[sq][slot]
	for k in it_fits[it]:
		if keys.has(k):
			return true
	return false


## The cost of recruiting squad index `sq` at feature f, or -1 if not offered.
func recruit_cost(f: int, sq: int) -> int:
	var r := hf_recruits[f]
	for i in range(0, r.size(), 2):
		if r[i] == sq:
			return r[i + 1]
	return -1


func has_activity(feature: int, activity: String) -> bool:
	return hf_activities[feature] & (1 << ACTIVITIES.find(activity)) != 0


func _compile(t: TemplateTable, map: String) -> void:
	for tid in _of_kind(t, "item"):
		_compile_item(tid, t.values_of(tid))
	for tid in _of_kind(t, "squad"):
		var v := t.values_of(tid)
		_compile_members(t, v)
		squad_ids.append(tid)
		sq_names.append(String(v.get("name", tid)))
		sq_value.append(int(v.get("value", 0)))
		var size := 0
		for m: Dictionary in v.get("members", []):
			size += int(m.get("count", 1))
		sq_size.append(size)
		# Squad features presets sort on: legend archetype, doctrine, keywords.
		var tags := PackedStringArray(v.get("keywords", []))
		for k: String in ["legend_archetype", "doctrine"]:
			if v.has(k):
				tags.append(String(v[k]))
		sq_tags.append(tags)
	for tid in _of_kind(t, "battleforce_preset"):
		var v := t.values_of(tid)
		preset_ids.append(tid)
		pr_prefer.append(PackedStringArray(v.get("prefer", [])))
		pr_avoid.append(PackedStringArray(v.get("avoid", [])))
	for tid in _of_kind(t, "hex_feature"):
		_compile_feature(tid, t.values_of(tid))
	for tid in feature_ids:
		var into := String(t.values_of(tid).get("converts_to", ""))
		var to := feature_index(into) if into != "" else -1
		hf_converts_to.append(to)
		if to < 0 and has_activity(feature_index(tid), "convert"):
			errors.append("%s: the convert activity needs 'converts_to'" % tid)
		var rec := PackedInt64Array()
		for o: Dictionary in t.values_of(tid).get("recruits", []):
			rec.append_array([squad_index(String(o["squad"])), int(o["cost"])])
		hf_recruits.append(rec)
		var prod := PackedInt64Array()
		for o: Dictionary in t.values_of(tid).get("produces", []):
			if o.has("squad") == o.has("item"):
				errors.append("%s: a production option names one squad or one item" % tid)
			prod.append_array([squad_index(String(o.get("squad", ""))), int(o["turns"]), int(o.get("cost", 0)),
				item_index(String(o.get("item", ""))), int(o.get("count", 1))])
		hf_produces.append(prod)
		var f := feature_index(tid)
		if rec.is_empty() == has_activity(f, "recruit"):
			errors.append("%s: the recruit activity and 'recruits' go together" % tid)
	for tid in _of_kind(t, "commander"):
		var v := t.values_of(tid)
		commander_ids.append(tid)
		cm_names.append(String(v.get("name", tid)))
		cm_mp.append(int(v["movement_points"]))
		cm_sight.append(int(v.get("sight", 2)))
		cm_squad.append(String(v.get("squad", "")))
		cm_own_squad.append(squad_index(String(v.get("squad", ""))))
		var army := PackedInt64Array()
		for sq: String in v.get("army", []):
			army.append(squad_index(sq))
		cm_army.append(army)
		cm_army_cap.append(int(v.get("army_cap", DEFAULT_ARMY_CAP)))
		if army.size() > cm_army_cap[cm_army_cap.size() - 1]:
			errors.append("%s: starts with more squads than its army_cap" % tid)
	if not t.has(map) or t.kind_of(map) != "overworld_map":
		errors.append("unknown overworld map '%s'" % map)
		return
	var m := t.values_of(map)
	triggers = TriggerRules.compile(t, PackedStringArray(m.get("triggers", [])), "overworld", feature_ids)
	errors.append_array(triggers.errors)
	width = int(m["width"])
	height = int(m["height"])
	base_cost = int(m.get("base_move_cost", DEFAULT_BASE_COST))
	var passes_in: Array = m["passes"]
	for i in passes_in.size():
		_compile_pass(i, passes_in[i])
	var bf: Dictionary = m.get("battleforce", {})
	bf_cap_squads = int(bf.get("squads", DEFAULT_BATTLEFORCE_SQUADS))
	bf_cap_value = int(bf.get("value", 0))
	battle_scenario = String(m.get("battle_scenario", ""))
	detachment_sight = int(m.get("detachment_sight", DEFAULT_DETACHMENT_SIGHT))
	convoy_mp = int(m.get("convoy_movement", DEFAULT_CONVOY_MOVEMENT))
	var starts_in: Array = m.get("starts", [])
	for i in starts_in.size():
		var v: Dictionary = starts_in[i]
		var cm := commander_index(String(v["commander"]))
		if cm < 0:
			errors.append("%s start %d: unknown commander '%s'" % [map, i, v["commander"]])
		elif not Hex.in_bounds(int(v["col"]), int(v["row"]), width, height):
			errors.append("%s start %d: outside the %dx%d map" % [map, i, width, height])
		else:
			starts.append({"player": int(v["player"]), "commander": cm,
				"plot": Hex.plot(int(v["col"]), int(v["row"]), width)})


## Players of a match on this map: those with a start or a pre-owned
## feature, ascending.
func players() -> PackedInt64Array:
	var seen := {}
	for st in starts:
		seen[st["player"]] = true
	for p in passes:
		if p["owner"] > 0:
			seen[p["owner"]] = true
	var out := PackedInt64Array(seen.keys())
	out.sort()
	return out


static func _of_kind(t: TemplateTable, kind: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for tid in t.ids():
		if not t.is_abstract(tid) and t.kind_of(tid) == kind:
			ids.append(tid)
	ids.sort()
	return ids


func _compile_item(tid: String, v: Dictionary) -> void:
	item_ids.append(tid)
	it_names.append(String(v.get("name", tid)))
	it_icons.append(String(v.get("icon", "")))
	it_tags.append(PackedStringArray(v.get("tags", [])))
	it_value.append(int(v.get("value", 0)))
	var w := String(v.get("weapon", ""))
	var d := String(v.get("defense", ""))
	if w != "" and d != "":
		errors.append("%s: an item fills one slot (a weapon or a defense, not both)" % tid)
	it_slot.append(SLOT_WEAPON if w != "" else (SLOT_DEFENSE if d != "" else SLOT_KIT))
	it_weapon.append(w)
	it_defense.append(d)
	it_bundles.append(PackedStringArray(v.get("bundles", [])))
	it_fits.append(PackedStringArray(v.get("fits", [])))


## Member slots in battle order (leaders first, BattleRules._compile_squads)
## with the keys items' `fits` match.
func _compile_members(t: TemplateTable, v: Dictionary) -> void:
	var leaders := []
	var others := []
	for m: Dictionary in v.get("members", []):
		var uid := String(m["unit"])
		var uv := t.values_of(uid) if t.has(uid) else {}
		var keys := PackedStringArray([uid])
		keys.append_array(PackedStringArray(uv.get("tags", [])))
		keys.append(String(v.get("faction", "")))
		var lead := (uv.get("tags", []) as Array).has("leader")
		for _i in int(m.get("count", 1)):
			(leaders if lead else others).append(keys)
	leaders.append_array(others)
	sq_member_keys.append(leaders)


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
	var grants := PackedInt64Array()
	for g: Dictionary in v.get("items", []):
		grants.append_array([item_index(String(g["item"])), int(g.get("count", 1))])
	hf_items.append(grants)
	hf_guard.append(PackedStringArray(v.get("guard", [])))
	hf_activity_cost.append(int(v.get("activity_cost", 0)))
	hf_refit_cost.append(int(v.get("refit_cost", 0)))
	hf_battlefield.append(String(v.get("battlefield", "")))
	hf_choices.append(PackedStringArray(v.get("choices", ["accept", "decline"])))
	hf_dispersal.append(int(v.get("dispersal_turns", 0)))


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
