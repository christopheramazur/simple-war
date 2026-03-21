extends GutTest

const BattlefieldCoordinateMapper := preload("res://src/battle/runtime/battlefield_coordinate_mapper.gd")
const BattlefieldSimulation := preload("res://src/battle/runtime/battlefield_simulation.gd")

func test_resolve_combat_step_applies_damage_simultaneously() -> void:
	var mapper := BattlefieldCoordinateMapper.new()
	var sim := BattlefieldSimulation.new(mapper)
	sim.spawn_poc_units()

	CampaignRuntime.reset_battle_session()

	for i in range(sim.player_units.size()):
		if i != 0:
			sim.player_units[i].alive = false
			sim.player_units[i].durability = 0
	for i in range(sim.enemy_units.size()):
		if i != 0:
			sim.enemy_units[i].alive = false
			sim.enemy_units[i].durability = 0

	sim.player_units[0].position = Vector2(0, 0)
	sim.enemy_units[0].position = Vector2(10, 0)
	sim.player_units[0].durability = 2
	sim.enemy_units[0].durability = 2
	sim.player_units[0].alive = true
	sim.enemy_units[0].alive = true

	sim.resolve_combat_step()

	assert_false(sim.player_units[0].alive)
	assert_false(sim.enemy_units[0].alive)
	assert_eq(CampaignRuntime.player_units_destroyed, 1)
	assert_eq(CampaignRuntime.enemy_units_destroyed, 1)
