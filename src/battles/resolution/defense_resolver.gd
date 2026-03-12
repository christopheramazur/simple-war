class_name DefenseResolver
extends RefCounted

## "Being Attacked" process.
## Receives DamageInstance objects and applies armour mitigation against
## the target model. Determines if the model survives. Does not know
## about how the attack was generated.


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
