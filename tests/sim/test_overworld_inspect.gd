extends GutTest
## Feature inspection (GDD 04 §4.4): OverworldSession.inspect_feature, from
## sight or memory, and inspect_plot, which lists each feature through it.
## Task sw-63wt.6. test_vale: player 1 starts at (2,6), player 2 at (13,5).

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _session(seed_value: int = 7) -> OverworldSession:
	return OverworldSession.create(_l().templates, _l().data_hash, "test_vale", seed_value)


## The first feature `player` sees right now as [feature ID, plot], or [].
func _visible_feature(s: OverworldSession, player: int) -> Array:
	var obs := s.observe(player)
	for p: int in obs["plots"]:
		var entry: Dictionary = obs["plots"][p]
		if entry["visible"] and not (entry["features"] as Array).is_empty():
			return [int(entry["features"][0]["id"]), p]
	return []


func test_in_sight_feature_returns_live_facts() -> void:
	var s := _session()
	var found := _visible_feature(s, 1)
	assert_false(found.is_empty(), "the start sees a feature")
	var info := s.inspect_feature(1, found[0])
	assert_eq(info["id"], found[0])
	assert_eq(info["plot"], found[1])
	assert_true(info["visible"])
	assert_eq(info["turn"], s.observe(1)["turn"], "seen now")
	for key in ["name", "owner", "controllable", "guard", "activities", "recruits", "hires", "produces", "line"]:
		assert_has(info, key)
	var row := s.state.features.row_of(found[0])
	assert_eq(info["owner"], s.state.features.owner[row])


func test_out_of_sight_feature_is_remembered_with_its_last_seen_turn() -> void:
	var s := _session()
	var sight := OverworldVision.sight(s.state, 1)
	var plot := -1
	var fid := -1
	for row in s.state.features.count():
		if sight[s.state.features.plot[row]] == 0:
			plot = s.state.features.plot[row]
			fid = s.state.features.id_at(row)
			break
	assert_ne(fid, -1, "a feature out of sight")
	assert_eq(s.inspect_feature(1, fid), {}, "never seen, so unknown")
	# Player 1 glimpses the plot at turn 0, then the turn resolves without it in sight.
	OverworldVision.glimpse(s.state, 1, plot, 0)
	var seen := s.inspect_feature(1, fid)
	assert_false(seen["visible"])
	assert_eq(seen["turn"], 0)
	s.ready(1)
	s.ready(2)
	assert_eq(s.turns_resolved(), 1)
	var later := s.inspect_feature(1, fid)
	assert_false(later["visible"])
	assert_eq(later["turn"], 0, "still the turn it was last seen")
	assert_eq(later["owner"], seen["owner"])
	assert_eq(later["plot"], plot)


func test_dead_unknown_and_strangers_get_nothing() -> void:
	var s := _session()
	var found := _visible_feature(s, 1)
	assert_false(found.is_empty())
	assert_eq(s.inspect_feature(1, 999999), {}, "unknown ID")
	assert_eq(s.inspect_feature(9, found[0]), {}, "not for someone who is not playing")
	s.state.remove_feature(found[0])
	assert_eq(s.inspect_feature(1, found[0]), {}, "a dead feature")


func test_inspect_plot_lists_each_feature_as_inspect_feature_does() -> void:
	var s := _session()
	var found := _visible_feature(s, 1)
	var plot_info := s.inspect_plot(1, found[1])
	assert_false((plot_info["features"] as Array).is_empty())
	for f: Dictionary in plot_info["features"]:
		var one := s.inspect_feature(1, f["id"])
		one.erase("plot")
		one.erase("visible")
		one.erase("turn")
		assert_eq(one, f)


func test_enemy_feature_exposes_no_owner_state() -> void:
	var s := _session()
	var found := _visible_feature(s, 1)
	# Give the feature an enemy owner with hidden production state behind it.
	s.state.features.set_value(found[0], &"owner", 2)
	s.state.features.set_value(found[0], &"output", 0)
	s.state.features.set_value(found[0], &"progress", 3)
	var info := s.inspect_feature(1, found[0])
	assert_eq(info["owner"], 2)
	assert_eq(info["line"], {}, "no supply line of the enemy's")
	for o: Dictionary in info["produces"]:
		assert_eq(o["progress"], -1, "no enemy progress")
		assert_false(o["selected"], "no enemy selected output")


func test_own_producing_feature_shows_its_progress() -> void:
	var s := _session()
	var sight := OverworldVision.sight(s.state, 1)
	var plot := -1
	for p in sight.size():
		if sight[p] == 1:
			plot = p
			break
	# Put a producing feature on a plot in sight and make it player 1's.
	var found := -1
	for t in s.rules.hf_names.size():
		if found == -1 and s.rules.production_count(t) > 0:
			found = s.state.add_feature(plot, t, 1)
	assert_ne(found, -1, "the map has a producing feature template")
	s.state.features.set_value(found, &"owner", 1)
	s.state.features.set_value(found, &"output", 0)
	s.state.features.set_value(found, &"progress", 2)
	var info := s.inspect_feature(1, found)
	assert_eq(info["owner"], 1)
	var chosen: Array = (info["produces"] as Array).filter(func(o: Dictionary) -> bool: return o["selected"])
	assert_eq(chosen.size(), 1)
	assert_eq(chosen[0]["progress"], 2)
