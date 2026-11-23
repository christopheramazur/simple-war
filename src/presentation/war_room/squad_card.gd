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
## exact percent and the points to the next lower band only at higher
## verbosity (sw-1jy.4); never colour alone.
## A first, one-page form of the inspection window (Mocks/
## inspection_window.png); tabs and traces are InspectionTabs (sw-ll4.20).

const ORDER_NAMES: Dictionary = {
	"hold": "Holding", "move": "Moving", "attack_move": "Attack-moving", "attack": "Attacking",
	"fall_back": "Falling back", "withdraw": "Withdrawing",
}

## Band glyphs, a ladder from empty/low to filled/high so the state reads
## without colour. Presentation only: the bands themselves come from the API.
## Placeholder glyph per SIMPL pool (sw-1jy.7), distinct in shape from each
## other and from the band icons so greyscale still tells them apart; the
## art-direction interview replaces them. Overridable by "pool_icon.<id>".
const POOL_ICONS: Dictionary = {
	"stamina": "■", "instinct": "◉", "morale": "♥", "prowess": "✚", "legend": "★",
}


## `squad`: its entry in observe_battle's "squads". `insp`: inspect_battle's
## result ({} shows only what the observation has). `viewer`: the player
## looking. `tps`: ticks per second, for effect times. `verbose`: also show
## value / capacity, the exact percent and the sim's points-to-drop on the
## SIMPL meters, and the exact tick counts on weapon timers. `ctx`: display
## context the caller resolves — "rules" (BattleRules: range bands, damage
## types, timer totals), "weapon_names" (weapon ID -> display name) and
## "target_name" (the engaged squad's name, for the activity line).
static func build(squad: Dictionary, insp: Dictionary, viewer: int, tps: int = 10, verbose: bool = false, ctx: Dictionary = {}) -> VBoxContainer:
	return UiPanel.build("squad_card", model(squad, insp, viewer, tps, verbose, ctx))


## The view model (sw-zsm): {"items": [...]} for data/ui/panels/squad_card.json.
## Each item carries one of: head, text / wrapped (+ style, tip), bar, meter,
## kv, progress. The panel only draws it; every number is the simulation's.
static func model(squad: Dictionary, insp: Dictionary, viewer: int, tps: int = 10, verbose: bool = false, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = []
	var own := int(squad.get("player", 0)) == viewer
	items.append(_t(String(squad.get("name", squad.get("template", "Squad"))), "SubheadLabel"))
	var alive := int(squad.get("alive", 0))
	var size := int(squad.get("size", alive))
	var who := "yours" if own else ("neutral" if int(squad.get("player", 0)) >= 30 else "enemy, player %d" % int(squad.get("player", 0)))
	items.append(_t("%d / %d units  ·  %s" % [alive, size, who], "SmallGoodLabel" if alive >= size else ("SmallAccentLabel" if alive * 2 >= size else "SmallBadLabel")))
	# What the squad is doing, in the glossary's words (sw-ll4.27.3). The
	# code is the simulation's (BattleActivity); enemies carry behaviour only.
	var act := int(squad.get("activity", insp.get("activity", -1)))
	if act >= 0:
		var tname := String(ctx.get("target_name", ""))
		if act == BattleActivity.Squad.ENGAGED and tname.is_empty():
			tname = "the enemy"
		items.append(_t(Glossary.activity_text(act, tname), "SmallAccentLabel"))
	if own:
		var order := String(squad.get("order", "hold"))
		var order_item := _t("Order: %s" % ORDER_NAMES.get(order, order.capitalize()), "SmallDimLabel")
		order_item["tip"] = OrderTips.tip(order)
		items.append(order_item)
		var hp_max := float(squad.get("hp_max", 0))
		if hp_max > 0.0:
			items.append({"bar": _bar_model("Health", 1.0 - float(squad.get("hp_lost", 0)) / hp_max, "Good", "")})
		var pools: Dictionary = squad.get("pools", {})
		var floors: Array = squad.get("band_floor_pct", [])
		for p: String in pools:
			var pd: Dictionary = pools[p]
			var cap := float(pd["capacity"])
			var frac := float(pd["value"]) / cap if cap > 0.0 else 0.0
			if DataSchema.SIMPL.has(p) and floors.size() == DataSchema.BANDS.size():
				items.append({"meter": _meter_model(p, pd, floors, verbose, ctx.get("glossary") as Glossary)})
			else:
				items.append({"bar": _bar_model(p.capitalize(), frac, _pool_tone(p),
					"%s  %s" % [Fixed.to_display(pd["value"]), String(pd["band"]).capitalize()])})
	items.append({"head": "Reach"})
	var reach := "Weapon range %s m" % Fixed.to_display(int(squad.get("range", 0))) if int(squad.get("range", 0)) > 0 else "No ranged weapon"
	items.append(_t("%s  ·  sight %s m" % [reach, Fixed.to_display(int(squad.get("sight", 0)))], "SmallLabel"))
	if own and not insp.is_empty():
		_weapons(items, insp, ctx, tps, verbose)
	if insp.is_empty():
		return {"items": items}
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
		items.append({"head": "%d × %s" % [us.size(), first["name"]]})
		items.append(_t("Health %s / %s" % [Fixed.to_display(hp), Fixed.to_display(hp_top)], "SmallLabel"))
		var defence := PackedStringArray()
		var move := PackedStringArray()
		for e: Dictionary in first.get("stats", []):
			var stat := String(e["stat"])
			if stat == "movement.walk":
				move.append("walk %s" % _fmt(e))
			elif stat == "movement.run":
				move.append("run %s" % _fmt(e))
			elif stat.begins_with("defense.") and int(e["value"]) != 0:
				defence.append("%s %s" % [e["name"], _fmt(e)])
		_mode_items(items, first)
		if not move.is_empty():
			items.append(_t("Speed: " + ", ".join(move), "SmallLabel"))
		items.append(_t("Defence: " + (", ".join(defence) if not defence.is_empty() else "none"), "CaptionDimLabel", true))
	var effects: Array = insp.get("effects", [])
	if not effects.is_empty():
		items.append({"head": "Effects"})
		for fx: Dictionary in effects:
			var left := int(fx.get("remaining_ticks", -1))
			var time := "lasts the battle" if left < 0 else "%.1f s left" % (float(left) / maxi(tps, 1))
			var stacks := "" if int(fx.get("stacks", 1)) <= 1 else " ×%d" % int(fx["stacks"])
			items.append(_t("%s%s  (%s)" % [fx["name"], stacks, time], "SmallAccentLabel"))
			for text: String in fx.get("lines", []):
				items.append(_t("  " + text, "CaptionDimLabel", true))
	return {"items": items}


## A text item: drawn wrapped when `wrap`.
static func _t(text: String, style: String, wrap: bool = false) -> Dictionary:
	return {"wrapped" if wrap else "text": text, "style": style}


static func _bar_model(name: String, frac: float, tone: String, text: String) -> Dictionary:
	return {"name": name, "frac": frac, "tone": tone, "text": text}


## The accuracy / damage line of each weapon mode in `unit`'s stats (a kv item each).
static func _mode_items(items: Array, unit: Dictionary) -> void:
	var modes := {}
	for e: Dictionary in unit.get("stats", []):
		var stat := String(e["stat"])
		if stat.begins_with("weapon.modes"):
			var m: Dictionary = modes.get(e["label"], {})
			m["accuracy" if stat.ends_with("accuracy") else "damage"] = e
			modes[e["label"]] = m
	for label: String in modes:
		var m: Dictionary = modes[label]
		var values: Array = []
		if m.has("accuracy"):
			values.append({"text": "%s to hit" % _fmt(m["accuracy"]), "tone": _tone(m["accuracy"])})
		if m.has("damage"):
			values.append({"text": "· %s damage" % _fmt(m["damage"]), "tone": _tone(m["damage"])})
		items.append({"kv": {"key": "%s:" % String(label).capitalize(), "values": values}})


## The live weapon block (sw-ll4.27.3): one block per weapon the squad's
## units carry, from the inspection's unit reports (BattleActivity.
## unit_report). Name, damage type, modes, the range band against each
## unit's target distance, ammo, reload / cooldown progress, the hold-fire
## reason in the glossary's words, and shots / hits this turn when the
## caller carries them (playback). Every number is the simulation's.
static func _weapons(items: Array, insp: Dictionary, ctx: Dictionary, tps: int, verbose: bool) -> void:
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
	items.append({"head": "Weapons"})
	if not any_shots:
		items.append(_t("Shots and hits this turn show during playback.", "CaptionDimLabel", true))
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
			title += " · %s" % String(rules.damage_types[rules.wp_type[w]]).capitalize()
			reload_total = rules.wp_reload[w]
			for m in range(rules.wp_mode_start[w], rules.wp_mode_start[w] + rules.wp_mode_count[w]):
				cool_total = maxi(cool_total, rules.md_cooldown[m])
		items.append(_t(title, "SmallLabel"))
		_mode_items(items, first)
		if w >= 0:
			items.append(_t("Range %s–%s m" % [Fixed.to_display(rules.wp_min_range[w]), Fixed.to_display(rules.wp_range[w])], "CaptionDimLabel"))
		for u: Dictionary in us:
			_weapon_unit(items, u, String(labels[int(u["id"])]), w, rules, reload_total, cool_total, tps, verbose)


## One unit's weapon state: the hold reason in words, time to fire, ammo,
## the target's distance against the range band, and shots / hits this turn.
static func _weapon_unit(items: Array, u: Dictionary, uname: String, w: int, rules: BattleRules,
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
	items.append(_t(txt, "SmallLabel", true))
	if rl + cd > 0:
		var total := reload_total if rl > 0 else cool_total
		var left := rl if rl > 0 else cd
		items.append({"progress": {"frac": 1.0 - float(left) / total if total > 0 else 0.0}})


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


## One SIMPL pool as the meter section's model (sw-1jy.3): the segment edges
## and the ticks sit at the band floors the observation carries, the fill is
## the pool's theme tone, and the band reads as icon + word, never colour
## alone. `floors` is the compiled band_floor_pct; the sim owns the mapping.
static func _meter_model(pool: String, pd: Dictionary, floors: Array, verbose: bool, glossary: Glossary = null) -> Dictionary:
	var tone := _pool_tone(pool)
	var d := {"pool": pool, "tone": tone, "floors": floors,
		"label": "%s %s" % [pool_icon(pool), pool_word(pool, glossary)], "label_style": "Caption%sLabel" % tone}
	if glossary != null and glossary.has("term_" + pool):
		# Hover shows the glossary definition (GDD 01 pillar 3).
		var tip := glossary.tooltip("term_" + pool)
		d["label_tip"] = "%s: %s" % [tip["title"], tip["text"]]
	var cap := float(pd["capacity"])
	d["pct"] = float(pd["value"]) / cap * 100.0 if cap > 0.0 else 0.0
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
	d["text"] = text
	d["tip"] = ledger_text(pool, pd.get("ledger", []))
	return d


## The pool's glyph through the translation table, with the placeholder
## fallback until the art pass.
static func pool_icon(pool: String) -> String:
	var key := "pool_icon." + pool
	var s := String(TranslationServer.translate(key))
	return s if s != key else String(POOL_ICONS.get(pool, "·"))


## The pool's name: the glossary term's name, else the "pool.<id>" key.
static func pool_word(pool: String, glossary: Glossary = null) -> String:
	if glossary != null and glossary.has("term_" + pool):
		return glossary.name_of("term_" + pool)
	var key := "pool." + pool
	var s := String(TranslationServer.translate(key))
	return s if s != key else pool.capitalize()


## The pool's source-tagged ledger as tooltip lines, the sim's exact net
## amounts (sw-1jy.6): "Source: +1.5". Exact numbers only, no magnitude words.
static func ledger_text(pool: String, ledger: Array) -> String:
	var lines := PackedStringArray(["%s: net change by source this battle" % pool.capitalize()])
	if ledger.is_empty():
		lines.append("No changes yet")
	for e: Dictionary in ledger:
		var amt := int(e["amount"])
		lines.append("%s: %s%s" % [Glossary.ledger_source_text(String(e["source"])), "+" if amt > 0 else "", Fixed.to_display(amt)])
	return "\n".join(lines)


## The band word through the translation table (the glossary's "band.<id>"
## keys), with the English fallback until translation tables exist.
static func _band_word(band: String) -> String:
	var key := "band." + band
	var s := String(TranslationServer.translate(key))
	return s if s != key else band.capitalize()


static func _band_icon(band: String) -> String:
	return BandGlyphs.icon(band)


static func _fmt(e: Dictionary) -> String:
	var v := int(e["value"])
	if String(e["stat"]).ends_with("accuracy"):
		return "%d%%" % Fixed.to_int_round(v * 100)
	var u := String(e["unit"])
	if u == "%":
		return Fixed.to_display(v) + "%"
	return Fixed.to_display(v) if u.is_empty() else "%s %s" % [Fixed.to_display(v), u]
