extends GutTest
## Panel content as data (sw-ijp.4): a spec plus a read-only view model builds
## the widgets; buttons emit action ids; a bad spec is refused with reasons.


func test_shipped_specs_are_valid() -> void:
	for id in ["hex_card", "reserves", "squad_card"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/panels/%s.json" % id))
		assert_eq(UiPanel.validate(data), PackedStringArray(), id)


func test_lines_use_tone_styles() -> void:
	var p := UiPanel.build("hex_card", {"lines": [{"text": "A", "tone": "head"}, {"text": "B", "tone": "dim"}, {"text": "C", "tone": "?"}]})
	add_child_autofree(p)
	assert_eq(p.get_child_count(), 3)
	assert_eq((p.get_child(0) as Label).text, "A")
	assert_eq((p.get_child(0) as Label).theme_type_variation, &"CardAccentLabel")
	assert_eq((p.get_child(1) as Label).theme_type_variation, &"CaptionDimLabel")
	assert_eq((p.get_child(2) as Label).theme_type_variation, &"CaptionLabel")


func test_buttons_emit_action_ids_with_bound_args() -> void:
	var model := {"groups": [{"title": "Cmdr", "squads": [
		{"text": "Send in A", "disabled": false, "commander": 7, "squad": 3},
		{"text": "B: no", "disabled": true, "commander": 7, "squad": 4}]}]}
	var p := UiPanel.build("reserves", model)
	add_child_autofree(p)
	var got := []
	p.action_invoked.connect(func(a: String, args: Array) -> void: got.append([a, args]))
	var buttons := p.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 2)
	assert_true((buttons[1] as Button).disabled)
	(buttons[0] as Button).pressed.emit()
	(buttons[1] as Button).pressed.emit()
	assert_eq(got, [["send_reserve", [7, 3]]])


func test_show_hides_a_section() -> void:
	var p := UiPanel.new()
	add_child_autofree(p)
	p.show_model({"sections": [{"kind": "label", "text": "x", "show": "on"}]}, {"on": false})
	assert_eq(p.get_child_count(), 0)
	p.show_model({"sections": [{"kind": "label", "text": "x", "show": "on"}]}, {"on": true})
	assert_eq(p.get_child_count(), 1)


func test_bad_specs_are_refused() -> void:
	assert_false(UiPanel.validate({}).is_empty())
	assert_false(UiPanel.validate({"sections": [{"kind": "script"}]}).is_empty())
	assert_false(UiPanel.validate({"sections": [{"kind": "label", "code": "x"}]}).is_empty())
	assert_false(UiPanel.validate({"sections": [{"kind": "button", "text": "x"}]}).is_empty())
	assert_false(UiPanel.validate({"sections": [{"kind": "list", "bind": "a", "each": [{"kind": "nope"}]}]}).is_empty())


func test_bar_kv_progress_and_label_tip() -> void:
	var p := UiPanel.new()
	add_child_autofree(p)
	var spec := {"sections": [
		{"kind": "bar", "bind": "b"},
		{"kind": "kv", "bind": "kv", "key_style": "SmallDimLabel", "styles": {"up": "SmallGoodLabel"}},
		{"kind": "progress", "bind": "pr"},
		{"kind": "label", "bind": "t", "style_bind": "st", "tip": "tip"}]}
	p.show_model(spec, {"b": {"name": "Health", "frac": 0.5, "tone": "Good", "text": "x"},
		"kv": {"key": "K:", "values": [{"text": "v", "tone": "up"}]}, "pr": {"frac": 0.0},
		"t": "hi", "st": "SmallLabel", "tip": "tip text"})
	assert_eq(p.get_child_count(), 4)
	assert_eq(((p.get_child(0) as HBoxContainer).get_child(0) as Label).text, "Health")
	assert_eq(((p.get_child(1) as HBoxContainer).get_child(1) as Label).theme_type_variation, &"SmallGoodLabel")
	assert_eq((p.get_child(3) as Label).tooltip_text, "tip text")


func test_meter_draws_segments_and_ticks() -> void:
	var p := UiPanel.new()
	add_child_autofree(p)
	p.show_model({"sections": [{"kind": "meter", "bind": "m"}]}, {"m": {"pool": "morale", "label": "M", "pct": 50.0,
		"floors": [0, 20, 40, 60, 80], "text": "t", "tip": "ledger"}})
	var row := p.get_child(0) as HBoxContainer
	assert_eq(row.tooltip_text, "ledger")
	var bands := row.find_children("*", "Panel", true, false).filter(func(n: Node) -> bool: return n.has_meta(&"band"))
	assert_eq(bands.size(), 5)
