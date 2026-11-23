class_name InspectionTabs
extends RefCounted
## The inspection window's tabs (sw-ll4.20, Mocks/inspection_window.png) over
## inspect_battle's data: Squad (the SquadCard page, with per-unit cards that
## open a unit in Units), Units (one unit's defensive and offensive stats,
## hover for how each is calculated), Effects (rules text, timing, who each
## affects) and Abilities (owner only). Pure formatting: the tab and the
## selected unit are the caller's (BattlePanel) and come back through
## `on_pick`. Every number is the simulation's.

const TABS: Array = ["squad", "units", "effects", "abilities"]
const TAB_NAMES: Dictionary = {"squad": "Squad", "units": "Units", "effects": "Effects", "abilities": "Abilities"}


## The tab names available for `insp`: abilities only when the owner's
## report carries them.
static func tabs_for(insp: Dictionary) -> Array:
	var out := ["squad", "units", "effects"]
	if insp.has("abilities"):
		out.append("abilities")
	return out


## `on_pick`: Callable(tab: String, unit_id: int) called when a tab button or
## a unit card is pressed. `tab`: the shown tab; `unit`: the selected unit id
## for Units (-1 = the first).
static func build(squad: Dictionary, insp: Dictionary, viewer: int, tps: int, verbose: bool, ctx: Dictionary,
		tab: String, unit: int, on_pick: Callable) -> VBoxContainer:
	if insp.is_empty():
		return SquadCard.build(squad, insp, viewer, tps, verbose, ctx)
	var names := tabs_for(insp)
	if not names.has(tab):
		tab = "squad"
	var col := VBoxContainer.new()
	col.theme_type_variation = &"CardGap"
	# Flows onto a second line when the column is narrow (sw-7m6).
	var bar := HFlowContainer.new()
	for t: String in names:
		var n := String(TAB_NAMES[t])
		if t == "effects":
			n += " (%d)" % (insp.get("effects", []) as Array).size()
		elif t == "abilities":
			n += " (%d)" % (insp.get("abilities", []) as Array).size()
		var b := Button.new()
		b.text = n
		b.toggle_mode = true
		b.button_pressed = t == tab
		b.set_meta(&"tab", t)
		b.pressed.connect(on_pick.bind(t, unit))
		bar.add_child(b)
	col.add_child(bar)
	match tab:
		"units":
			_units(col, insp, unit, on_pick)
		"effects":
			_effects(col, insp, tps)
		"abilities":
			_abilities(col, insp, tps)
		_:
			col.add_child(SquadCard.build(squad, insp, viewer, tps, verbose, ctx))
			_unit_cards(col, insp, on_pick)
			_opponent_view(col, insp, ctx.get("opponent_insp", {}))
	return col


## One compact card per unit; pressing it opens the unit in Units.
static func _unit_cards(col: VBoxContainer, insp: Dictionary, on_pick: Callable) -> void:
	var units: Array = insp.get("units", [])
	if units.is_empty():
		return
	col.add_child(UiTheme.label("Units", "CardHeadLabel"))
	var labels := SquadCard._unit_labels(units)
	for u: Dictionary in units:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s / %s" % [labels[int(u["id"])], Fixed.to_display(u["hp"]), Fixed.to_display(u["hp_max"])]
		if int(u["hp"]) <= 0:
			b.text += "  (down)"
		b.set_meta(&"unit", int(u["id"]))
		b.pressed.connect(on_pick.bind("units", int(u["id"])))
		col.add_child(b)


static func _units(col: VBoxContainer, insp: Dictionary, unit: int, on_pick: Callable) -> void:
	var units: Array = insp.get("units", [])
	if units.is_empty():
		col.add_child(UiTheme.label("No units to show.", "SmallDimLabel"))
		return
	var labels := SquadCard._unit_labels(units)
	var sel: Dictionary = units[0]
	for u: Dictionary in units:
		if int(u["id"]) == unit:
			sel = u
	var strip := HFlowContainer.new()
	for u: Dictionary in units:
		var b := Button.new()
		b.text = String(labels[int(u["id"])])
		b.toggle_mode = true
		b.button_pressed = int(u["id"]) == int(sel["id"])
		b.set_meta(&"unit", int(u["id"]))
		b.pressed.connect(on_pick.bind("units", int(u["id"])))
		strip.add_child(b)
	col.add_child(strip)
	col.add_child(UiTheme.label("Defensive", "CardHeadLabel"))
	var offensive := []
	for e: Dictionary in sel.get("stats", []):
		var stat := String(e["stat"])
		if stat == "unit.hp":
			col.add_child(_stat_row("HP", "%s / %s" % [Fixed.to_display(sel["hp"]), Fixed.to_display(sel["hp_max"])], "SmallLabel", trace_text(e)))
		elif stat.begins_with("defense."):
			col.add_child(_entry_row(e))
		else:
			offensive.append(e)
	col.add_child(UiTheme.label("Offensive", "CardHeadLabel"))
	for e: Dictionary in offensive:
		col.add_child(_entry_row(e))
	col.add_child(UiTheme.label("Coloured values are modified; hover one for how it is calculated.", "CaptionDimLabel", true))


static func _entry_row(e: Dictionary) -> Control:
	var name := String(e["name"])
	if not String(e.get("label", "")).is_empty():
		name += " (%s)" % e["label"]
	return _stat_row(name, SquadCard._fmt(e), SquadCard._tone(e), trace_text(e))


static func _stat_row(name: String, value: String, tone: String, tip: String) -> Control:
	var row := HBoxContainer.new()
	var n := UiTheme.label(name, "SmallLabel")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := UiTheme.label(value, tone)
	row.add_child(v)
	if not tip.is_empty():
		row.tooltip_text = tip
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		v.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


## How a stat is calculated, from its trace: the base, each step's terms (the
## bundle that contributed and by how much) and the result.
static func trace_text(e: Dictionary) -> String:
	var name := String(e["name"])
	if not String(e.get("label", "")).is_empty():
		name += " (%s)" % e["label"]
	var base := e.duplicate()
	base["value"] = e["base"]
	var lines := PackedStringArray(["%s: how it's calculated" % name, "Base  %s" % SquadCard._fmt(base)])
	for step: Dictionary in e.get("trace", []):
		var terms := PackedStringArray()
		for t: Dictionary in step.get("terms", []):
			terms.append("%s %s" % [t["name"], Fixed.to_display(int(t["amount"]))])
		var at := e.duplicate()
		at["value"] = step["value"]
		lines.append("%s  %s%s" % [String(step["step"]).capitalize(), SquadCard._fmt(at),
			"  (%s)" % ", ".join(terms) if not terms.is_empty() else ""])
	lines.append("Result  %s" % SquadCard._fmt(e))
	return "\n".join(lines)


static func _effects(col: VBoxContainer, insp: Dictionary, tps: int) -> void:
	var effects: Array = insp.get("effects", [])
	if effects.is_empty():
		col.add_child(UiTheme.label("No effects.", "SmallDimLabel"))
		return
	var labels := SquadCard._unit_labels(insp.get("units", []))
	for fx: Dictionary in effects:
		var left := int(fx.get("remaining_ticks", -1))
		var time := "lasts the battle" if left < 0 else "%.1f s left" % (float(left) / maxi(tps, 1))
		var stacks := "" if int(fx.get("stacks", 1)) <= 1 else " ×%d" % int(fx["stacks"])
		col.add_child(UiTheme.label("%s%s  (%s)" % [fx["name"], stacks, time], "SmallAccentLabel"))
		for text: String in fx.get("lines", []):
			col.add_child(UiTheme.label("  " + text, "CaptionDimLabel", true))
		var acc: Dictionary = fx.get("accumulator", {})
		if not acc.is_empty() and acc.has("text"):
			col.add_child(UiTheme.label("  " + String(acc["text"]), "CaptionDimLabel", true))
		var uid := int(fx.get("unit", -1))
		col.add_child(UiTheme.label("  Affects: %s" % ("whole squad" if uid < 0 else String(labels.get(uid, "a unit"))), "CaptionDimLabel"))


static func _abilities(col: VBoxContainer, insp: Dictionary, tps: int) -> void:
	var abs: Array = insp.get("abilities", [])
	if abs.is_empty():
		col.add_child(UiTheme.label("No abilities.", "SmallDimLabel"))
		return
	for a: Dictionary in abs:
		var state := "ready"
		if bool(a.get("toggle", false)):
			state = "on" if bool(a.get("on", false)) else "off"
		if int(a.get("cooldown_ticks", 0)) > 0:
			state = "cooling down %.1f s" % (float(a["cooldown_ticks"]) / maxi(tps, 1))
		elif int(a.get("readying_ticks", 0)) > 0:
			state = "readying %.1f s" % (float(a["readying_ticks"]) / maxi(tps, 1))
		col.add_child(UiTheme.label("%s  (%s)" % [a["name"], state], "SmallAccentLabel"))
		var costs := PackedStringArray()
		var cd: Dictionary = a.get("costs", {})
		for p: String in cd:
			costs.append("%s %s" % [p.capitalize(), Fixed.to_display(int(cd[p]))])
		if not costs.is_empty():
			col.add_child(UiTheme.label("  Costs: " + ", ".join(costs), "CaptionDimLabel"))
		for text: String in a.get("lines", []):
			col.add_child(UiTheme.label("  " + text, "CaptionDimLabel", true))


## "What the opponent sees" (E2Q12): for your own squad, the effects you hold
## that they see disguised (or not at all), and the stats that differ.
static func _opponent_view(col: VBoxContainer, mine: Dictionary, theirs: Dictionary) -> void:
	if theirs.is_empty() or not mine.has("abilities"):
		return
	col.add_child(UiTheme.label("What the opponent sees", "CardHeadLabel"))
	var seen := {}
	for e: Dictionary in theirs.get("effects", []):
		seen[e["bundle"]] = e
	var shown := {}
	for e: Dictionary in mine.get("effects", []):
		shown[e["bundle"]] = true
		if not seen.has(e["bundle"]):
			col.add_child(UiTheme.label("  %s is disguised" % e["name"], "SmallAccentLabel"))
	for e: Dictionary in theirs.get("effects", []):
		if not shown.has(e["bundle"]):
			col.add_child(UiTheme.label("  They see %s instead" % e["name"], "CaptionDimLabel"))
	var diffs := 0
	var mu: Array = mine.get("units", [])
	var tu: Array = theirs.get("units", [])
	for i in mini(mu.size(), tu.size()):
		for e: Dictionary in tu[i].get("stats", []):
			for m: Dictionary in mu[i].get("stats", []):
				if m["stat"] == e["stat"] and m.get("label", "") == e.get("label", "") and m["value"] != e["value"]:
					diffs += 1
					col.add_child(UiTheme.label("  %s: you %s, they %s" % [e["name"], SquadCard._fmt(m), SquadCard._fmt(e)], "CaptionDimLabel", true))
	if diffs == 0 and seen.size() == shown.size():
		col.add_child(UiTheme.label("  The same as you see.", "CaptionDimLabel"))
