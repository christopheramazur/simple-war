class_name ItemData
extends RefCounted

## Runtime representation of an item loaded from Items.json.

var id: String = ""
var display_name: String = ""
var description: String = ""
var attack_profiles: Array[AttackProfile] = []
var armour: ArmourData = null
var consumable: bool = false


func has_weapon() -> bool:
	return not attack_profiles.is_empty()


func has_armour() -> bool:
	return armour != null


func get_ranged_profiles() -> Array[AttackProfile]:
	var result: Array[AttackProfile] = []
	for profile in attack_profiles:
		if profile.category == "ranged":
			result.append(profile)
	return result


func get_melee_profiles() -> Array[AttackProfile]:
	var result: Array[AttackProfile] = []
	for profile in attack_profiles:
		if profile.category == "melee":
			result.append(profile)
	return result
