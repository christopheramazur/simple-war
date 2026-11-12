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
## Spec keys: type, required (default false), min, max (ints), enum (strings),
## keys (allowed keys of a map), unit (display unit of a stat), stat (false
## keeps a numeric field out of the stat registry; see StatRegistry).

const DAMAGE_TYPES: Array[String] = ["kinetic", "energy", "explosive", "magic"]
const SIMPL: Array[String] = ["stamina", "instinct", "morale", "prowess", "legend"]
const BANDS: Array[String] = ["broken", "fraying", "neutral", "primed", "surging"]

## Effect language vocabulary (GDD 02 §2.13). Closed: engine-provided.
const EFFECT_OPS: Array[String] = ["modify", "damage", "heal", "pool_flow", "apply_bundle", "order"]
## Orders an "order" effect gives its holder (reactions, E3Q7). "attack"
## attacks the first squad the effect's target selector picks.
const ORDERS: Array[String] = ["hold", "fall_back", "attack"]
const MOD_KINDS: Array[String] = ["flat", "increased", "more", "override"]
## When an effect acts. "while" = continuously (modify); "apply"/"expire" =
## once; "every" = periodically; hooks = on that event (depth 1, E2Q5);
## "accumulator" = when the bundle's accumulator reaches its threshold.
const EFFECT_WHEN: Array[String] = ["while", "apply", "expire", "every", "attack", "hit", "damaged", "kill", "casualty", "accumulator"]
const HOOK_EVENTS: Array[String] = ["attack", "hit", "damaged", "kill", "casualty"]
const ACC_EVENTS: Array[String] = ["second", "attack", "hit", "damaged", "casualty", "distance"]
const SELECTS: Array[String] = ["self", "source", "other", "allies", "enemies", "squads"]
const STACKING: Array[String] = ["refresh", "stack", "independent", "strongest"]
## What loses a readying or readied ability state (E3Q6).
const LOSE_EVENTS: Array[String] = ["move", "attack", "damaged", "casualty"]

## Overworld (GDD 02 §2.9). Activities need a commander's route to end on
## the plot; "stable" outcomes resolve during planning, "uncertain" ones at
## the start of a turn with an uncontested commander (R6Q14).
const HEX_ACTIVITIES: Array[String] = ["refit", "recruit", "battle", "convert"]
const HEX_INTERACTIONS: Array[String] = ["none", "stable", "uncertain"]
## Map generation passes (R3Q13), applied in order with the map's seed.
const MAP_PASSES: Array[String] = ["fill", "rect", "place", "line", "scatter"]

## Reusable object shapes.
const OBJECTS: Dictionary = {
	"fire_mode": {
		"shots": {"type": "int", "required": true, "min": 1},
		"cooldown_ticks": {"type": "int", "required": true, "min": 1},
		"accuracy": {"type": "fixed", "required": true},
		"damage": {"type": "fixed", "required": true, "min": 0},
		"moving": {"type": "bool"},
		"aoe_radius": {"type": "fixed"},
		"crit_every": {"type": "int", "min": 0},
		"crit_bonus_pct": {"type": "int", "min": 0},
	},
	"absorb": {
		"flat": {"type": "fixed", "min": 0},
		"pct": {"type": "int", "min": 0, "max": 100},
	},
	"squad_member": {
		"unit": {"type": "ref:unit", "required": true},
		"count": {"type": "int", "required": true, "min": 1, "stat": false},
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
	## A squad a feature's recruit activity offers, and its price in Value
	## (separate from the squad's battle value, R6Q15).
	"recruit_option": {
		"squad": {"type": "ref:squad", "required": true},
		"cost": {"type": "int", "required": true, "min": 0},
	},
	## Battleforce caps (R2Q1): most squads, and most total strength (Value
	## scaled by units alive; 0 = no limit).
	"battleforce_cap": {
		"squads": {"type": "int", "min": 1},
		"value": {"type": "int", "min": 0},
	},
	## A commander a player starts a match on this map with.
	"map_start": {
		"player": {"type": "int", "required": true, "min": 1},
		"commander": {"type": "ref:commander", "required": true},
		"col": {"type": "int", "required": true, "min": 0},
		"row": {"type": "int", "required": true, "min": 0},
	},
	## One map-generation pass. fill: every plot. rect: col,row,w,h. place:
	## col,row. line: col,row to to_col,to_row. scatter: `count` plots picked
	## with the map's seed inside the optional rect, skipping plots holding an
	## `avoid` feature and keeping `spacing` hexes between picks. `owner`
	## pre-assigns a controllable feature to a player.
	"map_pass": {
		"op": {"type": "string", "required": true, "enum": MAP_PASSES},
		"feature": {"type": "ref:hex_feature", "required": true},
		"col": {"type": "int", "min": 0},
		"row": {"type": "int", "min": 0},
		"w": {"type": "int", "min": 1},
		"h": {"type": "int", "min": 1},
		"to_col": {"type": "int", "min": 0},
		"to_row": {"type": "int", "min": 0},
		"count": {"type": "int", "min": 1},
		"spacing": {"type": "int", "min": 0},
		"avoid": {"type": "list:ref:hex_feature"},
		"owner": {"type": "int", "min": 0},
	},
	# --- effect language (GDD 02 §2.13, 03 §3.4) ---
	"selector": {
		"select": {"type": "string", "required": true, "enum": SELECTS},
		"within": {"type": "fixed", "min": 0},
		"tags": {"type": "list:string"},
		"max": {"type": "int", "min": 1},
	},
	## Stack source: magnitude is multiplied by this count (E4Q2).
	"per": {
		"source": {"type": "string", "required": true, "enum": ["selector", "pool", "accumulator"]},
		"selector": {"type": "obj:selector"},
		"pool": {"type": "string", "enum": SIMPL},
		"each": {"type": "fixed", "min": 0},
	},
	"condition": {
		"pool": {"type": "string", "enum": SIMPL},
		"band_at_least": {"type": "string", "enum": BANDS},
		"band_at_most": {"type": "string", "enum": BANDS},
		"moving": {"type": "bool"},
		"firing": {"type": "bool"},
		"hp_below_pct": {"type": "int", "min": 0, "max": 100},
		"has_keyword": {"type": "string"},
		## Feature IDs; holds while the squad's centroid stands on one of them.
		"on_feature": {"type": "list:string"},
	},
	"effect": {
		"op": {"type": "string", "required": true, "enum": EFFECT_OPS},
		"when": {"type": "string", "enum": EFFECT_WHEN},
		"stat": {"type": "string"},
		"mod": {"type": "string", "enum": MOD_KINDS},
		"amount": {"type": "fixed"},
		"damage_type": {"type": "string", "enum": DAMAGE_TYPES},
		"pool": {"type": "string", "enum": SIMPL},
		"bundle": {"type": "ref:bundle"},
		"order": {"type": "string", "enum": ORDERS},
		"target": {"type": "obj:selector"},
		"per": {"type": "obj:per"},
		"condition": {"type": "obj:condition"},
		"every_s": {"type": "fixed", "min": 0},
		"cooldown_s": {"type": "fixed", "min": 0},
		"restores": {"type": "bool"},
		"tags": {"type": "list:string"},
	},
	## Durations (E2Q7, E3Q9, E3Q10). Hexes and banks belong to the overworld
	## and campaigns; inside a battle they last the whole battle.
	"duration": {
		"seconds": {"type": "fixed", "min": 0},
		"turns": {"type": "int", "min": 1},
		"hexes": {"type": "int", "min": 1},
		"bank": {"type": "string"},
	},
	"stacking": {
		"policy": {"type": "string", "enum": STACKING},
		"per": {"type": "string", "enum": ["target", "source"]},
		"max_stacks": {"type": "int", "min": 1},
	},
	## E2Q9: counts an event, fires the bundle's "accumulator" effects at the
	## threshold and returns to start; resets early on reset_on or idle time.
	"accumulator": {
		"event": {"type": "string", "required": true, "enum": ACC_EVENTS},
		"threshold": {"type": "fixed", "required": true, "min": 0},
		"step": {"type": "fixed", "min": 0},
		"start": {"type": "fixed", "min": 0},
		"reset_on": {"type": "string", "enum": HOOK_EVENTS},
		"reset_after_s": {"type": "fixed", "min": 0},
	},
	## Ability activation (E2Q10, E3Q6, E3Q7). Costs are paid on use. A
	## toggle pays its upkeep while on and switches off when a pool it sinks
	## falls to auto_off_band (default Broken, R8Q2); a toggle that sinks
	## nothing starts on (R7Q4). Reactions are queued in the reaction window
	## and fire on contact with the trigger. ready_s > 0 readies first (Prowess
	## Vacuum per second while readying); the bundle, the readied state,
	## applies when readying ends. lose_on events cancel readying and end the
	## readied state.
	"activation": {
		"timing": {"type": "string", "enum": ["order", "reaction"]},
		"costs": {"type": "map:fixed", "keys": SIMPL, "min": 0},
		"upkeep_per_s": {"type": "map:fixed", "keys": SIMPL, "min": 0},
		"auto_off_band": {"type": "string", "enum": BANDS},
		"cooldown_s": {"type": "fixed", "min": 0},
		"charges": {"type": "int", "min": 1},
		"ready_s": {"type": "fixed", "min": 0},
		"readying_prowess_per_s": {"type": "fixed", "min": 0},
		"lose_on": {"type": "list:string", "enum": LOSE_EVENTS},
		"range": {"type": "fixed", "min": 0},
		"targeting": {"type": "string", "enum": ["none", "self", "squad", "point"]},
		"toggle": {"type": "bool"},
	},
}

const KINDS: Dictionary = {
	"tag": {
		"name": {"type": "string"},
		"description": {"type": "string"},
	},
	## A named group of effects: statuses, items, traits, features, zone
	## conditions, Ruin effects (E1Q2).
	"bundle": {
		"name": {"type": "string"},
		"text": {"type": "string"},
		"tags": {"type": "list:string"},
		"effects": {"type": "list:obj:effect", "required": true},
		"duration": {"type": "obj:duration"},
		"stacking": {"type": "obj:stacking"},
		"accumulator": {"type": "obj:accumulator"},
		## What deception-tagged bundles show to inspection (E2Q12).
		"disguise": {"type": "ref:bundle"},
	},
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
		"resist_pct": {"type": "map:int", "keys": DAMAGE_TYPES},
		"flat": {"type": "fixed", "min": 0},
		"percent": {"type": "int", "min": 0, "max": 100},
		"floor": {"type": "map:fixed", "keys": DAMAGE_TYPES, "min": 0},
		"absorb": {"type": "map:obj:absorb", "keys": DAMAGE_TYPES},
	},
	"movement": {
		"walk": {"type": "fixed", "required": true},
		"run": {"type": "fixed", "required": true},
		"accel": {"type": "fixed"},
		"turn_deg_per_s": {"type": "int", "min": 1},
		"terrain_cost_pct": {"type": "map:int"},
	},
	## A bundle plus an activation (E2Q10). Detection, Concealment and
	## reactions are abilities (E3Q7).
	"ability": {
		"name": {"type": "string"},
		"text": {"type": "string"},
		"tags": {"type": "list:string"},
		"bundle": {"type": "ref:bundle", "required": true},
		"activation": {"type": "obj:activation"},
	},
	"unit": {
		"name": {"type": "string"},
		"hp": {"type": "fixed", "required": true, "min": 1},
		"size_class": {"type": "string", "enum": ["small", "medium", "large", "huge"]},
		"defense": {"type": "ref:defense", "required": true},
		"movement": {"type": "ref:movement", "required": true},
		"weapon": {"type": "ref:weapon"},
		"proficiency_pct": {"type": "int", "min": 0},
		"traits": {"type": "list:string"},
		"tags": {"type": "list:string"},
		"bundles": {"type": "list:ref:bundle"},
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
		"pools": {"type": "map:obj:pool", "keys": SIMPL},
		"abilities": {"type": "list:ref:ability"},
		## Bases that ability bundles modify (R7Q4): concealment shrinks the
		## range at which plain Sight spots the squad; detection spots
		## concealed squads within its radius.
		"concealment_pct": {"type": "int", "min": 0, "max": 100},
		"detection_radius": {"type": "fixed", "min": 0},
		"keywords": {"type": "list:string"},
		"bundles": {"type": "list:ref:bundle"},
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
	## An overworld plot feature (GDD 02 §2.9, 03 §3.5). A plot holds any
	## number of features; they are not terrain types. move_cost adds to the
	## map's base cost (a plot never costs less than 1). sight: radius in
	## hexes its controller sees. cache_value: Value picked up by the first
	## commander through; the feature is then removed. guard: neutral squads
	## that fight whoever enters. activity_cost: Value paid to perform an
	## activity here. converts_to: what the "convert" activity turns this
	## feature into (owned by the converting player).
	"hex_feature": {
		"name": {"type": "string"},
		"tags": {"type": "list:string"},
		"move_cost": {"type": "int"},
		"impassable": {"type": "bool"},
		"sight": {"type": "int", "min": 0},
		"controllable": {"type": "bool"},
		"interaction": {"type": "string", "enum": HEX_INTERACTIONS},
		"activities": {"type": "list:string", "enum": HEX_ACTIVITIES},
		"value_per_turn": {"type": "int", "min": 0},
		"cache_value": {"type": "int", "min": 0},
		"guard": {"type": "list:ref:squad"},
		"activity_cost": {"type": "int", "min": 0},
		"converts_to": {"type": "ref:hex_feature"},
		## Squads the recruit activity offers here.
		"recruits": {"type": "list:obj:recruit_option"},
		## Value per lost unit the refit activity restores here.
		"refit_cost": {"type": "int", "min": 0},
		"bundles": {"type": "list:ref:bundle"},
	},
	## A commander (GDD 02 §2.3, §2.9): anchors an army and moves on the
	## overworld. movement_points: per turn, in the map's move-cost units.
	## sight: radius in hexes. squad: the commander's own squad in battles.
	"commander": {
		"name": {"type": "string"},
		"tags": {"type": "list:string"},
		"movement_points": {"type": "int", "required": true, "min": 1},
		"sight": {"type": "int", "min": 0},
		"squad": {"type": "ref:squad"},
		## Squads the commander starts with, besides its own.
		"army": {"type": "list:ref:squad"},
		## Most squads the army holds, besides the commander's own.
		"army_cap": {"type": "int", "min": 0},
	},
	## A seeded overworld map template (R3Q13): an empty width x height hex
	## rectangle (odd-r offset rows) that its passes fill with features.
	## `starts` places each player's starting commanders.
	"overworld_map": {
		"name": {"type": "string"},
		"width": {"type": "int", "required": true, "min": 1},
		"height": {"type": "int", "required": true, "min": 1},
		"base_move_cost": {"type": "int", "min": 1},
		"passes": {"type": "list:obj:map_pass", "required": true},
		"starts": {"type": "list:obj:map_start"},
		"battleforce": {"type": "obj:battleforce_cap"},
	},
	## An archetype preset for battleforce auto-fill (R2Q1): squads with a
	## feature (legend archetype, doctrine or keyword) earlier in `prefer`
	## come first, strongest first within a rank; `avoid` is never picked.
	"battleforce_preset": {
		"name": {"type": "string"},
		"prefer": {"type": "list:string"},
		"avoid": {"type": "list:string"},
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
		inner.erase("keys")
		for key: Variant in v:
			if fs.has("keys") and not (fs["keys"] as Array).has(key):
				errors.append("%s: '%s' has unknown key '%s' (allowed: %s)" % [tid, path, key, fs["keys"]])
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
			var fv := 0
			if typeof(v) == TYPE_INT:
				fv = Fixed.from_int(v)
			elif typeof(v) == TYPE_STRING and Fixed.parse_decimal(v).ok:
				fv = Fixed.parse_decimal(v).value
			else:
				errors.append("%s: '%s' must be an integer or decimal string" % [tid, path])
				return
			if fs.has("min") and fv < Fixed.from_int(fs["min"]):
				errors.append("%s: '%s' below minimum %d" % [tid, path, fs["min"]])
			if fs.has("max") and fv > Fixed.from_int(fs["max"]):
				errors.append("%s: '%s' above maximum %d" % [tid, path, fs["max"]])
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
