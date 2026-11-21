extends RefCounted
## Mock (sw-1jy.3): the squad card's segmented SIMPL meters — five countable
## segments per pool, ticks at the band floors the ruleset compiles, band
## icon + word, exact percent only at higher verbosity. Live data from
## BattleSession.observe; the pools are flowed to chosen percentages so every
## band shows on one contact sheet. Render with
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
	var root := Control.new()
	root.custom_minimum_size = Vector2(1380, 480)
	root.add_child(UiTheme.backdrop("ScreenBackgroundPanel"))
	var sheet := VBoxContainer.new()
	sheet.theme_type_variation = &"ListGap"
	sheet.position = Vector2(24, 18)
	root.add_child(sheet)
	sheet.add_child(UiTheme.label("Squad card: segmented SIMPL meters", "SubheadLabel"))
	var marks := PackedStringArray()
	for f in floors.slice(1):
		marks.append(str(f))
	sheet.add_child(UiTheme.label("Five segments per pool; ticks at the compiled band floors (%s), read from the observation, never the UI. "
		% " / ".join(marks) + "Band icon + word always, never colour alone; the exact percent only at higher verbosity. "
		+ "Live BattleSession.observe data, pools flowed to the shown percentages.", "SmallDimLabel", true))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 24)
	sheet.add_child(line)
	line.add_child(_variant(s, row, mine, _mid_band(floors), false, "One band per pool",
		"Broken through Surging, top to bottom. Each segment spans one band."))
	var edges := []
	for b in range(1, floors.size()):
		edges.append(int(floors[b]))
	edges.append(100)
	line.add_child(_variant(s, row, mine, edges, false, "Fills ending on a threshold",
		"Each fill stops exactly at a tick: the segment edge and the band floor agree."))
	line.add_child(_variant(s, row, mine, _mid_band(floors), true, "Higher verbosity",
		"Adds value / capacity and the exact percent."))
	return root


## One card per variant: flow every pool to its percent, re-observe, format.
static func _variant(s: BattleSession, row: int, mine: int, percents: Array, verbose: bool, title: String, note: String) -> Control:
	var st := s.state
	for p in 5:
		var cap := Pools.capacity(st, row, p)
		Pools.flow(st, row, p, Fixed.round_div(int(percents[p]) * cap, 100) - Pools.value(st, row, p), &"mock")
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"BattleColumnPanel"
	var col := VBoxContainer.new()
	col.theme_type_variation = &"CardGap"
	panel.add_child(col)
	col.add_child(UiTheme.label(title, "CardHeadLabel"))
	col.add_child(UiTheme.label(note, "CaptionDimLabel", true))
	col.add_child(SquadCard.build(_squad(s, mine), {}, 1, st.rules.tps, verbose))
	return panel


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
