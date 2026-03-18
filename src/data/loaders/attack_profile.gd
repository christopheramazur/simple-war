class_name AttackProfile
extends RefCounted

## Runtime representation of an AttackProfileComponent (rule 220.4).
## Produced by the Combat System's Attack Pipeline from base attack
## definitions merged with per-Item overrides.

var id: String = ""
var display_name: String = ""
var category: String = "melee"  # "melee" or "ranged"
var skill_category: String = ""  # used to look up WeaponSkillComponent value

var range_min: int = 0
var range_short: int = 0
var range_long: int = 0
var range_max: int = 1

var damage_type: String = "kinetic"
var damage_value: int = 0
var damage_count: int = 1

var has_splash: bool = false
var splash_close: int = 0
var splash_medium: int = 0
var splash_far: int = 0


func is_in_range(distance: float) -> bool:
	return distance >= range_min and distance <= range_max


func get_range_penalty(distance: float) -> float:
	if distance < range_min or distance > range_max:
		return -1.0  # out of range
	if distance >= range_short and distance <= range_long:
		return 0.0  # effective range
	if distance < range_short:
		var band_short := float(range_short - range_min)
		if band_short <= 0:
			return 0.0
		return -0.15 * (1.0 - (distance - range_min) / band_short)
	# distance > range_long
	var band_long := float(range_max - range_long)
	if band_long <= 0:
		return 0.0
	return -0.15 * ((distance - range_long) / band_long)
