extends GutTest
## The battle glance summary (sw-1jy.5, GDD 01 pillar 1, 02 §2.8): the worst
## SIMPL band across the player's OWN squads only (fog-safe), and a
## backward-looking trend from the session's recorded history — headless
## through the Game API. Bands are read as the API reports them; no
## thresholds are re-declared here.

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## Player 1 in two battles (the war room demo's shape): the bandit camp and
## a meeting with player 2. `battle_turns` battle turns have run; the phase
## is Planning (a full turn is ready → intermission → ready → planning).
func _session(battle_turns: int = 0) -> OverworldSession:
	var l := _l()
	var cfg := ClockConfig.new()
	cfg.reaction_enabled = false
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7, cfg)
	assert_not_null(s)
	var a := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(12, 4, W))
	s.set_route(1, a, PackedInt64Array([Hex.plot(11, 3, W)]))
	var b := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(5, 5, W))
	Commanders.spawn(s.state, 2, "field_commander", Hex.plot(6, 5, W))
	s.set_route(1, b, PackedInt64Array([Hex.plot(6, 5, W)]))
	for i in battle_turns + 1:
		_ready_all(s)
		_ready_all(s)
	assert_eq(s.battles.size(), 2, "two battles running")
	assert_eq(s.phase_name(), "PLANNING")
	return s


func _ready_all(s: OverworldSession) -> void:
	for p in s.players():
		s.ready(p)


func _camp_eid(s: OverworldSession) -> int:
	for eid: int in s.battles:
		if (s.battles[eid] as OverworldBattle).state.players.has(OverworldBattles.NEUTRAL):
			return eid
	return -1


func _own_rows(b: OverworldBattle, player: int) -> Array[int]:
	var out: Array[int] = []
	for row in b.state.squads.count():
		if b.state.squads.player[row] == player and b.state.squads.is_active(row):
			out.append(row)
	return out


func _drain(b: OverworldBattle, row: int, pool: int) -> void:
	Pools.flow(b.state, row, pool, -Pools.value(b.state, row, pool), &"test")


func _fill(b: OverworldBattle, row: int, pool: int) -> void:
	Pools.flow(b.state, row, pool, Pools.capacity(b.state, row, pool) - Pools.value(b.state, row, pool), &"test")


## The worst band the API itself reports for the player's own fighting
## squads (observe_battle hides enemy pools).
func _reported_worst(s: OverworldSession, eid: int, player: int) -> String:
	var worst := DataSchema.BANDS.size() - 1
	for sq: Dictionary in s.observe_battle(player, eid)["squads"]:
		if sq["player"] != player or sq.get("destroyed", false) or sq.get("withdrawn", false):
			continue
		for pool: Dictionary in (sq["pools"] as Dictionary).values():
			worst = mini(worst, DataSchema.BANDS.find(String(pool["band"])))
	return DataSchema.BANDS[worst]


func test_worst_band_aggregates_own_squads_only() -> void:
	var s := _session()
	var eid := _camp_eid(s)
	assert_ne(eid, -1)
	var b: OverworldBattle = s.battles[eid]
	var before := s.battle_summary(1, eid)
	assert_eq(before["band"], _reported_worst(s, eid, 1), "the worst band the API reports for own squads")
	assert_eq(before["trend"], "steady", "recorded at the battle's start, nothing has run since")
	# Enemy pools stay hidden and never leak into the summary.
	for sq: Dictionary in s.observe_battle(1, eid)["squads"]:
		if sq["player"] != 1:
			assert_false(sq.has("pools"), "enemy pools are hidden")
	for row in b.state.squads.count():
		if b.state.squads.player[row] != 1:
			for p in DataSchema.SIMPL.size():
				_drain(b, row, p)
	assert_eq(s.battle_summary(1, eid)["band"], before["band"], "broken enemy pools change nothing")
	# One own pool broken makes it the worst, named with its squad.
	var rows := _own_rows(b, 1)
	assert_gt(rows.size(), 0)
	var morale := DataSchema.SIMPL.find("morale")
	_drain(b, rows[0], morale)
	var sum := s.battle_summary(1, eid)
	assert_eq(sum["band"], "broken")
	assert_eq(sum["pool"], "morale")
	assert_eq(sum["squad"], b.state.squads.id_at(rows[0]))
	assert_eq(sum["band"], _reported_worst(s, eid, 1))


func test_summary_only_for_players_in_the_battle() -> void:
	var s := _session()
	var eid := _camp_eid(s)
	assert_eq(s.battle_summary(2, eid), {}, "player 2 does not fight the guards")
	assert_eq(s.battle_summary(9, eid), {}, "nor does a stranger")
	assert_eq(s.battle_summary(1, -1), {})
	var other := -1
	for e: int in s.battles:
		if e != eid:
			other = e
	assert_false(s.battle_summary(2, other).is_empty(), "player 2 fights in the other battle")
	assert_false(s.battle_summary(1, other).is_empty())


func test_trend_compares_with_the_last_recorded_value() -> void:
	var s := _session()
	var eid := _camp_eid(s)
	var b: OverworldBattle = s.battles[eid]
	var rows := _own_rows(b, 1)
	var morale := DataSchema.SIMPL.find("morale")
	var start := s.battle_summary(1, eid)
	assert_eq(start["trend"], "steady")
	assert_eq(start["prev_band"], start["band"], "the record from the battle's start")
	# A band crossing shows at once, against the last record — no turn has
	# resolved, and drafted orders (a forecast) never move the trend.
	_drain(b, rows[0], morale)
	assert_eq(s.battle_summary(1, eid)["trend"], "worsening")
	assert_eq(s.battle_summary(1, eid)["prev_band"], start["band"])
	var order := {"type": "hold", "squad": b.state.squads.id_at(rows[0])}
	assert_eq(s.submit_battle_orders(1, eid, [order]).size(), 0)
	s.forecast_battle(1, eid, [order])
	assert_eq(s.battle_summary(1, eid)["trend"], "worsening", "a forecast is not a trend")
	# Resolving the turn records the new worst band; the trend settles.
	_ready_all(s)
	_ready_all(s)
	var after := s.battle_summary(1, eid)
	assert_eq(after["trend"], "steady", "the record now matches the present")
	assert_eq(after["prev_band"], after["band"])
	assert_eq(after["band"], _reported_worst(s, eid, 1))
	# Filling every own pool reads as improving against that record.
	for row in _own_rows(b, 1):
		for p in DataSchema.SIMPL.size():
			_fill(b, row, p)
	var surged := s.battle_summary(1, eid)
	assert_eq(surged["band"], "surging")
	assert_eq(surged["trend"], "improving" if after["band"] != "surging" else "steady")


func test_the_recorded_history_survives_a_save() -> void:
	var s := _session(1)
	var eid := _camp_eid(s)
	var b: OverworldBattle = s.battles[eid]
	var rows := _own_rows(b, 1)
	assert_gt(rows.size(), 0)
	_drain(b, rows[0], DataSchema.SIMPL.find("morale"))
	var before := s.battle_summary(1, eid)
	var l := _l()
	var t := OverworldSession.load_save(s.save(), l.templates, l.data_hash)
	assert_not_null(t)
	assert_eq(t.battle_summary(1, eid), before, "the trend's reference loads with the game")
