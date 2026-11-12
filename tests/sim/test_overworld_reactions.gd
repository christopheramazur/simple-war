extends GutTest
## The reaction window for battles run by OverworldSession (GDD 02 §2.2,
## R3Q1). Task sw-o1m.2.7. Player 1's field commander attacks the bandit
## camp (11,3); its rifle squads have the halt, fall back and retarget
## reactions.

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _session(cfg: ClockConfig = null) -> OverworldSession:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7, cfg)
	var a := Commanders.spawn(s.state, 1, "field_commander", P(12, 4))
	assert_eq(s.set_route(1, a, PackedInt64Array([P(11, 3)])), "")
	_ready_all(s)  # planning -> execute -> intermission
	_ready_all(s)  # intermission -> planning; the battle has begun
	_close_in(s)
	return s


func _ready_all(s: OverworldSession) -> void:
	for p in s.players():
		s.ready(p)


## Moves player 1's squads to 20 m from the guards, on their own side, so
## the coming turn has engagements to react to.
func _close_in(s: OverworldSession) -> void:
	var st: BattleState = (s.battles.values()[0] as OverworldBattle).state
	var sq := st.squads
	var u := st.units
	var g := -1
	for row in sq.count():
		if sq.player[row] != 1:
			g = row
	for row in sq.count():
		if sq.player[row] != 1:
			continue
		var dx := sq.cx[row] - sq.cx[g]
		var dy := sq.cy[row] - sq.cy[g]
		var dist := maxi(Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[g], sq.cy[g]), 1)
		var mx := sq.cx[g] + dx * Fixed.from_int(20) / dist - sq.cx[row]
		var my := sq.cy[g] + dy * Fixed.from_int(20) / dist - sq.cy[row]
		for urow in u.count():
			if u.squad[urow] == sq.id_at(row):
				u.set_value(u.id_at(urow), &"x", u.x[urow] + mx)
				u.set_value(u.id_at(urow), &"y", u.y[urow] + my)
	Centroids.update(st)


## Plays battle turns (orders from a ZoneController for player 1) until the
## reaction window offers player 1 something. Returns its engagement, or -1.
func _to_window(s: OverworldSession) -> int:
	var fighter := ZoneController.new(1)
	for i in 30:
		match s.clock.phase:
			PulseClock.Phase.PLANNING:
				if s.battles.is_empty():
					return -1
				var eid: int = s.battles.keys()[0]
				s.submit_battle_orders(1, eid, fighter.orders(s.observe_battle(1, eid)))
				_ready_all(s)
			PulseClock.Phase.REACTION:
				if not s.reaction_opportunities(1).is_empty():
					return s.reaction_opportunities(1)[0]["engagement"]
				_ready_all(s)
			_:
				_ready_all(s)
	return -1


func test_no_window_without_battles() -> void:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	_ready_all(s)
	assert_eq(s.clock.phase, PulseClock.Phase.INTERMISSION, "straight to execute")
	assert_false(s.clock.config.reaction_enabled)


func test_the_window_opens_for_battles() -> void:
	var s := _session()
	assert_eq(s.battles.size(), 1)
	assert_eq(s.submit_reaction(1, s.battles.keys()[0], 1, "halt", 2), "reactions are only accepted in the reaction window")
	var eid := _to_window(s)
	assert_ne(eid, -1, "player 1 is offered a reaction")
	assert_eq(s.clock.phase, PulseClock.Phase.REACTION)
	assert_true(s.clock.is_ready(2), "a player with nothing to react to is ready at once")
	assert_false(s.clock.is_ready(1))
	var o: Dictionary = s.reaction_opportunities(1)[0]
	assert_eq(s.observe(1)["reactions"].size(), s.reaction_opportunities(1).size())
	assert_eq(s.submit_reaction(1, eid, o["squad"], "no_such", o["trigger"]), "no such reaction opportunity")
	assert_eq(s.submit_reaction(2, eid, o["squad"], o["reactions"][0], o["trigger"]), "no such reaction opportunity")
	assert_eq(s.submit_reaction(1, eid, o["squad"], o["reactions"][0], o["trigger"]), "")
	var kinds := s.input_log.map(func(i: Dictionary) -> String: return i["kind"])
	assert_true(kinds.has("reaction"))
	var turns := s.turns_resolved()
	s.ready(1)
	assert_eq(s.turns_resolved(), turns + 1, "the window closes and the turn executes")
	assert_eq(s.reaction_opportunities(1), [])


func test_save_load_and_replay_in_the_window() -> void:
	var s := _session()
	var eid := _to_window(s)
	assert_ne(eid, -1)
	var o: Dictionary = s.reaction_opportunities(1)[0]
	s.submit_reaction(1, eid, o["squad"], o["reactions"][0], o["trigger"])
	var bytes := s.save()
	var loaded := OverworldSession.load_save(bytes, _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.clock.phase, PulseClock.Phase.REACTION)
	assert_eq(loaded.reaction_opportunities(1), s.reaction_opportunities(1))
	for x in [s, loaded]:
		x.ready(1)
		for t in 4:
			_ready_all(x)
	assert_eq(loaded.turn_hashes, s.turn_hashes)
	assert_eq(loaded.state_hash_hex(), s.state_hash_hex())


func test_reactions_replay() -> void:
	var s := _session()
	var eid := _to_window(s)
	assert_ne(eid, -1)
	var o: Dictionary = s.reaction_opportunities(1)[0]
	s.submit_reaction(1, eid, o["squad"], o["reactions"][0], o["trigger"])
	s.ready(1)
	# A twin session given the same inputs (the spawned commander is set up
	# the same way, outside the log) reaches the same hashes.
	var twin := _session()
	var log: Array = s.input_log.slice(twin.input_log.size())
	twin.replay_inputs(log)
	assert_eq(twin.turn_hashes, s.turn_hashes)
	assert_eq(twin.state_hash_hex(), s.state_hash_hex())


func test_config_can_turn_reactions_off() -> void:
	var cfg := ClockConfig.new()
	cfg.reaction_enabled = false
	var s := _session(cfg)
	for i in 12:
		_ready_all(s)
		assert_ne(s.clock.phase, PulseClock.Phase.REACTION)
	var loaded := OverworldSession.load_save(s.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded)
	_ready_all(loaded)
	assert_ne(loaded.clock.phase, PulseClock.Phase.REACTION, "the setting survives a save")


func test_battles_are_counted_for_bonus_time() -> void:
	var s := _session()
	assert_eq(s.clock.phase, PulseClock.Phase.PLANNING)
	var counts: Dictionary = s.clock.snapshot()["battles"]
	assert_eq(counts[1], 1, "player 1 fights a battle this turn")
	assert_eq(counts[2], 0)
