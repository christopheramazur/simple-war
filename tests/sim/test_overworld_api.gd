extends GutTest
## Overworld Game API, saves, replays with per-turn hash checks, and a
## headless scenario (GDD 04 §4.4, R7Q14, R8Q5). Task sw-o1m.1.5.
## test_vale starts: player 1 field commander (2,6) and outrider (1,5);
## player 2 field commander (13,5) and outrider (14,4).

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _session(seed_value: int = 7) -> OverworldSession:
	return OverworldSession.create(_l().templates, _l().data_hash, "test_vale", seed_value)


func _controllers() -> Dictionary:
	return {1: ExpandController.new(1), 2: ExpandController.new(2)}


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _own(obs: Dictionary, player: int) -> Array:
	return (obs["commanders"] as Array).filter(func(c: Dictionary) -> bool: return c["player"] == player)


func test_session_starts_in_planning_with_the_map_starts() -> void:
	var s := _session()
	assert_not_null(s)
	assert_eq(s.phase_name(), "PLANNING")
	assert_eq(s.players(), PackedInt64Array([1, 2]))
	var obs := s.observe(1)
	assert_eq(obs["turn"], 0)
	assert_eq(_own(obs, 1).size(), 2)
	assert_eq(_own(obs, 2).size(), 0, "the enemy starts in the fog")
	assert_true(obs["plots"].has(P(2, 6)))
	assert_false(obs["plots"].has(P(13, 5)))


func test_unknown_map_is_refused() -> void:
	assert_null(OverworldSession.create(_l().templates, _l().data_hash, "nowhere", 1))
	assert_string_contains(OverworldSession.last_error, "unknown overworld map")


func test_orders_only_in_planning_and_for_own_commanders() -> void:
	var s := _session()
	var mine: int = _own(s.observe(1), 1)[0]["id"]
	var theirs: int = _own(s.observe(2), 2)[0]["id"]
	assert_eq(s.set_route(1, theirs, PackedInt64Array([P(12, 5)])), "not your commander")
	assert_eq(s.set_route(3, mine, PackedInt64Array([P(3, 6)])), "unknown player")
	var route := s.path(1, mine, P(6, 6))
	assert_false(route.is_empty())
	assert_eq(s.set_route(1, mine, route), "")
	s.ready(1)
	assert_eq(s.phase_name(), "PLANNING", "waits for player 2")
	s.ready(2)
	assert_eq(s.phase_name(), "INTERMISSION")
	assert_eq(s.turns_resolved(), 1)
	assert_eq(s.set_route(1, mine, PackedInt64Array()), "orders are only accepted during planning")
	assert_eq(s.observe(1)["commanders"].filter(func(c: Dictionary) -> bool: return c["id"] == mine)[0]["plot"],
		route[route.size() - 1])


func test_path_is_cut_to_the_budget() -> void:
	var s := _session()
	var mine: int = _own(s.observe(1), 1)[0]["id"]
	var route := s.path(1, mine, P(15, 11))
	assert_false(route.is_empty())
	assert_eq(OverworldOrders.validate_route(s.state, 1, mine, route), "", "affordable as cut")
	assert_lt(route.size(), Hex.plot_distance(P(2, 6), P(15, 11), W))
	assert_eq(s.path(2, mine, P(3, 6)), PackedInt64Array(), "not your commander")


func test_timeout_resolves_the_turn() -> void:
	var s := _session()
	s.advance(60000 + 30000)  # planning plus the whole reserve
	assert_eq(s.turns_resolved(), 1)


func test_events_are_filtered_by_fog() -> void:
	var s := _session()
	s.ready(1)
	s.ready(2)
	var evs: Array = s.observe(1)["events"]
	assert_false(evs.is_empty(), "its own production")
	for e: Dictionary in evs:
		assert_ne(e["data"].get("player", 1), 2, "nothing about player 2")


func test_headless_scenario_is_deterministic() -> void:
	var a := HeadlessOverworld.play(_session(), _controllers(), 8)
	var b := HeadlessOverworld.play(_session(), _controllers(), 8)
	assert_eq(a.turns_resolved(), 8)
	assert_eq(a.turn_hashes, b.turn_hashes)
	assert_gt(a.state.value_of(1), 0)
	assert_gt(a.state.value_of(2), 0)
	var village := a.rules.feature_index("hex_village")
	var home1 := a.state.feature_row(P(1, 6), village)
	var home2 := a.state.feature_row(P(14, 5), village)
	assert_eq([a.state.features.owner[home1], a.state.features.owner[home2]], [2, 1],
		"each side raided the other's village")
	assert_gt(a.state.engagements.count(), 0, "the outriders met")
	assert_gt(a.state.memory[1].size(), 60, "explored")
	assert_gt(a.state.memory[2].size(), 60)
	var c := HeadlessOverworld.play(_session(8), _controllers(), 8)
	assert_ne(c.turn_hashes[7], a.turn_hashes[7], "another seed, another game")


func test_save_load_continues_identically() -> void:
	var full := HeadlessOverworld.play(_session(), _controllers(), 8)
	var half := HeadlessOverworld.play(_session(), _controllers(), 4)
	var loaded := OverworldSession.load_save(half.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.state.state_hash_hex(), half.state.state_hash_hex())
	assert_eq(loaded.observe(1), half.observe(1))
	HeadlessOverworld.play(loaded, _controllers(), 8)
	assert_eq(loaded.turn_hashes, full.turn_hashes)


func test_replay_checks_every_turn_hash() -> void:
	var s := HeadlessOverworld.play(_session(), _controllers(), 6)
	var bytes := s.save()
	var r := OverworldSession.rebuild(bytes, _l().templates, _l().data_hash)
	assert_not_null(r, OverworldSession.last_error)
	assert_eq(r.state.state_hash_hex(), s.state.state_hash_hex())
	var data: Dictionary = bytes_to_var(bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
	data["hashes"][3] = "0".repeat(64)
	var tampered := var_to_bytes(data).compress(FileAccess.COMPRESSION_GZIP)
	assert_null(OverworldSession.rebuild(tampered, _l().templates, _l().data_hash))
	assert_eq(OverworldSession.last_error, "turn 4 did not reproduce its recorded hash")
	assert_null(OverworldSession.load_save(bytes, _l().templates, "other"))
