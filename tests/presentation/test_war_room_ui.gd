extends GutTest
## The war room UI pass (sw-ll4.19): what a battle observation carries for
## drawing squads, the squad card, turn playback, overworld move range and
## waypoints, sending garrisons and convoys, and the options screen.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const SETTINGS := "user://test_settings.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


## The demo room: player 1 in two battles.
func _demo() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	return w


func _skirmish() -> WarRoom:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
	w.record_match = false
	add_child_autofree(w)
	return w


func _own_commander(w: WarRoom) -> Dictionary:
	for c: Dictionary in w.session.observe(1)["commanders"]:
		if c["player"] == 1 and c["engagement"] < 0:
			return c
	return {}


func _texts(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_texts(c, out)
	return out


func test_a_battle_observation_says_how_to_draw_a_squad() -> void:
	var w := _demo()
	assert_true(w.contexts.tab_in())
	var eid := w.contexts.focus
	var obs := w.session.observe_battle(1, eid)
	var mine: Array = obs["squads"].filter(func(q: Dictionary) -> bool: return q["player"] == 1)
	assert_gt(mine.size(), 0)
	var sq: Dictionary = mine[0]
	assert_eq(sq["name"], "Rifle squad")
	assert_eq([sq["alive"], sq["size"]], [8, 8])
	assert_eq(sq["range"], 40 * Fixed.ONE, "its longest weapon")
	assert_gt(sq["sight"], 0)
	assert_true(sq.has("facing"))
	var units: Array = obs["units"].filter(func(u: Dictionary) -> bool: return u["squad"] == sq["id"])
	assert_eq(units.size(), 8, "every unit has a position to draw")


func test_the_squad_card_shows_strength_weapons_and_range() -> void:
	var w := _demo()
	w.contexts.tab_in()
	var eid := w.contexts.focus
	var sq: Dictionary = w.session.observe_battle(1, eid)["squads"][0]
	var insp := w.session.inspect_battle(1, eid, sq["id"])
	assert_eq(insp["units"].size(), 8)
	assert_eq(w.session.inspect_battle(2, eid, sq["id"]), {}, "not for a player who is not in the battle")
	var card := SquadCard.build(sq, insp, 1)
	autofree(card)
	var text := "\n".join(_texts(card))
	assert_string_contains(text, "Rifle squad")
	assert_string_contains(text, "8 / 8 units  ·  yours")
	assert_string_contains(text, "Weapon range 40 m")
	assert_string_contains(text, "60% to hit")
	assert_string_contains(text, "7 × Trooper")
	# Clicking a squad opens its card in the battle panel.
	await get_tree().process_frame
	assert_eq(w.card_squad(), -1)
	w._on_battle_pressed(Vector2(sq["x"], sq["y"]) / float(Fixed.ONE), MOUSE_BUTTON_LEFT, false, false, false, false)
	assert_eq(w.card_squad(), sq["id"])
	await get_tree().process_frame
	assert_true(w._battle_col.visible)
	assert_string_contains("\n".join(_texts(w._battle_box)), "Weapon range 40 m")
	assert_eq(w._main.squad_at(Vector2(sq["x"], sq["y"]) / float(Fixed.ONE)), sq["id"])


func test_a_turn_plays_out_before_the_next_planning_is_shown() -> void:
	var w := _demo()
	w.turn_seconds = 5.0
	w.contexts.tab_in()
	var eid := w.contexts.focus
	var pl := w.planner(eid)
	pl.select(pl.own_squads())
	var squad: int = pl.selection[0]
	pl.move_to(pl.selection_centre() + Vector2(30, 0))
	var turn := w.session.turns_resolved()
	var guard := 0
	while w.session.turns_resolved() == turn and guard < 4:
		guard += 1
		w.end_turn_requested.emit()
	assert_eq(w.session.turns_resolved(), turn + 1, "the game has resolved the turn")
	assert_true(w.playing(), "and the room is playing it back")
	assert_string_contains(w.hints(), "playing out")
	var rec: Dictionary = w.session.playback(1)[eid]
	var frames: Array = rec["frames"]
	assert_eq(frames.size(), (rec["rules"] as BattleRules).ticks_per_turn + 1, "the start and every tick")
	var first: Vector2 = frames[0][squad]["units"][0]
	var last: Vector2 = frames[frames.size() - 1][squad]["units"][0]
	assert_gt(last.x, first.x + 5.0, "the squad walks across the turn")
	assert_false(w.session.playback(2).has(eid) and w.session.playback(2)[eid]["frames"][0].has(squad),
		"a player who cannot see the squad gets no frames of it")
	assert_false(w._main._play.is_empty(), "the view shows the playback")
	# Ending the turn again only skips the playback.
	w.end_turn_requested.emit()
	assert_false(w.playing())
	assert_eq(w.session.turns_resolved(), turn + 1)
	await get_tree().process_frame
	assert_true(w._main._play.is_empty(), "the view shows the present again")


func test_the_overworld_turn_plays_out_too() -> void:
	var w := _skirmish()
	w.turn_seconds = 5.0
	var me := _own_commander(w)
	var cid: int = me["id"]
	w.contexts.select_commander(cid)
	var reach: Dictionary = w.session.reach(1, cid)["reach"]
	var far: int = me["plot"]
	for p: int in reach:
		if not reach.has(far) or int(reach[p]) > int(reach[far]):
			far = p
	assert_eq(w.route_to(far), "")
	var route: PackedInt64Array = w.session.state.routes[cid]
	w.end_turn_requested.emit()
	assert_true(w.playing())
	var walk: Array = w._play["walks"]["commanders"][cid]
	assert_eq(walk[0], me["plot"], "the walk starts where the commander stood")
	assert_eq(walk.slice(1), Array(route).slice(0, walk.size() - 1), "and goes through the hexes of its route")
	assert_eq(w._main._extra["play"], w._play["walks"])
	w._process(2.5)
	assert_almost_eq(float(w._main._extra["t"]), 0.5, 0.01, "half the time, half the way")
	w._process(2.6)
	assert_false(w.playing(), "the playback ends by itself")


func test_without_playback_time_the_result_shows_at_once() -> void:
	var w := _demo()
	w.end_turn_requested.emit()
	assert_false(w.playing())
	assert_false(w.session.keep_playback)
	assert_eq(w.session.playback(1), {})


func test_reach_and_waypoints() -> void:
	var w := _skirmish()
	var me := _own_commander(w)
	var cid: int = me["id"]
	var here: int = me["plot"]
	w.contexts.select_commander(cid)
	var r := w.session.reach(1, cid)
	var reach: Dictionary = r["reach"]
	assert_gt(int(r["budget"]), 0)
	assert_gt(reach.size(), 6)
	assert_false(reach.has(here))
	for p: int in reach:
		assert_true(int(reach[p]) <= int(r["budget"]))
	assert_eq(w.session.reach(2, cid), {}, "not for another player")
	# Two legs: next door, then on to a hex beside that one.
	var width := w.session.rules.width
	var a := -1
	var b := -1
	for p in Hex.neighbours(here, width, w.session.rules.height):
		if not reach.has(p):
			continue
		for q in Hex.neighbours(p, width, w.session.rules.height):
			if q != here and reach.has(q) and not Hex.adjacent(here, q, width) and a < 0:
				a = p
				b = q
	assert_ne(a, -1)
	assert_eq(w.route_to(a), "")
	assert_eq(w.session.state.routes[cid], PackedInt64Array([a]))
	assert_eq(w.route_to(b, true), "")
	assert_eq(w.session.state.routes[cid], PackedInt64Array([a, b]), "the waypoint continues the route")
	assert_eq(w.session.reach(1, cid)["spent"], reach[a] + w.session.state.move_cost(b))
	assert_string_contains(w.hints(), "Shift+right click: add a waypoint")
	# A right click on the commander clears the route.
	w._on_hex_clicked(here, MOUSE_BUTTON_RIGHT, false)
	assert_false(w.session.state.routes.has(cid))
	# The view is told what is in reach.
	assert_eq(w._overworld_extra()["reach"], reach)


func test_a_garrison_is_sent_to_a_hex_or_called_to_a_commander() -> void:
	var w := _skirmish()
	var me := _own_commander(w)
	var cid: int = me["id"]
	var here: int = me["plot"]
	var s := w.session.state
	var did := s.detachments.spawn({&"player": 1, &"plot": here})
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": s.rules.squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	var to: int = (w.session.reach(1, cid)["reach"] as Dictionary).keys()[0]
	w.arm_target("rally", did, "the garrison")
	assert_string_contains(w.hints(), "Click the hex")
	w._on_hex_clicked(to, MOUSE_BUTTON_LEFT, false)
	assert_eq(s.detachments.get_value(did, &"dest_plot"), to)
	assert_string_contains(w.hints(), "Left click", "the hint is back to normal")
	# Clicking one of your commanders sends it to that commander instead.
	w.arm_target("rally", did, "the garrison")
	w._on_hex_clicked(here, MOUSE_BUTTON_LEFT, false)
	assert_eq([s.detachments.get_value(did, &"dest_plot"), s.detachments.get_value(did, &"dest_commander")], [-1, cid])
	# A right click cancels.
	w.arm_target("rally", did, "the garrison")
	w._on_hex_clicked(to, MOUSE_BUTTON_RIGHT, false)
	assert_eq(s.detachments.get_value(did, &"dest_commander"), cid)
	assert_eq(w.send_to(to), "nothing to send")


func test_settings_are_saved_and_the_options_screen_changes_them() -> void:
	assert_false(GameSettings.saved())
	assert_eq(GameSettings.value("turn_seconds"), 5.0, "turns play out over five seconds by default")
	assert_eq(GameSettings.value("window_mode"), "windowed")
	assert_eq(GameSettings.set_value("nonsense", 1), "no such setting")
	var o := OptionsScreen.open_over(self)
	autofree(o)
	var turn: OptionButton = o.find_child("Turn", true, false)
	assert_eq(turn.get_item_text(turn.selected), "5 seconds")
	turn.select(1)
	turn.item_selected.emit(1)
	assert_eq(GameSettings.value("turn_seconds"), 2.0)
	var mode: OptionButton = o.find_child("Mode", true, false)
	var size: OptionButton = o.find_child("Size", true, false)
	assert_false(size.disabled)
	mode.item_selected.emit(1)
	assert_eq(GameSettings.value("window_mode"), "borderless")
	assert_true(size.disabled, "fullscreen uses the screen's resolution")
	size.item_selected.emit(size.item_count - 1)
	assert_true(GameSettings.saved())
	# A fresh read of the file gives the same values.
	GameSettings.path = "user://elsewhere.cfg"
	assert_eq(GameSettings.value("window_mode"), "windowed")
	GameSettings.path = SETTINGS
	assert_eq(GameSettings.value("window_mode"), "borderless")
	assert_eq(GameSettings.value("turn_seconds"), 2.0)
	assert_eq(GameSettings.sizes_for(Vector2i(1920, 1080)).back(), Vector2i(1920, 1080))
	assert_eq(GameSettings.sizes_for(Vector2i(800, 600)), [Vector2i(1280, 720)] as Array[Vector2i])
	# A room started from the menu plays turns out over the saved time.
	var w := _demo()
	assert_eq(w.turn_time(), 0.0)
	w.use_settings = true
	assert_eq(w.turn_time(), 2.0)


func test_the_main_menu_has_options() -> void:
	var m: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	add_child_autofree(m)
	var b: Button = m.find_child("Options", true, false)
	assert_not_null(b)
	b.pressed.emit()
	assert_not_null(m.get_children().filter(func(c: Node) -> bool: return c is OptionsScreen).front())
