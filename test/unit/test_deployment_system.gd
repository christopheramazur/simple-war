extends GutTest

const DEPLOYMENT_SYSTEM := preload("res://src/battle/systems/deployment_system.gd")

var deployment: DeploymentSystem

func before_all() -> void:
	deployment = DEPLOYMENT_SYSTEM.new()

func test_player_deployment_legal_in_inclusive_bounds() -> void:
	assert_true(deployment.is_player_deployment_legal(Vector2(0, 0), 200.0))
	assert_true(deployment.is_player_deployment_legal(Vector2(199.99, 20.0), 200.0))

func test_player_deployment_legal_rejects_outside_y_upper_bound() -> void:
	assert_false(deployment.is_player_deployment_legal(Vector2(10, 20.01), 200.0))

func test_player_deployment_legal_rejects_outside_x_bounds() -> void:
	assert_false(deployment.is_player_deployment_legal(Vector2(-0.01, 10), 200.0))
	assert_false(deployment.is_player_deployment_legal(Vector2(200.01, 10), 200.0))

