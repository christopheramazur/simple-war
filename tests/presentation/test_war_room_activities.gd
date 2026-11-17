extends GutTest
## Planning activities from the commander panel (sw-kys.2): a commander
## routed to its own village sees recruit and hire buttons, and pressing
## "Hire" plans the hire.

const SETTINGS := "user://test_settings_activities.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


func _buttons(node: Node, out: Array[Button] = []) -> Array[Button]:
	if node is Button:
		out.append(node as Button)
	for c in node.get_children():
		_buttons(c, out)
	return out


func test_hire_from_the_commander_panel() -> void:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
	w.record_match = false
	add_child_autofree(w)
	var me := {}
	for c: Dictionary in w.session.observe(1)["commanders"]:
		if c["player"] == 1:
			me = c
	var cid: int = me["id"]
	var village := Hex.plot(1, 4, w.session.rules.width)
	w.contexts.select_commander(cid)
	assert_eq(w.route_to(village), "")
	w.session.state.value[1] = 30
	await wait_process_frames(2)
	var hire: Button = null
	var recruit_engineers := false
	for b in _buttons(w):
		if b.text.begins_with("Hire a field commander"):
			hire = b
		if b.text.begins_with("Recruit Engineer team"):
			recruit_engineers = true
	assert_true(recruit_engineers, "the village recruits engineers")
	assert_not_null(hire, "a hire button")
	if hire == null:
		return
	hire.pressed.emit()
	assert_eq(w.session.observe(1)["activities"][cid]["activity"], "hire")
	assert_eq(w.session.observe(1)["activities"][cid]["option"], "field_commander")


func _labels(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		out.append((node as Label).text)
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	for c in node.get_children():
		_labels(c, out)
	return out


## sw-kys.8: a garrison is selected and steered like a commander.
func test_steer_a_garrison_like_a_commander() -> void:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
	w.record_match = false
	add_child_autofree(w)
	var s := w.session
	var me := {}
	for c: Dictionary in s.observe(1)["commanders"]:
		if c["player"] == 1:
			me = c
	var at: int = me["plot"]
	var did := Detachments.drop(s.state, int(me["id"]), at)
	assert_gt(did, -1)
	w._on_hex_clicked(at, MOUSE_BUTTON_LEFT)
	assert_eq(w.contexts.selected, int(me["id"]), "the commander first")
	w._on_hex_clicked(at, MOUSE_BUTTON_LEFT)
	assert_eq(w.contexts.selected_detachment, did, "then the garrison on its hex")
	await wait_process_frames(2)
	assert_true(Array(_labels(w)).any(func(t: String) -> bool: return t.begins_with("Garrison")), "its panel")
	var width := s.rules.width
	var far := Hex.plot(9, 4, width)
	w._on_hex_clicked(far, MOUSE_BUTTON_RIGHT)
	var route: PackedInt64Array = s.observe(1)["convoy_routes"].get(did, PackedInt64Array())
	assert_false(route.is_empty(), "right click routes it")
	assert_eq(route[route.size() - 1], far)
	var extra := Hex.plot(9, 7, width)
	w._on_hex_clicked(extra, MOUSE_BUTTON_RIGHT, true)
	route = s.observe(1)["convoy_routes"].get(did, PackedInt64Array())
	assert_eq(route[route.size() - 1], extra, "shift adds a waypoint")
	assert_true(route.has(far), "through the first destination")
	w._on_hex_clicked(at, MOUSE_BUTTON_RIGHT)
	assert_false(s.observe(1)["convoy_routes"].has(did), "right click on its own hex halts it")
