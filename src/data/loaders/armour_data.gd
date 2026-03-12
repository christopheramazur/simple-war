class_name ArmourData
extends RefCounted

## Runtime representation of an armour component from an item.

var value: int = 0
var type: String = "none"
var resistances: Dictionary = {}  # damage_type -> int modifier
var hit_modifiers: Dictionary = {}  # e.g. { "ranged": 0.05, "damage:energy": 0.10 }


func get_effective_value(damage_type: String) -> int:
	var modifier: int = resistances.get(damage_type, 0)
	return maxi(0, value + modifier)
