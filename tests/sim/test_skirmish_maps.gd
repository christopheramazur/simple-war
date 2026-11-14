extends GutTest
## First-loop skirmish maps (GDD 05 §5.4, A2Q3, A2Q4): mirror maps (180°
## rotation, players 1 and 2 swapped), the authored skirmish_mirror and the
## seeded skirmish_seeded. Task sw-884.9.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules(map: String) -> OverworldRules:
	var r := OverworldRules.compile(_l().templates, map, _l().data_hash)
	assert_eq(r.errors, PackedStringArray(), map)
	return r


## Plot -> sorted "template:owner" strings.
func _layout(s: OverworldState) -> Dictionary:
	var out := {}
	var f := s.features
	for row in f.count():
		var list: Array = out.get(f.plot[row], [])
		list.append("%d:%d" % [f.tmpl[row], f.owner[row]])
		list.sort()
		out[f.plot[row]] = list
	return out


func _mirrored(r: OverworldRules, entries: Array) -> Array:
	var out := []
	for e: String in entries:
		var parts := e.split(":")
		out.append("%s:%d" % [parts[0], OverworldRules.mirror_player(int(parts[1]))])
	out.sort()
	return out


func test_mirror_is_an_exact_hex_symmetry() -> void:
	var r := _rules("skirmish_mirror")
	assert_eq([r.width, r.height], [20, 10])
	for a in r.plot_count():
		assert_eq(r.mirror_plot(r.mirror_plot(a)), a)
		for b in [0, 37, 104, 199]:
			assert_eq(Hex.plot_distance(r.mirror_plot(a), r.mirror_plot(b), r.width), Hex.plot_distance(a, b, r.width))


func test_authored_map_is_mirrored_with_one_commander_each() -> void:
	var r := _rules("skirmish_mirror")
	assert_true(r.elimination and r.mirror)
	assert_eq(r.players(), PackedInt64Array([1, 2]))
	assert_eq(r.starts.size(), 2, "one commander per side")
	assert_eq(r.starts[1]["player"], 2)
	assert_eq(r.starts[1]["plot"], r.mirror_plot(r.starts[0]["plot"]))
	_assert_symmetric(OverworldState.create(1, r, 1))


func _assert_symmetric(s: OverworldState) -> void:
	var r := s.rules
	var lay := _layout(s)
	var villages := 0
	for plot: int in lay:
		assert_eq(lay.get(r.mirror_plot(plot), []), _mirrored(r, lay[plot]), "plot %d" % plot)
		if lay[plot].has("%d:1" % r.feature_index("hex_village")):
			villages += 1
	assert_eq(villages, 1, "each side owns its home village")


func test_seeded_map_is_mirrored_and_varies_by_seed() -> void:
	var r := _rules("skirmish_seeded")
	var layouts := {}
	for seed_value in [1, 2, 3, 4, 5]:
		var s := OverworldState.create(1, r, seed_value)
		_assert_symmetric(s)
		var key := str(_layout(s))
		assert_eq(str(_layout(OverworldState.create(1, r, seed_value))), key, "same seed, same map")
		layouts[key] = true
		for f in ["hex_mine", "hex_barracks", "hex_bandit_camp", "hex_lake"]:
			var n := 0
			for row in s.features.count():
				n += 1 if s.features.tmpl[row] == r.feature_index(f) else 0
			assert_eq(n, 2, "%s: one per side" % f)
	assert_gt(layouts.size(), 3, "seeds give different maps")


func test_story_vale_does_not_inherit_elimination() -> void:
	assert_false(_rules("trigger_vale").elimination)


func test_mirror_needs_an_even_height() -> void:
	var defs := [
		{"id": "grass", "kind": "hex_feature", "values": {"name": "Grass"}},
		{"id": "odd", "kind": "overworld_map", "values": {"width": 4, "height": 5, "mirror": true,
			"passes": [{"op": "fill", "feature": "grass"}]}},
	]
	var r := OverworldRules.compile(TemplateTable.build(defs), "odd")
	assert_eq(r.errors.size(), 1, str(r.errors))
	assert_string_contains(r.errors[0], "even height")


func test_a_skirmish_plays_to_a_finish() -> void:
	for map in ["skirmish_mirror", "skirmish_seeded"]:
		var x := OverworldSession.create(_l().templates, _l().data_hash, map, 2)
		var ctl := {1: ExpandController.new(1), 2: ExpandController.new(2)}
		HeadlessOverworld.play(x, ctl, 40)
		assert_gt(x.turns_resolved(), 1, map)
		assert_true(x.state.value[1] > 0 or x.state.value[2] > 0, "%s: production pays" % map)
