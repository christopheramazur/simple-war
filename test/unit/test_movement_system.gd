extends GutTest

const MOVEMENT_SYSTEM := preload("res://src/battle/systems/movement_system.gd")

var movement: MovementSystem

func before_all() -> void:
	movement = MOVEMENT_SYSTEM.new()

func test_snap_to_grid_rounds_to_nearest() -> void:
	var p := Vector2(2.1, 3.7)
	var snapped_pos := movement.snap_to_grid(p, 1.0)
	assert_eq(snapped_pos, Vector2(2.0, 4.0))

func test_move_toward_with_budget_returns_target_when_within_budget() -> void:
	var origin := Vector2(0, 0)
	var target := Vector2(3, 4) # distance = 5
	var result := movement.move_toward_with_budget(origin, target, 5.0)
	assert_eq(result, target)

func test_move_toward_with_budget_moves_along_direct_path() -> void:
	var origin := Vector2(0, 0)
	var target := Vector2(3, 4) # distance = 5
	var result := movement.move_toward_with_budget(origin, target, 2.0)
	# direction = (3/5, 4/5), step = 2 => (1.2, 1.6)
	assert_almost_eq(result.x, 1.2, 0.0001)
	assert_almost_eq(result.y, 1.6, 0.0001)

