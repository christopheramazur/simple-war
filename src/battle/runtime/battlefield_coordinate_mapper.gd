extends RefCounted
class_name BattlefieldCoordinateMapper
## Screen ↔ world mapping for the battlefield board and reserve strip (view layer helper; no game rules).

const BattlefieldLayout := preload("res://src/battle/runtime/battlefield_layout.gd")

func board_rect() -> Rect2:
	return BattlefieldLayout.board_rect()

func world_to_screen(world_position: Vector2) -> Vector2:
	var br := board_rect()
	return Vector2(
		br.position.x + (world_position.x * BattlefieldLayout.WORLD_SCALE),
		br.position.y + ((BattlefieldLayout.BATTLEFIELD_HEIGHT - world_position.y) * BattlefieldLayout.WORLD_SCALE)
	)

func screen_to_world(screen_position: Vector2) -> Vector2:
	var br := board_rect()
	return Vector2(
		(screen_position.x - br.position.x) / BattlefieldLayout.WORLD_SCALE,
		BattlefieldLayout.BATTLEFIELD_HEIGHT - ((screen_position.y - br.position.y) / BattlefieldLayout.WORLD_SCALE)
	)

func unit_selection_screen_rect(unit) -> Rect2:
	var center := world_to_screen(unit.position)
	return Rect2(center - Vector2(24, 18), Vector2(48, 36))

func reserve_units_panel_origin() -> Vector2:
	var br := board_rect()
	return Vector2(br.end.x + BattlefieldLayout.RESERVE_PANEL_X_OFFSET, br.position.y + BattlefieldLayout.RESERVE_PANEL_Y_OFFSET)

func reserve_unit_at_screen(screen_pos: Vector2, reserve_units: Array) -> Variant:
	var panel_origin := reserve_units_panel_origin()
	for i in range(reserve_units.size()):
		var pos := panel_origin + Vector2(0, i * BattlefieldLayout.RESERVE_UNIT_SPACING_Y)
		var rect := Rect2(pos - BattlefieldLayout.RESERVE_SLOT_SIZE * 0.5, BattlefieldLayout.RESERVE_SLOT_SIZE)
		if rect.has_point(screen_pos):
			return reserve_units[i]
	return null

func rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var mn := Vector2(mini(a.x, b.x), mini(a.y, b.y))
	var mx := Vector2(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2(mn, mx - mn)
