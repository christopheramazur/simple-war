class_name SquadCard
extends RefCounted
## The squad card of the war room's battle panel (sw-ll4.19): one squad's
## strength, pools, order, weapons (range, accuracy, damage), movement,
## defence, effects and unit health. It only formats what the game reports
## (observe_battle and inspect_battle): every number is the simulation's.
## SIMPL pools draw as five-segment meters with ticks at the band floors the
## observation carries (sw-1jy.3, GDD 02 §2.8): band icon + word always, the
## exact percent and the points to the next lower band only at higher
## verbosity (sw-1jy.4); never colour alone.
## A first, one-page form of the inspection window (Mocks/
## inspection_window.png); the tabs and per-stat traces are not built.

const ORDER_NAMES: Dictionary = {
	"hold": "Holding", "move": "Moving", "attack_move": "Attack-moving", "attack": "Attacking",
	"fall_back": "Falling back", "withdraw": "Withdrawing",
}

## Band glyphs, a ladder from empty/low to filled/high so the state reads
## without colour. Presentation only: the bands themselves come from the API.
const BAND_ICONS: Dictionary = {
	"broken": "×", "fraying": "▽", "neutral": "◇", "primed": "△", "surging": "▲",
}


## `squad`: its entry in observe_battle's "squads". `insp`: inspect_battle's
## result ({} shows only what the observation has). `viewer`: the player
## looking. `tps`: ticks per second, for effect times. `verbose`: also show
## value / capacity, the exact percent and the sim's points-to-drop on the
## SIMPL meters.
static func build(squad: Dictionary, insp: Dictionary, viewer: int, tps: int = 10, verbose: bool = false) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.theme_type_variation = &"CardGap"
	var own := int(squad.get("player", 0)) == viewer
	col.add_child(_lbl(String(squad.get("name", squad.get("template", "Squad"))), "SubheadLabel"))
	var alive := int(squad.get("alive", 0))
	var size := int(squad.get("size", alive))
	var who := "yours" if own else ("neutral" if int(squad.get("player", 0)) >= 30 else "enemy, player %d" % int(squad.get("player", 0)))
	col.add_child(_lbl("%d / %d units  ·  %s" % [alive, size, who], "SmallGoodLabel" if alive >= size else ("SmallAccentLabel" if alive * 2 >= size else "SmallBadLabel")))
	if own:
		var order := String(squad.get("order", "hold"))
		col.add_child(_lbl("Order: %s" % ORDER_NAMES.get(order, order.capitalize()), "SmallDimLabel"))
		var hp_max := float(squad.get("hp_max", 0))
		if hp_max > 0.0:
			col.add_child(_stat_bar("Health", 1.0 - float(squad.get("hp_lost", 0)) / hp_max, "Good", ""))
		var pools: Dictionary = squad.get("pools", {})
		var floors: Array = squad.get("band_floor_pct", [])
		for p: String in pools:
			var pd: Dictionary = pools[p]
			var cap := float(pd["capacity"])
			var frac := float(pd["value"]) / cap if cap > 0.0 else 0.0
			if DataSchema.SIMPL.has(p) and floors.size() == DataSchema.BANDS.size():
				col.add_child(_simpl_meter(p, pd, floors, verbose))
			else:
				col.add_child(_stat_bar(p.capitalize(), frac, _pool_tone(p),
					"%s  %s" % [Fixed.to_display(pd["value"]), String(pd["band"]).capitalize()]))
	col.add_child(_head("Reach"))
	var reach := "Weapon range %s m" % Fixed.to_display(int(squad.get("range", 0))) if int(squad.get("range", 0)) > 0 else "No ranged weapon"
	col.add_child(_lbl("%s  ·  sight %s m" % [reach, Fixed.to_display(int(squad.get("sight", 0)))], "SmallLabel"))
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
		col.add_child(_lbl("Health %s / %s" % [Fixed.to_display(hp), Fixed.to_display(hp_top)], "SmallLabel"))
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
			line.add_child(_lbl("%s:" % String(label).capitalize(), "SmallDimLabel"))
			if m.has("accuracy"):
				line.add_child(_lbl("%s to hit" % _fmt(m["accuracy"]), _tone(m["accuracy"])))
			if m.has("damage"):
				line.add_child(_lbl("· %s damage" % _fmt(m["damage"]), _tone(m["damage"])))
			col.add_child(line)
		if not move.is_empty():
			col.add_child(_lbl("Speed: " + ", ".join(move), "SmallLabel"))
		col.add_child(_lbl("Defence: " + (", ".join(defence) if not defence.is_empty() else "none"), "CaptionDimLabel", true))
	var effects: Array = insp.get("effects", [])
	if not effects.is_empty():
		col.add_child(_head("Effects"))
		for fx: Dictionary in effects:
			var left := int(fx.get("remaining_ticks", -1))
			var time := "lasts the battle" if left < 0 else "%.1f s left" % (float(left) / maxi(tps, 1))
			var stacks := "" if int(fx.get("stacks", 1)) <= 1 else " ×%d" % int(fx["stacks"])
			col.add_child(_lbl("%s%s  (%s)" % [fx["name"], stacks, time], "SmallAccentLabel"))
			for text: String in fx.get("lines", []):
				col.add_child(_lbl("  " + text, "CaptionDimLabel", true))
	return col


## Coloured when an effect has changed the value from its base.
static func _tone(e: Dictionary) -> String:
	if int(e["value"]) > int(e["base"]):
		return "SmallGoodLabel"
	return "SmallBadLabel" if int(e["value"]) < int(e["base"]) else "SmallLabel"


## The tone named after a pool, if the styles have one.
static func _pool_tone(pool: String) -> String:
	var tone := pool.capitalize()
	return tone if (UiTheme.styles().get("tones", {}) as Dictionary).has(tone) else "Text"


## One SIMPL pool as five countable segments (sw-1jy.3): the segment edges
## and the ticks sit at the band floors the observation carries, the fill is
## the pool's theme tone, and the band reads as icon + word, never colour
## alone. `floors` is the compiled band_floor_pct; the sim owns the mapping.
static func _simpl_meter(pool: String, pd: Dictionary, floors: Array, verbose: bool) -> Control:
	var tone := _pool_tone(pool)
	var row := HBoxContainer.new()
	var l := _lbl(pool.capitalize(), "Caption%sLabel" % tone)
	l.custom_minimum_size = Vector2(62, 0)
	row.add_child(l)
	var c := Control.new()
	c.custom_minimum_size = Vector2(120, 8)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(UiTheme.backdrop("ScreenBackgroundPanel"))
	var cap := float(pd["capacity"])
	var pct := float(pd["value"]) / cap * 100.0 if cap > 0.0 else 0.0
	for b in DataSchema.BANDS.size():
		var lo := 0.0 if b == 0 else float(floors[b])
		var hi := float(floors[b + 1]) if b + 1 < floors.size() else 100.0
		var seg := Panel.new()
		seg.theme_type_variation = "LineBar"
		seg.set_meta(&"band", b)
		seg.anchor_left = lo / 100.0
		seg.anchor_right = hi / 100.0
		seg.anchor_bottom = 1.0
		seg.offset_left = 1.0
		seg.offset_right = -1.0
		c.add_child(seg)
		var fill := clampf((pct - lo) / (hi - lo), 0.0, 1.0) if hi > lo else 0.0
		if fill > 0.0:
			var f := Panel.new()
			f.theme_type_variation = "%sBar" % tone
			f.anchor_right = fill
			f.anchor_bottom = 1.0
			seg.add_child(f)
	# Ticks at every inner floor, a little taller than the bar so the
	# thresholds stay visible whatever the fill does.
	for b in range(1, floors.size()):
		var tick := Panel.new()
		tick.theme_type_variation = "DimBar"
		tick.set_meta(&"tick", int(floors[b]))
		tick.anchor_left = float(floors[b]) / 100.0
		tick.anchor_right = tick.anchor_left
		tick.anchor_bottom = 1.0
		tick.offset_left = -1.0
		tick.offset_top = -2.0
		tick.offset_bottom = 2.0
		c.add_child(tick)
	row.add_child(c)
	var band := String(pd["band"])
	var text := "%s %s  %s" % [_band_icon(band), _band_word(band), Fixed.to_display(pd["value"])]
	if verbose:
		var pct_i := Fixed.round_div(int(pd["value"]) * 100, int(pd["capacity"])) if int(pd["capacity"]) > 0 else 0
		text += " / %s  (%d%%)" % [Fixed.to_display(pd["capacity"]), pct_i]
		# The distance is the sim's own arithmetic (sw-1jy.4), read here,
		# never recomputed: how many points this pool can lose before the
		# band drops. Broken has no lower band, so it adds nothing.
		var drop := BattleRules.points_to_drop(int(pd["value"]), int(pd["capacity"]), PackedInt64Array(floors))
		var bi := DataSchema.BANDS.find(band)
		if drop >= 0 and bi > 0:
			text += "  · %s to %s" % [Fixed.to_display(drop), _band_word(DataSchema.BANDS[bi - 1])]
	row.add_child(_lbl(text, "CaptionDimLabel"))
	return row


## The band word through the translation table (the glossary's "band.<id>"
## keys), with the English fallback until translation tables exist.
static func _band_word(band: String) -> String:
	var key := "band." + band
	var s := String(TranslationServer.translate(key))
	return s if s != key else band.capitalize()


static func _band_icon(band: String) -> String:
	var key := "band_icon." + band
	var s := String(TranslationServer.translate(key))
	return s if s != key else String(BAND_ICONS.get(band, "·"))


static func _fmt(e: Dictionary) -> String:
	var v := int(e["value"])
	if String(e["stat"]).ends_with("accuracy"):
		return "%d%%" % Fixed.to_int_round(v * 100)
	var u := String(e["unit"])
	if u == "%":
		return Fixed.to_display(v) + "%"
	return Fixed.to_display(v) if u.is_empty() else "%s %s" % [Fixed.to_display(v), u]


static func _head(text: String) -> Label:
	return _lbl(text, "CardHeadLabel")


static func _lbl(text: String, style: String, wrap: bool = false) -> Label:
	return UiTheme.label(text, style, wrap)


static func _stat_bar(name: String, frac: float, tone: String, text: String) -> Control:
	var row := HBoxContainer.new()
	var l := _lbl(name, "Caption%sLabel" % tone)
	l.custom_minimum_size = Vector2(62, 0)
	row.add_child(l)
	var c := Control.new()
	c.custom_minimum_size = Vector2(70, 6)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(UiTheme.backdrop("LineBar"))
	var fill := Panel.new()
	fill.theme_type_variation = "%sBar" % tone
	fill.anchor_right = clampf(frac, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	c.add_child(fill)
	row.add_child(c)
	if not text.is_empty():
		row.add_child(_lbl(text, "CaptionDimLabel"))
	return row
