extends RefCounted
## Throwaway mock (sw-ps1.7, iteration 2 sw-046, E4Q3, E4Q4): the inspection
## window as one tabbed window, drawn in four states on one contact sheet and
## fed by BattleSession.inspect. Formatting lives here only because this is a
## mock; the real window will format the same API data the same way. Render
## with `hx godot mock res://src/presentation/mocks/inspection_window_mock.gd`.

const ONE := Fixed.ONE
const W := 600
const W_NARROW := 360
const TIP_W := 290
const H := 900
const GAP := 24
## Placeholder: squads have no capacity in the data model yet.
const MOCK_CAPACITY := 10

const BG := Color("12151a")
const FRAME := Color("171b21")
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
const OFFENSIVE_PREFIXES: Array[String] = ["movement.", "weapon.", "unit.proficiency"]

static var _tps: int = 10


static func build() -> Control:
	var d := _data()
	var root := Control.new()
	root.custom_minimum_size = Vector2(W * 3 + W_NARROW + TIP_W + GAP * 5, H + 150)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var sheet := _vbox(10)
	sheet.position = Vector2(GAP, 14)
	root.add_child(sheet)
	sheet.add_child(_lbl("Inspection window: iteration 2", 24, TEXT))
	sheet.add_child(_lbl("One window, four states. Live data from BattleSession.inspect (player 1 and the opponent's view) plus observe() for pools. "
		+ "The header (pools, unit capacity, squad-wide effects) shows on every tab. Capacity 10 is a placeholder: squads have no capacity in the data yet.", 13, DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	sheet.add_child(row)
	row.add_child(_variant("Squad tab", "Unit cards: click one to open it in Units. Visibility and the opponent's view below.",
		_squad_tab(d), W))
	var tip_target := {}
	var units_wide := HBoxContainer.new()
	units_wide.add_theme_constant_override("separation", 0)
	var wide := _variant("Units tab", "Defensive | Offensive. Coloured = modified; hover for how it's calculated.",
		_units_tab(d, false, tip_target), W)
	units_wide.add_child(wide)
	var room := Control.new()
	room.custom_minimum_size = Vector2(TIP_W, 0)
	units_wide.add_child(room)
	row.add_child(units_wide)
	row.add_child(_variant("Effects tab", "Rules text and timing; tiles say who it affects (unit tiles open that unit).",
		_effects_tab(d), W))
	row.add_child(_variant("Units tab, narrow", "Resized: one column. HP, speed, offensive, defensive.",
		_units_tab(d, true, {}), W_NARROW))
	var tip := _tooltip(tip_target["entry"])
	tip.target = tip_target["row"]
	tip.beside = wide
	root.add_child(tip)
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
	Effects.apply(st, fx.index_of("bleeding"), mine, st.units.id_at(units[5]), enemy)
	st.units.set_value(st.units.id_at(units[2]), &"hp", 6 * ONE)
	st.units.set_value(st.units.id_at(units[5]), &"hp", 3 * ONE)
	st.squads.set_value(mine, &"seen_by", st.squads.seen_by[row] | BattleSquads.bit(2))
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
	return {"own": s.inspect(1, mine), "enemy": Inspection.squad(st, mine, 2), "pools": pools,
		"spotted": st.squads.seen_by[row] & BattleSquads.bit(2) != 0}


## Effects grouped by bundle: one entry per bundle, listing who it is on.
static func _groups(v: Dictionary) -> Array:
	var order: Array = []
	var by := {}
	for e: Dictionary in v["effects"]:
		if not by.has(e["bundle"]):
			by[e["bundle"]] = {"first": e, "on": []}
			order.append(e["bundle"])
		by[e["bundle"]]["on"].append(e)
	return order.map(func(b: String) -> Dictionary: return by[b])


# --- window frame ----------------------------------------------------------

static func _window(d: Dictionary, active: String, body: Control, narrow: bool) -> Control:
	var v: Dictionary = d["own"]
	var box := _vbox(10)
	box.add_child(_header(d, narrow))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for t: Array in [["Squad", "Squad"], ["Units", "Units"], ["Effects", "Effects (%d)" % _groups(v).size()],
			["Abilities", "Abilities (%d)" % v["abilities"].size()]]:
		var on: bool = t[0] == active
		tabs.add_child(_chip(t[1], ACCENT if on else PANEL2, BG if on else TEXT, 13 if narrow else 14))
	box.add_child(tabs)
	box.add_child(body)
	return box


static func _header(d: Dictionary, narrow: bool) -> Control:
	var v: Dictionary = d["own"]
	var pools: Dictionary = d["pools"]
	var p := _panel(PANEL, 10)
	var b := _vbox(6)
	p.add_child(b)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var name := _lbl(v["name"], 20, TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var cap := _chip("%d / %d units" % [v["units"].size(), MOCK_CAPACITY], PANEL2, TEXT, 12)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(cap)
	var who := _lbl(("P%d" if narrow else "Player %d") % v["player"], 13, DIM)
	top.add_child(who)
	b.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for pool: String in DataSchema.SIMPL:
		var pd: Dictionary = pools[pool]
		var c := _vbox(2)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := pool.capitalize() if not narrow else pool.substr(0, 3).capitalize()
		c.add_child(_lbl("%s  %s" % [t, _n(pd["value"])], 12, POOL_COLORS[pool]))
		c.add_child(_bar(float(pd["value"]) / float(pd["capacity"]), POOL_COLORS[pool], 0, 5))
		if not narrow:
			c.add_child(_lbl(String(pd["band"]).capitalize(), 11, DIM))
		row.add_child(c)
	b.add_child(row)
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 6)
	var lead := _lbl("Squad effects", 11, DIM)
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(lead)
	for g: Dictionary in _groups(v):
		if g["first"]["unit"] < 0:
			strip.add_child(_effect_chip(g["first"]))
	b.add_child(strip)
	return p


# --- Squad tab --------------------------------------------------------------

static func _squad_tab(d: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var body := _vbox(10)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var units: Array = v["units"]
	for i in units.size():
		grid.add_child(_card(v, units, i))
	body.add_child(grid)
	body.add_child(_visibility(d))
	return _window(d, "Squad", body, false)


static func _card(v: Dictionary, units: Array, i: int) -> Control:
	var u: Dictionary = units[i]
	var p := _panel(PANEL, 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var portrait := Portrait.new()
	portrait.rank = u["template"] == "sergeant"
	portrait.hurt = u["hp"] < u["hp_max"]
	h.add_child(portrait)
	var b := _vbox(3)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	var top := HBoxContainer.new()
	var name := _lbl(_unit_label(units, i), 14, TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	top.add_child(_lbl("%s/%s" % [_n(u["hp"]), _n(u["hp_max"])], 12, TEXT if u["hp"] == u["hp_max"] else DOWN))
	b.add_child(top)
	b.add_child(_bar(float(u["hp"]) / float(u["hp_max"]), UP if u["hp"] * 2 > u["hp_max"] else DOWN, 0, 4))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 3)
	for key: Array in [["weapon.modes.*.accuracy", "aimed", "accuracy"], ["weapon.modes.*.damage", "aimed", "damage"],
			["defense.evasion_pct", "", "evasion"], ["movement.walk", "", "move"]]:
		var e := _find(u["stats"], key[0], key[1])
		var col := _changed_color(e)
		stats.add_child(Icon.make(key[2], col if col != TEXT else DIM))
		var l := _lbl(_fmt(e, e["value"], true), 12, col)
		l.custom_minimum_size = Vector2(30, 0)
		stats.add_child(l)
	b.add_child(stats)
	var badges := HFlowContainer.new()
	badges.add_theme_constant_override("h_separation", 4)
	for e: Dictionary in v["effects"]:
		if e["unit"] == u["id"]:
			badges.add_child(_effect_chip(e, 10))
	if badges.get_child_count() > 0:
		b.add_child(badges)
	var go := _lbl("›", 18, DIM)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(go)
	return p


static func _visibility(d: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var en: Dictionary = d["enemy"]
	var p := _panel(PANEL, 10)
	var b := _vbox(5)
	p.add_child(b)
	b.add_child(_lbl("Visibility", 14, ACCENT))
	var spotted: bool = d["spotted"]
	b.add_child(_pair("Spotted by the enemy", "Yes: they can inspect this squad" if spotted else "No", DOWN if spotted else UP))
	var vis := HBoxContainer.new()
	vis.add_theme_constant_override("separation", 18)
	for key: String in ["squad.sight", "squad.concealment_pct", "squad.detection_radius"]:
		var e := _find(v["stats"], key)
		vis.add_child(_lbl("%s %s" % [e["name"], _fmt(e, e["value"])], 12, _changed_color(e)))
	b.add_child(vis)
	b.add_child(_sep())
	b.add_child(_lbl("What the opponent sees", 13, TEXT))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	var real := {}
	for e: Dictionary in v["effects"]:
		real[e["bundle"]] = e["name"]
	for g: Dictionary in _groups(en):
		var e: Dictionary = g["first"]
		chips.add_child(_effect_chip(e, 11, false))
		if not real.has(e["bundle"]):
			chips.add_child(_lbl("(disguises %s)" % _disguised_name(v, en), 11, DIM))
	b.add_child(chips)
	var mine: Dictionary = v["units"][1]
	var theirs: Dictionary = en["units"][1]
	var diffs := PackedStringArray()
	for e: Dictionary in theirs["stats"]:
		var r := _find(mine["stats"], e["stat"], e["label"])
		if r["value"] != e["value"]:
			diffs.append("%s %s (really %s)" % [_stat_name(e), _fmt(e, e["value"]), _fmt(r, r["value"])])
	var l := _lbl("Troopers: " + ", ".join(diffs), 12, TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 60, 0)
	b.add_child(l)
	b.add_child(_lbl("Pools and abilities stay hidden.", 11, DIM))
	return p


## The owner's bundle that the opponent sees disguised.
static func _disguised_name(v: Dictionary, en: Dictionary) -> String:
	var seen := {}
	for e: Dictionary in en["effects"]:
		seen[e["bundle"]] = true
	for e: Dictionary in v["effects"]:
		if not seen.has(e["bundle"]):
			return e["name"]
	return "?"


# --- Units tab --------------------------------------------------------------

static func _units_tab(d: Dictionary, narrow: bool, tip_target: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var units: Array = v["units"]
	var body := _vbox(10)
	var picks := HFlowContainer.new()
	picks.add_theme_constant_override("h_separation", 4)
	picks.add_theme_constant_override("v_separation", 4)
	for i in units.size():
		picks.add_child(_chip(_unit_label(units, i), LINE if i == 0 else PANEL, TEXT if i == 0 else DIM, 11))
	body.add_child(picks)
	var u: Dictionary = units[0]
	var off: Array = []
	var def: Array = []
	for e: Dictionary in u["stats"]:
		var is_off := OFFENSIVE_PREFIXES.any(func(pre: String) -> bool: return String(e["stat"]).begins_with(pre))
		(off if is_off else def).append(e)
	var hp := _stat_row("HP", "%s / %s" % [_n(u["hp"]), _n(u["hp_max"])], TEXT if u["hp"] == u["hp_max"] else DOWN)
	if narrow:
		var col := _panel(PANEL, 10)
		var rows := _vbox(2)
		col.add_child(rows)
		rows.add_child(hp)
		var moves := off.filter(func(e: Dictionary) -> bool: return String(e["stat"]).begins_with("movement."))
		for e: Dictionary in moves:
			rows.add_child(_entry_row(e, false))
		rows.add_child(_section("Offensive"))
		for e: Dictionary in off:
			if not moves.has(e):
				rows.add_child(_entry_row(e, false))
		rows.add_child(_section("Defensive"))
		for e: Dictionary in def:
			rows.add_child(_entry_row(e, false))
		body.add_child(col)
	else:
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 8)
		var dp := _column("Defensive")
		dp.get_child(0).add_child(hp)
		for e: Dictionary in def:
			dp.get_child(0).add_child(_entry_row(e, false))
		var op := _column("Offensive")
		for e: Dictionary in off:
			var hovered: bool = e["stat"] == "weapon.modes.*.accuracy" and e["label"] == "aimed"
			var r := _entry_row(e, hovered)
			op.get_child(0).add_child(r)
			if hovered:
				tip_target["row"] = r
				tip_target["entry"] = e
		cols.add_child(dp)
		cols.add_child(op)
		body.add_child(cols)
	body.add_child(_lbl("Selected: %s. Coloured values are modified." % _unit_label(units, 0), 11, DIM))
	return _window(d, "Units", body, narrow)


static func _column(title: String) -> Control:
	var p := _panel(PANEL, 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	var rows := _vbox(2)
	p.add_child(rows)
	rows.add_child(_section(title))
	return p


static func _section(title: String) -> Control:
	var l := _lbl(title.to_upper(), 11, DIM)
	l.custom_minimum_size = Vector2(0, 22)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


static func _entry_row(e: Dictionary, hovered: bool) -> Control:
	return _stat_row(_stat_name(e), _fmt(e, e["value"]), _changed_color(e), hovered)


static func _stat_row(name: String, value: String, col: Color, hovered: bool = false) -> Control:
	var p := _panel(PANEL2 if hovered else Color(0, 0, 0, 0), 3)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	if hovered:
		sb.border_width_left = 3
		sb.border_color = ACCENT
	var h := HBoxContainer.new()
	p.add_child(h)
	var n := _lbl(name, 13, ACCENT if hovered else TEXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(_lbl(value, 13, col))
	return p


static func _tooltip(e: Dictionary) -> Follow:
	var t := Follow.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL2
	sb.border_color = ACCENT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	t.add_theme_stylebox_override("panel", sb)
	t.custom_minimum_size = Vector2(TIP_W - 20, 0)
	var b := _vbox(4)
	t.add_child(b)
	b.add_child(_lbl("%s: how it's calculated" % _stat_name(e), 13, ACCENT))
	for step: Dictionary in e["trace"]:
		b.add_child(_trace_line(e, step))
	b.add_child(_lbl("(hover tooltip; contents to be refined)", 10, DIM))
	return t


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
			what = "\n".join(parts)
	var l := _lbl(what, 12, TEXT if step["step"] not in ["base", "result"] else DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := _lbl(_fmt(e, step["value"]), 12, ACCENT if step["step"] == "result" else TEXT)
	val.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(val)
	return h


# --- Effects tab ------------------------------------------------------------

static func _effects_tab(d: Dictionary) -> Control:
	var v: Dictionary = d["own"]
	var body := _vbox(8)
	for g: Dictionary in _groups(v):
		var e: Dictionary = g["first"]
		var p := _panel(PANEL, 10)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		p.add_child(h)
		var left := _vbox(2)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(left)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		top.add_child(_lbl(e["name"], 15, _tag_color(e)))
		var when := _lbl(_remaining(e), 12, DIM)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(when)
		left.add_child(top)
		for line: String in e["lines"]:
			left.add_child(_lbl(line, 12, TEXT))
		var acc: Dictionary = e["accumulator"]
		if not acc.is_empty():
			var prog := HBoxContainer.new()
			prog.add_theme_constant_override("separation", 8)
			var bar := _bar(float(acc["value"]) / float(acc["threshold"]), ACCENT, 140, 6)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			prog.add_child(bar)
			prog.add_child(_lbl(acc["text"], 12, ACCENT))
			left.add_child(prog)
		var right := _vbox(4)
		right.custom_minimum_size = Vector2(170, 0)
		h.add_child(right)
		right.add_child(_lbl("Affects", 11, DIM))
		for inst: Dictionary in g["on"]:
			right.add_child(_who_tile(v, inst))
		body.add_child(p)
	return _window(d, "Effects", body, false)


## Whole squad: a plain label tile. A unit: a button tile that opens its card.
static func _who_tile(v: Dictionary, inst: Dictionary) -> Control:
	var squad: bool = inst["unit"] < 0
	var p := _panel(PANEL2 if squad else LINE, 5)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	if not squad:
		sb.border_width_bottom = 2
		sb.border_color = Color("4a5566")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var stacks := "  x%d" % inst["stacks"] if inst["stacks"] > 1 else ""
	var t := _lbl(("Whole squad" if squad else _unit_name_by_id(v, inst["unit"])) + stacks, 12, DIM if squad else TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if not squad:
		h.add_child(_lbl("›", 13, ACCENT))
	return p


# --- shared pieces ----------------------------------------------------------

static func _variant(title: String, note: String, body: Control, width: int) -> Control:
	var col := _vbox(6)
	col.custom_minimum_size = Vector2(width, 0)
	col.add_child(_lbl(title, 18, ACCENT))
	var n := _lbl(note, 12, DIM)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(width, 34)
	col.add_child(n)
	var frame := _panel(FRAME, 12)
	frame.custom_minimum_size = Vector2(width, H)
	frame.add_child(body)
	col.add_child(frame)
	return col


static func _effect_chip(e: Dictionary, size: int = 11, timed: bool = true) -> Control:
	var txt: String = e["name"] + (" x%d" % e["stacks"] if e["stacks"] > 1 else "")
	if timed:
		txt += "  " + _remaining(e, true)
	return _chip(txt, Color(_tag_color(e), 0.18), _tag_color(e), size)


static func _tag_color(e: Dictionary) -> Color:
	var tags: PackedStringArray = e["tags"]
	if tags.has("debuff") or tags.has("wound"):
		return DOWN
	if tags.has("buff"):
		return UP
	return ACCENT


static func _changed_color(e: Dictionary) -> Color:
	if e["value"] == e["base"]:
		return TEXT
	return UP if e["value"] > e["base"] else DOWN


static func _remaining(e: Dictionary, short: bool = false) -> String:
	if e["remaining_ticks"] < 0:
		return "∞" if short else "lasts the battle"
	return ("%s s" if short else "%s s left") % Fixed.to_display(Fixed.from_ratio(e["remaining_ticks"], _tps))


static func _pair(a: String, b: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_lbl(a, 12, DIM))
	h.add_child(_lbl(b, 12, col))
	return h


static func _sep() -> Control:
	var c := ColorRect.new()
	c.color = LINE
	c.custom_minimum_size = Vector2(0, 1)
	return c


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
static func _fmt(e: Dictionary, v: int, short: bool = false) -> String:
	if String(e["stat"]).ends_with("accuracy"):
		return "%d%%" % Fixed.to_int_round(v * 100)
	var u: String = e["unit"]
	match u:
		"%":
			return _n(v) + "%"
		"":
			return _n(v)
		_:
			return _n(v) if short else "%s %s" % [_n(v), u]


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


## Stat shorthand icons, drawn so the mock needs no art.
class Icon extends Control:
	var kind: String = ""
	var color: Color = Color.WHITE

	static func make(k: String, c: Color) -> Icon:
		var i := Icon.new()
		i.kind = k
		i.color = c
		i.custom_minimum_size = Vector2(14, 14)
		i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return i

	func _draw() -> void:
		var s := size
		var c := s / 2.0
		var r := minf(s.x, s.y) / 2.0 - 1.0
		match kind:
			"accuracy":
				draw_arc(c, r - 1.5, 0.0, TAU, 24, color, 1.5, true)
				draw_line(Vector2(c.x, 0), Vector2(c.x, s.y), color, 1.5)
				draw_line(Vector2(0, c.y), Vector2(s.x, c.y), color, 1.5)
			"damage":
				var pts := PackedVector2Array()
				for k in 17:
					var a := TAU * k / 16.0
					pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
				draw_colored_polygon(pts, color)
			"evasion":
				var pts := PackedVector2Array([Vector2(1.5, 1.5), Vector2(s.x - 1.5, 1.5), Vector2(s.x - 1.5, s.y * 0.5),
					Vector2(c.x, s.y - 1), Vector2(1.5, s.y * 0.5), Vector2(1.5, 1.5)])
				draw_colored_polygon(pts, Color(color, 0.3))
				draw_polyline(pts, color, 1.5, true)
			"move":
				for dx: float in [0.0, 5.0]:
					draw_polyline(PackedVector2Array([Vector2(1 + dx, 2), Vector2(6 + dx, c.y), Vector2(1 + dx, s.y - 2)]), color, 2.0, true)


## Placeholder portrait: a silhouette; a rank chevron for leaders, a red
## corner when hurt.
class Portrait extends Control:
	var rank: bool = false
	var hurt: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color("2b323d"))
		var fig := Color("58637a")
		draw_circle(Vector2(s.x / 2, s.y * 0.36), s.x * 0.17, fig, true, -1.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.16, s.y), Vector2(s.x * 0.24, s.y * 0.68),
			Vector2(s.x * 0.76, s.y * 0.68), Vector2(s.x * 0.84, s.y)]), fig)
		if rank:
			for dy: float in [4.0, 9.0]:
				draw_polyline(PackedVector2Array([Vector2(4, dy + 4), Vector2(9, dy), Vector2(14, dy + 4)]), Color("e6b450"), 2.0, true)
		if hurt:
			draw_colored_polygon(PackedVector2Array([Vector2(s.x - 12, s.y), Vector2(s.x, s.y - 12), Vector2(s.x, s.y)]), Color("e8735f"))


## The breakdown tooltip: sits to the right of the window, level with the
## hovered row, with a pointer back to it.
class Follow extends PanelContainer:
	var target: Control
	var beside: Control
	const POINT_Y := 18.0

	func _process(_delta: float) -> void:
		if target == null or beside == null:
			return
		global_position = Vector2(beside.global_position.x + beside.size.x + 12,
			target.global_position.y + target.size.y / 2.0 - POINT_Y)
		queue_redraw()

	func _draw() -> void:
		var col := Color("e6b450")
		draw_colored_polygon(PackedVector2Array([Vector2(1, POINT_Y - 8), Vector2(-10, POINT_Y), Vector2(1, POINT_Y + 8)]), col)
