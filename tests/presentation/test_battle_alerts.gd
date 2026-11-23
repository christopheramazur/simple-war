extends GutTest
## The persistent battle-alert panel and its duration setting (sw-9un).

var _old_path: String


func before_each() -> void:
	_old_path = GameSettings.path
	GameSettings.path = "user://test_alerts.cfg"
	GameSettings._loaded_from = ""


func after_each() -> void:
	DirAccess.remove_absolute(GameSettings.path)
	GameSettings.path = _old_path
	GameSettings._loaded_from = ""


func _panel() -> BattleAlerts:
	var p := BattleAlerts.new()
	add_child_autofree(p)
	return p


func test_an_alert_in_an_unwatched_battle_waits_for_the_return() -> void:
	var p := _panel()
	p.add("alert", "Lost 2 squads.", 7, 3, false)
	p.add("start", "A battle begins.", 8, 3, true)
	assert_eq(p.new_count(), 1, "only the unwatched battle's alert is new")
	p.focus_changed(8)
	assert_eq(p.new_count(), 1, "looking at another battle changes nothing")
	p.focus_changed(7)
	assert_eq(p.new_count(), 0, "returning to the battle sees its alert")
	assert_eq(p.entries.size(), 2, "alerts stay listed")


func test_new_alerts_age_out_unless_until_dismissed() -> void:
	var p := _panel()
	p.seconds = 6.0
	p.add("end", "Ended.", 1, 2, false)
	p.tick(7.0)
	assert_eq(p.new_count(), 0)
	p.seconds = 0.0
	p.add("end", "Ended.", 1, 2, false)
	p.tick(1000.0)
	assert_eq(p.new_count(), 1, "0 means until dismissed")
	p.dismiss_all()
	assert_eq(p.entries.size(), 0)


func test_alerts_say_their_kind_in_words() -> void:
	var p := _panel()
	p.add("alert", "Lost.", 1, 2, false)
	var found := false
	for c in p.get_children():
		if c is Label and "ALERT" in (c as Label).text and "NEW" in (c as Label).text:
			found = true
	assert_true(found)


func test_the_duration_setting_survives_a_restart() -> void:
	assert_eq(float(GameSettings.value("alert_seconds")), 6.0)
	assert_eq(GameSettings.set_value("alert_seconds", 60.0), "")
	GameSettings._loaded_from = ""  # a fresh start reads the file again
	assert_eq(float(GameSettings.value("alert_seconds")), 60.0)
	assert_true(GameSettings.ALERT_SECONDS.max() >= 60.0, "at least 10x the default")
