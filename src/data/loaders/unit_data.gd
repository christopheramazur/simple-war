class_name UnitData
extends RefCounted

## Runtime representation of a unit during combat.
## Contains live model instances with mutable state.

var id: String = ""
var display_name: String = ""
var faction_keywords: Array[String] = []
var unit_keywords: Array[String] = []

var endurance: int = 0
var durability: int = 0
var morale: int = 0
var speed: int = 0
var reflex: int = 0
var value: int = 0

var models: Array[ModelData] = []

# Spatial position on the battlefield (center of the unit)
var position: Vector2 = Vector2.ZERO

# Order for this turn: "attack", "move_closer", "move_away". Only one action per turn.
var order: String = "move_closer"

# Weapon competence defaults for this unit (copied to models on creation)
var weapon_skill: Dictionary = {}

# Distance moved this turn (world units), used for movement-based evasion.
var distance_moved_this_turn: float = 0.0


func get_alive_models() -> Array[ModelData]:
	var alive: Array[ModelData] = []
	for model in models:
		if not model.is_destroyed:
			alive.append(model)
	return alive


func get_alive_count() -> int:
	var count := 0
	for model in models:
		if not model.is_destroyed:
			count += 1
	return count


func is_destroyed() -> bool:
	return get_alive_count() == 0


func get_total_models() -> int:
	return models.size()


func get_destroyed_count() -> int:
	return get_total_models() - get_alive_count()


func has_attack_in_range(distance: float) -> bool:
	for model in get_alive_models():
		for profile in model.get_all_attack_profiles():
			if profile.is_in_range(distance):
				return true
	return false
