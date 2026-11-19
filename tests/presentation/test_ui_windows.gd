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
