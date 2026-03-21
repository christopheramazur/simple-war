extends GutTest

const BATTLEFIELD_SCENE := preload("res://src/ui/battlefield.tscn")

func test_resolve_combat_step_applies_damage_simultaneously() -> void:
	var battlefield := BATTLEFIELD_SCENE.instantiate()
	add_child(battlefield)
	await wait_process_frames(1) # allow _ready() to spawn unit runtime objects

	CampaignRuntime.reset_battle_session()

	# Put both sides into a minimal "one unit each" scenario.
	for i in range(battlefield.player_units.size()):
		if i != 0:
			battlefield.player_units[i].alive = false
			battlefield.player_units[i].durability = 0
	for i in range(battlefield.enemy_units.size()):
		if i != 0:
			battlefield.enemy_units[i].alive = false
			battlefield.enemy_units[i].durability = 0

	# Make sure the two surviving units are mutually in range.
	battlefield.player_units[0].position = Vector2(0, 0)
	battlefield.enemy_units[0].position = Vector2(10, 0) # <= EFFECTIVE_RANGE (20)
	battlefield.player_units[0].durability = 2
	battlefield.enemy_units[0].durability = 2
	battlefield.player_units[0].alive = true
	battlefield.enemy_units[0].alive = true

	battlefield._resolve_combat_step()

	assert_false(battlefield.player_units[0].alive)
	assert_false(battlefield.enemy_units[0].alive)
	assert_eq(CampaignRuntime.player_units_destroyed, 1)
	assert_eq(CampaignRuntime.enemy_units_destroyed, 1)

	battlefield.queue_free()

