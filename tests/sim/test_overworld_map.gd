extends GutTest
## Hex maths, hex features, seeded map templates and the overworld state
## (GDD 02 §2.9, 03 §3.5). Task sw-o1m.1.1.

const W := 16
const H := 12

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_rules_cache = OverworldRules.compile(_l().templates, "test_vale", _l().data_hash)
	return _rules_cache


func _f(id: String) -> int:
	return _rules().feature_index(id)


func _has(s: OverworldState, col: int, row: int, feature: String) -> bool:
	return s.feature_row(Hex.plot(col, row, W), _f(feature)) >= 0


# --- hex maths -------------------------------------------------------------

func test_offset_axial_round_trip() -> void:
	for row in H:
		for col in W:
			assert_eq(Hex.to_offset(Hex.to_axial(col, row)), Vector2i(col, row))
	assert_eq(Hex.to_offset(Hex.to_axial(-1, -1)), Vector2i(-1, -1), "negative rows too")


func test_neighbours_are_distance_one() -> void:
	var p := Hex.plot(5, 5, W)
	var n := Hex.neighbours(p, W, H)
	assert_eq(n.size(), 6)
	for q in n:
		assert_eq(Hex.plot_distance(p, q, W), 1)
	# odd-r: row 5 is odd, so its upper neighbours are cols 5 and 6.
	assert_true(n.has(Hex.plot(5, 4, W)) and n.has(Hex.plot(6, 4, W)))
	assert_eq(Hex.neighbours(0, W, H).size(), 2, "corner (0,0) has 2 on-map neighbours")


func test_distance() -> void:
	assert_eq(Hex.plot_distance(Hex.plot(0, 0, W), Hex.plot(3, 0, W), W), 3)
	assert_eq(Hex.plot_distance(Hex.plot(0, 0, W), Hex.plot(0, 4, W), W), 4)
	assert_eq(Hex.plot_distance(Hex.plot(2, 3, W), Hex.plot(7, 9, W), W), Hex.plot_distance(Hex.plot(7, 9, W), Hex.plot(2, 3, W), W))


func test_within_counts_a_hexagon() -> void:
	assert_eq(Hex.within(Hex.plot(8, 6, W), 2, W, H).size(), 19, "1 + 6 + 12")
	assert_eq(Hex.within(0, 1, W, H).size(), 3, "clipped at the corner")


func test_line_steps_between_neighbours() -> void:
	var a := Hex.plot(0, 6, W)
	var b := Hex.plot(15, 5, W)
	var l := Hex.line(a, b, W, H)
	assert_eq(l[0], a)
	assert_eq(l[l.size() - 1], b)
	assert_eq(l.size(), Hex.plot_distance(a, b, W) + 1)
	for i in range(1, l.size()):
		assert_eq(Hex.plot_distance(l[i - 1], l[i], W), 1)
	assert_eq(Hex.line(a, a, W, H), PackedInt64Array([a]))


# --- rules and generation ----------------------------------------------------

func test_rules_compile() -> void:
	var r := _rules()
	assert_true(r.is_valid(), str(r.errors))
	assert_eq([r.width, r.height, r.base_cost], [W, H, 10])
	var v := _f("hex_village")
	assert_eq(r.hf_controllable[v], 1)
	assert_true(r.has_activity(v, "recruit"))
	assert_false(r.has_activity(v, "battle"))
	assert_eq(r.hf_guard[_f("hex_bandit_camp")], PackedStringArray(["rifle_squad", "rifle_squad"]))
	assert_eq(r.passes.size(), 11)


func test_bad_maps_report_errors() -> void:
	var defs := [
		{"id": "grass", "kind": "hex_feature", "values": {"name": "Grass"}},
		{"id": "bad", "kind": "overworld_map", "values": {"width": 4, "height": 4, "passes": [
			{"op": "rect", "feature": "grass", "col": 2, "row": 2, "w": 4, "h": 1},
			{"op": "place", "feature": "grass"},
			{"op": "place", "feature": "grass", "col": 1, "row": 1, "owner": 1},
		]}},
	]
	var r := OverworldRules.compile(TemplateTable.build(defs), "bad")
	assert_eq(r.errors.size(), 3, str(r.errors))
	assert_string_contains(r.errors[0], "outside the 4x4 map")
	assert_string_contains(r.errors[1], "place needs 'col'")
	assert_string_contains(r.errors[2], "not controllable")
	assert_false(OverworldRules.compile(TemplateTable.build(defs), "nope").is_valid())


func test_generation_places_features() -> void:
	var s := OverworldState.create(1, _rules(), 7)
	assert_true(_has(s, 0, 0, "hex_plains") and _has(s, 15, 11, "hex_plains"), "fill covers every plot")
	assert_true(_has(s, 2, 1, "hex_forest") and _has(s, 5, 3, "hex_forest"))
	assert_false(_has(s, 6, 1, "hex_forest"))
	assert_true(_has(s, 7, 2, "hex_lake"))
	assert_true(_has(s, 0, 6, "hex_road") and _has(s, 15, 5, "hex_road"))
	var village := s.feature_row(Hex.plot(1, 6, W), _f("hex_village"))
	assert_eq(s.features.owner[village], 1, "pre-owned by player 1")
	var caches := 0
	var cache_plots := PackedInt64Array()
	for row in s.features.count():
		if s.features.tmpl[row] == _f("hex_supply_cache"):
			caches += 1
			cache_plots.append(s.features.plot[row])
			for avoid: String in ["hex_lake", "hex_village", "hex_mine", "hex_bandit_camp"]:
				assert_eq(s.feature_row(s.features.plot[row], _f(avoid)), -1)
	assert_eq(caches, 3)
	for i in cache_plots.size():
		for j in range(i + 1, cache_plots.size()):
			assert_gt(Hex.plot_distance(cache_plots[i], cache_plots[j], W), 3, "spacing 3")


func test_same_seed_same_map() -> void:
	var a := OverworldState.create(1, _rules(), 7)
	var b := OverworldState.create(1, _rules(), 7)
	var c := OverworldState.create(1, _rules(), 8)
	assert_eq(a.state_hash_hex(), b.state_hash_hex())
	assert_ne(_caches(a), _caches(c), "another seed scatters elsewhere")


func _caches(s: OverworldState) -> PackedInt64Array:
	var out := PackedInt64Array()
	for row in s.features.count():
		if s.features.tmpl[row] == _f("hex_supply_cache"):
			out.append(s.features.plot[row])
	out.sort()
	return out


func test_move_cost() -> void:
	var s := OverworldState.create(1, _rules(), 7)
	assert_eq(s.move_cost(Hex.plot(0, 0, W)), 10, "plains: base cost")
	assert_eq(s.move_cost(Hex.plot(3, 2, W)), 15, "forest +5")
	assert_eq(s.move_cost(Hex.plot(11, 9, W)), 20, "hills +10")
	assert_eq(s.move_cost(Hex.plot(0, 6, W)), 5, "road -5")
	assert_eq(s.move_cost(Hex.plot(7, 2, W)), -1, "lake: impassable")


func test_features_come_and_go() -> void:
	var s := OverworldState.create(1, _rules(), 7)
	var p := Hex.plot(4, 9, W)
	var id := s.add_feature(p, _f("hex_mine"), 2)
	assert_eq(s.add_feature(p, _f("hex_mine")), id, "one of each template per plot")
	assert_eq(s.features_at(p).size(), 2, "plains and mine")
	var before := s.state_hash_hex()
	s.remove_feature(id)
	assert_eq(s.feature_row(p, _f("hex_mine")), -1)
	assert_true(_has(s, 1, 6, "hex_village"), "the cache survives swap-remove")
	assert_ne(s.state_hash_hex(), before)


func test_snapshot_round_trip() -> void:
	var s := OverworldState.create(1, _rules(), 7)
	s.turn = 3
	var snap := s.snapshot()
	var t := OverworldState.new(1, _rules(), 99)
	t.restore(snap)
	assert_eq(t.state_hash_hex(), s.state_hash_hex())
	assert_eq(t.move_cost(Hex.plot(0, 6, W)), 5, "restore rebuilds the plot cache")
