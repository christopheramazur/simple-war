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
