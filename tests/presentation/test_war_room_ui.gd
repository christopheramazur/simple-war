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
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
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
	assert_true(w.layout.regions["battle"].visible)
	assert_string_contains("\n".join(_texts(w._battle_box)), "Weapon range 40 m")
	assert_eq(w._main.squad_at(Vector2(sq["x"], sq["y"]) / float(Fixed.ONE)), sq["id"])


## A copy of the inspection with every weapon mode shifted from its base:
## accuracy by 10 percentage points, damage by 1, up or down (sw-vld).
func _shifted_insp(insp: Dictionary, dir: int) -> Dictionary:
	var out := insp.duplicate(true)
	for u: Dictionary in out["units"]:
		for e: Dictionary in u["stats"]:
			var stat := String(e["stat"])
			if stat.begins_with("weapon.modes"):
				var step := Fixed.ONE / 10 if stat.ends_with("accuracy") else Fixed.ONE
				e["value"] = int(e["base"]) + dir * step
	return out


## Buffed and debuffed weapon stats read their direction in TEXT under every
## theme, and the tones stay (sw-vld, GDD accessibility: never colour alone).
func test_the_squad_card_marks_changed_stats_in_text_under_every_theme() -> void:
	var w := _demo()
	w.contexts.tab_in()
	var eid := w.contexts.focus
	var sq: Dictionary = w.session.observe_battle(1, eid)["squads"][0]
	var insp := w.session.inspect_battle(1, eid, sq["id"])
	for id: String in UiTheme.ids():
		UiTheme.apply(get_window(), id)
		for dir: int in [1, -1]:
			var shifted := _shifted_insp(insp, dir)
			var card := SquadCard.build(sq, shifted, 1)
			autofree(card)
			var text := "\n".join(_texts(card))
			var mark := "+" if dir > 0 else "-"
			assert_string_contains(text, "(%s10%%)" % mark,
				"accuracy's direction in text under theme '%s'" % id)
			assert_string_contains(text, "(%s" % mark, "damage's direction in text too")
			# The named-style pipeline stays: the tone still names the change.
			var want_tone := &"SmallGoodLabel" if dir > 0 else &"SmallBadLabel"
			var found := 0
			for l: Label in card.find_children("*", "Label", true, false):
				if l.text.contains("to hit"):
					found += 1
					assert_eq(l.theme_type_variation, want_tone, "the tone stays under theme '%s'" % id)
			assert_gt(found, 0, "the card shows accuracy lines")
	UiTheme.apply(get_window(), "default")
	# A hurt squad's Health bar reads the remaining / max numbers.
	var hurt := sq.duplicate(true)
	hurt["hp_lost"] = int(sq["hp_max"]) / 4
	var card := SquadCard.build(hurt, insp, 1)
	autofree(card)
	assert_string_contains("\n".join(_texts(card)), "%s / %s" % [
		Fixed.to_display(int(sq["hp_max"]) - int(hurt["hp_lost"])), Fixed.to_display(int(sq["hp_max"]))],
		"the Health row shows remaining / max when hurt")


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


## Ends a turn in the demo's first battle with its first own squad moving,
## so the room plays the turn back; returns that squad's id (sw-ll4.27.4).
func _play_a_moving_turn(w: WarRoom) -> int:
	w.turn_seconds = 5.0
	assert_true(w.contexts.tab_in())
	var pl := w.planner(w.contexts.focus)
	pl.select(pl.own_squads())
	var squad: int = pl.selection[0]
	pl.move_to(pl.selection_centre() + Vector2(30, 0))
	var turn := w.session.turns_resolved()
	var guard := 0
	while w.session.turns_resolved() == turn and guard < 4:
		guard += 1
		w.end_turn_requested.emit()
	assert_true(w.playing(), "the room plays the resolved turn back")
	return squad


## A left click during playback inspects the squad under it instead of
## skipping; no click or planning command issues orders (sw-ll4.27.4). The
## click reaches the battle view, which routes it to _on_battle_pressed.
func test_playback_clicks_inspect_but_never_skip_or_order() -> void:
	var w := _demo()
	var squad := _play_a_moving_turn(w)
	var eid := w.contexts.focus
	var pl := w.planner(eid)
	await get_tree().process_frame
	await get_tree().process_frame
	# The hint and the banner name only the keys.
	assert_string_contains(w.hints(), "Space or Esc")
	assert_string_contains(w._phase_text.text, "Space or Esc")
	assert_false(w.hints().contains("click: skip"), "the hint no longer offers click-to-skip")
	assert_false(w._phase_text.text.contains("click to skip"), "nor does the banner")
	# A left click on the playing squad: its card shows, playback goes on.
	var centre := Vector2.ZERO
	var found := false
	for d: Dictionary in w._main._battle_squads():
		if d["id"] == squad:
			centre = d["c"]
			found = true
	assert_true(found, "the squad is drawn mid-playback")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = w._main.to_view(centre)
	mb.pressed = true
	w._main._gui_input(mb)
	mb.pressed = false
	w._main._gui_input(mb)
	assert_true(w.playing(), "a click no longer skips the playback")
	assert_eq(w._inspected, squad, "the click inspected the squad under it")
	assert_eq(w.card_squad(), squad)
	var squad_name := ""
	for sq: Dictionary in w.session.observe_battle(1, eid)["squads"]:
		if sq["id"] == squad:
			squad_name = String(sq["name"])
	assert_string_contains("
".join(_texts(w._battle_box)), squad_name, "the battle panel shows its card")
	await get_tree().process_frame
	assert_eq(w._main._overlay.get("inspected", -1), squad, "the view highlights the inspected squad")
	# Right clicks, box selects and planning commands order nothing meanwhile.
	var drafts_before := pl.drafts.duplicate(true)
	var selection_before := pl.selection.duplicate()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	w._main._gui_input(mb)
	mb.pressed = false
	w._main._gui_input(mb)
	w._on_battle_pressed(centre, MOUSE_BUTTON_RIGHT, false, false, false, false)
	w._on_battle_box(Rect2(centre, Vector2(10, 10)), false)
	w._on_command(&"hold", 0)
	assert_true(w.playing(), "none of them skipped the playback")
	assert_eq(pl.drafts, drafts_before, "none of them drafted an order")
	assert_eq(pl.selection, selection_before, "the selection is untouched")


## During a battle's playback the view takes the wheel, middle-drag, the
## keyboard pan and the hover; the side panels stay blocked and the stage is
## open to the view (sw-bafi.1).
func test_playback_camera_and_hover_reach_the_battle_view() -> void:
	var w := _demo()
	var squad := _play_a_moving_turn(w)
	await get_tree().process_frame
	var view_mid := w._main.size / 2.0
	# The wheel zooms the battle camera; the playback goes on.
	var z0 := w.contexts.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = view_mid
	w._main._gui_input(wheel)
	assert_gt(w.contexts.zoom, z0, "the wheel zooms the battle camera during playback")
	assert_true(w.playing(), "zooming does not end the playback")
	# Middle-drag pans it.
	var c0: Vector2 = w.contexts.battle_centre
	var mid := InputEventMouseButton.new()
	mid.button_index = MOUSE_BUTTON_MIDDLE
	mid.pressed = true
	w._main._gui_input(mid)
	var drag := InputEventMouseMotion.new()
	drag.position = view_mid + Vector2(60, 60)
	drag.relative = Vector2(60, 60)
	drag.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	w._main._gui_input(drag)
	mid.pressed = false
	w._main._gui_input(mid)
	var c1: Vector2 = w.contexts.battle_centre
	assert_ne(c1, c0, "middle-drag pans the battle camera during playback")
	# The keyboard pan works too.
	w._on_pan(Vector2.LEFT)
	assert_ne(w.contexts.battle_centre, c1, "the arrow keys pan during playback")
	# Hover: the squad under the cursor is marked and its card shows, with
	# nothing else selected to take the card.
	w.planner(w.contexts.focus).select([])
	var centre := Vector2.ZERO
	for d: Dictionary in w._main._battle_squads():
		if d["id"] == squad:
			centre = d["c"]
	var motion := InputEventMouseMotion.new()
	motion.position = w._main.to_view(centre)
	w._main._gui_input(motion)
	assert_eq(w._hovered, squad, "hovering a squad during playback marks it")
	assert_eq(w.card_squad(), squad, "its card shows")
	# A repeat over the same squad leaves the card as it is.
	var card_before := w._battle_box.get_children().map(func(c: Node) -> int: return c.get_instance_id())
	w._on_squad_hovered(squad)
	var card_after := w._battle_box.get_children().map(func(c: Node) -> int: return c.get_instance_id())
	assert_eq(card_after, card_before, "a repeat hover does not rebuild the card")
	assert_true(w.playing(), "hovering does not end the playback")


## The side panels are blocked during playback; the battle stage is not.
func test_playback_blocker_leaves_the_battle_stage_open() -> void:
	var w := _demo()
	_play_a_moving_turn(w)
	await get_tree().process_frame
	var inv := w._blocker.get_global_transform().affine_inverse()
	var side: Control = w.layout.regions["side"]
	var stage: Control = w.layout.regions["stage"]
	assert_true(w._blocker._has_point(inv * side.get_global_rect().get_center()), "the side panels stay blocked")
	assert_false(w._blocker._has_point(inv * stage.get_global_rect().get_center()), "the battle stage is open")


## Space and Esc still skip the playback to its end (sw-ll4.27.4).
func test_space_and_esc_skip_the_playback() -> void:
	var w := _demo()
	_play_a_moving_turn(w)
	w.keys.actions[&"end_turn"].triggered.emit()
	assert_false(w.playing(), "Space skips to the end")
	await get_tree().process_frame
	assert_true(w._main._play.is_empty(), "the view shows the present again")
	_play_a_moving_turn(w)
	w.keys.actions[&"cancel"].triggered.emit()
	assert_false(w.playing(), "Esc skips too")


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
	var walk: Dictionary = w._play["walks"]["commanders"][cid]
	var plots: Array = walk["plots"]
	var times: Array = walk["times"]
	assert_eq(plots[0], me["plot"], "the walk starts where the commander stood")
	assert_eq(plots.slice(1), Array(route).slice(0, plots.size() - 1), "and goes through the hexes of its route")
	assert_eq(times[0], 0)
	assert_eq(times.back(), int(reach[plots.back()]), "each hex is entered when its movement points are spent")
	var span := int(w._play["walks"]["span"])
	assert_true(span >= int(times.back()), "the turn stands for a full move")
	assert_eq(w._main._extra["play"], w._play["walks"])
	# One speed for everyone: at half the turn the walker is where half the
	# turn's movement points take it, and it waits once its move is done.
	w._process(2.5)
	assert_almost_eq(float(w._main._extra["t"]), 0.5, 0.01)
	var half := w._main._along(walk, 0.5)
	var i := 0
	while i < times.size() - 1 and float(times[i + 1]) <= span * 0.5:
		i += 1
	var want := w._main._centre(plots[i])
	if i < times.size() - 1:
		want = want.lerp(w._main._centre(plots[i + 1]), (span * 0.5 - times[i]) / float(times[i + 1] - times[i]))
	assert_almost_eq(half.x, want.x, 0.01)
	assert_eq(w._main._along(walk, 1.0), w._main._centre(plots.back()))
	assert_eq(w._main._along(walk, float(times.back()) / span), w._main._centre(plots.back()), "it stops when its own move is done")
	w._process(2.6)
	assert_false(w.playing(), "the playback ends by itself")


func test_a_convoy_that_delivers_is_still_seen_walking() -> void:
	var w := _skirmish()
	w.turn_seconds = 5.0
	var me := _own_commander(w)
	var cid: int = me["id"]
	var s := w.session.state
	var reach: Dictionary = w.session.reach(1, cid)["reach"]
	var from := -1
	for p: int in reach:
		if int(reach[p]) > 0 and int(reach[p]) <= s.rules.convoy_mp and from < 0:
			from = p
	var did := s.detachments.spawn({&"player": 1, &"plot": from, &"dest_commander": cid})
	s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": s.rules.squad_index("rifle_squad"), &"alive": 8, &"size": 8})
	w.end_turn_requested.emit()
	assert_true(w.playing())
	assert_true(s.detachments.is_alive(did), "the shell stays after delivery (sw-ll4.26.2)")
	assert_eq(s.detachments.get_value(did, &"plot"), me["plot"])
	assert_false(Convoys.is_convoy(s, s.detachments.row_of(did)), "it halts there")
	var walks: Dictionary = w._play["walks"]["detachments"]
	assert_true(walks.has(did), "it is still seen walking there")
	assert_eq(walks[did]["plots"][0], from)
	assert_eq(walks[did]["plots"].back(), me["plot"])
	assert_eq((w._play["walks"]["gone"] as Array).size(), 0, "nothing vanished")


func test_hovering_a_hex_says_what_is_there() -> void:
	var w := _skirmish()
	var s := w.session
	var obs := s.observe(1)
	# A feature the player knows that produces something.
	var found := -1
	for p: int in obs["plots"]:
		for f: Dictionary in obs["plots"][p]["features"]:
			if int(f["tmpl"]) >= 0 and s.rules.production_count(int(f["tmpl"])) > 0 and found < 0:
				found = p
	if found < 0:
		for row in s.state.features.count():
			if s.rules.production_count(s.state.features.tmpl[row]) > 0 and found < 0:
				found = s.state.features.plot[row]
				s.state.features.set_value(s.state.features.id_at(row), &"owner", 1)
	assert_ne(found, -1, "the map has a producing feature")
	var info := s.inspect_plot(1, found)
	if not info["known"]:
		pass_test("the producing feature is not in sight on this seed")
		return
	var feat: Dictionary = info["features"].filter(func(f: Dictionary) -> bool: return not (f["produces"] as Array).is_empty())[0]
	assert_gt(int(feat["produces"][0]["turns"]), 0)
	var text := "\n".join(HexCard.lines(info, s.rules, 1).map(func(l: Array) -> String: return l[0]))
	assert_string_contains(text, str(feat["name"]))
	assert_string_contains(text, "every %d turn" % int(feat["produces"][0]["turns"]))
	assert_eq(s.inspect_plot(1, -1)["known"], false)
	assert_eq(s.inspect_plot(9, found)["known"], false, "not for someone who is not playing")
	# The hover card shows it, and hides over a battle view or unknown ground.
	w._on_hex_hovered(found)
	assert_true(w._hover_card.is_visible_in_tree())
	assert_string_contains("\n".join(_texts(w._hover_card)), str(feat["name"]))
	w._on_hex_hovered(-1)
	assert_false(w._hover_card.is_visible_in_tree())
	# The player's own commander's hex names the commander and its army.
	var mine := _own_commander(w)
	var here := "\n".join(HexCard.lines(s.inspect_plot(1, mine["plot"]), s.rules, 1).map(func(l: Array) -> String: return l[0]))
	assert_string_contains(here, "Your Commander")


func test_themes_are_data_and_fields_differ_from_buttons() -> void:
	UiTheme.reload()
	var ids := UiTheme.ids()
	assert_eq(ids[0], "default")
	assert_has(Array(ids), "high_contrast")
	assert_has(Array(ids), "large")
	assert_eq(UiTheme.profile("no_such_theme")["id"], "default", "an unknown id falls back")
	var part := UiTheme.complete({"id": "mine", "colors": {"accent": "ff0000", "nonsense": "zz"}})
	assert_eq(part["colors"]["accent"], "ff0000")
	assert_eq(part["colors"]["panel"], UiTheme.FALLBACK["colors"]["panel"], "what a profile leaves out is filled in")
	var t := UiTheme.build(UiTheme.profile("default"))
	var field := t.get_stylebox("normal", "OptionButton") as StyleBoxFlat
	var button := t.get_stylebox("normal", "Button") as StyleBoxFlat
	var edit := t.get_stylebox("normal", "LineEdit") as StyleBoxFlat
	assert_eq(field.bg_color, edit.bg_color, "a dropdown is drawn as a field")
	assert_ne(field.bg_color, button.bg_color, "and not as a button")
	assert_gt(field.border_width_left, 0, "fields have a border")
	assert_eq(UiTheme.build(UiTheme.profile("large")).default_font_size, 20)
	# Picking one in the options applies it to the window and saves it.
	var o := OptionsScreen.open_over(self)
	autofree(o)
	var pick: OptionButton = o.find_child("Theme", true, false)
	var at := Array(ids).find("high_contrast")
	pick.select(at)
	pick.item_selected.emit(at)
	assert_eq(GameSettings.value("ui_theme"), "high_contrast")
	assert_eq((get_window().theme.get_stylebox("normal", "Button") as StyleBoxFlat).border_width_left, 2)
	GameSettings.set_value("ui_theme", "default")
	UiTheme.apply(get_window())


func test_the_main_menu_fits_a_short_window() -> void:
	var holder := Control.new()
	holder.size = Vector2(853, 480)
	add_child_autofree(holder)
	var m: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	holder.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = m.find_child("Scroll", true, false)
	var menu: Control = m.find_child("Menu", true, false)
	assert_almost_eq(scroll.size.y, 480.0, 1.0, "the menu's scroll area is the window")
	assert_gt(menu.size.y, 480.0, "the menu is taller than this window")
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y, "so it scrolls instead of being cut off")
	assert_lt(menu.size.y, 700.0, "and it fits a 720-pixel window without scrolling")


func test_without_playback_time_the_result_shows_at_once() -> void:
	var w := _demo()
	w.end_turn_requested.emit()
	assert_false(w.playing())
	assert_false(w.session.keep_playback)
	assert_eq(w.session.playback(1), {})


func test_battle_tabs_and_tiles_show_the_worst_band_and_trend() -> void:
	var w := _demo()
	var eids := w.contexts.battles()
	assert_eq(eids.size(), 2, "the demo has two battles")
	# Break one own squad's morale in the first battle.
	var b: OverworldBattle = w.session.battles[eids[0]]
	var row := -1
	for r in b.state.squads.count():
		if b.state.squads.player[r] == 1 and b.state.squads.is_active(r):
			row = r
			break
	assert_ne(row, -1)
	var morale := DataSchema.SIMPL.find("morale")
	Pools.flow(b.state, row, morale, -Pools.value(b.state, row, morale), &"test")
	w._queue_refresh()
	await get_tree().process_frame
	var sum := w.session.battle_summary(1, eids[0])
	assert_eq(sum["band"], "broken")
	var texts := "\n".join(_texts(w._menu))
	assert_string_contains(texts, EventText.band_word("broken"), "the tab says the band as a word")
	assert_string_contains(texts, String(BandGlyphs.ICONS["broken"]), "and an icon, never colour alone")
	assert_string_contains(texts, EventText.trend_word(String(sum["trend"])), "with the backward-looking trend")
	var sums: Dictionary = w._main._extra["summaries"]
	assert_eq(sums.size(), 2, "both battle tiles carry a summary")
	assert_eq(sums[eids[0]]["band"], "broken")
	assert_eq(sums[eids[1]], w.session.battle_summary(1, eids[1]))


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
	assert_true(m.ui.find(&"options") is OptionsScreen)
	b.pressed.emit()
	assert_eq(m.ui.windows().size(), 1, "pressing again does not stack a second one")
