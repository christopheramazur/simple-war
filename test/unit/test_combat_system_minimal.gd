extends GutTest

const COMBAT_SYSTEM := preload("res://src/battle/systems/combat_system_minimal.gd")
const UNIT_RUNTIME := preload("res://src/battle/runtime/unit_runtime.gd")

var combat: CombatSystemMinimal

func before_all() -> void:
	combat = COMBAT_SYSTEM.new()

func test_queued_damage_returns_base_damage_when_in_range() -> void:
	var attacker := UNIT_RUNTIME.new("a", "Attacker", "Human", 10.0, 10, 1, Vector2(0, 0))
	var target := UNIT_RUNTIME.new("t", "Target", "Enemy", 10.0, 10, 1, Vector2(10, 0)) # distance 10 <= 20
	assert_eq(combat.queued_damage(attacker, target), 2)

func test_queued_damage_returns_zero_when_out_of_range() -> void:
	var attacker := UNIT_RUNTIME.new("a", "Attacker", "Human", 10.0, 10, 1, Vector2(0, 0))
	var target := UNIT_RUNTIME.new("t", "Target", "Enemy", 10.0, 10, 1, Vector2(21, 0)) # distance 21 > 20
	assert_eq(combat.queued_damage(attacker, target), 0)

