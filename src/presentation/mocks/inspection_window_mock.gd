extends RefCounted
## Throwaway mock (sw-ps1.7, E4Q3, E4Q4): three layout variants of the
## inspection window on one contact sheet, fed by BattleSession.inspect.
## Formatting lives here only because this is a mock; the real window will
## format the same API data the same way. Render with mock_runner.gd.

const ONE := Fixed.ONE
const W := 600
const H := 900
const GAP := 24

const BG := Color("12151a")
const PANEL := Color("1d2128")
const PANEL2 := Color("262c35")
const LINE := Color("323a46")
const TEXT := Color("dde2ea")
const DIM := Color("8a93a3")
const UP := Color("74d18a")
const DOWN := Color("e8735f")
const ACCENT := Color("e6b450")
const POOL_COLORS: Dictionary = {
	"stamina": Color("5bb6d9"), "instinct": Color("b38be0"), "morale": Color("74d18a"),
	"prowess": Color("e6b450"), "legend": Color("e07ab0"),
}

static var _tps: int = 10


static func build() -> Control:
	var d := _data()
	var sheet := VBoxContainer.new()
	sheet.custom_minimum_size = Vector2(W * 3 + GAP * 4, H + 150)
	sheet.add_theme_constant_override("separation", 10)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := Control.new()
	root.custom_minimum_size = sheet.custom_minimum_size
	root.add_child(bg)
	root.add_child(sheet)
	sheet.position = Vector2(GAP, 14)
	sheet.add_child(_lbl("Inspection window: layout variants", 24, TEXT))
	sheet.add_child(_lbl("Mock for sw-ps1.7. Live data from BattleSession.inspect(player 1, Rifle squad) plus observe() for pools. "
		+ "Effects: Inspired, Feigned rout (deception), Steady Aim, Hardy (Sergeant), Bleeding x2 (Trooper 2).", 13, DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	sheet.add_child(row)
	row.add_child(_variant("A  Tabs + breakdown", "One unit at a time; the selected stat's calculation below.", _tabs(d)))
	row.add_child(_variant("B  Unit cards", "Every unit at a glance; changed numbers coloured; effects as badges.", _cards(d)))
	row.add_child(_variant("C  Ledger", "Effects with their rules text, then the modifier ledger; opponent's view.", _ledger(d)))
	return root


# --- data ------------------------------------------------------------------

static func _data() -> Dictionary:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	var st := s.state
	_tps = st.rules.tps
	var mine := -1
	for q: Dictionary in s.observe(1)["squads"]:
		if q["template"] == "rifle_squad":
			mine = q["id"]
			break
	var enemy: int = s.observe(2)["squads"][0]["id"]
	var row := st.squads.row_of(mine)
	var fx := st.rules.fx
	var units := Centroids.units_of(st, row)
	Effects.apply(st, fx.index_of("inspired"), mine)
	Effects.apply(st, fx.index_of("feigned_rout"), mine)
	Effects.apply(st, fx.index_of("steady_aim"), mine)
	Effects.apply(st, fx.index_of("hardy"), mine, st.units.id_at(units[0]))
	for _i in 2:
		Effects.apply(st, fx.index_of("bleeding"), mine, st.units.id_at(units[2]), enemy)
	st.units.set_value(st.units.id_at(units[2]), &"hp", 6 * ONE)
	st.units.set_value(st.units.id_at(units[5]), &"hp", 3 * ONE)
	Pools.flow(st, row, BattleSquads.MORALE, 14 * ONE, &"mock")
	Pools.flow(st, row, BattleSquads.INSTINCT, -21 * ONE, &"mock")
	Pools.flow(st, row, BattleSquads.PROWESS, 9 * ONE, &"mock")
	EffectSystem.new().run(st)
	st.tick = 24
	for _i in 2:
		Effects.on_event(st, "hit", mine, -1, -1, -1, ONE)
	var pools := {}
	for q: Dictionary in s.observe(1)["squads"]:
		if q["id"] == mine:
			pools = q["pools"]
	return {"own": s.inspect(1, mine), "enemy": Inspection.squad(st, mine, 2), "pools": pools}


# --- variant A: tabs + breakdown --------------------------------------------

static func _tabs(d: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var box := _vbox(10)
	box.add_child(_header(v, d["pools"], false))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for t: Array in [["Squad", false], ["Units", true], ["Effects (%d)" % v["effects"].size(), false], ["Abilities (%d)" % v["abilities"].size(), false]]:
		tabs.add_child(_chip(t[0], ACCENT if t[1] else PANEL2, BG if t[1] else TEXT, 14))
	box.add_child(tabs)
	var picks := HBoxContainer.new()
	picks.add_theme_constant_override("separation", 4)
	var units: Array = v["units"]
	for i in units.size():
		picks.add_child(_chip(_unit_label(units, i), LINE if i == 0 else PANEL, TEXT if i == 0 else DIM, 11))
	box.add_child(picks)
	var u: Dictionary = units[0]
	var table := _panel(PANEL, 10)
	var rows := _vbox(3)
	table.add_child(rows)
	rows.add_child(_row3("Sergeant", "base", "now", DIM, 13))
	rows.add_child(_row3("HP", "", "%s / %s" % [_n(u["hp"]), _n(u["hp_max"])], TEXT, 14))
	for e: Dictionary in u["stats"]:
		var changed: bool = e["value"] != e["base"]
		rows.add_child(_row3(_stat_name(e), _fmt(e, e["base"]), _fmt(e, e["value"]),
			(UP if e["value"] > e["base"] else DOWN) if changed else TEXT, 14, e["stat"] == "weapon.modes.*.accuracy" and e["label"] == "aimed"))
	box.add_child(table)
	var acc := _find(u["stats"], "weapon.modes.*.accuracy", "aimed")
	var bd := _panel(PANEL2, 10)
	var lines := _vbox(4)
	bd.add_child(lines)
	lines.add_child(_lbl("Accuracy (aimed): how it's calculated", 14, ACCENT))
	for step: Dictionary in acc["trace"]:
		lines.add_child(_trace_line(acc, step))
	box.add_child(bd)
	return box


# --- variant B: unit cards --------------------------------------------------

static func _cards(d: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var box := _vbox(10)
	box.add_child(_header(v, d["pools"], true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var units: Array = v["units"]
	for i in units.size():
		grid.add_child(_card(v, units, i))
	box.add_child(grid)
	box.add_child(_lbl("Squad effects", 13, DIM))
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 6)
	for e: Dictionary in v["effects"]:
		if e["unit"] < 0:
			strip.add_child(_effect_chip(e))
	box.add_child(strip)
	return box


static func _card(v: Dictionary, units: Array, i: int) -> Control:
	var u: Dictionary = units[i]
	var p := _panel(PANEL, 8)
	p.custom_minimum_size = Vector2((W - 8) / 2.0, 0)
	var b := _vbox(4)
	p.add_child(b)
	var top := HBoxContainer.new()
	var name := _lbl(_unit_label(units, i), 14, TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var hp_col := TEXT if u["hp"] == u["hp_max"] else DOWN
	top.add_child(_lbl("%s / %s HP" % [_n(u["hp"]), _n(u["hp_max"])], 13, hp_col))
	b.add_child(top)
	b.add_child(_bar(float(u["hp"]) / float(u["hp_max"]), UP if u["hp"] * 2 > u["hp_max"] else DOWN, 0, 5))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	for key: Array in [["weapon.modes.*.accuracy", "aimed", "Acc"], ["defense.evasion_pct", "", "Eva"], ["movement.walk", "", "Walk"], ["unit.hp", "", "Max HP"]]:
		var e := _find(u["stats"], key[0], key[1])
		var col := TEXT if e["value"] == e["base"] else (UP if e["value"] > e["base"] else DOWN)
		stats.add_child(_lbl("%s %s" % [key[2], _fmt(e, e["value"])], 12, col))
	b.add_child(stats)
	var badges := HFlowContainer.new()
	badges.add_theme_constant_override("h_separation", 4)
	for e: Dictionary in v["effects"]:
		if e["unit"] == u["id"]:
			badges.add_child(_effect_chip(e))
	if badges.get_child_count() == 0:
		badges.add_child(_lbl("squad effects only", 11, DIM))
	b.add_child(badges)
	return p


# --- variant C: ledger ------------------------------------------------------

static func _ledger(d: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var box := _vbox(8)
	box.add_child(_header(v, d["pools"], true))
	for e: Dictionary in v["effects"]:
		var p := _panel(PANEL, 8)
		var b := _vbox(2)
		p.add_child(b)
		var top := HBoxContainer.new()
		var who := "" if e["unit"] < 0 else "  on %s" % _unit_name_by_id(v, e["unit"])
		var title := _lbl("%s%s%s" % [e["name"], " x%d" % e["stacks"] if e["stacks"] > 1 else "", who], 14, _tag_color(e))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title)
		top.add_child(_lbl(_remaining(e), 12, DIM))
		b.add_child(top)
		for line: String in e["lines"]:
			b.add_child(_lbl(line, 12, TEXT))
		var acc: Dictionary = e["accumulator"]
		if not acc.is_empty():
			var prog := HBoxContainer.new()
			prog.add_theme_constant_override("separation", 8)
			var bar := _bar(float(acc["value"]) / float(acc["threshold"]), ACCENT, 160, 6)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			prog.add_child(bar)
			prog.add_child(_lbl(acc["text"], 12, ACCENT))
			b.add_child(prog)
		box.add_child(p)
	var led := _panel(PANEL2, 8)
	var rows := _vbox(2)
	led.add_child(rows)
	rows.add_child(_lbl("Ledger: Sergeant", 13, DIM))
	rows.add_child(_row5(["Stat", "Base", "Flat", "Incr.", "More", "Now"], DIM))
	var u: Dictionary = v["units"][0]
	for e: Dictionary in u["stats"]:
		if e["value"] == e["base"] and e["trace"].size() <= 2:
			continue
		var cols := {"flat": "", "increased": "", "more": ""}
		var names := PackedStringArray()
		for step: Dictionary in e["trace"]:
			if not cols.has(step["step"]):
				continue
			var parts := PackedStringArray()
			for t: Dictionary in step["terms"]:
				parts.append(("%+d%%" if step["step"] != "flat" else "%+s") % (_pct(t["amount"]) if step["step"] != "flat" else _n(t["amount"])))
				names.append(t["name"])
			cols[step["step"]] = ", ".join(parts)
		rows.add_child(_row5([_stat_name(e), _fmt(e, e["base"]), cols["flat"], cols["increased"], cols["more"], _fmt(e, e["value"])],
			UP if e["value"] > e["base"] else (DOWN if e["value"] < e["base"] else TEXT)))
		rows.add_child(_lbl("      from " + ", ".join(names), 11, DIM))
	box.add_child(led)
	var opp := _panel(Color("2a2024"), 8)
	var ob := _vbox(2)
	opp.add_child(ob)
	ob.add_child(_lbl("What the opponent sees (deception)", 13, DOWN))
	var seen := PackedStringArray()
	for e: Dictionary in d["enemy"]["effects"]:
		seen.append(e["name"])
	ob.add_child(_lbl("Effects: " + ", ".join(seen), 12, TEXT))
	var e_acc := _find(d["enemy"]["units"][1]["stats"], "weapon.modes.*.accuracy", "aimed")
	var e_eva := _find(d["enemy"]["units"][1]["stats"], "defense.evasion_pct")
	ob.add_child(_lbl("Trooper accuracy %s (really %s), evasion %s" % [_fmt(e_acc, e_acc["value"]),
		_fmt(e_acc, _find(v["units"][1]["stats"], "weapon.modes.*.accuracy", "aimed")["value"]), _fmt(e_eva, e_eva["value"])], 12, TEXT))
	box.add_child(opp)
	return box


# --- shared pieces ----------------------------------------------------------

static func _variant(title: String, note: String, body: Control) -> Control:
	var col := _vbox(6)
	col.custom_minimum_size = Vector2(W, 0)
	col.add_child(_lbl(title, 18, ACCENT))
	col.add_child(_lbl(note, 12, DIM))
	var frame := _panel(Color("171b21"), 12)
	frame.custom_minimum_size = Vector2(W, H)
	frame.add_child(body)
	col.add_child(frame)
	return col


static func _header(v: Dictionary, pools: Dictionary, compact: bool) -> Control:
	var p := _panel(PANEL, 10)
	var b := _vbox(6)
	p.add_child(b)
	var top := HBoxContainer.new()
	var name := _lbl(v["name"], 20, TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	top.add_child(_lbl("%d models  ·  Player %d" % [v["units"].size(), v["player"]], 13, DIM))
	b.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for pool: String in DataSchema.SIMPL:
		var pd: Dictionary = pools[pool]
		var c := _vbox(2)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := pool.capitalize() if not compact else pool.substr(0, 3).capitalize()
		c.add_child(_lbl("%s  %s" % [t, _n(pd["value"])], 12, POOL_COLORS[pool]))
		c.add_child(_bar(float(pd["value"]) / float(pd["capacity"]), POOL_COLORS[pool], 0, 5))
		if not compact:
			c.add_child(_lbl(String(pd["band"]).capitalize(), 11, DIM))
		row.add_child(c)
	b.add_child(row)
	return p


static func _trace_line(e: Dictionary, step: Dictionary) -> Control:
	var h := HBoxContainer.new()
	var what := ""
	match step["step"]:
		"base":
			what = "Base"
		"result":
			what = "Result"
		"clamp":
			what = "Clamped to range"
		"round":
			what = "Rounded"
		_:
			var parts := PackedStringArray()
			for t: Dictionary in step["terms"]:
				var amt := _pct(t["amount"])
				var word: String = {"flat": "%+s" % _n(t["amount"]), "increased": "%+d%% increased" % amt, "more": "%d%% more" % amt, "override": "set to %s" % _n(t["amount"])}[step["step"]]
				parts.append("%s  %s" % [t["name"], word])
			what = ",  ".join(parts)
	var l := _lbl(what, 13, TEXT if step["step"] not in ["base", "result"] else DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(_lbl(_fmt(e, step["value"]), 13, ACCENT if step["step"] == "result" else TEXT))
	return h


static func _effect_chip(e: Dictionary) -> Control:
	var txt := "%s%s  %s" % [e["name"], " x%d" % e["stacks"] if e["stacks"] > 1 else "", _remaining(e)]
	return _chip(txt, Color(_tag_color(e), 0.18), _tag_color(e), 11)


static func _tag_color(e: Dictionary) -> Color:
	var tags: PackedStringArray = e["tags"]
	if tags.has("debuff") or tags.has("wound"):
		return DOWN
	if tags.has("buff"):
		return UP
	return ACCENT


static func _remaining(e: Dictionary) -> String:
	if e["remaining_ticks"] < 0:
		return "lasts the battle"
	return "%s s left" % Fixed.to_display(Fixed.from_ratio(e["remaining_ticks"], _tps))


static func _row3(a: String, b: String, c: String, col: Color, size: int, hi: bool = false) -> Control:
	var h := HBoxContainer.new()
	var la := _lbl(a, size, ACCENT if hi else (TEXT if col == DIM else TEXT))
	la.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(la)
	var lb := _lbl(b, size, DIM)
	lb.custom_minimum_size = Vector2(110, 0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(lb)
	var lc := _lbl(c, size, col)
	lc.custom_minimum_size = Vector2(110, 0)
	lc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(lc)
	return h


static func _row5(cells: Array, col: Color) -> Control:
	var h := HBoxContainer.new()
	var widths := [150, 62, 62, 70, 110, 70]
	for i in cells.size():
		var l := _lbl(str(cells[i]), 12, col if i in [0, 5] else (DIM if col == DIM else TEXT))
		l.custom_minimum_size = Vector2(widths[i], 0)
		if i > 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return h


static func _find(stats: Array, stat: String, label: String = "") -> Dictionary:
	for e: Dictionary in stats:
		if e["stat"] == stat and (label.is_empty() or e["label"] == label):
			return e
	return {}


static func _stat_name(e: Dictionary) -> String:
	return e["name"] + (" (%s)" % e["label"] if e["label"] != "" else "")


static func _unit_label(units: Array, i: int) -> String:
	var n: String = units[i]["name"]
	var same := 0
	for j in i + 1:
		if units[j]["name"] == n:
			same += 1
	var total := units.filter(func(u: Dictionary) -> bool: return u["name"] == n).size()
	return n if total == 1 else "%s %d" % [n, same]


static func _unit_name_by_id(v: Dictionary, uid: int) -> String:
	var units: Array = v["units"]
	for i in units.size():
		if units[i]["id"] == uid:
			return _unit_label(units, i)
	return "unit %d" % uid


## Display: accuracy as a percentage, otherwise one decimal plus the unit.
static func _fmt(e: Dictionary, v: int) -> String:
	if String(e["stat"]).ends_with("accuracy"):
		return "%d%%" % Fixed.to_int_round(v * 100)
	var u: String = e["unit"]
	match u:
		"%":
			return _n(v) + "%"
		"":
			return _n(v)
		_:
			return "%s %s" % [_n(v), u]


static func _n(v: int) -> String:
	return Fixed.to_display(v)


static func _pct(v: int) -> int:
	return Fixed.to_int_round(v)


static func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func _chip(text: String, bg: Color, fg: Color, size: int) -> Control:
	var p := _panel(bg, 4)
	p.add_child(_lbl(text, size, fg))
	return p


static func _panel(color: Color, pad: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func _bar(frac: float, color: Color, w: int, h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	var back := ColorRect.new()
	back.color = LINE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_right = clampf(frac, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	c.add_child(fill)
	return c
