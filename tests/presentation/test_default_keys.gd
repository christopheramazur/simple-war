extends GutTest
## Each GUIDE context exposes its actions with the default keys (sw-ll4.9.2).


func _first_key(g: GuideKeys, name: StringName) -> GUIDEInputKey:
	return (g.keys[name] as Array)[0]


func test_war_room_context_actions_and_keys() -> void:
	var g := DefaultKeys.war_room()
	var want := {&"end_turn": KEY_SPACE, &"next_battle": KEY_TAB, &"cancel": KEY_ESCAPE, &"follow": KEY_F,
		&"next_player": KEY_V, &"deselect_all": KEY_BACKSPACE, &"pan_left": KEY_LEFT, &"pan_right": KEY_RIGHT,
		&"pan_up": KEY_UP, &"pan_down": KEY_DOWN, &"route_via": KEY_SHIFT}
	for name: StringName in want:
		assert_true(g.actions.has(name), "has %s" % name)
		assert_eq(_first_key(g, name).key, want[name], "default key of %s" % name)
		assert_true((g.actions[name] as GUIDEAction).is_remappable)
	assert_true(_first_key(g, &"previous_battle").shift, "Shift+Tab goes back")
	assert_eq(g.text_of(&"previous_battle"), "Shift+Tab")


func test_replay_context_actions_and_keys() -> void:
	var g := DefaultKeys.replay()
	assert_eq(g.actions.size(), 6)
	assert_eq(_first_key(g, &"replay_toggle").key, KEY_SPACE)
	assert_eq((g.keys[&"replay_faster"] as Array).size(), 2, "= and numpad +")
	assert_eq(_first_key(g, &"replay_restart").key, KEY_HOME)


func test_contexts_enable_with_the_scene_and_release_it() -> void:
	var node := Node.new()
	add_child_autofree(node)
	var g := DefaultKeys.war_room()
	var guide := get_tree().root.get_node_or_null(^"GUIDE")
	if guide == null:
		pass_test("no GUIDE autoload in this run")
		return
	g.enable(node)
	assert_true(guide.is_mapping_context_enabled(g.context))
	g.disable(node)
	assert_false(guide.is_mapping_context_enabled(g.context))


func test_controls_help_lists_the_bound_keys() -> void:
	var text := ""
	for part: Array in ControlsHelp.help():
		text += part[1]
	assert_string_contains(text, "Space: end the turn")
	assert_string_contains(text, "Shift+Tab")
	assert_string_contains(text, "Backspace: deselect")


func test_every_planning_order_action_has_a_tooltip() -> void:
	var p := PlanningInput.new()
	for id in OrderTips.ids():
		var a := OrderTips.action_of(id)
		if a != &"":
			assert_true(p.actions.has(a), "%s action exists" % id)
		for k in OrderTips.keys_of(id):
			assert_true(OrderTips.EN.has(k) and not String(OrderTips.EN[k]).is_empty(), "key %s has text" % k)
		assert_string_contains(OrderTips.tip(id, p), OrderTips.name_of(id))
	for a: StringName in [&"hold", &"attack_move", &"fall_back", &"withdraw", &"run", &"abilities"]:
		var found := false
		for o: Dictionary in OrderTips.ORDERS:
			found = found or o["action"] == a
		assert_true(found, "%s has an order tip" % a)
	assert_string_contains(OrderTips.tip("hold", p), "Key: H")
	assert_string_contains(OrderTips.tip("withdraw", p), "Shift+W")
	assert_string_contains(OrderTips.reaction_tip("halt"), "Hold")
	p.free()


## Every core action has a default gamepad mapping, all remappable GUIDE
## actions (sw-dqq). next_player is replay-only (a paddle button).
func test_every_core_action_has_a_pad_mapping() -> void:
	var g := DefaultKeys.war_room()
	for name: StringName in [&"end_turn", &"next_battle", &"previous_battle", &"focus_controls", &"cancel", &"follow",
			&"deselect_all", &"pan_left", &"pan_right", &"pan_up", &"pan_down", &"route_via", &"zoom_in", &"zoom_out",
			&"next_squad", &"previous_squad", &"inspect_squad", &"next_player"]:
		assert_gt((g.pads[name] as Array).size(), 0, "war room %s has a pad input" % name)
	var r := DefaultKeys.replay()
	for name: StringName in r.actions:
		assert_gt((r.pads[name] as Array).size(), 0, "replay %s has a pad input" % name)
	var p := PlanningInput.new()
	for name: StringName in [&"hold", &"attack_move", &"fall_back", &"withdraw", &"run", &"abilities"]:
		assert_gt((p.pad_names[name] as Array).size(), 0, "planning %s has a pad input" % name)
	p.free()


func test_pad_inputs_stay_out_of_key_text_and_are_device_neutral() -> void:
	var g := DefaultKeys.war_room()
	assert_eq(g.text_of(&"end_turn"), "Space")
	assert_eq(g.pad_text_of(&"end_turn"), "Start")
	assert_eq(g.pad_text_of(&"pan_left"), "Left stick left")
	assert_eq(g.pad_text_of(&"pan_down"), "Left stick down")
	var text := ""
	for part: Array in ControlsHelp.help():
		text += part[1]
	assert_string_contains(text, "Dpad right")
	assert_false(text.contains("Xbox") or text.contains("Cross"))


func test_stick_directions_are_limited_to_one_sign() -> void:
	var g := DefaultKeys.war_room()
	var seen := {}
	for m: GUIDEActionMapping in g.context.mappings:
		if m.action.name in [&"pan_left", &"pan_right"]:
			for im: GUIDEInputMapping in m.input_mappings:
				if im.input is GUIDEInputJoyAxis1D:
					assert_eq(im.modifiers.size(), 1)
					seen[m.action.name] = (im.modifiers[0] as GUIDEModifierPositiveNegative).range
	assert_eq(seen[&"pan_left"], GUIDEModifierPositiveNegative.LimitRange.NEGATIVE)
	assert_eq(seen[&"pan_right"], GUIDEModifierPositiveNegative.LimitRange.POSITIVE)
