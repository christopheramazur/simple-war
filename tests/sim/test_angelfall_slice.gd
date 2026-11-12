extends GutTest
## The M4 vertical slice (sw-cf6, GDD 06 §6.9, R6Q16): Angelfall played
## through the Game API from start to end. Jeff walks to the blockade with
## no battleforce and disperses it, then takes his army to the spaceport;
## the battle is fought by EvacuationController against the Angels'
## GuardController. Jeff's death ends the mission lost.

const W := 12

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


## Plays up to `turns` overworld turns; returns the session.
func _play(seed_value: int, turns: int = 30) -> OverworldSession:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "angelfall_frontier", seed_value)
	var s := x.state
	var j: int = s.commanders.ids()[0]
	x.set_battleforce(1, j, OverworldBattleforce.NONE, PackedInt64Array(), false)
	var goal := P(7, 3)
	var ctl := EvacuationController.new(1)
	var guard := 0
	while s.outcome.is_empty() and x.turns_resolved() < turns and guard < turns * 4:
		guard += 1
		if x.clock.phase == PulseClock.Phase.PLANNING and s.commanders.is_alive(j):
			var at: int = s.commanders.get_value(j, &"plot")
			if at == P(7, 3) or at == P(8, 3):
				x.set_battleforce(1, j, "", PackedInt64Array(), true)
				goal = P(10, 3)
			if s.commanders.get_value(j, &"engagement") < 0 and at != goal:
				x.set_route(1, j, x.path(1, j, goal))
			for eid: int in x.battles:
				x.submit_battle_orders(1, eid, ctl.orders(x.observe_battle(1, eid)))
		x.ready(1)
	return x


func test_the_mission_can_be_won() -> void:
	var x := _play(5)
	var o := x.observe(1)
	assert_eq(o["outcome"].get("outcome", ""), "won", str(o["outcome"]))
	assert_eq(x.state.vars.get("angels_dispersed", 0), 1, "the blockade was dispersed, not fought")
	assert_gt(x.turns_resolved(), 3)
	assert_true(x.last_events.any(func(e: SimEvent) -> bool: return e.type == &"mission_ended"))


func test_the_slice_replays() -> void:
	var x := _play(6)
	var rebuilt := OverworldSession.rebuild(x.save(), _l().templates, _l().data_hash)
	assert_not_null(rebuilt, OverworldSession.last_error)
	assert_eq(rebuilt.state_hash_hex(), x.state_hash_hex())
	assert_eq(rebuilt.state.outcome, x.state.outcome)


func test_losing_jeff_loses_the_mission() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "angelfall_frontier", 5)
	var s := x.state
	var j: int = s.commanders.ids()[0]
	# Jeff alone (his army sent away) against the spaceport's Angels.
	for id in OverworldArmies.of(s, j):
		if s.squads.get_value(id, &"own") == 0:
			s.squads.despawn(id)
	s.commanders.set_value(j, &"plot", P(9, 3))
	x.set_route(1, j, PackedInt64Array([P(10, 3)]))
	var guard := 0
	while s.outcome.is_empty() and guard < 60:
		guard += 1
		x.ready(1)
	assert_eq(s.outcome.get("outcome", ""), "lost")
	assert_false(s.commanders.is_alive(j))


func test_the_angels_hunt_civilians() -> void:
	var br := BattleRules.compile(_l().templates, "angelfall_spaceport")
	var obs := {"squads": [
		{"id": 1, "player": 30, "template": "angel_host", "x": 0, "y": 0, "destroyed": false, "withdrawn": false},
		{"id": 2, "player": 1, "template": "cr0_patrol", "x": Fixed.from_int(5), "y": 0, "destroyed": false, "withdrawn": false},
		{"id": 3, "player": 1, "template": "civilian_group", "x": Fixed.from_int(50), "y": 0, "destroyed": false, "withdrawn": false}]}
	assert_eq(GuardController.orders(obs, br, 30), [{"squad": 1, "type": "attack", "target": 3}], "past the robots, for the civilians")
