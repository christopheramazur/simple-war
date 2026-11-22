extends GutTest
## The inspection window's tabs (sw-ll4.20): tab buttons, per-unit cards,
## stat traces in tooltips, effects and abilities, the opponent's view.

var _session: BattleSession
var _picked: Array = []


func before_each() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	_session = BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	_picked = []


func _pair(player: int) -> Array:
	for q: Dictionary in _session.observe(1)["squads"]:
		if q["player"] == player:
			return [q, _session.inspect(1, q["id"])]
	return [{}, {}]


func _pick(tab: String, unit: int) -> void:
	_picked = [tab, unit]


func _build(player: int, tab: String, unit: int = -1) -> VBoxContainer:
	var p := _pair(player)
	var c := InspectionTabs.build(p[0], p[1], 1, 10, false, {}, tab, unit, _pick)
	autofree(c)
	return c


func _texts(n: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _find(n: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, pred))
	return out


func test_own_squad_has_four_tabs() -> void:
	var c := _build(1, "squad")
	var tabs := _find(c, func(n: Node) -> bool: return n is Button and n.has_meta(&"tab"))
	assert_eq(tabs.size(), 4)
	(tabs[1] as Button).pressed.emit()
	assert_eq(_picked[0], "units")


func test_opponent_view_has_no_abilities_tab() -> void:
	var p := _pair(2)
	if p[1].is_empty():
		pending("enemy not inspectable at start")
		return
	assert_false(InspectionTabs.tabs_for(p[1]).has("abilities"))


func test_squad_tab_has_unit_cards_that_open_units() -> void:
	var c := _build(1, "squad")
	var cards := _find(c, func(n: Node) -> bool: return n is Button and n.has_meta(&"unit"))
	assert_gt(cards.size(), 0)
	(cards[0] as Button).pressed.emit()
	assert_eq(_picked[0], "units")


func test_units_tab_stat_rows_carry_traces() -> void:
	var c := _build(1, "units")
	var tips := _find(c, func(n: Node) -> bool: return n is HBoxContainer and (n as Control).tooltip_text.contains("how it's calculated"))
	assert_gt(tips.size(), 0)
	assert_true((tips[0] as Control).tooltip_text.contains("Base"))
	assert_true((tips[0] as Control).tooltip_text.contains("Result"))
	assert_true("Defensive" in _texts(c))
	assert_true("Offensive" in _texts(c))


func test_effects_and_abilities_tabs_build() -> void:
	assert_gt(_texts(_build(1, "effects")).size(), 0)
	var c := _build(1, "abilities")
	assert_gt(_texts(c).size(), 1)


func test_panel_keeps_tab_across_refresh() -> void:
	var p := _pair(1)
	var panel := BattlePanel.new()
	add_child_autofree(panel)
	panel.show_battle("T", _session.observe(1), p[0], p[1], 1, 10)
	panel._pick("effects", -1)
	var tabs := _find(panel, func(n: Node) -> bool: return n is Button and n.has_meta(&"tab") and (n as Button).button_pressed)
	assert_eq((tabs[0] as Button).get_meta(&"tab"), "effects")
