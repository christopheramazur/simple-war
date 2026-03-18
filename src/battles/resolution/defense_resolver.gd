class_name DefenseResolver
extends RefCounted

## Combat System Defense Pipeline (rule 220.6).
## Receives Damage Instances and applies ArmourComponent mitigation against
## the target Model Entity. Updates DamageTakenComponent and
## DestructionStateComponent. Does not know about the Attack Pipeline.


func resolve_damage(dmg: DamageInstance, target: ModelData) -> DamageInstance:
	if target.is_destroyed:
		return dmg

	var armour_value := target.get_total_armour_value(dmg.damage_type)
	var mitigated := maxi(0, dmg.damage_value - armour_value)

	dmg.armour_applied = armour_value
	dmg.mitigated_value = mitigated

	if mitigated > 0:
		var killed := target.apply_damage(mitigated)
		dmg.resulted_in_kill = killed

	return dmg


func resolve_all(instances: Array[DamageInstance], target: ModelData) -> Array[DamageInstance]:
	var results: Array[DamageInstance] = []
	for dmg in instances:
		results.append(resolve_damage(dmg, target))
	return results
