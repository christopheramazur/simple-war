class_name ModelData
extends RefCounted

## Runtime representation of a single model instance during combat.
## Tracks mutable state (current durability, damage taken) separately
## from the template data.

var id: String = ""
var display_name: String = ""
var items: Array[ItemData] = []

# Stats inherited from the parent unit definition
var endurance: int = 0
var durability: int = 0
var morale: int = 0
var speed: int = 0
var reflex: int = 0

# Weapon competence per category, e.g. { "rifle": 8, "launcher": 4 }
var weapon_skill: Dictionary = {}

# Mutable combat state
var damage_taken: int = 0
var is_destroyed: bool = false


func get_remaining_durability() -> int:
	return maxi(0, durability - damage_taken)


func get_all_attack_profiles() -> Array[AttackProfile]:
	var profiles: Array[AttackProfile] = []
	for item in items:
		profiles.append_array(item.attack_profiles)
	return profiles


func get_ranged_profiles() -> Array[AttackProfile]:
	var profiles: Array[AttackProfile] = []
	for item in items:
		profiles.append_array(item.get_ranged_profiles())
	return profiles


func get_melee_profiles() -> Array[AttackProfile]:
	var profiles: Array[AttackProfile] = []
	for item in items:
		profiles.append_array(item.get_melee_profiles())
	return profiles


func get_total_armour_value(damage_type: String) -> int:
	var total := 0
	for item in items:
		if item.has_armour():
			total += item.armour.get_effective_value(damage_type)
	return total


func get_hit_modifier_for_profile(profile: AttackProfile) -> float:
	var total_mod := 0.0
	for item in items:
		if not item.has_armour():
			continue
		var mods: Dictionary = item.armour.hit_modifiers
		if mods.is_empty():
			continue
		# Generic category ("ranged" / "melee")
		total_mod += float(mods.get(profile.category, 0.0))
		# By damage type (e.g. "damage:energy")
		if profile.damage_type != "":
			var key := "damage:" + profile.damage_type
			total_mod += float(mods.get(key, 0.0))
	return total_mod


func apply_damage(amount: int) -> bool:
	damage_taken += amount
	if damage_taken >= durability:
		is_destroyed = true
	return is_destroyed
