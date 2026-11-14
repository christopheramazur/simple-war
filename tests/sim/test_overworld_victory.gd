extends GutTest
## Built-in overworld win condition (GDD 05 §5.4, A2Q2): on a map with
## `elimination` (test_vale), the last team with commanders wins; the last
## commanders of every team falling together is a draw. Task sw-884.8.
## Battles reuse test_vale's guarded bandit camp (11,3).

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _s(elimination: bool = true) -> OverworldState:
	var r := OverworldRules.compile(_l().templates, "test_vale", _l().data_hash)
	assert_true(r.elimination, "test_vale is a skirmish map")
	r.elimination = elimination
	return OverworldState.create(1, r, 7)


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


## Player 1's field commander fights the bandit camp's guard and loses or
## wins; returns the battle's events.
func _fight(s: OverworldState, player_wins: bool) -> Array:
	var a := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(11, 3)]))
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	var errs := PackedStringArray()
	var b := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_eq(errs, PackedStringArray())
	if not player_wins:
		for bid: int in b.links:
			if b.links[bid] >= 0:
				b.state.squads.set_value(bid, &"destroyed", 1)
	var w := 1 if player_wins else OverworldBattles.NEUTRAL
	b.state.result = {"winner": w, "reason": "annihilation", "turn": 3, "scores": {}, "survivors": {}}
	s.events.drain()
	OverworldBattles.finish(s, b)
	return s.events.drain().filter(func(e: SimEvent) -> bool: return e.type == &"mission_ended")


func test_losing_the_last_commander_loses() -> void:
	var s := _s()
	Commanders.spawn(s, 2, "field_commander", P(13, 5))
	var ended := _fight(s, false)
	assert_eq(s.outcome["outcome"], "lost", "player 1's view")
	assert_eq(s.outcome["winner"], 2)
	assert_eq(s.outcome["key"], "elimination")
	assert_eq(ended.size(), 1, "mission_ended is announced once")


func test_last_side_standing_wins() -> void:
	var s := _s()
	var b2 := Commanders.spawn(s, 2, "field_commander", P(13, 5))
	s.commanders.despawn(b2)  # player 2's last commander fell earlier
	_fight(s, true)
	assert_eq(s.outcome["outcome"], "won")
	assert_eq(s.outcome["winner"], 1)


func test_everyone_falling_together_is_a_draw() -> void:
	var s := _s()
	_fight(s, false)
	assert_eq(s.outcome["outcome"], "drew")
	assert_eq(s.outcome["winner"], 0)


func test_no_win_while_both_sides_have_commanders() -> void:
	var s := _s()
	Commanders.spawn(s, 2, "field_commander", P(13, 5))
	_fight(s, true)
	assert_true(s.outcome.is_empty())


func test_maps_without_elimination_do_not_end() -> void:
	var s := _s(false)
	Commanders.spawn(s, 2, "field_commander", P(13, 5))
	_fight(s, false)
	assert_true(s.outcome.is_empty(), "story maps end through their triggers")


func test_session_reports_the_winner() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 3)
	for id in x.state.commanders.ids():
		if x.state.commanders.get_value(id, &"player") == 2:
			x.state.commanders.despawn(id)
	OverworldVictory.check(x.state)
	assert_eq(SimMetrics._overworld_winner(x), 1)
	assert_eq(x.observe(2)["outcome"]["winner"], 1, "every player sees who won")
	x.state.events.drain()  # saves are taken at a tick boundary
	var saved := OverworldSession.load_save(x.save(), _l().templates, _l().data_hash)
	assert_eq(saved.state.outcome, x.state.outcome, "the outcome survives a save")
