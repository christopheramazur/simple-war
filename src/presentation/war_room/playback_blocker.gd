class_name PlaybackBlocker
extends UiWindow
## The war room's blocker while a turn plays out (sw-ll4.27.4, sw-bafi.1 U1 C1,
## sw-bafi.9 U1 C8). It takes every mouse event over the screen except the
## regions in `uncovered`, so what it covers cannot plan or act mid-turn
## (their buttons and wheel stay dead). A battle leaves its stage open (the
## view inspects, zooms and pans); the overworld leaves its stage and the side
## panels' lists open, whose planning controls are disabled with the reason.

## The regions the blocker leaves to the views; empty covers all of the screen.
var uncovered: Array[Control] = []


func _has_point(point: Vector2) -> bool:
	var at := get_global_transform() * point
	for c: Control in uncovered:
		if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree() and c.get_global_rect().has_point(at):
			return false
	return Rect2(Vector2.ZERO, size).has_point(point)
