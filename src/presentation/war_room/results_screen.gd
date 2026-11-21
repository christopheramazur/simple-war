class_name ResultsScreen
extends UiWindow
## The results screen (sw-ll4.11): shown over the war room when the match
## ends. Says who won and why, how long it took and what each side lost
## (MatchDriver.stats), and offers to play again, go to the menu, or look
## at the map. Presentation only.

signal play_again
signal main_menu

## `result`: "won", "lost" or "drew" for the viewer. `reason`: the outcome's
## text. `stats`: MatchDriver.stats. `offer`: {"replay": show "Play again",
## "menu": show "Main menu", "note": a line under the tallies}.
static func open_over(parent: Node, result: String, reason: String, stats: Dictionary, viewer: int, offer: Dictionary = {}) -> ResultsScreen:
	var r := ResultsScreen.new()
	r.id = &"results"
	r._build(result, reason, stats, viewer, offer)
	UiRoot.of(parent).open(r)
	return r


func _build(result: String, reason: String, stats: Dictionary, viewer: int, offer: Dictionary) -> void:
	var note := String(offer.get("note", ""))
	var col := dialog(520)
	var title := Label.new()
	title.name = "Title"
	title.text = {"won": "Victory", "lost": "Defeat"}.get(result, "Draw")
	title.theme_type_variation = {"won": &"HeroGoodLabel", "lost": &"HeroBadLabel"}.get(result, &"HeroAccentLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var why := Label.new()
	why.name = "Reason"
	why.text = reason
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	why.custom_minimum_size = Vector2(470, 0)
	col.add_child(why)
	col.add_child(HSeparator.new())
	var turns := int(stats.get("turns", 0))
	var battles := int(stats.get("battles", 0))
	col.add_child(_dim("%d turn%s  ·  %d battle%s" % [turns, "" if turns == 1 else "s", battles, "" if battles == 1 else "s"]))
	var grid := GridContainer.new()
	grid.name = "Stats"
	grid.columns = 4
	grid.theme_type_variation = &"StatsGap"
	for head: String in ["", "Squads lost", "Commanders lost", "Features taken"]:
		grid.add_child(_dim(head))
	var players: Dictionary = stats.get("players", {})
	var ids: Array = players.keys()
	ids.sort()
	for p: int in ids:
		var row: Dictionary = players[p]
		var who := _dim(EventText.side(p, viewer))
		if TeamPalette.has(p):  # a side's colour is its identity, not a theme's
			who.add_theme_color_override("font_color", TeamPalette.text_color(p))
		grid.add_child(who)
		for key: String in ["squads_lost", "commanders_lost", "features_taken"]:
			var n := Label.new()
			n.text = str(int(row.get(key, 0)))
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(n)
	col.add_child(grid)
	if not note.is_empty():
		var l := _dim(note)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size = Vector2(470, 0)
		l.theme_type_variation = &"CaptionDimLabel"
		col.add_child(l)
	col.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.theme_type_variation = &"FormGap"
	if bool(offer.get("replay", false)):
		row.add_child(_button("Again", "Play again", play_again.emit))
	if bool(offer.get("menu", false)):
		row.add_child(_button("Menu", "Main menu", main_menu.emit))
	var look := _button("Look", "Look at the map", close_screen)
	focus_target = look  # the harmless choice, for a player still pressing Space
	row.add_child(look)
	col.add_child(row)


func close_screen() -> void:
	close()


func _button(node_name: String, text: String, on: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on)
	return b


func _dim(text: String) -> Label:
	return UiTheme.label(text, "DimLabel")
