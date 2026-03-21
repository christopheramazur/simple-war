extends GutTest

const BattleWorldHost := preload("res://src/battle/runtime/battle_world_host.gd")
func test_battle_world_has_scope_entity() -> void:
	var host := BattleWorldHost.new()
	add_child(host)
	await wait_process_frames(1)
	assert_true(host.world != null)
	assert_eq(host.world.entities.size(), 1)
	var e: Entity = host.world.entities[0]
	const SCRIPT_SCOPE := "res://src/battle/components/c_battle_scope.gd"
	assert_true(e.components.has(SCRIPT_SCOPE))
	host.queue_free()
