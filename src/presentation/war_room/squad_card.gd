class_name SquadCard
extends RefCounted
## The squad card of the war room's battle panel (sw-ll4.19): one squad's
## strength, pools, order, weapons (range, accuracy, damage), movement,
## defence, effects and unit health. It only formats what the game reports
## (observe_battle and inspect_battle): every number is the simulation's.
## A first, one-page form of the inspection window (Mocks/
## inspection_window.png); the tabs and per-stat traces are not built.

const TEXT := Color("dde2ea")
const DIM := Color("8a93a3")
const LINE := Color("323a46")
const ACCENT := Color("e6b450")
const UP := Color("74d18a")
const DOWN := Color("e8735f")
const POOL_COLORS: Dictionary = {
	"stamina": Color("5bb6d9"), "instinct": Color("b38be0"), "morale": Color("74d18a"),
	"prowess": Color("e6b450"), "legend": Color("e07ab0"),
}
const ORDER_NAMES: Dictionary = {
	"hold": "Holding", "move": "Moving", "attack_move": "Attack-moving", "attack": "Attacking",
	"fall_back": "Falling back", "withdraw": "Withdrawing",
}


## `squad`: its entry in observe_battle's "squads". `insp`: inspect_battle's
## result ({} shows only what the observation has). `viewer`: the player
## looking. `tps`: ticks per second, for effect times.
static func build(squad: Dictionary, insp: Dictionary, viewer: int, tps: int = 10) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var own := int(squad.get("player", 0)) == viewer
	col.add_child(_lbl(String(squad.get("name", squad.get("template", "Squad"))), 18, TEXT))
	var alive := int(squad.get("alive", 0))
	var size := int(squad.get("size", alive))
	var who := "yours" if own else ("neutral" if int(squad.get("player", 0)) >= 30 else "enemy, player %d" % int(squad.get("player", 0)))
	col.add_child(_lbl("%d / %d units  ·  %s" % [alive, size, who], 13, UP if alive >= size else (ACCENT if alive * 2 >= size else DOWN)))
	if own:
		var order := String(squad.get("order", "hold"))
		col.add_child(_lbl("Order: %s" % ORDER_NAMES.get(order, order.capitalize()), 13, DIM))
		var hp_max := float(squad.get("hp_max", 0))
		if hp_max > 0.0:
			col.add_child(_stat_bar("Health", 1.0 - float(squad.get("hp_lost", 0)) / hp_max, UP, ""))
		var pools: Dictionary = squad.get("pools", {})
		for p: String in pools:
			var pd: Dictionary = pools[p]
			var cap := float(pd["capacity"])
			col.add_child(_stat_bar(p.capitalize(), float(pd["value"]) / cap if cap > 0.0 else 0.0, POOL_COLORS.get(p, TEXT),
				"%s  %s" % [Fixed.to_display(pd["value"]), String(pd["band"]).capitalize()]))
	col.add_child(_head("Reach"))
	var reach := "Weapon range %s m" % Fixed.to_display(int(squad.get("range", 0))) if int(squad.get("range", 0)) > 0 else "No ranged weapon"
	col.add_child(_lbl("%s  ·  sight %s m" % [reach, Fixed.to_display(int(squad.get("sight", 0)))], 13, TEXT))
	if insp.is_empty():
		return col
	# One block per unit type: count, health, weapon modes, movement, defence.
	var groups := {}
	var order_of := []
	for u: Dictionary in insp.get("units", []):
		var key := String(u["template"])
		if not groups.has(key):
			groups[key] = []
			order_of.append(key)
		(groups[key] as Array).append(u)
	for key: String in order_of:
		var us: Array = groups[key]
		var first: Dictionary = us[0]
		var hp := 0
		var hp_top := 0
		for u: Dictionary in us:
			hp += int(u["hp"])
			hp_top += int(u["hp_max"])
		col.add_child(_head("%d × %s" % [us.size(), first["name"]]))
		col.add_child(_lbl("Health %s / %s" % [Fixed.to_display(hp), Fixed.to_display(hp_top)], 13, TEXT))
		var modes := {}
		var defence := PackedStringArray()
		var move := PackedStringArray()
		for e: Dictionary in first.get("stats", []):
			var stat := String(e["stat"])
			if stat.begins_with("weapon.modes"):
				var m: Dictionary = modes.get(e["label"], {})
				m["accuracy" if stat.ends_with("accuracy") else "damage"] = e
				modes[e["label"]] = m
			elif stat == "movement.walk":
				move.append("walk %s" % _fmt(e))
			elif stat == "movement.run":
				move.append("run %s" % _fmt(e))
			elif stat.begins_with("defense.") and int(e["value"]) != 0:
				defence.append("%s %s" % [e["name"], _fmt(e)])
		for label: String in modes:
			var m: Dictionary = modes[label]
			var line := HBoxContainer.new()
			line.add_child(_lbl("%s:" % String(label).capitalize(), 13, DIM))
			if m.has("accuracy"):
				line.add_child(_lbl("%s to hit" % _fmt(m["accuracy"]), 13, _tone(m["accuracy"])))
			if m.has("damage"):
				line.add_child(_lbl("· %s damage" % _fmt(m["damage"]), 13, _tone(m["damage"])))
			col.add_child(line)
		if not move.is_empty():
			col.add_child(_lbl("Speed: " + ", ".join(move), 13, TEXT))
		col.add_child(_lbl("Defence: " + (", ".join(defence) if not defence.is_empty() else "none"), 12, DIM, true))
	var effects: Array = insp.get("effects", [])
	if not effects.is_empty():
		col.add_child(_head("Effects"))
		for fx: Dictionary in effects:
			var left := int(fx.get("remaining_ticks", -1))
			var time := "lasts the battle" if left < 0 else "%.1f s left" % (float(left) / maxi(tps, 1))
			var stacks := "" if int(fx.get("stacks", 1)) <= 1 else " ×%d" % int(fx["stacks"])
			col.add_child(_lbl("%s%s  (%s)" % [fx["name"], stacks, time], 13, ACCENT))
			for text: String in fx.get("lines", []):
				col.add_child(_lbl("  " + text, 12, DIM, true))
	return col


## Coloured when an effect has changed the value from its base.
static func _tone(e: Dictionary) -> Color:
	if int(e["value"]) > int(e["base"]):
		return UP
	return DOWN if int(e["value"]) < int(e["base"]) else TEXT


static func _fmt(e: Dictionary) -> String:
	var v := int(e["value"])
	if String(e["stat"]).ends_with("accuracy"):
		return "%d%%" % Fixed.to_int_round(v * 100)
	var u := String(e["unit"])
	if u == "%":
		return Fixed.to_display(v) + "%"
	return Fixed.to_display(v) if u.is_empty() else "%s %s" % [Fixed.to_display(v), u]


static func _head(text: String) -> Label:
	var l := _lbl(text, 13, ACCENT)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func _lbl(text: String, size: int, color: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _stat_bar(name: String, frac: float, color: Color, text: String) -> Control:
	var row := HBoxContainer.new()
	var l := _lbl(name, 12, color)
	l.custom_minimum_size = Vector2(62, 0)
	row.add_child(l)
	var c := Control.new()
	c.custom_minimum_size = Vector2(70, 6)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back := ColorRect.new()
	back.color = LINE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_right = clampf(frac, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	c.add_child(fill)
	row.add_child(c)
	if not text.is_empty():
		row.add_child(_lbl(text, 12, DIM))
	return row
