extends GutTest
## Overworld playback (sw-bafi.9, U1 C8): the camera and every information
## view work while a turn plays out on the overworld; planning and activity
## controls are disabled with the reason, and their actions change nothing.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const SETTINGS := "user://test_settings_owp.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


## The demo room with a resolved turn playing back on the overworld.
func _playing_overworld() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	w.turn_seconds = 5.0
	var turn := w.session.turns_resolved()
	var guard := 0
	while w.session.turns_resolved() == turn and guard < 4:
		guard += 1
		w.end_turn_requested.emit()
	assert_true(w.playing(), "the room plays the resolved turn back")
	assert_eq(w.contexts.focus, ViewContexts.OVERWORLD, "on the overworld")
	return w


## The player's first commander not in a battle, as observed now.
func _own_commander(w: WarRoom) -> Dictionary:
	for c: Dictionary in w.session.observe(1)["commanders"]:
		if c["player"] == 1 and c["engagement"] < 0:
			return c
	return {}


func _buttons(node: Node, out: Array[BaseButton] = []) -> Array[BaseButton]:
	for c in node.get_children():
		if c is BaseButton:
			out.append(c)
		_buttons(c, out)
	return out


## The session's state as the player sees it: a refused action leaves it as is.
func _snapshot(w: WarRoom) -> String:
	return var_to_str(w.session.observe(1))


func test_the_map_and_side_lists_are_open_but_the_footer_is_not() -> void:
	var w := _playing_overworld()
	await get_tree().process_frame
	var inv := w._blocker.get_global_transform().affine_inverse()
	var stage: Control = w.layout.regions["stage"]
	assert_false(w._blocker._has_point(inv * stage.get_global_rect().get_center()), "the overworld stage is open")
	assert_not_null(w._side_scroll, "the side column's list is found")
	assert_false(w._blocker._has_point(inv * w._side_scroll.get_global_rect().get_center()), "the side lists are open")
	assert_true(w._blocker._has_point(inv * w._end_button.get_global_rect().get_center()), "the footer stays covered")
	assert_string_contains(w.hints(), "Available in Planning")


func test_the_camera_zooms_and_follows_during_overworld_playback() -> void:
	var w := _playing_overworld()
	await get_tree().process_frame
	var z0 := w.contexts.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = w._main.size / 2.0
	w._main._gui_input(wheel)
	assert_lt(w.contexts.zoom, z0, "the wheel zooms the overworld camera")
	w.keys.actions[&"zoom_out"].triggered.emit()
	assert_lt(w.contexts.zoom, z0 * 0.8 + 0.0001, "the zoom key works too")
	var cmd := _own_commander(w)
	assert_false(cmd.is_empty())
	w.contexts.select_commander(cmd["id"])
	w.keys.actions[&"follow"].triggered.emit()
	assert_eq(w.contexts.followed, int(cmd["id"]), "follow works")
	assert_eq(w.contexts.camera_plot, int(cmd["plot"]), "and centres the camera on it")
	assert_true(w.playing(), "none of it ends the playback")


func test_hovering_a_hex_shows_its_card_during_playback() -> void:
	var w := _playing_overworld()
	await get_tree().process_frame
	var cmd := _own_commander(w)
	w._on_hex_hovered(int(cmd["plot"]))
	assert_true(w._hover_win.wanted, "the hex card is wanted")
	assert_true(w._hover_win.visible, "and shows in the playback context")
	assert_gt(w._hover_card.get_child_count(), 0, "with the hex's card in it")
	assert_true(w.playing())


func test_a_click_selects_to_inspect_with_the_actions_disabled() -> void:
	var w := _playing_overworld()
	var cmd := _own_commander(w)
	var before := _snapshot(w)
	w._on_hex_clicked(int(cmd["plot"]), MOUSE_BUTTON_LEFT)
	assert_eq(w.contexts.selected, int(cmd["id"]), "a left click selects the commander to inspect it")
	await get_tree().process_frame
	var buttons := _buttons(w._commander_box)
	assert_gt(buttons.size(), 0, "the commander panel shows its controls")
	for b: BaseButton in buttons:
		assert_true(b.disabled, "%s is disabled" % b.name)
		assert_eq(b.tooltip_text, "Available in Planning", "with the reason")
	assert_eq(_snapshot(w), before, "selecting changed nothing in the session")
	assert_true(w.playing())
	# In Planning the same controls work again.
	w.skip_playback()
	await get_tree().process_frame
	var enabled := _buttons(w._commander_box).filter(func(b: BaseButton) -> bool: return not b.disabled)
	assert_gt(enabled.size(), 0, "the controls are enabled in Planning")


func test_every_planning_action_is_refused_and_changes_nothing() -> void:
	var w := _playing_overworld()
	var cmd := _own_commander(w)
	w._on_hex_clicked(int(cmd["plot"]), MOUSE_BUTTON_LEFT)
	var cid := int(cmd["id"])
	var before := _snapshot(w)
	var note := "Available in Planning"
	var far := int(cmd["plot"]) + 1
	# A right click would route the commander.
	w._on_hex_clicked(far, MOUSE_BUTTON_RIGHT)
	assert_eq(w._hud_note, note, "a right click says why")
	assert_eq(w.route_to(far), note, "routes")
	assert_eq(w.clear_route(), note, "route clearing")
	assert_eq(w.set_battleforce(OverworldBattleforce.NONE, false), note, "battleforce")
	assert_eq(w.set_activity("refit"), note, "activities (purchases, production, hiring)")
	assert_eq(w.rally(cid, far, -1, "x"), note, "rally changes")
	assert_eq(w.supply_line(cid, far, -1, "x"), note, "supply lines")
	assert_eq(w.pick_up(cid), note, "pick-ups")
	assert_eq(w.steer_to(far), note, "convoy routes")
	assert_eq(w.halt_detachment(), note, "convoy halts")
	assert_eq(w.send_reserve(cid, 0), note, "reinforcements")
	w.arm_target("rally", cid, "x")
	assert_true(w._target.is_empty(), "send-to does not arm")
	# The panel's signals (its buttons) land on the same refusals.
	w._commander_box.battleforce_chosen.emit(OverworldBattleforce.NONE, false)
	w._commander_box.activity_requested.emit("refit", "")
	w._commander_box.route_clear_requested.emit()
	w._commander_box.target_armed.emit("line", cid, "x")
	assert_true(w._target.is_empty())
	assert_eq(_snapshot(w), before, "no draft changed and nothing was submitted")
	await get_tree().process_frame
	assert_true(w._hud.text.contains(note), "the status line shows the reason")
	assert_true(w.playing(), "none of them skipped the playback")
	w.skip_playback()
	assert_eq(w._hud_note, "", "the refusal does not linger into Planning")
