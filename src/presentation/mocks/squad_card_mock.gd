extends RefCounted
## Mock (sw-1jy.3, sw-ll4.27.3): the squad card's segmented SIMPL meters —
## five countable segments per pool, ticks at the band floors the ruleset
## compiles, band icon + word, exact percent only at higher verbosity — and
## the activity line and per-weapon status: what the squad is doing, why its
## guns are silent (glossary words), ammo, timers, the range band against the
## target's distance, shots / hits, and the card following a playback moment.
## Live data from BattleSession.observe / inspect; the pools are flowed to
## chosen percentages so every band shows on one contact sheet. Render with
## `hx godot mock res://src/presentation/mocks/squad_card_mock.gd`.


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	var mine := -1
	for q: Dictionary in s.observe(1)["squads"]:
		if q["template"] == "rifle_squad":
			mine = q["id"]
			break
	var row := s.state.squads.row_of(mine)
	var floors: Array = _squad(s, mine)["band_floor_pct"]
	var ctx := _ctx(s, l.templates)
	var root := Control.new()
	root.custom_minimum_size = Vector2(1380, 1620)
	root.add_child(UiTheme.backdrop("ScreenBackgroundPanel"))
	var sheet := VBoxContainer.new()
	sheet.theme_type_variation = &"ListGap"
	sheet.position = Vector2(24, 18)
	root.add_child(sheet)
	sheet.add_child(UiTheme.label("Squad card: SIMPL meters, activity and weapon status", "SubheadLabel"))
	var marks := PackedStringArray()
	for f in floors.slice(1):
		marks.append(str(f))
	sheet.add_child(UiTheme.label("Five segments per pool; ticks at the compiled band floors (%s), read from the observation, never the UI. "
		% " / ".join(marks) + "Band icon + word always, never colour alone; the exact percent only at higher verbosity. "
		+ "Live BattleSession.observe data, pools flowed to the shown percentages.", "SmallDimLabel", true))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 24)
	sheet.add_child(line)
	line.add_child(_variant(s, row, mine, _mid_band(floors), false, ctx, "One band per pool",
		"Broken through Surging, top to bottom. Each segment spans one band."))
	var edges := []
	for b in range(1, floors.size()):
		edges.append(int(floors[b]))
	edges.append(100)
	line.add_child(_variant(s, row, mine, edges, false, ctx, "Fills ending on a threshold",
		"Each fill stops exactly at a tick: the segment edge and the band floor agree."))
	line.add_child(_variant(s, row, mine, _mid_band(floors), true, ctx, "Higher verbosity",
		"Adds value / capacity and the exact percent."))
	# Activity and weapon status (sw-ll4.27.3), live inspection data.
	sheet.add_child(UiTheme.label("Activity and weapon status: the glossary's words for the simulation's codes; "
		+ "every number is the simulation's. The playback card follows the shown moment, not the end of the turn.",
		"SmallDimLabel", true))
	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 24)
	sheet.add_child(line2)
	line2.add_child(_wrap("Holding position", "The hold-position order still fires: HOLDING is not 'holding fire'. "
		+ "Each unit's hold reason, ammo and the weapon's range band.",
		SquadCard.build(_squad(s, mine), s.inspect(1, mine), 1, s.state.rules.tps, false, ctx)))
	var st := s.state
	var sq := st.squads
	var enemy := -1
	for r in sq.count():
		if sq.player[r] == 2 and sq.is_active(r):
			enemy = sq.id_at(r)
			sq.seen_by[r] |= BattleSquads.bit(1)
			break
	st.tick = 5
	sq.engaged[row] = enemy
	sq.fired_tick[row] = 4
	var ectx := ctx.duplicate()
	ectx["target_name"] = st.rules.sq_names[sq.tmpl[sq.row_of(enemy)]]
	line2.add_child(_wrap("Engaged", "Fired on the last completed tick: 'Firing at <target>'. The target's name "
		+ "comes from the observation.",
		SquadCard.build(_squad(s, mine), s.inspect(1, mine), 1, st.rules.tps, false, ectx)))
	var us := Centroids.units_of(st, row)
	st.units.set_value(st.units.id_at(us[0]), &"reload", 12)
	st.units.set_value(st.units.id_at(us[1]), &"cooldown", 25)
	line2.add_child(_wrap("Held fire: timers", "Reloading and cooling down, in words and seconds (ticks / tps), "
		+ "with the progress already done. Verbose adds the exact ticks.",
		SquadCard.build(_squad(s, mine), s.inspect(1, mine), 1, st.rules.tps, true, ectx)))
	line2.add_child(_playback_variant(s, mine, ctx))
	return root


## One card per meter variant: flow every pool to its percent, re-observe.
static func _variant(s: BattleSession, row: int, mine: int, percents: Array, verbose: bool, ctx: Dictionary,
		title: String, note: String) -> Control:
	var st := s.state
	for p in 5:
		var cap := Pools.capacity(st, row, p)
		Pools.flow(st, row, p, Fixed.round_div(int(percents[p]) * cap, 100) - Pools.value(st, row, p), &"mock")
	return _wrap(title, note, SquadCard.build(_squad(s, mine), {}, 1, st.rules.tps, verbose, ctx))


static func _wrap(title: String, note: String, card: Control) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BattleColumnPanel"
	var col := VBoxContainer.new()
	col.theme_type_variation = &"CardGap"
	panel.add_child(col)
	col.add_child(UiTheme.label(title, "CardHeadLabel"))
	col.add_child(UiTheme.label(note, "CaptionDimLabel", true))
	col.add_child(card)
	return panel


## The card at a playback moment: a hand-built record in the API's shape
## (two units engaging an enemy at 39 m), formatted by SquadCard.moment.
static func _playback_variant(s: BattleSession, mine: int, ctx: Dictionary) -> Control:
	var insp := s.inspect(1, mine)
	var units := []
	for i in 2:
		var u: Dictionary = (insp["units"] as Array)[i].duplicate(true)
		u["id"] = i + 1
		u["ammo"] = 30
		u["magazine"] = 30
		u["reload"] = 0
		u["cooldown"] = 0
		u["hold"] = BattleActivity.Hold.NONE
		u["victim"] = -1
		u["victim_dist"] = 0
		units.append(u)
	var base_squad := _squad(s, mine)
	base_squad["id"] = 101
	base_squad["alive"] = 2
	base_squad["size"] = 2
	base_squad["activity"] = BattleActivity.Squad.IDLE
	base_squad["target"] = -1
	var f0 := {101: {"player": 1, "facing": 0, "ids": [1, 2], "units": [Vector2(0, 0), Vector2(2, 0)],
			"tmpls": ["trooper", "trooper"], "hp": [1.0, 1.0], "acts": [0, 0],
			"activity": BattleActivity.Squad.READY,
			"holds": [BattleActivity.Hold.NONE, BattleActivity.Hold.RELOADING],
			"reload": [0, 9], "cooldown": [0, 0], "ammo": [30, 0]},
		202: {"player": 2, "facing": 0, "ids": [99], "units": [Vector2(39, 0)],
			"tmpls": ["trooper"], "hp": [1.0], "acts": [0], "activity": BattleActivity.Squad.IDLE}}
	var f1 := {101: {"player": 1, "facing": 0, "ids": [1, 2], "units": [Vector2(0, 0), Vector2(2, 0)],
			"tmpls": ["trooper", "trooper"], "hp": [1.0, 1.0], "acts": [0, 0],
			"activity": BattleActivity.Squad.ENGAGED,
			"holds": [BattleActivity.Hold.NONE, BattleActivity.Hold.NONE],
			"reload": [0, 0], "cooldown": [0, 0], "ammo": [29, 30]},
		202: f0[202]}
	var rec := {"frames": [f0, f1], "volleys": [[1, 1, 99, true]], "hits": [[1, 99, 3 * Fixed.ONE, 1]], "shots": []}
	var m := SquadCard.moment(rec, 1.0, 101, 1, base_squad, {"id": 101, "units": units})
	var pctx := ctx.duplicate()
	pctx["target_name"] = "Enemy squad"
	return _wrap("Playback moment", "The shown frame, not the end of the turn: engaged, the volley's victim at "
		+ "39 m against the range band, ammo spent, 1 shot / 1 hit so far.",
		SquadCard.build(m["squad"], m["insp"], 1, s.state.rules.tps, false, pctx))


static func _ctx(s: BattleSession, t: TemplateTable) -> Dictionary:
	var names := {}
	for wid: String in s.state.rules.weapon_index:
		names[wid] = String(t.values_of(wid).get("name", wid))
	return {"rules": s.state.rules, "weapon_names": names}


static func _squad(s: BattleSession, mine: int) -> Dictionary:
	for q: Dictionary in s.observe(1)["squads"]:
		if q["id"] == mine:
			return q
	return {}


## A percent safely inside each band, derived from the compiled floors.
static func _mid_band(floors: Array) -> Array:
	var out := []
	for b in floors.size():
		var hi := int(floors[b + 1]) if b + 1 < floors.size() else 100
		out.append((int(floors[b]) + hi) / 2)
	return out
