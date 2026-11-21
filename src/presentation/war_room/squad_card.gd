class_name SquadCard
extends RefCounted
## The squad card of the war room's battle panel (sw-ll4.19): one squad's
## strength, pools, order, weapons (range, accuracy, damage), movement,
## defence, effects and unit health. It only formats what the game reports
## (observe_battle and inspect_battle): every number is the simulation's.
## Since sw-ll4.27.3 it also says what the squad is doing and why its guns
## are silent (BattleActivity codes through the Glossary), per weapon and
## per unit, and follows the shown moment during playback (moment()).
## SIMPL pools draw as five-segment meters with ticks at the band floors the
## observation carries (sw-1jy.3, GDD 02 §2.8): band icon + word always, the
## exact percent only at higher verbosity; never colour alone.
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
## value / capacity and the exact percent on the SIMPL meters, and the exact
## tick counts on weapon timers. `ctx`: display context the caller resolves —
## "rules" (BattleRules: range bands, damage types, timer totals),
## "weapon_names" (weapon ID -> display name) and "target_name" (the engaged
## squad's name, for the activity line).
static func build(squad: Dictionary, insp: Dictionary, viewer: int, tps: int = 10, verbose: bool = false, ctx: Dictionary = {}) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.theme_type_variation = &"CardGap"
	var own := int(squad.get("player", 0)) == viewer
	col.add_child(_lbl(String(squad.get("name", squad.get("template", "Squad"))), "SubheadLabel"))
	var alive := int(squad.get("alive", 0))
	var size := int(squad.get("size", alive))
	var who := "yours" if own else ("neutral" if int(squad.get("player", 0)) >= 30 else "enemy, player %d" % int(squad.get("player", 0)))
	col.add_child(_lbl("%d / %d units  ·  %s" % [alive, size, who], "SmallGoodLabel" if alive >= size else ("SmallAccentLabel" if alive * 2 >= size else "SmallBadLabel")))
	# What the squad is doing, in the glossary's words (sw-ll4.27.3). The
	# code is the simulation's (BattleActivity); enemies carry behaviour only.
	var act := int(squad.get("activity", insp.get("activity", -1)))
	if act >= 0:
		var tname := String(ctx.get("target_name", ""))
		if act == BattleActivity.Squad.ENGAGED and tname.is_empty():
			tname = "the enemy"
		col.add_child(_lbl(Glossary.activity_text(act, tname), "SmallAccentLabel"))
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
	if own and not insp.is_empty():
		_weapons(col, insp, ctx, tps, verbose)
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


## The live weapon block (sw-ll4.27.3): one block per weapon the squad's
## units carry, from the inspection's unit reports (BattleActivity.
## unit_report). Name, damage type, modes, the range band against each
## unit's target distance, ammo, reload / cooldown progress, the hold-fire
## reason in the glossary's words, and shots / hits this turn when the
## caller carries them (playback). Every number is the simulation's.
static func _weapons(col: VBoxContainer, insp: Dictionary, ctx: Dictionary, tps: int, verbose: bool) -> void:
	var units: Array = insp.get("units", [])
	var groups := {}
	var order := []
	var labels := _unit_labels(units)
	var any_shots := false
	for u: Dictionary in units:
		if not u.has("weapon"):
			continue  # enemy units carry no report (fog)
		var wid := String(u["weapon"])
		if wid.is_empty():
			continue  # unarmed: no weapon block
		if not groups.has(wid):
			groups[wid] = []
			order.append(wid)
		(groups[wid] as Array).append(u)
		any_shots = any_shots or u.has("shots")
	if order.is_empty():
		return
	col.add_child(_head("Weapons"))
	if not any_shots:
		col.add_child(_lbl("Shots and hits this turn show during playback.", "CaptionDimLabel", true))
	var rules: BattleRules = ctx.get("rules")
	var wnames: Dictionary = ctx.get("weapon_names", {})
	for wid: String in order:
		var us: Array = groups[wid]
		var first: Dictionary = us[0]
		var w := int(rules.weapon_index.get(wid, -1)) if rules != null else -1
		var title := "%d × %s" % [us.size(), String(wnames.get(wid, wid.replace("_", " ").capitalize()))]
		var reload_total := 0
		var cool_total := 0
		if w >= 0:
			title += " · %s" % String(DataSchema.DAMAGE_TYPES[rules.wp_type[w]]).capitalize()
			reload_total = rules.wp_reload[w]
			for m in range(rules.wp_mode_start[w], rules.wp_mode_start[w] + rules.wp_mode_count[w]):
				cool_total = maxi(cool_total, rules.md_cooldown[m])
		col.add_child(_lbl(title, "SmallLabel"))
		var modes := {}
		for e: Dictionary in first.get("stats", []):
			var stat := String(e["stat"])
			if stat.begins_with("weapon.modes"):
				var m: Dictionary = modes.get(e["label"], {})
				m["accuracy" if stat.ends_with("accuracy") else "damage"] = e
				modes[e["label"]] = m
		for label: String in modes:
			var m: Dictionary = modes[label]
			var line := HBoxContainer.new()
			line.add_child(_lbl("%s:" % String(label).capitalize(), "SmallDimLabel"))
			if m.has("accuracy"):
				line.add_child(_lbl("%s to hit" % _fmt(m["accuracy"]), _tone(m["accuracy"])))
			if m.has("damage"):
				line.add_child(_lbl("· %s damage" % _fmt(m["damage"]), _tone(m["damage"])))
			col.add_child(line)
		if w >= 0:
			col.add_child(_lbl("Range %s–%s m" % [Fixed.to_display(rules.wp_min_range[w]), Fixed.to_display(rules.wp_range[w])], "CaptionDimLabel"))
		for u: Dictionary in us:
			_weapon_unit(col, u, String(labels[int(u["id"])]), w, rules, reload_total, cool_total, tps, verbose)


## One unit's weapon state: the hold reason in words, time to fire, ammo,
## the target's distance against the range band, and shots / hits this turn.
static func _weapon_unit(col: VBoxContainer, u: Dictionary, uname: String, w: int, rules: BattleRules,
		reload_total: int, cool_total: int, tps: int, verbose: bool) -> void:
	var hold := int(u.get("hold", BattleActivity.Hold.NONE))
	var rl := int(u.get("reload", 0))
	var cd := int(u.get("cooldown", 0))
	var ticks := rl if hold == BattleActivity.Hold.RELOADING else cd
	var txt := "%s: %s" % [uname, Glossary.hold_text(hold, ticks)]
	if rl + cd > 0:
		txt += " · fires in %.1f s" % (float(rl + cd) / maxi(tps, 1))
		if verbose:
			txt += " (%d ticks)" % (rl + cd)
	txt += " · ammo %d / %d" % [int(u.get("ammo", 0)), int(u.get("magazine", 0))]
	if int(u.get("victim", -1)) >= 0 and int(u.get("victim_dist", 0)) > 0:
		var vd := int(u["victim_dist"])
		var word := "in range"
		if w >= 0:
			if vd < rules.wp_min_range[w]:
				word = "inside minimum range"
			elif vd > rules.wp_range[w]:
				word = "beyond range"
		txt += " · target %s m (%s)" % [Fixed.to_display(vd), word]
	if u.has("shots"):
		var sh := int(u["shots"])
		var hi := int(u.get("hits", 0))
		txt += " · %d %s, %d %s" % [sh, "shot" if sh == 1 else "shots", hi, "hit" if hi == 1 else "hits"]
	col.add_child(_lbl(txt, "SmallLabel", true))
	if rl + cd > 0:
		var total := reload_total if rl > 0 else cool_total
		var left := rl if rl > 0 else cd
		col.add_child(_mini_bar(1.0 - float(left) / total if total > 0 else 0.0))


## Unit display names, duplicates numbered in inspection order (Trooper 1…).
static func _unit_labels(units: Array) -> Dictionary:
	var counts := {}
	for u: Dictionary in units:
		var n := String(u["name"])
		counts[n] = int(counts.get(n, 0)) + 1
	var seen := {}
	var out := {}
	for u: Dictionary in units:
		var n := String(u["name"])
		if int(counts[n]) > 1:
			seen[n] = int(seen.get(n, 0)) + 1
			out[int(u["id"])] = "%s %d" % [n, int(seen[n])]
		else:
			out[int(u["id"])] = n
	return out


## A thin progress bar (reload / cooldown), fill = the part already done.
static func _mini_bar(frac: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(120, 5)
	c.add_child(UiTheme.backdrop("LineBar"))
	var f := Panel.new()
	var tone := "Accent" if (UiTheme.styles().get("tones", {}) as Dictionary).has("Accent") else "Text"
	f.theme_type_variation = "%sBar" % tone
	f.anchor_right = clampf(frac, 0.0, 1.0)
	f.anchor_bottom = 1.0
	c.add_child(f)
	return c


## The card's dicts for the moment `t` (0..1) of a playback record
## (OverworldSession.playback): `base_squad` / `base_insp` are the end-of-turn
## observation and inspection; the shown frame overrides everything the
## moment knows — activity, alive and HP, hold reasons, ammo, timers, the
## victim (the unit's latest volley) and its distance, shots / hits up to the
## frame. Returns {"squad", "insp"}; the bases unchanged when the squad is
## not in the frame (it fell during the turn: the end state is what is left).
## Presentation only: reads the record, never changes it.
static func moment(rec: Dictionary, t: float, squad_id: int, viewer: int, base_squad: Dictionary, base_insp: Dictionary) -> Dictionary:
	var out := {"squad": base_squad, "insp": base_insp}
	var frames: Array = rec.get("frames", [])
	if frames.is_empty() or base_squad.is_empty():
		return out
	var fi := mini(int(t * (frames.size() - 1)), frames.size() - 1)
	var f: Dictionary = frames[fi]
	if not f.has(squad_id):
		return out
	var sd: Dictionary = f[squad_id]
	var own := int(sd["player"]) == viewer
	var ids: Array = sd["ids"]
	var hps: Array = sd["hp"]
	var squad := base_squad.duplicate(true)
	squad["activity"] = sd["activity"]
	var alive := 0
	var frac_sum := 0.0
	for i in ids.size():
		if float(hps[i]) > 0.0:
			alive += 1
		frac_sum += float(hps[i])
	squad["alive"] = alive
	var hp_max := float(squad.get("hp_max", 0))
	if hp_max > 0.0 and not ids.is_empty():
		squad["hp_lost"] = int(round(hp_max * (1.0 - frac_sum / ids.size())))
	# Every unit in the frame: its squad and position (metres), for victims.
	var usquad := {}
	var upos := {}
	for sid: int in f:
		var d: Dictionary = f[sid]
		for i in (d["ids"] as Array).size():
			usquad[int(d["ids"][i])] = sid
			upos[int(d["ids"][i])] = d["units"][i]
	# Volleys and hits up to the shown frame: shots, hits, and each shooter's
	# latest victim (the trace is in tick order).
	var shots := {}
	var hits := {}
	var last_victim := {}
	for v: Array in rec.get("volleys", []):
		if int(v[0]) > fi:
			continue
		shots[int(v[1])] = int(shots.get(int(v[1]), 0)) + 1
		last_victim[int(v[1])] = int(v[2])
	for h: Array in rec.get("hits", []):
		if int(h[0]) > fi:
			continue
		hits[int(h[3])] = int(hits.get(int(h[3]), 0)) + 1
	if own:
		# The moment's target: the latest volley's victim's squad. Enemy
		# targets stay as the observation sanitised them (fog).
		var target := int(squad.get("target", -1))
		for uid: int in ids:
			if last_victim.has(uid) and usquad.has(int(last_victim[uid])):
				target = int(usquad[int(last_victim[uid])])
		squad["target"] = target
	var insp := base_insp.duplicate(true)
	insp["activity"] = sd["activity"]
	if own:
		insp["target"] = squad["target"]
	var pos: Array = sd["units"]
	for u: Dictionary in insp.get("units", []):
		var uid := int(u["id"])
		var i := ids.find(uid)
		if i < 0:
			continue
		u["hp"] = int(round(float(hps[i]) * float(u["hp_max"])))
		if not own:
			continue
		u["hold"] = int(sd["holds"][i])
		u["reload"] = int(sd["reload"][i])
		u["cooldown"] = int(sd["cooldown"][i])
		u["ammo"] = int(sd["ammo"][i])
		var v := int(last_victim.get(uid, -1))
		u["victim"] = v if upos.has(v) else -1
		u["victim_dist"] = int((pos[i] as Vector2).distance_to(upos[v]) * Fixed.ONE) if u["victim"] >= 0 else 0
		u["shots"] = int(shots.get(uid, 0))
		u["hits"] = int(hits.get(uid, 0))
	out["squad"] = squad
	out["insp"] = insp
	return out


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
