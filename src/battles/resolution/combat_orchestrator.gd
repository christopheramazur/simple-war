class_name CombatOrchestrator
extends RefCounted

## Coordinates a full combat exchange between two forces.
## Distributes attacking models to closest target models,
## runs the attack and defense resolvers, and collects results.
##
## This is the only class that knows about both attack_resolver and
## defense_resolver. They remain decoupled from each other.

const MAX_TURNS := 20

var attack_resolver := AttackResolver.new()
var defense_resolver := DefenseResolver.new()


func resolve_battle(
	attacker_units: Array[UnitData],
	defender_units: Array[UnitData],
	starting_distance: float = 30.0
) -> CombatResult:
	var result := CombatResult.new()
	var attacker_start := _count_models(attacker_units)
	var defender_start := _count_models(defender_units)

	var distance := starting_distance

	for turn in range(1, MAX_TURNS + 1):
		result.turns_elapsed = turn

		# Headless sim: all units attack every turn (no move/attack split)
		for u in attacker_units:
			u.order = "attack"
		for u in defender_units:
			u.order = "attack"

		# Both sides attack simultaneously (uses unit positions for distance)
		var atk_events := _resolve_side_attacks(attacker_units, defender_units, distance)
		var def_events := _resolve_side_attacks(defender_units, attacker_units, distance)

		var atk_damage := _extract_damage_instances(atk_events)
		var def_damage := _extract_damage_instances(def_events)

		# Apply damage (defense resolver)
		_apply_damage_to_targets(atk_damage, defender_units, result)
		_apply_damage_to_targets(def_damage, attacker_units, result)

		result.attacker_models_remaining = _count_alive(attacker_units)
		result.defender_models_remaining = _count_alive(defender_units)
		result.attacker_models_lost = attacker_start - result.attacker_models_remaining
		result.defender_models_lost = defender_start - result.defender_models_remaining

		var battle_turn_log: TurnLog = _build_turn_log(turn, atk_events, def_events)
		result.turn_logs.append(battle_turn_log)

		if result.attacker_models_remaining <= 0 or result.defender_models_remaining <= 0:
			break

		# Simple movement: close distance each turn
		distance = maxf(1.0, distance - _get_closing_speed(attacker_units, defender_units))

	return result


func resolve_single_exchange(
	attacker_units: Array[UnitData],
	defender_units: Array[UnitData],
	distance: float = 15.0
) -> CombatResult:
	var result := CombatResult.new()
	result.turns_elapsed = 1

	var attacker_start := _count_models(attacker_units)
	var defender_start := _count_models(defender_units)

	var atk_events := _resolve_side_attacks(attacker_units, defender_units, distance)
	var def_events := _resolve_side_attacks(defender_units, attacker_units, distance)

	var atk_damage := _extract_damage_instances(atk_events)
	var def_damage := _extract_damage_instances(def_events)

	_apply_damage_to_targets(atk_damage, defender_units, result)
	_apply_damage_to_targets(def_damage, attacker_units, result)

	result.attacker_models_remaining = _count_alive(attacker_units)
	result.defender_models_remaining = _count_alive(defender_units)
	result.attacker_models_lost = attacker_start - result.attacker_models_remaining
	result.defender_models_lost = defender_start - result.defender_models_remaining

	var single_turn_log: TurnLog = _build_turn_log(1, atk_events, def_events)
	result.turn_logs.append(single_turn_log)

	return result


func _resolve_side_attacks(
	attacking_units: Array[UnitData],
	defending_units: Array[UnitData],
	_global_distance: float = 0.0
) -> Array[CombatEvent]:
	var all_events: Array[CombatEvent] = []

	for atk_unit in attacking_units:
		if atk_unit.order != "attack":
			continue
		var alive_attackers := atk_unit.get_alive_models()
		if alive_attackers.is_empty():
			continue

		var target_unit := _find_closest_unit(atk_unit, defending_units)
		if target_unit == null:
			continue

		var distance := atk_unit.position.distance_to(target_unit.position)

		for attacker in alive_attackers:
			var target_model := _find_closest_alive_model(target_unit)
			if target_model == null:
				break

			var events := attack_resolver.resolve_model_attacks(
				attacker, atk_unit, target_model, target_unit, distance
			)
			all_events.append_array(events)

	return all_events


func _extract_damage_instances(events: Array[CombatEvent]) -> Array[DamageInstance]:
	var out: Array[DamageInstance] = []
	for evt in events:
		if evt.hit and evt.damage_instance != null:
			out.append(evt.damage_instance)
	return out


func _build_turn_log(
	turn_number: int,
	attacker_events: Array[CombatEvent],
	defender_events: Array[CombatEvent]
) -> TurnLog:
	var out: TurnLog = TurnLog.new()
	out.turn_number = turn_number
	out.events.clear()
	out.events.append_array(attacker_events)
	out.events.append_array(defender_events)

	out.attacker_summary = _summarize_events(attacker_events)
	out.defender_summary = _summarize_events(defender_events)

	return out


func _summarize_events(events: Array[CombatEvent]) -> TurnLog.TurnLogSideSummary:
	var summary: TurnLog.TurnLogSideSummary = TurnLog.TurnLogSideSummary.new()
	summary.attacks_made = events.size()
	for evt in events:
		if evt.hit:
			summary.hits += 1
			if evt.damage_instance != null:
				summary.total_damage_dealt += evt.damage_instance.mitigated_value
				summary.total_damage_mitigated += evt.damage_instance.armour_applied
				if evt.damage_instance.resulted_in_kill:
					summary.models_killed += 1
		else:
			summary.misses += 1
	return summary


func _apply_damage_to_targets(
	instances: Array[DamageInstance],
	target_units: Array[UnitData],
	result: CombatResult
) -> void:
	for dmg in instances:
		var target_model := _find_model_by_id(dmg.target_model_id, dmg.target_unit_id, target_units)
		if target_model == null or target_model.is_destroyed:
			# Retarget to next alive model in the same unit
			var unit := _find_unit_by_id(dmg.target_unit_id, target_units)
			if unit != null:
				target_model = _find_closest_alive_model(unit)
			if target_model == null:
				continue

		defense_resolver.resolve_damage(dmg, target_model)
		result.damage_instances.append(dmg)
		result.total_damage_dealt += dmg.mitigated_value
		result.total_damage_mitigated += dmg.armour_applied
		if dmg.resulted_in_kill:
			result.models_destroyed += 1


func _find_closest_unit(source: UnitData, targets: Array[UnitData]) -> UnitData:
	var best: UnitData = null
	var best_dist := INF
	for unit in targets:
		if unit.is_destroyed():
			continue
		var dist := source.position.distance_to(unit.position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best


func _find_closest_alive_model(unit: UnitData) -> ModelData:
	var alive := unit.get_alive_models()
	if alive.is_empty():
		return null
	return alive[0]


func _find_model_by_id(model_id: String, unit_id: String, units: Array[UnitData]) -> ModelData:
	for unit in units:
		if unit.id == unit_id:
			for model in unit.models:
				if model.id == model_id and not model.is_destroyed:
					return model
	return null


func _find_unit_by_id(unit_id: String, units: Array[UnitData]) -> UnitData:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func _count_models(units: Array[UnitData]) -> int:
	var total := 0
	for unit in units:
		total += unit.get_total_models()
	return total


func _count_alive(units: Array[UnitData]) -> int:
	var total := 0
	for unit in units:
		total += unit.get_alive_count()
	return total


func _get_closing_speed(
	attacker_units: Array[UnitData],
	defender_units: Array[UnitData]
) -> float:
	var min_speed := 999
	for unit in attacker_units:
		if not unit.is_destroyed():
			min_speed = mini(min_speed, unit.speed)
	for unit in defender_units:
		if not unit.is_destroyed():
			min_speed = mini(min_speed, unit.speed)
	return float(min_speed) * 0.5
