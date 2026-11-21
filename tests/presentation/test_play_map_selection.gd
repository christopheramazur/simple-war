extends GutTest
## "Play this map" with a battle map selected the way the UI selects it
## (sw-ll4.26.1): picked in the Maps tab's own map list, or selected in the
## template tree on the left. Both must start a skirmish on the selected
## map, for every battle map of the core package.


func _screen() -> Control:
	var screen := MainMenu.editor_screen()
	add_child_autofree(screen)
	return screen


func _panel(screen: Control) -> WarDataPanel:
	return screen.find_child("WarData", true, false)


func _battle_maps(panel: WarDataPanel) -> PackedStringArray:
	return panel.model.ids_of("battle_map")


func _tree_item(item: TreeItem, id: String) -> TreeItem:
	if item == null:
		return null
	if item.get_metadata(0) == id:
		return item
	var it := item.get_first_child()
	while it != null:
		var found := _tree_item(it, id)
		if found != null:
			return found
		it = it.get_next()
	return null


## Selects a battle map in the template tree on the left, as a click does.
func _select_in_tree(panel: WarDataPanel, id: String) -> void:
	var it := _tree_item(panel._tree.get_root(), id)
	assert_not_null(it, "the tree lists '%s'" % id)
	if it != null:
		it.select(0)


## Picks a battle map in the Maps tab's map list, as a click does:
## OptionButton.select() alone does not emit item_selected.
func _pick_on_maps_tab(panel: WarDataPanel, id: String) -> void:
	var mp := panel.painter()
	for i in mp._maps.item_count:
		if mp._maps.get_item_text(i) == id:
			mp._maps.select(i)
			mp._maps.item_selected.emit(i)
			return
	assert_true(false, "the Maps tab lists '%s'" % id)


func _assert_battle_on(screen: Control, panel: WarDataPanel, why: String) -> void:
	assert_eq(why, "", "Play this map started")
	if why != "":
		return
	var over := screen.find_child("Playtest", true, false)
	assert_not_null(over, "the playtest overlay opened")
	if over == null:
		return
	var w: WarRoom = over.get_child(1)
	assert_eq(w.session.battles.size(), 1, "one battle began")
	var b: OverworldBattle = w.session.battles.values()[0]
	assert_eq([b.rules.width, b.rules.height], [panel.painter().canvas.width, panel.painter().canvas.height],
		"the battle is on the selected map")


func test_the_play_button_with_a_map_picked_on_the_maps_tab() -> void:
	var screen := _screen()
	var panel := _panel(screen)
	_pick_on_maps_tab(panel, "field_map")
	var play: Button = screen.find_child("Play", true, false)
	play.pressed.emit()
	var said: Label = screen.find_child("Said", true, false)
	_assert_battle_on(screen, panel, said.text)


## The reported flow (playtest 2026-11-17): a battle map selected in the
## template tree on the left, then the Play this map button.
func test_the_play_button_with_a_map_selected_in_the_template_tree() -> void:
	var screen := _screen()
	var panel := _panel(screen)
	_select_in_tree(panel, "field_map")
	assert_eq(panel.selected_id, "field_map")
	var play: Button = screen.find_child("Play", true, false)
	play.pressed.emit()
	var said: Label = screen.find_child("Said", true, false)
	_assert_battle_on(screen, panel, said.text)


func test_play_after_picking_each_map_on_the_maps_tab() -> void:
	for id in _battle_maps(_panel(_screen())):
		var screen := _screen()
		var panel := _panel(screen)
		_pick_on_maps_tab(panel, id)
		_assert_battle_on(screen, panel, MainMenu.play_map(screen, panel, "profile_utility"))


func test_play_after_selecting_each_map_in_the_template_tree() -> void:
	for id in _battle_maps(_panel(_screen())):
		var screen := _screen()
		var panel := _panel(screen)
		_select_in_tree(panel, id)
		assert_eq(panel.selected_id, id)
		_assert_battle_on(screen, panel, MainMenu.play_map(screen, panel, "profile_utility"))
