extends GutTest
## Windows and their root (sw-ijp.2): layers, Esc, focus, keys held back
## under a modal, and windows shown only in their view contexts.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const SETTINGS := "user://test_settings_windows.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


func _esc() -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.pressed = true
	return k


func _screen() -> Control:
	var s := Control.new()
	s.size = Vector2(800, 600)
	add_child_autofree(s)
	return s


func _modal(window_id: StringName) -> UiWindow:
	var w := UiWindow.new()
	w.id = window_id
	var b := Button.new()
	b.name = "Ok"
	w.dialog(200).add_child(b)
	return w


func test_a_root_stacks_windows_on_layers() -> void:
	var ui := UiRoot.of(_screen())
	var hud := UiWindow.new()
	hud.layer = UiWindow.Layer.HUD
	ui.open(hud)
	var a := ui.open(_modal(&"a"))
	var b := ui.open(_modal(&"b"))
	assert_eq(hud.get_parent().get_index(), 0, "the HUD is under everything")
	assert_eq(a.get_parent(), b.get_parent())
	assert_gt(b.get_index(), a.get_index(), "the newest modal is on top")
	assert_eq(ui.top(), b)
	assert_eq(ui.find(&"a"), a)
	assert_eq(UiRoot.of(a), ui, "a window finds the root that owns it")


func test_esc_closes_the_top_modal_only() -> void:
	var ui := UiRoot.of(_screen())
	var a := ui.open(_modal(&"a"))
	var b := ui.open(_modal(&"b"))
	ui._unhandled_input(_esc())
	assert_true(b.is_queued_for_deletion())
	assert_false(a.is_queued_for_deletion())
	assert_eq(ui.top(), a)
	ui._unhandled_input(_esc())
	assert_null(ui.top())


func test_toggle_opens_then_closes() -> void:
	var ui := UiRoot.of(_screen())
	var made := ui.toggle(&"help", _modal.bind(&"help"))
	assert_not_null(made)
	assert_null(ui.toggle(&"help", _modal.bind(&"help")))
	assert_null(ui.find(&"help"))


func test_a_modal_takes_focus_and_gives_it_back() -> void:
	var s := _screen()
	var before := Button.new()
	s.add_child(before)
	before.grab_focus()
	var ui := UiRoot.of(s)
	var w := ui.open(_modal(&"a"))
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), w.find_child("Ok", true, false))
	w.close()
	assert_eq(get_viewport().gui_get_focus_owner(), before)


func test_windows_follow_the_view_context() -> void:
	var ui := UiRoot.of(_screen())
	var card := UiWindow.new()
	card.layer = UiWindow.Layer.HUD
	card.contexts = PackedStringArray(["overworld"])
	ui.open(card)
	ui.context = &"battle"
	assert_false(card.visible)
	ui.context = &"overworld"
	assert_true(card.visible)
	card.wanted = false
	assert_false(card.visible, "its owner can still hide it")


func test_the_war_room_owns_its_windows() -> void:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	assert_eq(w.get_child(w.get_child_count() - 1), w.ui, "drawn last, hears keys first")
	assert_eq(w.ui.context, &"overworld")
	assert_false(w._blocker.visible, "the playback blocker waits for a turn to play")
	w.toggle_help()
	assert_not_null(w.ui.find(&"help"))
	assert_false(w.ui.find(&"help").captures_keys, "the controls list leaves Space to the game")
	w.ui._unhandled_input(_esc())
	assert_null(w.ui.find(&"help"), "Esc closes it")
	var o := OptionsScreen.open_over(w)
	assert_eq(UiRoot.of(o), w.ui)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var turns := [0]
	w.end_turn_requested.connect(func() -> void: turns[0] += 1)
	Input.parse_input_event(space)
	await get_tree().process_frame
	assert_eq(turns[0], 0, "keys don't reach the war room under the options")
	o.close()
	assert_true(w.contexts.tab_in())
	w._refresh()
	assert_eq(w.ui.context, &"battle")


## A modal whose body is taller than any small viewport, with a Close at the
## bottom (the options-screen shape that clipped at 200%, sw-opt).
func _tall_modal(window_id: StringName) -> UiWindow:
	var w := UiWindow.new()
	w.id = window_id
	var col := w.dialog(300)
	var title := Label.new()
	title.text = "Tall"
	col.add_child(title)
	for i in 24:
		var row := Label.new()
		row.text = "Row %d" % i
		row.custom_minimum_size = Vector2(0, 24)
		col.add_child(row)
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	col.add_child(close)
	return w


## The dialog body scrolls on one axis inside a viewport-bound region and the
## Close button stays reachable at the bottom (XAG 101, sw-opt).
func _assert_dialog_fits(size: Vector2) -> void:
	var s := Control.new()
	s.size = size
	add_child_autofree(s)
	var ui := UiRoot.of(s)
	var w := ui.open(_tall_modal(&"tall"))
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := w.find_child("Scroll", true, false) as ScrollContainer
	assert_not_null(scroll, "the dialog body is wrapped in a scroll")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "no horizontal / two-axis scroll")
	assert_eq(scroll.focus_mode, Control.FOCUS_NONE, "the scroll traps no focus")
	assert_true(scroll.size.y <= size.y + 0.5, "the scroll region is bounded by the viewport height")
	var v := scroll.get_v_scroll_bar()
	assert_gt(v.max_value, 0.0, "the tall body overflows and can scroll")
	scroll.scroll_vertical = int(v.max_value)
	await get_tree().process_frame
	var close := w.find_child("Close", true, false) as Button
	var cr := close.get_global_rect()
	var sr := s.get_global_rect()
	assert_true(cr.position.y >= sr.position.y - 0.5 and cr.end.y <= sr.end.y + 0.5,
		"Close is reachable on-screen at the bottom of the scroll")


func test_dialog_scrolls_and_close_reachable_at_640x400() -> void:
	await _assert_dialog_fits(Vector2(640, 400))


func test_dialog_scrolls_and_close_reachable_at_640x360() -> void:
	await _assert_dialog_fits(Vector2(640, 360))


func test_controls_help_fits_a_small_viewport() -> void:
	var s := Control.new()
	s.size = Vector2(640, 400)
	add_child_autofree(s)
	var ui := UiRoot.of(s)
	var w := ui.open(ControlsHelp.window())
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := w.find_child("Scroll", true, false) as ScrollContainer
	assert_not_null(scroll, "the help list scrolls when it is taller than the window")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "help never scrolls two axes")
	var centre := scroll.get_child(0) as CenterContainer
	var panel := centre.get_child(0) as PanelContainer
	assert_true(centre.size.x <= s.size.x + 0.5 and panel.size.x <= s.size.x + 0.5,
		"the help body is capped to the viewport width and wraps, never clips")


func test_sizes_include_the_deck_native_1280x800() -> void:
	assert_true(GameSettings.SIZES.has(Vector2i(1280, 800)), "SIZES offers the Deck native size")
	assert_true(GameSettings.sizes_for(Vector2i(1280, 800)).has(Vector2i(1280, 800)),
		"windowed mode can pick 1280x800 on a Deck screen")


func test_telemetry_opt_in_defaults_off_and_saves() -> void:
	assert_false(bool(GameSettings.value("telemetry_opt_in")), "off until the player opts in")
	var o := OptionsScreen.open_over(_screen())
	var box := o.find_child("Telemetry", true, false) as CheckBox
	assert_not_null(box)
	box.button_pressed = true
	assert_true(bool(GameSettings.value("telemetry_opt_in")))
	o.close()
