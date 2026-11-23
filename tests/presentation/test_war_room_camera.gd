extends GutTest
## The battle camera (zoom about the cursor, pan, reset on leaving) and
## Space staying "end turn" after a button was clicked.

const ROOM := "res://src/presentation/war_room/war_room.tscn"


func _demo() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	return w


func _in_battle() -> WarRoom:
	var w := _demo()
	assert_true(w.contexts.tab_in())
	w._refresh()
	await get_tree().process_frame
	assert_gt(w._main.size.x, 200.0, "laid out")
	return w


func test_wheel_zooms_the_battle_about_the_cursor() -> void:
	var w := await _in_battle()
	var v := w._main
	var fit := v.battle_area()
	var at := fit.position + fit.size * Vector2(0.45, 0.55)
	for _i in 5:
		v.zoom_camera(1.25, at)
	assert_almost_eq(w.contexts.zoom, pow(1.25, 5), 0.001, "the contexts own the zoom")
	w._show_main()
	assert_gt(v.battle_area().size.x, fit.size.x * 3.0, "the field is drawn larger")
	# Once the field overflows the view, zooming keeps the point under the cursor.
	var m := v.to_battle(at)
	v.zoom_camera(1.25, at)
	w._show_main()
	assert_almost_eq(v.to_view(m).distance_to(at), 0.0, 0.5, "the point under the cursor stays put")
	assert_almost_eq(v.to_battle(v.to_view(Vector2(40, 30))).distance_to(Vector2(40, 30)), 0.0, 0.01)
	for _i in 30:
		v.zoom_camera(0.8, at)
	assert_eq(w.contexts.zoom, 1.0, "never smaller than the whole field")
	assert_eq(w.contexts.battle_centre, ViewContexts.NO_CENTRE)
	assert_eq(v.battle_area(), fit)


func test_panning_moves_a_zoomed_battle_and_stops_at_its_edge() -> void:
	var w := await _in_battle()
	var v := w._main
	v.pan_camera(Vector2(100, 0))
	assert_eq(w.contexts.zoom, 1.0, "a fitted field does not pan")
	v.zoom_camera(3.0, v.size / 2.0)
	w._show_main()
	var before := v.battle_area().position
	w.keys.actions[&"pan_right"].triggered.emit()
	assert_almost_eq(v.battle_area().position.x, before.x - WarRoom.PAN_STEP, 0.5, "the right arrow shows more to the right")
	for _i in 200:
		v.pan_camera(Vector2(100, 0))
	var area := v.battle_area()
	assert_almost_eq(area.end.x, v.size.x - 16.0, 0.5, "the field's edge stops at the view's")
	w.contexts.exit()
	assert_eq(w.contexts.zoom, 1.0)
	assert_eq(w.contexts.battle_centre, ViewContexts.NO_CENTRE, "leaving a battle resets its camera")


func _tap(keycode: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame  # GUIDE reads the key state once a frame
	await get_tree().process_frame
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func test_space_presses_a_focused_button_and_ends_the_turn_otherwise() -> void:
	var w := _demo()
	w.turn_seconds = 0.0
	var turns := [0]
	w.end_turn_requested.connect(func() -> void: turns[0] += 1)
	var pressed := [0]
	var other := Button.new()
	other.text = "Something else"
	other.pressed.connect(func() -> void: pressed[0] += 1)
	w.add_child(other)
	other.grab_focus()
	assert_eq(get_viewport().gui_get_focus_owner(), other)
	await _tap(KEY_SPACE)
	assert_eq(pressed[0], 1, "Space presses the focused button")
	assert_eq(turns[0], 0, "and does not end the turn")
	await _tap(KEY_ENTER)
	assert_eq(pressed[0], 2, "Enter presses a focused button")
	other.release_focus()
	await _tap(KEY_SPACE)
	assert_eq(turns[0], 1, "with no focus Space ends the turn")
