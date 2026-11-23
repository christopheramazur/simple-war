extends GutTest
## Trigger vocabulary part 2 (GDD 03 §3.5, sw-ll4.28): apply_bundle and
## reveal_area in battle; spawn_commander, give_squad, give_item,
## start_engagement and the commander_at check on the overworld.

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## The fixture templates plus `extra` trigger definitions.
func _with(extra: Array) -> TemplateTable:
	var defs := _l().defs.duplicate()
	defs.append_array(extra)
	return TemplateTable.build(defs)


func test_validation_names() -> void:
	var tt := _with([
		{"id": "x", "kind": "trigger", "values": {"on": "turn_resolved", "do": [
			{"do": "give_item", "item": "nope"}, {"do": "apply_bundle", "bundle": "nope"}]}}])
	var ow := TriggerRules.compile(tt, PackedStringArray(["x"]), "overworld", PackedStringArray())
	assert_eq(ow.errors.size(), 2, "; ".join(ow.errors))
	var bt := TriggerRules.compile(tt, PackedStringArray(["x"]), "battle", PackedStringArray())
	assert_eq(bt.errors.size(), 2, "; ".join(bt.errors))


func test_overworld_actions() -> void:
	var r := OverworldRules.compile(_l().templates, "trigger_vale", _l().data_hash)
	var s := OverworldState.create(1, r, 7)
	var tt := _with([
		{"id": "sp", "kind": "trigger", "values": {"on": "turn_resolved", "do": [
			{"do": "spawn_commander", "commander": "field_commander", "player": 1, "col": 2, "row": 2},
			{"do": "spawn_commander", "commander": "field_commander", "player": 2, "col": 2, "row": 2}]}},
		{"id": "tw", "kind": "trigger", "values": {"on": "turn_resolved",
			"if": [{"check": "commander_at", "col": 2, "row": 2, "player": 1}, {"check": "commander_at", "col": 2, "row": 2, "value": 3, "op": "<"}, {"check": "turn", "value": 0}],
			"do": [{"do": "give_squad", "squad": "scout_team", "player": 1, "col": 2, "row": 2},
				{"do": "give_item", "item": "lmg_kit", "count": 3, "player": 1, "col": 2, "row": 2},
				{"do": "start_engagement", "col": 2, "row": 2}]}}])
	var tr := TriggerRules.compile(tt, PackedStringArray(["sp", "tw"]), "overworld", r.feature_ids)
	assert_eq(tr.errors.size(), 0, "; ".join(tr.errors))
	tr.run(s, [])
	var p := Hex.plot(2, 2, W)
	assert_eq(Commanders.at(s, p).size(), 2)
	var mine := -1
	for cid in Commanders.at(s, p):
		if s.commanders.get_value(cid, &"player") == 1:
			mine = cid
	assert_eq(OverworldArmies.count(s, mine), s.rules.cm_army[s.commanders.get_value(mine, &"tmpl")].size() + 1, "the gifted squad")
	var kit := s.rules.item_index("lmg_kit")
	assert_eq(WarChest.count_of(s, kit, mine, -1, -1), 3)
	assert_ne(s.engagement_at(p), -1)
	assert_eq(s.commanders.get_value(mine, &"engagement"), s.engagement_at(p))


func test_battle_bundle_and_reveal() -> void:
	var tt := _with([
		{"id": "bb", "kind": "trigger", "values": {"on": "turn_resolved", "do": [
			{"do": "apply_bundle", "bundle": "hardy", "player": 1},
			{"do": "reveal_area", "player": 1, "x": 100, "y": 50, "radius": 400, "turns": 2}]}}])
	var s := BattleSession.create(_l().templates, _l().data_hash, "hangar_drill", 3)
	var st := s.state
	var tr := TriggerRules.compile(tt, PackedStringArray(["bb"]), "battle", st.rules.zone_ids)
	assert_eq(tr.errors.size(), 0, "; ".join(tr.errors))
	tr.run(st, [])
	var hardy := st.rules.fx.index_of("hardy")
	var n := 0
	for row in st.effects.count():
		if st.effects.bundle[row] == hardy:
			n += 1
			assert_eq(st.squads.player[st.squads.row_of(st.effects.holder_squad[row])], 1)
	assert_gt(n, 0, "side 1 squads got the bundle")
	assert_eq(st.reveals.size(), 1)
	var enemy := -1
	for row in st.squads.count():
		if st.squads.player[row] == 2 and st.squads.is_active(row):
			enemy = row
	assert_ne(enemy, -1)
	var sq := st.squads
	st.reveals = [[1, sq.cx[enemy], sq.cy[enemy], Fixed.from_int(5), -1]]
	var hv := VisionSystem.new()
	sq.set_value(sq.id_at(enemy), &"seen_by", 0)
	hv.run(st)
	assert_ne(sq.seen_by[enemy] & BattleSquads.bit(1), 0, "revealed to side 1")
	var h1 := st.state_hash()
	st.reveals = []
	assert_ne(st.state_hash(), h1, "reveals are hashed")
