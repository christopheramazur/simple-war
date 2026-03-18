extends GutTest

## Tests for DefenseResolver -- the "Being Attacked" process.

var resolver: DefenseResolver


func before_each() -> void:
	resolver = DefenseResolver.new()


func _make_model(durability: int) -> ModelData:
	var m := ModelData.new()
	m.id = "test_target"
	m.durability = durability
	m.endurance = 10
	m.reflex = 10
	m.speed = 10
	return m


func _make_armour(value: int, resistances: Dictionary = {}) -> ArmourData:
	var a := ArmourData.new()
	a.value = value
	a.type = "test"
	a.resistances = resistances
	return a


func _make_armour_item(armour: ArmourData) -> ItemData:
	var item := ItemData.new()
	item.id = "test_armour"
	item.armour = armour
	return item


func _make_damage(value: int, type: String = "kinetic") -> DamageInstance:
	var dmg := DamageInstance.new()
	dmg.damage_value = value
	dmg.damage_type = type
	dmg.source_model_id = "attacker"
	dmg.target_model_id = "test_target"
	return dmg


func test_damage_exceeding_durability_destroys_model() -> void:
	var model := _make_model(10)
	var dmg := _make_damage(15)

	resolver.resolve_damage(dmg, model)

	assert_true(model.is_destroyed, "Model should be destroyed when damage >= durability")
	assert_true(dmg.resulted_in_kill, "DamageInstance should record the kill")


func test_damage_below_durability_does_not_destroy() -> void:
	var model := _make_model(10)
	var dmg := _make_damage(5)

	resolver.resolve_damage(dmg, model)

	assert_false(model.is_destroyed, "Model should survive when damage < durability")
	assert_eq(model.damage_taken, 5, "Damage should be tracked")
	assert_false(dmg.resulted_in_kill, "Should not record a kill")


func test_damage_equal_to_durability_destroys_model() -> void:
	var model := _make_model(10)
	var dmg := _make_damage(10)

	resolver.resolve_damage(dmg, model)

	assert_true(model.is_destroyed, "Damage equal to durability should destroy")


func test_armour_reduces_damage() -> void:
	var model := _make_model(10)
	var armour := _make_armour(5)
	model.equipped_items.append(_make_armour_item(armour))
	var dmg := _make_damage(8)

	resolver.resolve_damage(dmg, model)

	assert_eq(dmg.mitigated_value, 3, "Damage should be reduced by armour value")
	assert_eq(dmg.armour_applied, 5, "Applied armour should be recorded")
	assert_false(model.is_destroyed, "Model should survive after mitigation")


func test_armour_resistance_modifies_effective_armour() -> void:
	var model := _make_model(10)
	var armour := _make_armour(5, {"concussive": -2})
	model.equipped_items.append(_make_armour_item(armour))
	var dmg := _make_damage(6, "concussive")

	resolver.resolve_damage(dmg, model)

	assert_eq(dmg.armour_applied, 3,
		"Concussive should reduce effective armour by resistance modifier")
	assert_eq(dmg.mitigated_value, 3, "Mitigated damage should reflect reduced armour")


func test_armour_cannot_go_below_zero() -> void:
	var model := _make_model(10)
	var armour := _make_armour(2, {"energy": -5})
	model.equipped_items.append(_make_armour_item(armour))
	var dmg := _make_damage(4, "energy")

	resolver.resolve_damage(dmg, model)

	assert_eq(dmg.armour_applied, 0,
		"Effective armour should be floored at 0")
	assert_eq(dmg.mitigated_value, 4,
		"Full damage should apply when armour is ineffective")


func test_sub_lethal_damage_accumulates() -> void:
	var model := _make_model(10)
	var dmg1 := _make_damage(4)
	var dmg2 := _make_damage(4)
	var dmg3 := _make_damage(4)

	resolver.resolve_damage(dmg1, model)
	assert_false(model.is_destroyed)
	assert_eq(model.damage_taken, 4)

	resolver.resolve_damage(dmg2, model)
	assert_false(model.is_destroyed)
	assert_eq(model.damage_taken, 8)

	resolver.resolve_damage(dmg3, model)
	assert_true(model.is_destroyed, "Accumulated damage should eventually destroy")


func test_zero_damage_after_armour_does_nothing() -> void:
	var model := _make_model(10)
	var armour := _make_armour(10)
	model.equipped_items.append(_make_armour_item(armour))
	var dmg := _make_damage(5)

	resolver.resolve_damage(dmg, model)

	assert_eq(model.damage_taken, 0, "Zero mitigated damage should not be applied")
	assert_false(model.is_destroyed)


func test_already_destroyed_model_is_skipped() -> void:
	var model := _make_model(10)
	model.is_destroyed = true
	var dmg := _make_damage(20)

	resolver.resolve_damage(dmg, model)

	assert_eq(dmg.mitigated_value, 0, "No damage should process on destroyed models")
