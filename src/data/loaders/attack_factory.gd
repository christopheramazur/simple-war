class_name AttackFactory
extends RefCounted

## Loads base AttackProfileComponent definitions from Attacks.json and
## resolves weapon attack references (attack_id + per-Item overrides)
## into runtime AttackProfile instances for the Combat System's
## Attack Pipeline.
##
## Items define weapons that reference a base attack by id and optionally
## override any field. Unoverridden fields are inherited from the base.
## Nested objects (range, damage, splash) use deep merge — only the keys
## you specify are replaced, the rest are kept from the base.

var _attacks: Dictionary = {}  # id -> Dictionary (raw JSON)


func load_all() -> void:
	var raw := DataLoader.load_attacks()
	if not raw.has("attacks"):
		push_error("AttackFactory: Attacks.json missing 'attacks' key")
		return
	for entry: Dictionary in raw["attacks"]:
		var id: String = entry.get("id", "")
		if id.is_empty():
			push_error("AttackFactory: attack entry missing 'id'")
			continue
		_attacks[id] = entry


func get_base(id: String) -> Dictionary:
	if not _attacks.has(id):
		push_error("AttackFactory: unknown attack '%s'" % id)
		return {}
	return _attacks[id]


func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_attacks.keys())
	return ids


func resolve(weapon_attack_entry: Dictionary) -> AttackProfile:
	var attack_id: String = weapon_attack_entry.get("attack_id", "")
	if attack_id.is_empty():
		push_error("AttackFactory: weapon attack entry missing 'attack_id'")
		return null

	var base := get_base(attack_id)
	if base.is_empty():
		return null

	var merged := base.duplicate(true)
	_deep_merge(merged, weapon_attack_entry)

	return _parse_profile(merged)


func _deep_merge(base: Dictionary, overrides: Dictionary) -> void:
	for key: String in overrides:
		if key == "attack_id":
			continue
		var value: Variant = overrides[key]
		if value is Dictionary and base.has(key) and base[key] is Dictionary:
			_deep_merge(base[key], value)
		else:
			base[key] = value


func _parse_profile(merged: Dictionary) -> AttackProfile:
	var profile := AttackProfile.new()
	profile.id = merged.get("id", "")
	profile.display_name = merged.get("display_name", "")
	profile.category = merged.get("category", "melee")
	profile.skill_category = merged.get("skill_category", "")

	var range_raw: Dictionary = merged.get("range", {})
	profile.range_min = range_raw.get("min", 0)
	profile.range_short = range_raw.get("short", 0)
	profile.range_long = range_raw.get("long", 0)
	profile.range_max = range_raw.get("max", 1)

	var damage_raw: Dictionary = merged.get("damage", {})
	profile.damage_type = damage_raw.get("type", "kinetic")
	profile.damage_value = damage_raw.get("value", 0)
	profile.damage_count = damage_raw.get("count", 1)

	var splash_raw: Dictionary = damage_raw.get("splash", {})
	if not splash_raw.is_empty():
		profile.splash_close = splash_raw.get("close", 0)
		profile.splash_medium = splash_raw.get("medium", 0)
		profile.splash_far = splash_raw.get("far", 0)
		profile.has_splash = true

	return profile
