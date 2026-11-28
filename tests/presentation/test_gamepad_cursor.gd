extends GutTest
## The pad cursor (sw-wut): the stick moves a pointer inside the window at a
## fixed speed, the buttons are A and the right bumper, and the buttons only
## go live while the cursor is driven.

const _BOUNDS := Rect2(Vector2.ZERO, Vector2(1000, 600))


func test_advance_moves_by_the_stick_over_time() -> void:
	var p := GamepadCursor.advance(Vector2(100, 100), Vector2(1, 0), 0.5, _BOUNDS)
	assert_almost_eq(p.x, 100.0 + GamepadCursor.SPEED * 0.5, 0.001, "full right for half a second")
	assert_almost_eq(p.y, 100.0, 0.001, "no vertical move")


func test_advance_holds_still_without_stick() -> void:
	var p := GamepadCursor.advance(Vector2(300, 200), Vector2.ZERO, 1.0, _BOUNDS)
	assert_eq(p, Vector2(300, 200))


func test_advance_stays_inside_the_window() -> void:
	var p := GamepadCursor.advance(Vector2(995, 5), Vector2(1, -1), 1.0, _BOUNDS)
	assert_eq(p, Vector2(1000, 0), "clamped to the top-right corner")


func test_diagonal_is_not_faster_than_straight() -> void:
	var straight := GamepadCursor.advance(Vector2(500, 300), Vector2(1, 0), 0.1, _BOUNDS) - Vector2(500, 300)
	var diagonal := GamepadCursor.advance(Vector2(500, 300), Vector2(1, 1), 0.1, _BOUNDS) - Vector2(500, 300)
	assert_almost_eq(diagonal.length(), straight.length(), 0.001, "unit length, not sqrt(2)")


func test_non_finite_stick_is_ignored() -> void:
	var p := GamepadCursor.advance(Vector2(10, 10), Vector2(INF, 0), 1.0, _BOUNDS)
	assert_eq(p, Vector2(10, 10))


func test_buttons_are_a_and_right_bumper() -> void:
	var c := GamepadCursor.new()
	var ms := c.button_context.mappings
	assert_eq(ms.size(), 2, "one mapping per button")
	var inputs: Array = []
	for m: GUIDEActionMapping in ms:
		for im: GUIDEInputMapping in m.input_mappings:
			inputs.append(im.input)
	assert_eq((inputs[0] as GUIDEInputJoyButton).button, JOY_BUTTON_A)
	assert_eq((inputs[1] as GUIDEInputJoyButton).button, JOY_BUTTON_RIGHT_SHOULDER)
	c.free()


func test_move_is_a_stick_pair_with_deadzone() -> void:
	var c := GamepadCursor.new()
	assert_eq(c.move_action.action_value_type, GUIDEAction.GUIDEActionValueType.AXIS_2D)
	var im: GUIDEInputMapping = (c.move_context.mappings[0] as GUIDEActionMapping).input_mappings[0]
	var axes := im.input as GUIDEInputJoyAxis2D
	assert_eq(axes.x, JOY_AXIS_RIGHT_X)
	assert_eq(axes.y, JOY_AXIS_RIGHT_Y)
	assert_true(im.modifiers[0] is GUIDEModifierDeadzone, "stick drift is cut by a deadzone")
	c.free()
