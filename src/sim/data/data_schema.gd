class_name DataSchema
extends RefCounted
## Field schemas for every template kind, and a validator for flattened
## templates. GDD 03 §3.2-3.5, R6Q25.
##
## Field types:
##   "int", "bool", "string", "fixed" (int or decimal string, e.g. "1.25"),
##   "dict" (free-form object), "ref:<kind>" (id of a template of that kind),
##   "list:<type>" (array of that type), "map:<type>" (object of that type),
##   "obj:<name>" (object checked against OBJECTS[name]).
## Spec keys: type, required (default false), min, max (ints), enum (strings).

const DAMAGE_TYPES: Array[String] = ["kinetic", "energy", "explosive", "magic"]
const SIMPL: Array[String] = ["stamina", "instinct", "morale", "prowess", "legend"]
const BANDS: Array[String] = ["broken", "fraying", "neutral", "primed", "surging"]

## Reusable object shapes.
const OBJECTS: Dictionary = {
	"fire_mode": {
		"shots": {"type": "int", "required": true, "min": 1},
		"cooldown_ticks": {"type": "int", "required": true, "min": 1},
		"accuracy": {"type": "fixed", "required": true},
		"damage": {"type": "int", "required": true, "min": 0},
		"moving": {"type": "bool"},
		"aoe_radius": {"type": "fixed"},
		"crit_every": {"type": "int", "min": 0},
		"crit_bonus_pct": {"type": "int", "min": 0},
	},
	"absorb": {
		"flat": {"type": "int", "min": 0},
		"pct": {"type": "int", "min": 0, "max": 100},
	},
	"squad_member": {
		"unit": {"type": "ref:unit", "required": true},
		"count": {"type": "int", "required": true, "min": 1},
	},
	"pool": {
		"capacity": {"type": "int", "min": 1},
		"start_pct": {"type": "int", "min": 0, "max": 100},
		"neutral_pct": {"type": "int", "min": 0, "max": 100},
		"drift_pct_per_s": {"type": "fixed"},
	},
	"formation": {
		"shape": {"type": "string", "enum": ["line", "column", "wedge", "blob"]},
		"spacing": {"type": "fixed"},
	},
	"rect": {
		"x": {"type": "fixed", "required": true},
		"y": {"type": "fixed", "required": true},
		"w": {"type": "fixed", "required": true},
		"h": {"type": "fixed", "required": true},
	},
	"terrain_rect": {
		"feature": {"type": "ref:feature", "required": true},
		"x": {"type": "int", "required": true, "min": 0},
		"y": {"type": "int", "required": true, "min": 0},
		"w": {"type": "int", "required": true, "min": 1},
		"h": {"type": "int", "required": true, "min": 1},
	},
	"zone": {
		"id": {"type": "string", "required": true},
		"x": {"type": "fixed", "required": true},
		"y": {"type": "fixed", "required": true},
		"radius": {"type": "fixed", "required": true},
		"decay": {"type": "int", "min": 0},
		"threshold": {"type": "int", "min": 1},
		"buffer": {"type": "int", "min": 0},
		"vp": {"type": "int", "min": 0},
	},
	"side": {
		"player": {"type": "int", "required": true, "min": 1},
		"deploy": {"type": "obj:rect", "required": true},
		"squads": {"type": "list:ref:squad", "required": true},
		"facing": {"type": "int"},
	},
	"victory": {
		"turn_limit": {"type": "int", "min": 1},
		"primary": {"type": "string", "enum": ["influence", "value"]},
		"score_target": {"type": "int", "min": 0},
		"annihilation": {"type": "bool"},
		"withdrawal": {"type": "bool"},
	},
	"end_hooks": {
		"loser": {"type": "string", "enum": ["scatter"]},
	},
	"reaction": {
		"id": {"type": "string", "required": true, "enum": ["halt", "fall_back", "retarget", "go_prone"]},
		"instinct_cost": {"type": "int", "min": 0},
	},
}

const KINDS: Dictionary = {
	"feature": {
		"name": {"type": "string"},
		"blocks_los": {"type": "bool"},
		"cover_evasion_pct": {"type": "int", "min": 0, "max": 100},
		"concealment_pct": {"type": "int", "min": 0, "max": 100},
	},
	"weapon": {
		"name": {"type": "string"},
		"range": {"type": "fixed", "required": true},
		"min_range": {"type": "fixed"},
		"damage_type": {"type": "string", "required": true, "enum": DAMAGE_TYPES},
		"modes": {"type": "map:obj:fire_mode", "required": true},
		"magazine": {"type": "int", "min": 0},
		"reload_ticks": {"type": "int", "min": 0},
	},
	"defense": {
		"evasion_pct": {"type": "int", "min": 0, "max": 100},
		"block_chance_pct": {"type": "int", "min": 0, "max": 100},
		"block_amount_pct": {"type": "int", "min": 0, "max": 100},
		"resist_pct": {"type": "map:int"},
		"flat": {"type": "int", "min": 0},
		"percent": {"type": "int", "min": 0, "max": 100},
		"floor": {"type": "map:int"},
		"absorb": {"type": "map:obj:absorb"},
	},
	"movement": {
		"walk": {"type": "fixed", "required": true},
		"run": {"type": "fixed", "required": true},
		"accel": {"type": "fixed"},
		"turn_deg_per_s": {"type": "int", "min": 1},
		"terrain_cost_pct": {"type": "map:int"},
	},
	"ability": {
		"type": {"type": "string", "required": true, "enum": ["detection", "concealment"]},
		"radius": {"type": "fixed"},
		"instinct_cost_per_s": {"type": "int", "min": 0},
		"auto_off_band": {"type": "string", "enum": BANDS},
		"base_pct": {"type": "int", "min": 0, "max": 100},
		"terrain_pct": {"type": "map:int"},
		"moving_pct": {"type": "int"},
		"firing_pct": {"type": "int"},
	},
	"unit": {
		"name": {"type": "string"},
		"hp": {"type": "int", "required": true, "min": 1},
		"size_class": {"type": "string", "enum": ["small", "medium", "large", "huge"]},
		"defense": {"type": "ref:defense", "required": true},
		"movement": {"type": "ref:movement", "required": true},
		"weapon": {"type": "ref:weapon"},
		"proficiency_pct": {"type": "int", "min": 0},
		"traits": {"type": "list:string"},
		"tags": {"type": "list:string"},
	},
	"squad": {
		"name": {"type": "string"},
		"faction": {"type": "string", "required": true},
		"doctrine": {"type": "string"},
		"members": {"type": "list:obj:squad_member", "required": true},
		"value": {"type": "int", "required": true, "min": 0},
		"capture_rate": {"type": "int", "min": 0},
		"sight": {"type": "fixed", "required": true},
		"formation": {"type": "obj:formation"},
		"pools": {"type": "map:obj:pool"},
		"abilities": {"type": "list:ref:ability"},
		"reactions": {"type": "list:obj:reaction"},
		"keywords": {"type": "list:string"},
		"legend_archetype": {"type": "string", "enum": ["damage", "tank", "scout", "sapper", "support"]},
	},
	"ruleset": {
		"ticks_per_second": {"type": "int", "min": 1},
		"band_floor_pct": {"type": "map:int"},
		"morale_interval_ticks": {"type": "int", "min": 1},
		"morale_rate_per_s": {"type": "fixed"},
		"morale_leech_pct": {"type": "int", "min": 0, "max": 100},
		"pool_defaults": {"type": "map:obj:pool"},
		"sinks": {"type": "dict"},
		"floats": {"type": "dict"},
	},
	"scenario": {
		"name": {"type": "string"},
		"ruleset": {"type": "ref:ruleset", "required": true},
		"width": {"type": "int", "required": true, "min": 1},
		"height": {"type": "int", "required": true, "min": 1},
		"ticks_per_turn": {"type": "int", "required": true, "min": 1},
		"terrain_default": {"type": "ref:feature", "required": true},
		"terrain": {"type": "list:obj:terrain_rect"},
		"zones": {"type": "list:obj:zone"},
		"sides": {"type": "list:obj:side", "required": true},
		"victory": {"type": "obj:victory", "required": true},
		"end_hooks": {"type": "obj:end_hooks"},
	},
}


## Validates every non-abstract template. Returns error strings.
static func validate(table: TemplateTable) -> PackedStringArray:
	var errors := PackedStringArray()
	for tid in table.ids():
		if table.is_abstract(tid):
			continue
		var kind := table.kind_of(tid)
		if not KINDS.has(kind):
			errors.append("%s: unknown kind '%s'" % [tid, kind])
			continue
		_check_object(table.values_of(tid), KINDS[kind], tid, "", table, errors)
	return errors


static func _check_object(values: Dictionary, spec: Dictionary, tid: String, path: String, table: TemplateTable, errors: PackedStringArray) -> void:
	for key: Variant in values:
		if not spec.has(key):
			errors.append("%s: unknown field '%s'" % [tid, _join(path, str(key))])
	for field: String in spec:
		var fs: Dictionary = spec[field]
		var p := _join(path, field)
		if not values.has(field):
			if fs.get("required", false):
				errors.append("%s: missing required field '%s'" % [tid, p])
			continue
		_check_value(values[field], fs, tid, p, table, errors)


static func _check_value(v: Variant, fs: Dictionary, tid: String, path: String, table: TemplateTable, errors: PackedStringArray) -> void:
	var t: String = fs["type"]
	if t.begins_with("list:"):
		if typeof(v) != TYPE_ARRAY:
			errors.append("%s: '%s' must be a list" % [tid, path])
			return
		var inner := fs.duplicate()
		inner["type"] = t.substr(5)
		for i in (v as Array).size():
			_check_value(v[i], inner, tid, "%s/%d" % [path, i], table, errors)
		return
	if t.begins_with("map:"):
		if typeof(v) != TYPE_DICTIONARY:
			errors.append("%s: '%s' must be an object" % [tid, path])
			return
		var inner := fs.duplicate()
		inner["type"] = t.substr(4)
		for key: Variant in v:
			_check_value(v[key], inner, tid, _join(path, str(key)), table, errors)
		return
	if t.begins_with("obj:"):
		if typeof(v) != TYPE_DICTIONARY:
			errors.append("%s: '%s' must be an object" % [tid, path])
			return
		_check_object(v, OBJECTS[t.substr(4)], tid, path, table, errors)
		return
	if t.begins_with("ref:"):
		var want := t.substr(4)
		if typeof(v) != TYPE_STRING or not table.has(v) or table.kind_of(v) != want:
			errors.append("%s: '%s' must reference a %s template (got %s)" % [tid, path, want, v])
		return
	match t:
		"int":
			if typeof(v) != TYPE_INT:
				errors.append("%s: '%s' must be an integer" % [tid, path])
				return
			if fs.has("min") and int(v) < int(fs["min"]):
				errors.append("%s: '%s' below minimum %d" % [tid, path, fs["min"]])
			if fs.has("max") and int(v) > int(fs["max"]):
				errors.append("%s: '%s' above maximum %d" % [tid, path, fs["max"]])
		"fixed":
			if typeof(v) == TYPE_INT:
				return
			if typeof(v) != TYPE_STRING or not Fixed.parse_decimal(v).ok:
				errors.append("%s: '%s' must be an integer or decimal string" % [tid, path])
		"bool":
			if typeof(v) != TYPE_BOOL:
				errors.append("%s: '%s' must be true or false" % [tid, path])
		"string":
			if typeof(v) != TYPE_STRING:
				errors.append("%s: '%s' must be a string" % [tid, path])
			elif fs.has("enum") and not (fs["enum"] as Array).has(v):
				errors.append("%s: '%s' must be one of %s" % [tid, path, fs["enum"]])
		"dict":
			if typeof(v) != TYPE_DICTIONARY:
				errors.append("%s: '%s' must be an object" % [tid, path])
		_:
			errors.append("schema bug: unknown type '%s' at %s" % [t, path])


## Reads a "fixed" field (int or decimal string) as a raw fixed value.
static func to_fixed(v: Variant, default_value: int = 0) -> int:
	if v == null:
		return default_value
	if typeof(v) == TYPE_INT:
		return Fixed.from_int(v)
	var r := Fixed.parse_decimal(str(v))
	return r.value if r.ok else default_value


static func _join(path: String, key: String) -> String:
	return key if path.is_empty() else path + "/" + key
