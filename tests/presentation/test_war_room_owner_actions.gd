extends GutTest
## Owner actions in the war room (sw-63wt.10, U1Q24, U1Q32): the selected
## owned village lists its buy options with price and markup; a planned buy
## shows as a pending line that can be cancelled; a buy the Value can't cover
## says why; a buy paid at end turn grows the garrison; during playback the
## actions are disabled with the reason, and a replay shows none. Skirmish
## mirror: player 1's village is at (1,4) and sells rifle, scout and
## engineer squads.

const SETTINGS := "user://test_settings_owner_actions.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


func _room() -> WarRoom:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
	w.record_match = false
	add_child_autofree(w)
	w.use_settings = false
	w.turn_seconds = 0.0
	return w


func _plot(w: WarRoom) -> int:
	return Hex.plot(1, 4, w.session.rules.width)


func _village(w: WarRoom) -> int:
	for f: Dictionary in w.session.inspect_plot(1, _plot(w))["features"]:
		if f["name"] == "Village" and int(f["owner"]) == 1:
			return int(f["id"])
	return -1


## The village selected, with `value` Value, shown.
func _select(w: WarRoom, value: int) -> int:
	var village := _village(w)
	assert_true(village >= 0, "player 1 owns the village")
	w.select_feature(village, _plot(w))
	w.session.state.value[1] = value
	w._refresh()
	return village


func _buttons(node: Node, prefix: String, out: Array[Button] = []) -> Array[Button]:
	if node is Button and (node as Button).text.begins_with(prefix):
		out.append(node as Button)
	for c in node.get_children():
		_buttons(c, prefix, out)
	return out


func _texts(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		out.append((node as Label).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	for c in node.get_children():
		_texts(c, out)
	return out


func _has_text(node: Node, part: String) -> bool:
	for t in _texts(node):
		if t.contains(part):
			return true
	return false


func _garrison_squads(w: WarRoom, plot: int) -> int:
	var n := 0
	for d: Dictionary in w.session.observe(1)["detachments"]:
		if int(d["player"]) == 1 and int(d["plot"]) == plot:
			n += (d.get("squads", []) as Array).size()
	return n


func test_the_selected_village_lists_its_buys_and_a_shortfall_says_why() -> void:
	var w := _room()
	_select(w, 0)
	var buys := _buttons(w._commander_box, "Buy ")
	assert_eq(buys.size(), 3, "a buy per recruits squad")
	for b in buys:
		assert_true(b.disabled, "no Value, so none can be bought")
		assert_string_contains(b.text, "remote)", "the price shows the markup")
	assert_true(_has_text(w._commander_box, "Can't buy: not enough Value (costs"), "the shortfall is the reason")
	assert_true(_has_text(w._commander_box, "Rally point"), "the rally point is listed")


func test_a_planned_buy_is_pending_and_can_be_cancelled() -> void:
	var w := _room()
	var village := _select(w, 30)
	var buy := _buttons(w._commander_box, "Buy ")[0]
	assert_false(buy.disabled)
	buy.pressed.emit()
	assert_eq((w.session.inspect_feature(1, village)["buys"] as Array).size(), 1, "the buy is planned")
	w._refresh()
	assert_true(_has_text(w._commander_box, "Planned: buy"), "a pending line")
	assert_true(_has_text(w._commander_box, "Can't buy: the limit for this turn is reached"), "one buy a turn")
	var cancel := _buttons(w._commander_box, "Cancel")
	assert_eq(cancel.size(), 1)
	cancel[0].pressed.emit()
	assert_true((w.session.inspect_feature(1, village)["buys"] as Array).is_empty(), "cancelled")
	assert_eq(int(w.session.observe(1)["value"]), 30, "nothing paid")


func test_buy_then_end_turn_grows_the_garrison() -> void:
	var w := _room()
	var village := _select(w, 30)
	var plot := _plot(w)
	var before := _garrison_squads(w, plot)
	var buy := _buttons(w._commander_box, "Buy ")[0]
	buy.pressed.emit()
	var price := int((w.session.inspect_feature(1, village)["buys"] as Array)[0]["price"])
	var turns := w.session.turns_resolved()
	w._end_turn()
	assert_eq(w.session.turns_resolved(), turns + 1, "the turn resolved")
	assert_eq(_garrison_squads(w, plot), before + 1, "the bought squad joins the garrison")
	assert_true(price > 0)


func test_playback_disables_owner_actions_with_the_reason() -> void:
	var w := _room()
	var village := _select(w, 30)
	(_buttons(w._commander_box, "Buy ")[0]).pressed.emit()
	assert_false((w.session.inspect_feature(1, village)["buys"] as Array).is_empty())
	w.turn_seconds = 5.0
	var guard := 0
	while not w.playing() and guard < 4:
		guard += 1
		w.end_turn_requested.emit()
	assert_true(w.playing(), "the turn plays back")
	w._refresh()
	var buys := _buttons(w._commander_box, "Buy ")
	assert_false(buys.is_empty())
	for b in buys:
		assert_true(b.disabled, "disabled during playback")
		assert_eq(b.tooltip_text, WarRoom.PLANNING_ONLY_NOTE, "the reason is the tooltip")
	for c in _buttons(w._commander_box, "Cancel"):
		assert_true(c.disabled)
	assert_true(_has_text(w._commander_box, "Owner actions are off"), "and says so")
	w.skip_playback()


func test_a_replay_shows_no_owner_actions() -> void:
	var w := _room()
	_select(w, 30)
	assert_false(_buttons(w._commander_box, "Buy ").is_empty(), "shown while the player plans")
	w.session.locked = true
	w._refresh()
	assert_true(_buttons(w._commander_box, "Buy ").is_empty(), "a replay takes no owner actions")
	assert_false(_has_text(w._commander_box, "Owner actions"))
	w.session.locked = false


func test_the_feed_names_a_cancelled_buy() -> void:
	var w := _room()
	var line := EventText.describe({"type": "owner_action_cancelled", "data": {"player": 1, "plot": _plot(w),
		"option": "scout_team", "reason": "engaged"}}, w.session.rules, 1)
	assert_string_contains(line, "Your buy of Scout Team")
	assert_string_contains(line, "(engaged)")
