extends GutTest
## The main menu and skirmish against an AI profile (sw-ip8.6): the menu lists
## the core controller profiles and the skirmish maps (the factory's first),
## and a skirmish war room plays player 2 with ProfileController.


func _menu() -> MainMenu:
	var m: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	add_child_autofree(m)
	return m


func _skirmish(profile: String = "profile_utility", seed_value: int = 3) -> WarRoom:
	var w := MainMenu.skirmish_room(profile, MainMenu.FACTORY_MAP, seed_value)
	add_child_autofree(w)
	return w


func test_menu_lists_profiles_and_skirmish_maps() -> void:
	var m := _menu()
	assert_eq(m.profiles[0], "profile_utility")
	assert_true(m.profiles.has("profile_aggressor") and m.profiles.has("profile_turtle"), str(m.profiles))
	assert_eq(m.maps[0], MainMenu.FACTORY_MAP)
	assert_true(m.maps.has("skirmish_mirror"), str(m.maps))
	assert_false(m.maps.has("angelfall_frontier"), "story maps are not skirmish maps")


func test_skirmish_room_plays_the_profile_as_player_two() -> void:
	var w := _skirmish("profile_turtle")
	assert_eq(w.session.map_id, MainMenu.FACTORY_MAP)
	assert_eq(w.ai.keys(), [2])
	assert_true(w.ai[2] is ProfileController)
	assert_eq(String(w.ai[2].profile.get("name", "")), "Turtle")


func test_the_ai_takes_its_turns() -> void:
	var w := _skirmish()
	var cmds := w.session.state.commanders
	var theirs: Array = Array(cmds.ids()).filter(func(c: int) -> bool: return cmds.get_value(c, &"player") == 2)
	assert_eq(theirs.size(), 1)
	var start: int = cmds.get_value(theirs[0], &"plot")
	for i in 4:
		w.end_turn_requested.emit()
	assert_eq(w.session.turns_resolved(), 4)
	assert_ne(cmds.get_value(theirs[0], &"plot"), start, "the AI commander moved")


func test_a_skirmish_ends_with_a_banner() -> void:
	var w := _skirmish()
	w.session.state.outcome = {"outcome": "lost", "winner": 2, "key": "", "text": "Player 2 wins.", "turn": 5}
	w._refresh()
	assert_true(w._banner.visible)
	assert_string_contains(w._banner_text.text, "Defeat")
	var turns := w.session.turns_resolved()
	w._ai_act()
	assert_eq(w.session.turns_resolved(), turns)


func test_the_ai_hunts_down_an_idle_player_on_the_mirror_map() -> void:
	await _hunt("skirmish_mirror")


func test_the_ai_hunts_down_an_idle_player_on_the_factory_map() -> void:
	await _hunt(MainMenu.FACTORY_MAP)  # seed 3 stalled before sw-884.14


## Needs multi-turn routes and the search fallback (UtilityOverworld), and
## for the factory map whole-army estimates with reinforcements (sw-884.14).
func _hunt(map: String) -> void:
	var w := MainMenu.skirmish_room("profile_utility", map, 3)
	add_child_autofree(w)
	var guard := 0
	var reinforced := 0
	while w.session.state.outcome.is_empty() and guard < 40:
		guard += 1
		w.end_turn_requested.emit()
		for e: Dictionary in w.session.observe(2).get("events", []):
			if e["type"] == &"squad_reinforced" and int((e["data"] if e.has("data") else e).get("player", 0)) == 2:
				reinforced += 1
	assert_eq(int(w.session.state.outcome.get("winner", 0)), 2, str(w.session.state.outcome))
	assert_gt(reinforced, 0, "the AI sent its reserves into the battle")


func test_reinforcements_are_spare_squads_strongest_first() -> void:
	var s := WarRoom.demo_session()
	var obs := s.observe(1)
	var out := ProfileController.new(1, {}).reinforcements(obs, s.rules)
	var spare := {}
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) == 1 and int(c["engagement"]) >= 0:
			var fighting := {}
			for id: int in c.get("battleforce", []):
				fighting[id] = true
			for q: Dictionary in c.get("army", []):
				if not bool(q["own"]) and not fighting.has(int(q["id"])) and int(q["alive"]) > 0:
					spare[int(q["id"])] = SimCriteria.squads_value(s.rules, [q])
	assert_eq(out.size(), spare.size())
	for i in range(1, out.size()):
		if out[i]["commander"] == out[i - 1]["commander"]:
			assert_true(spare[out[i - 1]["squad"]] >= spare[out[i]["squad"]], "strongest first")
	var idle := ProfileController.new(1, {"battle": {"process": "idle"}})
	assert_eq(idle.reinforcements(obs, s.rules), [])
