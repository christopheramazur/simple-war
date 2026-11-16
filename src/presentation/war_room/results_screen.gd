class_name ResultsScreen
extends Control
## The results screen (sw-ll4.11): shown over the war room when the match
## ends. Says who won and why, how long it took and what each side lost
## (MatchDriver.stats), and offers to play again, go to the menu, or look
## at the map. Presentation only.

signal play_again
signal main_menu
signal closed

const PANEL: Color = Color("1d2128")
const DIM: Color = Color("8a93a3")
const WON: Color = Color("74d18a")
const LOST: Color = Color("e8735f")


## `result`: "won", "lost" or "drew" for the viewer. `reason`: the outcome's
## text. `stats`: MatchDriver.stats. `offer`: {"replay": show "Play again",
## "menu": show "Main menu", "note": a line under the tallies}.
static func open_over(parent: Node, result: String, reason: String, stats: Dictionary, viewer: int, offer: Dictionary = {}) -> ResultsScreen:
	var r := ResultsScreen.new()
	r._build(result, reason, stats, viewer, offer)
	parent.add_child(r)
	return r


func _build(result: String, reason: String, stats: Dictionary, viewer: int, offer: Dictionary) -> void:
	var note := String(offer.get("note", ""))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.05, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_content_margin_all(24)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.name = "Title"
	title.text = {"won": "Victory", "lost": "Defeat"}.get(result, "Draw")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", WON if result == "won" else (LOST if result == "lost" else Color("e6b450")))
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
	grid.add_theme_constant_override("h_separation", 22)
	for head: String in ["", "Squads lost", "Commanders lost", "Features taken"]:
		grid.add_child(_dim(head))
	var players: Dictionary = stats.get("players", {})
	var ids: Array = players.keys()
	ids.sort()
	for p: int in ids:
		var row: Dictionary = players[p]
		var who := Label.new()
		who.text = EventText.side(p, viewer)
		who.add_theme_color_override("font_color", ContextView.PLAYER_COLORS.get(p, DIM))
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
		l.add_theme_font_size_override("font_size", 12)
		col.add_child(l)
	col.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if bool(offer.get("replay", false)):
		row.add_child(_button("Again", "Play again", play_again.emit))
	if bool(offer.get("menu", false)):
		row.add_child(_button("Menu", "Main menu", main_menu.emit))
	row.add_child(_button("Look", "Look at the map", close_screen))
	col.add_child(row)


func close_screen() -> void:
	closed.emit()
	queue_free()


func _button(node_name: String, text: String, on: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on)
	return b


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	return l
