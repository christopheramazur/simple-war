extends GutTest

## Tests for CombatOrchestrator -- coordinates full combat exchanges.

var orchestrator: CombatOrchestrator


func before_each() -> void:
	orchestrator = CombatOrchestrator.new()


func _make_simple_model(
	endurance: int, durability: int, reflex: int, speed: int,
	damage_value: int, range_max: int = 40
) -> ModelData:
	var m := ModelData.new()
	m.id = "model_%d" % randi()
	m.endurance = endurance
	m.durability = durability
	m.reflex = reflex
	m.speed = speed

	var profile := AttackProfile.new()
	profile.id = "atk_%d" % randi()
	profile.category = "ranged" if range_max > 2 else "melee"
	profile.range_min = 0 if range_max <= 2 else 5
	profile.range_short = 0 if range_max <= 2 else 10
	profile.range_long = 0 if range_max <= 2 else 30
	profile.range_max = range_max
	profile.damage_type = "kinetic"
	profile.damage_value = damage_value
	profile.damage_count = 1

	var item := ItemData.new()
	item.id = "weapon_%d" % randi()
	item.attack_profiles = [profile] as Array[AttackProfile]
	m.items.append(item)

	return m


func _make_unit_with_models(
	model_count: int, endurance: int, durability: int,
	reflex: int, speed: int, damage_value: int
) -> UnitData:
	var unit := UnitData.new()
	unit.id = "unit_%d" % randi()
	unit.endurance = endurance
	unit.durability = durability
	unit.reflex = reflex
	unit.speed = speed
	unit.position = Vector2.ZERO

	for _i in range(model_count):
		var model := _make_simple_model(endurance, durability, reflex, speed, damage_value)
		unit.models.append(model)

	return unit


func test_single_exchange_produces_result() -> void:
	var attacker := _make_unit_with_models(5, 10, 10, 5, 5, 5)
	var defender := _make_unit_with_models(5, 10, 10, 5, 5, 5)

	var result := orchestrator.resolve_single_exchange(
		[attacker] as Array[UnitData],
		[defender] as Array[UnitData],
		15.0
	)

	assert_not_null(result)
	assert_eq(result.turns_elapsed, 1)
	assert_eq(result.turn_logs.size(), 1, "Single exchange should produce one TurnLog")
	assert_gt(result.turn_logs[0].events.size(), 0, "TurnLog should contain combat events")


func test_full_battle_eventually_ends() -> void:
	seed(42)
	var attacker := _make_unit_with_models(5, 10, 10, 5, 5, 5)
	attacker.position = Vector2(100, 80)
	var defender := _make_unit_with_models(5, 10, 10, 5, 5, 5)
	defender.position = Vector2(100, 20)

	var result := orchestrator.resolve_battle(
		[attacker] as Array[UnitData],
		[defender] as Array[UnitData]
	)

	assert_true(
		result.attacker_models_remaining == 0 or result.defender_models_remaining == 0
		or result.turns_elapsed == CombatOrchestrator.MAX_TURNS,
		"Battle should end when one side is eliminated or max turns reached"
	)


func test_overwhelming_force_wins() -> void:
	seed(42)
	var big_force := _make_unit_with_models(20, 10, 5, 5, 5, 5)
	big_force.position = Vector2(100, 80)
	var small_force := _make_unit_with_models(2, 10, 5, 5, 5, 5)
	small_force.position = Vector2(100, 20)

	var attacker_wins := 0
	for _i in range(50):
		big_force = _make_unit_with_models(20, 10, 5, 5, 5, 5)
		big_force.position = Vector2(100, 80)
		small_force = _make_unit_with_models(2, 10, 5, 5, 5, 5)
		small_force.position = Vector2(100, 20)

		var result := orchestrator.resolve_battle(
			[big_force] as Array[UnitData],
			[small_force] as Array[UnitData]
		)
		if result.get_winner() == "attacker":
			attacker_wins += 1

	assert_gt(attacker_wins, 35,
		"20 models vs 2 should win the vast majority of the time")


func test_high_armour_unit_resists_weak_attacks() -> void:
	seed(42)
	var weak_attackers := _make_unit_with_models(10, 10, 5, 5, 5, 1)
	weak_attackers.position = Vector2(100, 80)

	var armoured_unit := _make_unit_with_models(1, 10, 50, 3, 3, 10)
	armoured_unit.position = Vector2(100, 20)
	var armour := ArmourData.new()
	armour.value = 10
	armour.type = "heavy"
	armour.resistances = {}
	var armour_item := ItemData.new()
	armour_item.id = "heavy_armour"
	armour_item.armour = armour
	armoured_unit.models[0].items.append(armour_item)

	var result := orchestrator.resolve_battle(
		[weak_attackers] as Array[UnitData],
		[armoured_unit] as Array[UnitData]
	)

	assert_gt(result.defender_models_remaining, 0,
		"Heavy armour should resist weak attacks for at least one battle")
