extends GutTest
## Game API, saves, replays and the headless Duel. Tasks sw-lgj.1, sw-qio.8, sw-lgj.2.

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _session(seed_value: int = 11) -> BattleSession:
	return BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", seed_value)


func _controllers() -> Dictionary:
	return {1: ZoneController.new(1), 2: ZoneController.new(2, {"fall_back_pct": 60})}


func test_session_starts_in_planning() -> void:
	var s := _session()
	assert_eq(s.phase_name(), "PLANNING")
	assert_eq(s.players(), PackedInt64Array([1, 2]))
	var obs := s.observe(1)
	assert_eq(obs["turn"], 1)
	for sq: Dictionary in obs["squads"]:
		assert_eq(sq["player"], 1, "enemies start out of sight")
	assert_eq(obs["zones"].size(), 3)


func test_orders_rejected_outside_planning_and_for_enemies() -> void:
	var s := _session()
	var theirs: int = s.observe(2)["squads"][0]["id"]
	var errs := s.submit_orders(1, [{"squad": theirs, "type": "hold"}])
	assert_string_contains(errs[0], "not your squad")
	s.ready(1)
	s.ready(2)
	assert_ne(s.phase_name(), "PLANNING")
	errs = s.submit_orders(1, [])
	assert_string_contains(errs[0], "only accepted during planning")


func test_turn_cycle_through_api() -> void:
	var s := _session()
	var c := _controllers()
	for p in s.players():
		s.submit_orders(p, c[p].orders(s.observe(p)))
		s.ready(p)
	# Reaction window opens (enabled by default); everyone passes.
	assert_eq(s.phase_name(), "REACTION")
	s.ready(1)
	s.ready(2)
	assert_eq(s.phase_name(), "INTERMISSION")
	assert_eq(s.state.turn, 1)
	s.ready(1)
	s.ready(2)
	assert_eq(s.phase_name(), "PLANNING")
	assert_eq(s.observe(1)["turn"], 2)


func test_timeouts_drive_the_clock() -> void:
	var s := _session()
	s.advance(60000 + 30000)
	assert_eq(s.phase_name(), "REACTION", "planning timed out with reserve spent")
	s.advance(10000)
	assert_eq(s.phase_name(), "INTERMISSION", "reaction window expired, turn executed")
	assert_eq(s.state.turn, 1)


func test_headless_duel_finishes_deterministically() -> void:
	var a := HeadlessDuel.play(_session(5), _controllers())
	var b := HeadlessDuel.play(_session(5), _controllers())
	assert_true(a.is_over())
	assert_eq(a.state.state_hash().hex_encode(), b.state.state_hash().hex_encode())
	assert_eq(a.state.result, b.state.result)
	assert_true(a.state.turn <= a.rules.turn_limit)


func test_observation_hides_unseen_enemies() -> void:
	var s := _session()
	var c := _controllers()
	for _t in 3:
		for p in s.players():
			s.submit_orders(p, c[p].orders(s.observe(p)))
		for p in s.players():
			s.ready(p)
		s.ready(1)
		s.ready(2)
		s.ready(1)
		s.ready(2)
	var obs := s.observe(1)
	var listed := 0
	for sq: Dictionary in obs["squads"]:
		if sq["player"] == 2:
			listed += 1
			var row := s.state.squads.row_of(sq["id"])
			assert_ne(s.state.squads.seen_by[row] & BattleSquads.bit(1), 0, "only seen enemies are listed")
			assert_false(sq.has("pools"), "no enemy internals")
	var truly_seen := 0
	var hidden := 0
	for row in s.state.squads.count():
		if s.state.squads.player[row] == 2 and s.state.squads.is_active(row):
			if s.state.squads.seen_by[row] & BattleSquads.bit(1) != 0:
				truly_seen += 1
			else:
				hidden += 1
	assert_eq(listed, truly_seen, "every seen enemy squad is listed, nothing more")
	var listed_units := 0
	for u: Dictionary in obs["units"]:
		var srow := s.state.squads.row_of(u["squad"])
		if s.state.squads.player[srow] == 2:
			listed_units += 1
			assert_ne(s.state.squads.seen_by[srow] & BattleSquads.bit(1), 0)
	gut.p("enemy squads listed %d, hidden %d, enemy units listed %d" % [listed, hidden, listed_units])


func test_save_load_continues_identically() -> void:
	var full := _session(9)
	var c := _controllers()
	HeadlessDuel.play(full, c, 3)
	# Play 3 turns, save in planning, load, finish; compare with uninterrupted.
	var part := _session(9)
	HeadlessDuel.play(part, _controllers(), 3)
	var bytes := part.save()
	var loaded := BattleSession.load_save(bytes, _l().templates, _l().data_hash)
	assert_not_null(loaded)
	assert_eq(loaded.state.state_hash().hex_encode(), part.state.state_hash().hex_encode())
	HeadlessDuel.play(full, c)
	HeadlessDuel.play(loaded, _controllers())
	assert_eq(loaded.state.state_hash().hex_encode(), full.state.state_hash().hex_encode())
	assert_eq(loaded.state.result, full.state.result)


func test_rebuild_from_inputs_matches_snapshot() -> void:
	var s := _session(13)
	HeadlessDuel.play(s, _controllers(), 4)
	var bytes := s.save()
	var rebuilt := BattleSession.rebuild(bytes, _l().templates, _l().data_hash)
	assert_not_null(rebuilt, "inputs reproduce the saved hash")
	assert_eq(rebuilt.state.state_hash().hex_encode(), s.state.state_hash().hex_encode())


func test_save_refuses_other_content() -> void:
	var s := _session()
	var bytes := s.save()
	assert_null(BattleSession.load_save(bytes, _l().templates, "not-the-same-hash"))
	assert_string_contains(BattleSession.last_error, "content differs")


func test_reaction_through_api() -> void:
	var s := _session(21)
	var c := _controllers()
	var reacted := false
	for _t in 6:
		if s.is_over():
			break
		for p in s.players():
			s.submit_orders(p, c[p].orders(s.observe(p)))
		for p in s.players():
			s.ready(p)
		var ops := s.reaction_opportunities(2)
		if not ops.is_empty() and not reacted:
			var o: Dictionary = ops[0]
			assert_eq(s.submit_reaction(2, o["squad"], "halt", o["trigger"]), "")
			assert_ne(s.submit_reaction(1, o["squad"], "halt", o["trigger"]), "", "not player 1's opportunity")
			reacted = true
		s.ready(1)
		s.ready(2)
		s.ready(1)
		s.ready(2)
	assert_true(reacted, "an opportunity arose within 6 turns")
