class_name SimpleBot
extends RefCounted

## Basic bot opponent: deploys units, sets orders (attack if in weapon range else move_closer),
## and moves only units that have order move_closer or move_away.
## Used by the battlefield scene to automate the defender side.


func deploy_units(units: Array[UnitData], deploy_y: float, field_width: float) -> void:
	var spacing := field_width / float(units.size() + 1)
	for i in range(units.size()):
		units[i].position = Vector2(spacing * (i + 1), deploy_y)


func set_orders(units: Array[UnitData], enemy_units: Array[UnitData]) -> void:
	## Set each unit's order: "attack" if any weapon is in range of closest enemy, else "move_closer".
	for unit in units:
		if unit.is_destroyed():
			continue
		var target := _find_closest_enemy(unit, enemy_units)
		if target == null:
			unit.order = "move_closer"
			continue
		var distance := unit.position.distance_to(target.position)
		unit.order = "attack" if unit.has_attack_in_range(distance) else "move_closer"


func advance_units(
	units: Array[UnitData],
	enemy_units: Array[UnitData],
	max_move: float = 5.0
) -> void:
	## Move only units with order "move_closer" toward closest enemy.
	for unit in units:
		if unit.is_destroyed() or unit.order != "move_closer":
			continue

		var target := _find_closest_enemy(unit, enemy_units)
		if target == null:
			continue

		var direction := (target.position - unit.position).normalized()
		var distance := unit.position.distance_to(target.position)
		var move_dist := minf(max_move, distance - 1.0)
		if move_dist > 0.0:
			var delta := direction * move_dist
			unit.position += delta
			unit.distance_moved_this_turn += delta.length()


func move_units_away(
	units: Array[UnitData],
	enemy_units: Array[UnitData],
	max_move: float = 5.0
) -> void:
	## Move only units with order "move_away" away from closest enemy.
	for unit in units:
		if unit.is_destroyed() or unit.order != "move_away":
			continue

		var target := _find_closest_enemy(unit, enemy_units)
		if target == null:
			continue

		var direction := (unit.position - target.position).normalized()
		var delta := direction * max_move
		unit.position += delta
		unit.distance_moved_this_turn += delta.length()


func _find_closest_enemy(unit: UnitData, enemies: Array[UnitData]) -> UnitData:
	var best: UnitData = null
	var best_dist := INF
	for enemy in enemies:
		if enemy.is_destroyed():
			continue
		var dist := unit.position.distance_to(enemy.position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best
