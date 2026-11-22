class_name DefaultKeys
extends RefCounted
## Default key sets of the war room and the replay viewer, as GUIDE
## contexts (sw-ll4.9.2). Planning keys live in PlanningInput. Each caller
## builds its own instance and enables it while its scene is in the tree;
## ControlsHelp reads the same builders for display text.


static func war_room() -> GuideKeys:
	var g := GuideKeys.new("War room")
	g.bind(&"end_turn", "End turn / skip playback", [GuideKeys.key(KEY_SPACE, false, false, true)])
	g.bind(&"next_battle", "Next battle", [GuideKeys.key(KEY_TAB)])
	g.bind(&"previous_battle", "Previous battle", [GuideKeys.key(KEY_TAB, false, true)])
	g.bind(&"focus_controls", "Focus the buttons (then Tab walks them)", [GuideKeys.key(KEY_F6, false, false, true)])
	g.bind(&"cancel", "Cancel / skip playback / leave battle", [GuideKeys.key(KEY_ESCAPE, false, false, true)])
	g.bind(&"follow", "Follow commander", [GuideKeys.key(KEY_F, false, false, true)])
	g.bind(&"next_player", "View next player (replay)", [GuideKeys.key(KEY_V, false, false, true)])
	g.bind(&"deselect_all", "Deselect everything", [GuideKeys.key(KEY_BACKSPACE, false, false, true)])
	g.bind(&"pan_left", "Pan left", [GuideKeys.key(KEY_LEFT, false, false, true)], GuideKeys.PULSE)
	g.bind(&"pan_right", "Pan right", [GuideKeys.key(KEY_RIGHT, false, false, true)], GuideKeys.PULSE)
	g.bind(&"pan_up", "Pan up", [GuideKeys.key(KEY_UP, false, false, true)], GuideKeys.PULSE)
	g.bind(&"pan_down", "Pan down", [GuideKeys.key(KEY_DOWN, false, false, true)], GuideKeys.PULSE)
	g.bind(&"route_via", "Route via the planned route (hold)", [GuideKeys.key(KEY_SHIFT, false, false, true)], GuideKeys.DOWN)
	return g


static func replay() -> GuideKeys:
	var g := GuideKeys.new("Replay viewer")
	g.bind(&"replay_toggle", "Play / pause", [GuideKeys.key(KEY_SPACE, false, false, true)])
	g.bind(&"replay_faster", "Faster", [GuideKeys.key(KEY_EQUAL, false, false, true), GuideKeys.key(KEY_KP_ADD, false, false, true)])
	g.bind(&"replay_slower", "Slower", [GuideKeys.key(KEY_MINUS, false, false, true), GuideKeys.key(KEY_KP_SUBTRACT, false, false, true)])
	g.bind(&"replay_next_turn", "Next turn", [GuideKeys.key(KEY_RIGHT, false, false, true)])
	g.bind(&"replay_prev_turn", "Previous turn", [GuideKeys.key(KEY_LEFT, false, false, true)])
	g.bind(&"replay_restart", "Restart", [GuideKeys.key(KEY_HOME, false, false, true)])
	return g
