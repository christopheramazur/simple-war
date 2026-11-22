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
