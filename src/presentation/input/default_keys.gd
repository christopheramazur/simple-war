class_name DefaultKeys
extends RefCounted
## Default key sets of the war room and the replay viewer, as GUIDE
## contexts (sw-ll4.9.2), with default gamepad mappings (sw-dqq). Planning keys live in PlanningInput. Each caller
## builds its own instance and enables it while its scene is in the tree;
## ControlsHelp reads the same builders for display text.


static func war_room() -> GuideKeys:
	var g := GuideKeys.new("War room")
	g.bind(&"end_turn", "End turn / skip playback", [GuideKeys.key(KEY_SPACE, false, false, true), GuideKeys.pad(JOY_BUTTON_START)])
	g.bind(&"next_battle", "Next battle", [GuideKeys.key(KEY_TAB), GuideKeys.pad(JOY_BUTTON_RIGHT_SHOULDER)])
	g.bind(&"previous_battle", "Previous battle", [GuideKeys.key(KEY_TAB, false, true), GuideKeys.pad(JOY_BUTTON_LEFT_SHOULDER)])
	g.bind(&"focus_controls", "Focus the buttons (then Tab walks them)", [GuideKeys.key(KEY_F6, false, false, true), GuideKeys.pad(JOY_BUTTON_BACK)])
	g.bind(&"cancel", "Cancel / skip playback / leave battle", [GuideKeys.key(KEY_ESCAPE, false, false, true), GuideKeys.pad(JOY_BUTTON_B)])
	g.bind(&"follow", "Follow commander", [GuideKeys.key(KEY_F, false, false, true), GuideKeys.pad(JOY_BUTTON_Y)])
	g.bind(&"deselect_all", "Deselect everything", [GuideKeys.key(KEY_BACKSPACE, false, false, true), GuideKeys.pad(JOY_BUTTON_MISC1)])
	g.bind(&"pan_left", "Pan left", [GuideKeys.key(KEY_LEFT, false, false, true), GuideKeys.stick(JOY_AXIS_LEFT_X, false)], GuideKeys.PULSE)
	g.bind(&"pan_right", "Pan right", [GuideKeys.key(KEY_RIGHT, false, false, true), GuideKeys.stick(JOY_AXIS_LEFT_X, true)], GuideKeys.PULSE)
	g.bind(&"pan_up", "Pan up", [GuideKeys.key(KEY_UP, false, false, true), GuideKeys.stick(JOY_AXIS_LEFT_Y, false)], GuideKeys.PULSE)
	g.bind(&"pan_down", "Pan down", [GuideKeys.key(KEY_DOWN, false, false, true), GuideKeys.stick(JOY_AXIS_LEFT_Y, true)], GuideKeys.PULSE)
	g.bind(&"route_via", "Route via the planned route (hold)", [GuideKeys.key(KEY_SHIFT, false, false, true), GuideKeys.stick(JOY_AXIS_TRIGGER_LEFT, true)], GuideKeys.DOWN)
	g.bind(&"zoom_in", "Zoom in", [GuideKeys.key(KEY_PAGEUP, false, false, true), GuideKeys.stick(JOY_AXIS_RIGHT_Y, false)], GuideKeys.PULSE)
	g.bind(&"zoom_out", "Zoom out", [GuideKeys.key(KEY_PAGEDOWN, false, false, true), GuideKeys.stick(JOY_AXIS_RIGHT_Y, true)], GuideKeys.PULSE)
	g.bind(&"next_squad", "Select next own squad (battle)", [GuideKeys.key(KEY_BRACKETRIGHT, false, false, true), GuideKeys.pad(JOY_BUTTON_DPAD_RIGHT)])
	g.bind(&"previous_squad", "Select previous own squad (battle)", [GuideKeys.key(KEY_BRACKETLEFT, false, false, true), GuideKeys.pad(JOY_BUTTON_DPAD_LEFT)])
	g.bind(&"inspect_squad", "Show / hide the selected squad's card", [GuideKeys.key(KEY_I, false, false, true), GuideKeys.pad(JOY_BUTTON_A)])
	g.bind(&"next_player", "View next player (replay)", [GuideKeys.key(KEY_V, false, false, true), GuideKeys.pad(JOY_BUTTON_PADDLE1)])
	return g


static func replay() -> GuideKeys:
	var g := GuideKeys.new("Replay viewer")
	g.bind(&"replay_toggle", "Play / pause", [GuideKeys.key(KEY_SPACE, false, false, true), GuideKeys.pad(JOY_BUTTON_A)])
	g.bind(&"replay_faster", "Faster", [GuideKeys.key(KEY_EQUAL, false, false, true), GuideKeys.key(KEY_KP_ADD, false, false, true), GuideKeys.pad(JOY_BUTTON_DPAD_UP)])
	g.bind(&"replay_slower", "Slower", [GuideKeys.key(KEY_MINUS, false, false, true), GuideKeys.key(KEY_KP_SUBTRACT, false, false, true), GuideKeys.pad(JOY_BUTTON_DPAD_DOWN)])
	g.bind(&"replay_next_turn", "Next turn", [GuideKeys.key(KEY_RIGHT, false, false, true), GuideKeys.pad(JOY_BUTTON_DPAD_RIGHT)])
	g.bind(&"replay_prev_turn", "Previous turn", [GuideKeys.key(KEY_LEFT, false, false, true), GuideKeys.pad(JOY_BUTTON_DPAD_LEFT)])
	g.bind(&"replay_restart", "Restart", [GuideKeys.key(KEY_HOME, false, false, true), GuideKeys.pad(JOY_BUTTON_BACK)])
	return g
