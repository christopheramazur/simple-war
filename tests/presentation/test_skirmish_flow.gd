extends GutTest
## The skirmish flow (sw-ll4.11): saving and loading a game, the autosave,
## the load list on the main menu, and the results screen. Also sw-007:
## a save taken mid-planning, after orders that push events at once.

const SAVES := "user://test_saves"


func before_each() -> void:
	_wipe()
	MatchDriver.save_dir = SAVES


func after_all() -> void:
	_wipe()
	MatchDriver.save_dir = "user://saves"


func _wipe() -> void:
	var d := DirAccess.open(SAVES)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(SAVES)


func _room(profile: String = "profile_utility") -> WarRoom:
	var w := MainMenu.skirmish_room(profile, "skirmish_mirror", 3)
	w.record_match = false
	add_child_autofree(w)
	return w


func _own(s: OverworldSession) -> Dictionary:
	for c: Dictionary in s.observe(1)["commanders"]:
		if c["player"] == 1:
			return c
	return {}


func test_a_game_saved_mid_planning_loads_and_continues_identically() -> void:
	var s := MatchDriver.play_session("skirmish_mirror", 3)
	var d := MatchDriver.new(s, 1)
	d.meta = {"map": "skirmish_mirror", "seed": 3, "profile": "", "human": 1}
	d.end_turn()
	var me := _own(s)
	var cid: int = me["id"]
	# An order that pushes an event at once (sw-007): picking up a squad.
	var did := s.state.detachments.spawn({&"player": 1, &"plot": me["plot"]})
	var sq := s.state.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": s.rules.squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	assert_eq(s.transfer_squad(1, sq, cid), "")
	assert_gt(s.state.events.size(), 0, "its event waits for the turn to resolve")
	var to: int = (s.reach(1, cid)["reach"] as Dictionary).keys()[0]
	assert_eq(s.set_route(1, cid, s.path(1, cid, to)), "")
	var path := d.save_game("mid")
	assert_eq(path, SAVES + "/mid.sav", MatchDriver.last_error)
	var back := MatchDriver.load_game(path)
	assert_not_null(back, MatchDriver.last_error)
	assert_eq(back.session.state_hash_hex(), s.state_hash_hex())
	assert_eq(back.session.state.events.size(), s.state.events.size(), "the waiting events came back")
	assert_eq(back.session.state.routes[cid], s.state.routes[cid])
	assert_eq([back.human, back.meta["map"], back.meta["seed"]], [1, "skirmish_mirror", 3])
	d.end_turn()
	back.end_turn()
	assert_eq(back.session.turns_resolved(), s.turns_resolved())
	assert_eq(back.session.state_hash_hex(), s.state_hash_hex(), "and the next turn resolves the same")
	assert_eq(back.session.last_events.map(func(e: SimEvent) -> StringName: return e.type),
		s.last_events.map(func(e: SimEvent) -> StringName: return e.type))


func test_saves_are_listed_newest_first_and_bad_files_are_left_out() -> void:
	assert_eq(MatchDriver.saves(), [] as Array[Dictionary])
	var d := MatchDriver.new(MatchDriver.play_session("skirmish_mirror", 3), 1)
	d.meta = {"map": "skirmish_mirror", "seed": 3, "profile": "profile_turtle", "human": 1}
	assert_ne(d.save_game("first"), "")
	assert_ne(d.save_game(), "", "a slot named from the map and the time")
	var junk := FileAccess.open(SAVES + "/junk.sav", FileAccess.WRITE)
	junk.store_string("not a save")
	junk.close()
	var found := MatchDriver.saves()
	assert_eq(found.size(), 2)
	for sv in found:
		assert_eq([sv["map"], sv["turn"], sv["profile"]], ["skirmish_mirror", 1, "profile_turtle"])
	assert_true(found.any(func(sv: Dictionary) -> bool: return sv["slot"] == "first"))
	assert_null(MatchDriver.load_game(SAVES + "/junk.sav"))
	assert_eq(MatchDriver.last_error, "unreadable save")
	assert_null(MatchDriver.load_game(SAVES + "/missing.sav"))


func test_a_loaded_game_plays_on_with_the_same_opponent_and_autosaves() -> void:
	var w := _room("profile_turtle")
	w.end_turn_requested.emit()
	var path := w.save_game()
	assert_ne(path, "")
	assert_string_contains(w._hud_note, "saved as skirmish_mirror-turn2-")
	var turn := w.session.turns_resolved()
	var loaded := MainMenu.load_room(path)
	assert_not_null(loaded, MatchDriver.last_error)
	loaded.record_match = false
	loaded.autosave = true
	add_child_autofree(loaded)
	assert_eq(loaded.session.state_hash_hex(), w.session.state_hash_hex())
	assert_eq(loaded.ai.keys(), [2])
	assert_eq(String(loaded.ai[2].profile.get("name", "")), "Turtle", "the saved opponent plays on")
	assert_eq(loaded.driver.stats["turns"], turn, "the tallies came with it")
	assert_null(loaded.match_log)
	loaded.end_turn_requested.emit()
	assert_eq(loaded.session.turns_resolved(), turn + 1)
	var auto := MatchDriver.saves().filter(func(sv: Dictionary) -> bool: return sv["slot"] == MatchDriver.AUTOSAVE)
	assert_eq(auto.size(), 1)
	assert_eq(auto[0]["turn"], turn + 2, "saved at the start of the next turn")
	assert_false(MatchDriver.saves().is_empty())


func test_the_main_menu_lists_saved_games() -> void:
	var m: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	add_child_autofree(m)
	assert_not_null(m.find_child("Load", true, false))
	var empty := m.open_saves()
	assert_true((empty.find_child("List", true, false).get_child(0) as Label).text.begins_with("No saved games yet"))
	empty.free()
	var d := MatchDriver.new(MatchDriver.play_session("skirmish_mirror", 3), 1)
	d.meta = {"map": "skirmish_mirror", "seed": 3, "profile": "profile_turtle", "human": 1}
	d.save_game(MatchDriver.AUTOSAVE)
	var over := m.open_saves()
	var list := over.find_child("List", true, false)
	assert_eq(list.get_child_count(), 1)
	var text: String = (list.get_child(0).get_child(0) as Button).text
	assert_string_contains(text, "Autosave")
	assert_string_contains(text, "turn 1 vs Turtle")


func test_saves_can_be_renamed_and_deleted() -> void:
	var d := MatchDriver.new(MatchDriver.play_session("skirmish_mirror", 3), 1)
	d.meta = {"map": "skirmish_mirror", "seed": 3, "profile": "profile_turtle", "human": 1}
	var a := d.save_game("first")
	var b := d.save_game("second")
	assert_eq(MatchDriver.rename_save(a, "second"), "", "a taken name is refused")
	assert_eq(MatchDriver.rename_save(a, "  fresh  "), SAVES + "/fresh.sav")
	assert_false(FileAccess.file_exists(a))
	assert_false(MatchDriver.delete_save(SAVES + "/../escape.sav"))
	assert_true(MatchDriver.delete_save(b))
	assert_eq(MatchDriver.saves().map(func(x: Dictionary) -> String: return x["slot"]), ["fresh"])


func test_the_ai_memory_is_saved_so_a_loaded_game_plays_on_the_same() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := MatchDriver.play_session("skirmish_mirror", 3)
	var d := MatchDriver.new(s, 1)
	d.meta = {"map": "skirmish_mirror", "seed": 3, "profile": "profile_utility", "human": 1}
	d.ai = MatchDriver.opponents(s, 1, "profile_utility", 3)
	for i in 3:
		d.end_turn()
	var pc: ProfileController = d.ai[2]
	pc._rng.next_u32()
	pc.fault = "crash"
	var back := MatchDriver.load_game(d.save_game("mem"))
	var bc: ProfileController = back.ai[2]
	assert_eq(bc._rng.get_state(), pc._rng.get_state(), "the random stream carries on")
	assert_eq(bc.fault, "crash")
	assert_eq(back._ai_step, d._ai_step)
	for i in 3:
		d.end_turn()
		back.end_turn()
	assert_eq(back.session.state_hash_hex(), d.session.state_hash_hex())
	assert_not_null(l)


func test_the_results_screen_opens_when_the_match_ends() -> void:
	var w := _room()
	var guard := 0
	while w.session.state.outcome.is_empty() and guard < 40:
		guard += 1
		w.end_turn_requested.emit()
	assert_false(w.session.state.outcome.is_empty(), "the AI beats an idle player")
	assert_null(w.results)
	await get_tree().process_frame
	assert_not_null(w.results, "the results open once the end is shown")
	assert_eq((w.results.find_child("Title", true, false) as Label).text, "Defeat")
	assert_ne((w.results.find_child("Reason", true, false) as Label).text, "")
	var stats: Dictionary = w.driver.stats
	assert_eq(stats["turns"], w.session.turns_resolved())
	assert_gt(int(stats["battles"]), 0)
	assert_gt(int(stats["players"][1]["squads_lost"]) + int(stats["players"][1]["commanders_lost"]), 0)
	var grid := w.results.find_child("Stats", true, false)
	assert_eq(grid.get_child_count(), 4 * (1 + (stats["players"] as Dictionary).size()))
	assert_not_null(w.results.find_child("Again", true, false), "the same map, seed and opponent can be played again")
	assert_not_null(w.results.find_child("Menu", true, false))
	# Looking at the map closes it, and it does not come back.
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), w.results.find_child("Look", true, false), "Space doesn't start a new game")
	(w.results.find_child("Look", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	w._queue_refresh()
	await get_tree().process_frame
	assert_false(is_instance_valid(w.results) and w.results.is_inside_tree())
