extends RefCounted
class_name DeploymentSystem

const PLAYER_ZONE_MAX_Y: float = 20.0
const ENEMY_ZONE_MIN_Y: float = 80.0

func is_player_deployment_legal(position: Vector2, battlefield_width: float) -> bool:
	return position.x >= 0.0 and position.x <= battlefield_width and position.y >= 0.0 and position.y <= PLAYER_ZONE_MAX_Y

func is_enemy_deployment_legal(position: Vector2, battlefield_width: float, battlefield_height: float) -> bool:
	return position.x >= 0.0 and position.x <= battlefield_width and position.y >= ENEMY_ZONE_MIN_Y and position.y <= battlefield_height
