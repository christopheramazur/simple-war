class_name UnitData
extends RefCounted

## Runtime representation of a Unit archetype Entity (rule 240.1).
## Contains live Model Entity instances with mutable Component state.
##
## Components mapped:
##   StatlineComponent – endurance, durability, morale, speed, reflex
##   FactionKeywordsComponent – faction_keywords (marker Components)
##   UnitKeywordsComponent – unit_keywords (marker Components)
##   ValueComponent – value
##   WeaponSkillComponent – weapon_skill (prototype extension)
##   PositionComponent – position (from Movement Rules 300-series)
##   CompositionComponent – models (expanded into Model Entity instances)

var id: String = ""
var display_name: String = ""
var faction_keywords: Array[String] = []
var unit_keywords: Array[String] = []

# StatlineComponent fields
var endurance: int = 0
var durability: int = 0
var morale: int = 0
var speed: int = 0
var reflex: int = 0

# ValueComponent
var value: int = 0

# Expanded CompositionComponent – live Model Entity instances
var models: Array[ModelData] = []

# PositionComponent – spatial position on the Battlefield Entity
var position: Vector2 = Vector2.ZERO

# Current Order for this Turn (set by the Battle System during Order Phase)
var order: String = "move_closer"

# WeaponSkillComponent defaults (copied to Model Entities on creation)
var weapon_skill: Dictionary = {}

# Movement System state – distance moved this Turn, used for evasion
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
