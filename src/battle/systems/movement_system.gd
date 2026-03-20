extends RefCounted
class_name MovementSystem

const EPSILON: float = 0.0001

func snap_to_grid(world_point: Vector2, spacing: float) -> Vector2:
	if spacing <= EPSILON:
		return world_point
	return Vector2(
		round(world_point.x / spacing) * spacing,
		round(world_point.y / spacing) * spacing
	)

func euclidean_distance(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)

func clamp_to_battlefield(point: Vector2, width: float, height: float) -> Vector2:
	return Vector2(
		clamp(point.x, 0.0, width),
		clamp(point.y, 0.0, height)
	)

func move_toward_with_budget(origin: Vector2, target: Vector2, budget: float) -> Vector2:
	var distance: float = euclidean_distance(origin, target)
	if distance <= budget:
		return target
	if distance <= EPSILON:
		return origin
	var direction: Vector2 = (target - origin).normalized()
	return origin + (direction * budget)

func is_in_range(origin: Vector2, target: Vector2, range_units: float) -> bool:
	# Fast squared-distance check for frequent range queries.
	return origin.distance_squared_to(target) <= (range_units * range_units)
