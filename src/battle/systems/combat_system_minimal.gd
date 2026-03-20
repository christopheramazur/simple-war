extends RefCounted
class_name CombatSystemMinimal

const EFFECTIVE_RANGE: float = 20.0
const BASE_DAMAGE: int = 2

func pick_closest_enemy(origin, enemies: Array) -> Variant:
	var closest = null
	var best_distance: float = INF
	for enemy in enemies:
		if not enemy.alive:
			continue
		var distance: float = origin.distance_to(enemy.position)
		if distance < best_distance:
			best_distance = distance
			closest = enemy
	return closest

func resolve_attack(attacker, target) -> bool:
	if attacker == null or target == null:
		return false
	var in_range: bool = attacker.position.distance_squared_to(target.position) <= (EFFECTIVE_RANGE * EFFECTIVE_RANGE)
	if not in_range:
		return false
	target.durability -= BASE_DAMAGE
	if target.durability <= 0:
		target.alive = false
		return true
	return false
