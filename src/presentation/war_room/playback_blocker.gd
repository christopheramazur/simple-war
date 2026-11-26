class_name PlaybackBlocker
extends UiWindow
## The war room's blocker while a turn plays out (sw-ll4.27.4, sw-bafi.1 U1 C1).
## It takes every mouse event over the screen except the stage, so the side
## panels cannot plan or act mid-turn (their buttons and wheel stay dead).
## While a battle is focused, `uncovered` (the stage region) passes events
## to the battle view, which inspects, zooms and pans; the overworld keeps the
## whole screen covered (C8 decides its playback controls).

## The region the blocker leaves to the views; null covers all of the screen.
var uncovered: Control


func _has_point(point: Vector2) -> bool:
	if uncovered != null and uncovered.is_inside_tree():
		if uncovered.get_global_rect().has_point(get_global_transform() * point):
			return false
	return Rect2(Vector2.ZERO, size).has_point(point)
