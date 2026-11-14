class_name SimVariant
extends RefCounted
## A configuration variant for harness runs (GDD 05 §5.1, R4Q11): what to
## change against the content as shipped, and who plays. A variant file is
## JSON (data/sim/variants/<name>.json):
##   {"name": "...", "text": "...",
##    "patches": {template ID: {field: value, ...}},   # merged into values
##    "controllers": {"<player>": {"profile": "zone" | "expand" |
##                     "evacuation" | "idle" | "utility" |
##                     <controller_profile template ID>, "params": {...},
##                     "genome": {...} (a profile as plain data, played by
##                     ProfileController; overrides "profile"),
##                     "forfeit_turn": N (leaves the game before turn N,
##                     a harness test of forfeits, B1Q4)}},
##    "turns": overworld turns to play (default 20; battles run to the end)}
## Patching rebuilds the template table, so a variant has its own data
## hash; replays of variant runs need the same variant (the replay viewer
## takes --variant=<path>).

var name: String = "baseline"
var data: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()
var templates: TemplateTable
var data_hash: String = ""


## Loads a variant file ("" = the baseline: no patches, default players).
static func load_file(path: String) -> SimVariant:
	var v := SimVariant.new()
	if path.is_empty():
		return v
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or typeof(j.data) != TYPE_DICTIONARY:
		v.errors.append("unreadable variant %s" % path)
		return v
	v.data = j.data
	v.name = String(v.data.get("name", path.get_file().get_basename()))
	return v


## Applies the patches to a loaded package set; sets templates/data_hash.
func apply(loader: PackageLoader) -> bool:
	var patches: Dictionary = data.get("patches", {})
	if patches.is_empty():
		templates = loader.templates
		data_hash = loader.data_hash
		return errors.is_empty()
	var defs := loader.defs.duplicate(true)
	var found := {}
	for d: Dictionary in defs:
		var id := String(d.get("id", ""))
		if patches.has(id):
			found[id] = true
			var values: Dictionary = d.get("values", {})
			_merge(values, patches[id])
			d["values"] = values
	for id: String in patches:
		if not found.has(id):
			errors.append("variant patches unknown template '%s'" % id)
	var t := TemplateTable.build(defs)
	errors.append_array(t.errors)
	if t.is_valid():
		errors.append_array(DataSchema.validate(t))
	if not errors.is_empty():
		return false
	templates = t
	data_hash = PackageLoader._hash(t)
	return true


## Deep merge: dictionaries merge, anything else replaces.
static func _merge(into: Dictionary, over: Dictionary) -> void:
	for k: String in over:
		if into.get(k) is Dictionary and over[k] is Dictionary:
			_merge(into[k], over[k])
		else:
			into[k] = over[k]


## The controller for a player: the variant's profile, else `default`.
## Profiles (ProfileController) take the run's seed for their fuzz.
func controller(player: int, default: String, seed_value: int = 0) -> Object:
	var spec: Dictionary = (data.get("controllers", {}) as Dictionary).get(str(player), {})
	var params: Dictionary = spec.get("params", {})
	var name := String(spec.get("profile", default))
	if spec.has("genome"):
		return ProfileController.new(player, spec["genome"], seed_value)
	if name == "utility":
		return ProfileController.new(player, {}, seed_value)
	if templates != null and templates.has(name) and templates.kind_of(name) == "controller_profile":
		return ProfileController.new(player, templates.values_of(name), seed_value)
	return ProfileController.new(player, builtin(name, params), seed_value)


## A built-in profile name as a two-layer profile, so every built-in plays
## both layers: zone and expand pair the rule-based ExpandController on the
## overworld with ZoneController battles (params go to the battle side);
## evacuation fights evacuation battles; idle does nothing on either.
static func builtin(name: String, params: Dictionary = {}) -> Dictionary:
	match name:
		"idle":
			return {"overworld": {"process": "idle"}, "battle": {"process": "idle"}}
		"evacuation":
			return {"overworld": {"process": "expand"}, "battle": {"process": "evacuation"}}
	return {"overworld": {"process": "expand"}, "battle": {"process": "zone", "params": params}}


## The turn before which a player leaves the game, -1 = never.
func forfeit_turn(player: int) -> int:
	var spec: Dictionary = (data.get("controllers", {}) as Dictionary).get(str(player), {})
	return int(spec.get("forfeit_turn", -1))


func turns() -> int:
	return int(data.get("turns", 20))


## Holds every squad and plans nothing: a do-nothing baseline profile.
class IdleController extends RefCounted:
	var player: int

	func _init(p: int) -> void:
		player = p

	func orders(_obs: Dictionary) -> Array:
		return []

	func reactions(_opps: Array) -> Array:
		return []

	func plan(_obs: Dictionary, _session: OverworldSession) -> Array:
		return []
