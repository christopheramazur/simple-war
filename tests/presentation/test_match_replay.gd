extends GutTest
## Match replays (sw-ll4.22): a recorded match is played back turn by turn
## from its match log, reproduces every turn's hash, takes no orders, and
## can be watched from either side in the war room.


## Plays a short skirmish with the match log on. Returns [log folder, the
## played session].
func _record(turns: int = 3) -> Array:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 5)
	add_child_autofree(w)
	assert_not_null(w.match_log)
	var cid := -1
	for c: Dictionary in w.session.observe(1)["commanders"]:
		if c["player"] == 1:
			cid = c["id"]
	w.contexts.select_commander(cid)
	var reach: Dictionary = w.session.reach(1, cid)["reach"]
	assert_eq(w.route_to(reach.keys()[reach.size() - 1]), "")
	for i in turns:
		w.end_turn_requested.emit()
	return [w.match_log.dir, w.session]


func test_a_recording_replays_turn_by_turn_with_the_same_hashes() -> void:
	var made := _record()
	var played: OverworldSession = made[1]
	var r := MatchReplay.open(made[0])
	assert_not_null(r, MatchReplay.last_error)
	assert_eq(r.turns(), 3)
	assert_eq([r.info["map"], int(r.info["seed"]), r.info["opponent"]], ["skirmish_mirror", 5, "profile_utility"])
	assert_eq(r.session.turns_resolved(), 0, "it starts at turn 1")
	assert_false(r.at_end())
	# It takes no orders, readies or time from outside.
	var cid: int = r.session.state.commanders.ids()[0]
	assert_eq(r.session.set_route(1, cid, PackedInt64Array()), "this is a replay: it takes no orders")
	r.session.ready(1)
	r.session.ready(2)
	assert_eq(r.session.turns_resolved(), 0)
	for i in 3:
		assert_true(r.step())
		assert_eq(r.session.turns_resolved(), i + 1)
		assert_eq(r.session.turn_hashes[i], played.turn_hashes[i], "turn %d is the turn that was played" % (i + 1))
	assert_eq(r.diverged_turn, -1)
	assert_true(r.at_end())
	assert_false(r.step(), "nothing after the last recorded turn")
	assert_true(r.session.locked)
	# The list has it, newest first.
	var found := MatchReplay.list()
	assert_eq(found[0]["dir"], made[0])
	assert_eq([found[0]["map"], found[0]["seed"]], ["skirmish_mirror", 5])
	assert_null(MatchReplay.open("user://no_such_match"))
	assert_string_contains(MatchReplay.last_error, "no recording")


func test_the_war_room_watches_a_replay_from_either_side() -> void:
	var made := _record()
	var w := MainMenu.replay_room(made[0])
	assert_not_null(w, MatchReplay.last_error)
	add_child_autofree(w)
	assert_null(w.match_log, "a replay is not recorded again")
	assert_eq(w._end_button.text, "Next turn (Space)")
	assert_string_contains(w.hints(), "Replay, watching as player 1 (turn 1 of 3)")
	w.end_turn_requested.emit()
	assert_eq(w.session.turns_resolved(), 1)
	assert_eq(w.driver.stats["turns"], 1, "the tallies follow the replay")
	# Orders are refused, and it can't be saved as a game.
	var cid := -1
	for c: Dictionary in w.session.observe(1)["commanders"]:
		if c["player"] == 1:
			cid = c["id"]
	w.contexts.select_commander(cid)
	var reach: Dictionary = w.session.reach(1, cid)["reach"]
	assert_eq(w.route_to(reach.keys()[0]), "this is a replay: it takes no orders")
	assert_eq(w.save_game(), "")
	# The other side: its own fog and commanders.
	w.view_next_player()
	assert_eq(w.player, 2)
	assert_string_contains(w.hints(), "watching as player 2")
	await get_tree().process_frame
	var own: Array = w.session.observe(2)["commanders"].filter(func(c: Dictionary) -> bool: return c["player"] == 2)
	assert_eq(w.contexts.camera_plot, own[0]["plot"], "the view starts on that player's commander")
	# Playing all runs to the end of the recording and stops.
	w.auto_play = true
	w.end_turn_requested.emit()
	w.end_turn_requested.emit()
	assert_eq(w.session.turns_resolved(), 3)
	w.end_turn_requested.emit()
	assert_eq(w.session.turns_resolved(), 3)
	assert_false(w.auto_play)
	assert_string_contains(w.hints(), "the recording has ended")


func test_the_main_menu_lists_replays() -> void:
	var made := _record(1)
	var m: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	add_child_autofree(m)
	assert_not_null(m.find_child("Replays", true, false))
	var over := m.open_replays()
	var first: Button = over.find_child("List", true, false).get_child(0)
	assert_string_contains(first.text, "seed 5 vs Utility")
	assert_true(String(made[0]).begins_with(MatchLog.root_dir()))
