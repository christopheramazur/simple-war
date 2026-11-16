class_name BattlePanel
extends VBoxContainer
## The war room's panel for a focused battle (split from war_room.gd,
## sw-ll4.8): the scores, the zones and one squad's card (SquadCard). It
## formats what it is given and holds nothing.

const DIM: Color = Color("8a93a3")


## `obs`: observe_battle's result. `squad`: the squad's entry in it ({} for
## none) and `insp` its inspect_battle result. `tps`: ticks per second.
func show_battle(title: String, obs: Dictionary, squad: Dictionary, insp: Dictionary, player: int, tps: int) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = "%s  ·  battle turn %d" % [title, int(obs.get("turn", 1))]
	head.add_theme_color_override("font_color", DIM)
	add_child(head)
	var scores: Dictionary = obs.get("scores", {})
	var who: Array = scores.keys()
	who.sort()
	for p: int in who:
		var l := _dim("%s:  influence %d  ·  value %d" % [EventText.side(p, player).capitalize(), int(scores[p]["influence"]), int(scores[p]["value"])])
		l.add_theme_color_override("font_color", ContextView.PLAYER_COLORS.get(p, DIM))
		add_child(l)
	for z: Dictionary in obs.get("zones", []):
		var owner := int(z["owner"])
		add_child(_dim("Zone %s: %s (%d of %d)" % [z["id"], "nobody" if owner == 0 else EventText.side(owner, player),
			int(z["amount"]), int(z["threshold"])]))
	add_child(HSeparator.new())
	if squad.is_empty():
		add_child(_dim("Click a squad to see its strength, weapons and range. Hovering one shows how far its weapons reach."))
		return
	add_child(SquadCard.build(squad, insp, player, tps))


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
