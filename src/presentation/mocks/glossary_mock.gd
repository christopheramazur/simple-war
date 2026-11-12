extends RefCounted
## Mock (sw-ip8.4): glossary tooltips fed by a real duel squad. Top: a
## line of text with its defined terms linked. Below: tooltips as the
## player would see them hovering terms on that squad: Bad Hit on a
## trooper and on a Hardy one (better, ▲), Evasion while dug in, Morale,
## and the squad after a casualty (worse, ▼). Render with
## `hx godot mock res://src/presentation/mocks/glossary_mock.gd`.

const ONE := Fixed.ONE
const BG := Color("12151a")
const GAP := 18.0


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var g := Glossary.from_templates(l.templates)
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	var st := s.state
	var sid := -1
	for q: Dictionary in s.observe(1)["squads"]:
		if q["template"] == "rifle_squad":
			sid = q["id"]
	var row := st.squads.row_of(sid)
	var units := Centroids.units_of(st, row)
	var before := {"inspection": s.inspect(1, sid), "unit": 1}
	Effects.apply(st, st.rules.fx.index_of("hardy"), sid, st.units.id_at(units[1]))
	Effects.apply(st, st.rules.fx.index_of("dug_in"), sid)
	Health.queue(st, -1, sid, st.units.id_at(units[7]), sid, 99 * ONE, 0)
	HealthSystem.new().run(st)
	st.commands.apply(st)
	Centroids.update(st)
	EffectSystem.new().run(st)
	Pools.flow(st, row, BattleSquads.MORALE, 14 * ONE, &"mock")
	var squad := {}
	for q: Dictionary in s.observe(1)["squads"]:
		if q["id"] == sid:
			squad = q
	var after := {"inspection": s.inspect(1, sid), "unit": 1, "squad": squad}

	var root := Control.new()
	root.custom_minimum_size = Vector2(1000, 310)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(GAP, GAP)
	col.size = root.custom_minimum_size - Vector2(GAP, GAP) * 2
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	var line := GlossaryLabel.new()
	line.glossary = g
	line.custom_minimum_size = Vector2(960, 0)
	line.add_theme_font_size_override("normal_font_size", 17)
	line.set_linked("One Bad Hit from breaking: the Squad's Morale is Fraying, and every Reaction costs Instinct. Hover a term.")
	col.add_child(line)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)
	for pair: Array in [["term_bad_hit", before], ["term_bad_hit", after], ["term_evasion", after],
			["term_morale", after], ["term_squad", after]]:
		var tip := GlossaryTooltip.new()
		grid.add_child(tip)
		tip.show_tip(g.tooltip(pair[0], pair[1]))
	return root
