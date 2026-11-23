extends GutTest
## Sending reinforcements from the war room (sw-dek): the battle lists the
## army's reserves, sends them, says why one can't go, and the battle menu
## flags reserves that could join.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const SETTINGS := "user://test_settings_reserves.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


## The demo room with a battle in view; its commander has one reserve.
func _in_battle() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	assert_true(w.contexts.tab_in())
	w._refresh()
	return w


func _buttons(w: WarRoom) -> Array[Button]:
	var out: Array[Button] = []
	for c in w._orders_box.find_children("*", "Button", true, false):
		out.append(c as Button)
	return out


func _send_buttons(w: WarRoom) -> Array[Button]:
	return _buttons(w).filter(func(b: Button) -> bool: return b.text.begins_with("Send in"))


func _menu_text(w: WarRoom) -> String:
	var out := ""
	for c in w._menu.get_children():
		if c is Label:
			out += (c as Label).text
	return out


func test_a_reserve_is_sent_from_the_battle_view() -> void:
	var w := _in_battle()
	var eid := w.contexts.focus
	assert_eq(w.reserves_ready(eid), 1)
	assert_string_contains(_menu_text(w), "1 reserve squad can join")
	var flagged := _menu_text(w).count("can join")
	var send := _send_buttons(w)
	assert_eq(send.size(), 1)
	send[0].pressed.emit()
	w._refresh()
	assert_true(w.session.reserves(1, eid)[0]["squads"][0]["sent"])
	assert_eq(w.reserves_ready(eid), 0)
	assert_eq(_menu_text(w).count("can join"), flagged - 1, "this battle is no longer flagged")
	assert_eq(_send_buttons(w).size(), 0)
	assert_true(_buttons(w).any(func(b: Button) -> bool: return b.disabled and b.text.contains("joins next battle turn")))
	assert_eq(w.session.input_log.filter(func(i: Dictionary) -> bool: return i["kind"] == "reinforce").size(), 1,
		"logged, so replays have it")


func test_a_full_battleforce_says_why() -> void:
	var w := _in_battle()
	var eid := w.contexts.focus
	var cap := w.session.rules.bf_cap_squads
	w.session.rules.bf_cap_squads = 2
	w._refresh()
	var g: Dictionary = w.session.reserves(1, eid)[0]
	var labels := _buttons(w).map(func(b: Button) -> String: return b.text if b.disabled else "")
	w.session.rules.bf_cap_squads = cap
	assert_eq(int(g["open"]), 0)
	assert_eq(g["squads"][0]["why"], "the battleforce cap is 2 squads")
	assert_true(labels.any(func(t: String) -> bool: return t.contains("the battleforce cap is 2 squads")))


func test_checking_a_reserve_changes_nothing() -> void:
	var w := _in_battle()
	var eid := w.contexts.focus
	var g: Dictionary = w.session.reserves(1, eid)[0]
	var spare: int = g["squads"][0]["squad"]
	assert_eq(OverworldOrders.reinforce_error(w.session.state, 1, int(g["commander"]), spare, 0), "")
	assert_eq(w.session.state.squads.get_value(spare, &"deployed"), -1)
	assert_false(w.session.reserves(2, eid).any(func(r: Dictionary) -> bool: return r["commander"] == g["commander"]),
		"another player is not told about them")
