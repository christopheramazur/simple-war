extends GutTest
## The squad card's SIMPL meter (sw-1jy.3) formats what the Game API reports:
## five segments and threshold ticks placed at the compiled band floors the
## observation carries, band icon + word, exact percent only at higher
## verbosity. The thresholds live in the rules, never here or in the UI.

const ONE := Fixed.ONE

var _session: BattleSession
var _sid: int = -1
var _row: int = -1


func before_each() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	_session = BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	for q: Dictionary in _session.observe(1)["squads"]:
		if q["player"] == 1:
			_sid = q["id"]
			break
	_row = _session.state.squads.row_of(_sid)


func _squad() -> Dictionary:
	for q: Dictionary in _session.observe(1)["squads"]:
		if q["id"] == _sid:
			return q
	return {}


func _set_pool(p: int, pct: int) -> void:
	var st := _session.state
	var cap := Pools.capacity(st, _row, p)
	Pools.flow(st, _row, p, Fixed.round_div(pct * cap, 100) - Pools.value(st, _row, p), &"test")


func _card(verbose: bool = false) -> VBoxContainer:
	var card := SquadCard.build(_squad(), {}, 1, 10, verbose)
	autofree(card)
	return card


func _texts(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_texts(c, out)
	return out


func _with_meta(node: Node, key: StringName, out: Array = []) -> Array:
	if node.has_meta(key):
		out.append(node)
	for c in node.get_children():
		_with_meta(c, key, out)
	return out


func test_the_observation_carries_the_compiled_band_floors() -> void:
	var sq := _squad()
	assert_eq(sq.get("band_floor_pct", []), Array(_session.state.rules.band_floor_pct),
		"the meter's ticks read the rules' floors, not their own")
	assert_eq((sq["band_floor_pct"] as Array).size(), DataSchema.BANDS.size())


func test_every_band_reads_as_icon_and_word() -> void:
	var floors: Array = _squad()["band_floor_pct"]
	for b in DataSchema.BANDS.size():
		var hi := int(floors[b + 1]) if b + 1 < floors.size() else 100
		_set_pool(b, (int(floors[b]) + hi) / 2)  # mid-band, read from the floors
	var pools: Dictionary = _squad()["pools"]
	for b in DataSchema.BANDS.size():
		assert_eq(String(pools[DataSchema.SIMPL[b]]["band"]), DataSchema.BANDS[b], "the sim maps mid-band")
	var text := "\n".join(_texts(_card()))
	for band: String in DataSchema.BANDS:
		assert_string_contains(text, String(BandGlyphs.ICONS[band]) + " " + band.capitalize(),
			"icon + word, never colour alone")


func test_segments_and_ticks_sit_at_the_api_floors() -> void:
	var floors: Array = _squad()["band_floor_pct"]
	var segments := _with_meta(_card(), &"band")
	assert_eq(segments.size(), 5 * DataSchema.BANDS.size(), "five segments per SIMPL pool")
	var meters := {}
	for seg: Panel in segments:
		var parent := seg.get_parent()
		if not meters.has(parent):
			meters[parent] = []
		(meters[parent] as Array).append(seg)
	assert_eq(meters.size(), 5, "one meter per pool")
	for parent: Control in meters:
		var segs: Array = meters[parent]
		for b in DataSchema.BANDS.size():
			var seg: Panel = segs[b]
			assert_eq(seg.get_meta(&"band"), b, "segments in band order")
			var lo := 0.0 if b == 0 else float(floors[b]) / 100.0
			var hi := float(floors[b + 1]) / 100.0 if b + 1 < floors.size() else 1.0
			assert_almost_eq(seg.anchor_left, lo, 0.0001, "segment %d left edge" % b)
			assert_almost_eq(seg.anchor_right, hi, 0.0001, "segment %d right edge" % b)
		var ticks := _with_meta(parent, &"tick")
		assert_eq(ticks.size(), floors.size() - 1, "a tick at every inner floor")
		for i in ticks.size():
			var tick: Panel = ticks[i]
			assert_eq(tick.get_meta(&"tick"), int(floors[i + 1]))
			assert_almost_eq(tick.anchor_left, float(floors[i + 1]) / 100.0, 0.0001)


func test_the_fill_follows_the_value_and_the_percent_is_verbose_only() -> void:
	_set_pool(BattleSquads.MORALE, 52)
	var st := _session.state
	var floors: Array = _squad()["band_floor_pct"]
	var b := Pools.band(st, _row, BattleSquads.MORALE)
	var text := "\n".join(_texts(_card()))
	assert_false(text.contains("%"), "no exact percent at the default verbosity")
	# Find Morale's meter by its tone-driven fill, then check every segment.
	var morale_segs := {}
	for seg: Panel in _with_meta(_card(), &"band"):
		if seg.get_child_count() > 0 and (seg.get_child(0) as Panel).theme_type_variation == &"MoraleBar":
			morale_segs[seg.get_parent()] = true
	assert_eq(morale_segs.size(), 1, "one meter fills with the Morale tone")
	for seg: Panel in _with_meta(_card(), &"band"):
		if not morale_segs.has(seg.get_parent()):
			continue
		var sb := int(seg.get_meta(&"band"))
		if sb < b:
			assert_eq(seg.get_child_count(), 1, "bands below the value are full")
			assert_almost_eq((seg.get_child(0) as Panel).anchor_right, 1.0, 0.0001)
		elif sb == b:
			var lo := float(floors[sb])
			var hi := float(floors[sb + 1]) if sb + 1 < floors.size() else 100.0
			assert_almost_eq((seg.get_child(0) as Panel).anchor_right, (52.0 - lo) / (hi - lo), 0.0001,
				"the current band fills to the value")
		else:
			assert_eq(seg.get_child_count(), 0, "bands above the value are empty")
	var vtext := "\n".join(_texts(_card(true)))
	assert_string_contains(vtext, "(52%)", "the exact percent at higher verbosity")
	assert_string_contains(vtext, "%s / %s" % [Fixed.to_display(Pools.value(st, _row, BattleSquads.MORALE)),
		Fixed.to_display(Pools.capacity(st, _row, BattleSquads.MORALE))], "value / capacity")


## The text label of one SIMPL meter row, found by its pool name label.
func _meter_text(pool: String, verbose: bool) -> String:
	for seg: Panel in _with_meta(_card(verbose), &"band"):
		var row: Node = seg.get_parent().get_parent()
		var first := row.get_child(0) as Label
		if first != null and first.text.ends_with(pool.capitalize()):
			return (row.get_child(row.get_child_count() - 1) as Label).text
	return ""


func test_verbose_shows_the_sim_distance_to_the_next_lower_band() -> void:
	# sw-1jy.4: the displayed distance equals the sim helper's value (GDD 02
	# §2.1, displayed = used); the card never does its own pool math.
	var st := _session.state
	var pcts: Array[int] = [52, 70, 22, 95, 44]
	for p in DataSchema.SIMPL.size():
		_set_pool(p, pcts[p])
	var default_text := "\n".join(_texts(_card()))
	for p in DataSchema.SIMPL.size():
		var d := BattleRules.points_to_drop(Pools.value(st, _row, p), Pools.capacity(st, _row, p),
			st.rules.band_floor_pct)
		var b := Pools.band(st, _row, p)
		var phrase := "%s to %s" % [Fixed.to_display(d), DataSchema.BANDS[b - 1].capitalize()]
		assert_false(default_text.contains(phrase), "no distance at the default verbosity")
		assert_string_contains(_meter_text(DataSchema.SIMPL[p], true), phrase,
			"%s shows the sim-derived distance" % DataSchema.SIMPL[p])


func test_a_broken_pool_has_no_distance_even_verbose() -> void:
	_set_pool(BattleSquads.MORALE, 5)
	var st := _session.state
	assert_eq(Pools.band(st, _row, BattleSquads.MORALE), Pools.BROKEN)
	assert_eq(BattleRules.points_to_drop(Pools.value(st, _row, BattleSquads.MORALE),
		Pools.capacity(st, _row, BattleSquads.MORALE), st.rules.band_floor_pct), -1, "no lower band")
	assert_false(_meter_text("morale", true).contains(" to "), "nothing below Broken")


func test_each_simpl_pool_has_a_unique_icon_and_glossary_name_with_hover() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var g := Glossary.from_templates(l.templates)
	var seen := {}
	for p: String in DataSchema.SIMPL:
		var icon := SquadCard.pool_icon(p)
		assert_false(seen.has(icon), "icon for %s is shared" % p)
		seen[icon] = true
		assert_false(BandGlyphs.ICONS.values().has(icon), "%s clashes with a band icon" % p)
		assert_eq(SquadCard.pool_word(p, g), g.name_of("term_" + p))
	var card := SquadCard.build(_squad(), {}, 1, 10, false, {"glossary": g})
	autofree(card)
	var labels := _with_meta(card, &"pool")
	assert_eq(labels.size(), 5)
	for lab: Label in labels:
		assert_true(lab.tooltip_text.contains(g.text_of("term_" + String(lab.get_meta(&"pool")))))


func test_pool_tooltip_matches_the_battle_ledger_exactly() -> void:
	var st := _session.state
	Pools.flow(st, _row, BattleSquads.MORALE, -6 * ONE, &"hp_lost")
	Pools.flow(st, _row, BattleSquads.MORALE, 2 * ONE + ONE / 2, &"drift")
	Pools.flow(st, _row, BattleSquads.MORALE, -ONE, &"hp_lost")
	var pd: Dictionary = _squad()["pools"]["morale"]
	var expect := []
	for k: String in st.ledger:
		if k.begins_with("%d|%d|" % [_sid, BattleSquads.MORALE]):
			expect.append(int(st.ledger[k]))
	var got := []
	for e: Dictionary in pd["ledger"]:
		got.append(int(e["amount"]))
	expect.sort()
	got.sort()
	assert_eq(got, expect, "API ledger equals the battle ledger")
	var tip := SquadCard.ledger_text("morale", pd["ledger"])
	assert_string_contains(tip, "Wounds: -7")
	assert_string_contains(tip, "Drift toward rest: +2.5")
	for w in ["slight", "major", "minor", "huge", "small"]:
		assert_false(tip.to_lower().contains(w), "no vague magnitude word " + w)
	var found := false
	for n: Node in _with_meta_tooltip(_card()):
		found = found or (n as Control).tooltip_text == SquadCard.ledger_text("morale", pd["ledger"])
	assert_true(found, "the morale meter row carries the tooltip")


func _with_meta_tooltip(node: Node, out: Array = []) -> Array:
	if node is Control and (node as Control).tooltip_text != "":
		out.append(node)
	for c in node.get_children():
		_with_meta_tooltip(c, out)
	return out
