extends GutTest
## Late joiners and reinforcements deploy (sw-bafi.13, U1 C12): a joining
## side's arrival area is fixed at Planning start and is the one used at
## Reveal (two joiners resolve ascending, each counting the earlier ones'
## areas as taken); arriving squads may be placed inside their area; the
## area is shown to that player only. test_vale: bandit camp (11,3) guarded
## by 2 rifle squads; field_commander: own rifle squad + 2 rifle squads.

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_rules_cache = OverworldRules.compile(_l().templates, "test_vale", _l().data_hash)
	return _rules_cache


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


## Player 1 fights the bandit camp's guards: [state, battle].
func _battle() -> Array:
	var s := OverworldState.create(1, _rules(), 7)
	var a := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(11, 3)]))
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	var errs := PackedStringArray()
	var b := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_eq(errs, PackedStringArray())
	return [s, b]


## Sends every squad of a new commander of `player` into b (as if it had
## walked onto the battle tile): its squad IDs.
func _send_in(s: OverworldState, b: OverworldBattle, player: int) -> Array:
	var c := Commanders.spawn(s, player, "field_commander", P(11, 3))
	var ids := []
	for id in OverworldArmies.of(s, c):
		s.squads.set_value(id, &"deployed", b.engagement)
		ids.append(id)
	return ids


func _side_area(b: OverworldBattle, player: int) -> PackedInt64Array:
	for sd in b.rules.sides:
		if sd["player"] == player:
			return sd["deploy"]
	return PackedInt64Array()


func _bid_of(b: OverworldBattle, id: int) -> int:
	for bid: int in b.links:
		if b.links[bid] == id:
			return bid
	return -1


func _inside(r: PackedInt64Array, x: int, y: int) -> bool:
	return x >= r[0] and y >= r[1] and x <= r[0] + r[2] and y <= r[1] + r[3]


func test_two_joiners_in_one_reveal_resolve_ascending_with_distinct_areas() -> void:
	var sb := _battle()
	var s: OverworldState = sb[0]
	var b: OverworldBattle = sb[1]
	var late3 := _send_in(s, b, 3)
	var late2 := _send_in(s, b, 2)
	assert_eq(OverworldBattles.joiners(s, b), [2, 3], "ascending, whatever the deployment order")
	OverworldBattles.plan_arrivals(s, b)
	var a2: Dictionary = b.arrivals[2]
	var a3: Dictionary = b.arrivals[3]
	assert_eq(a2, OverworldBattles.arrival_area(b, []), "the first joiner sees only the squads fighting")
	assert_eq(a3, OverworldBattles.arrival_area(b, [a2]), "the second counts the first's area as taken")
	assert_ne(a2["deploy"], a3["deploy"], "they do not land on each other")
	assert_eq(OverworldBattles.arrival_area_of(s, b, 3), a3)
	OverworldBattles.reinforce(s, b)
	assert_eq(_side_area(b, 2), a2["deploy"], "Reveal uses the area planned for 2")
	assert_eq(_side_area(b, 3), a3["deploy"], "Reveal uses the area planned for 3")
	for id: int in late2 + late3:
		var row := b.state.squads.row_of(_bid_of(b, id))
		assert_gt(row, -1)
		var pl := b.state.squads.player[row]
		assert_true(_inside(_side_area(b, pl), b.state.squads.ax[row], b.state.squads.ay[row]))
	assert_eq(b.arrivals, {}, "used up")


func test_unplanned_joiners_resolve_the_same_way() -> void:
	var sb := _battle()
	var s: OverworldState = sb[0]
	var b: OverworldBattle = sb[1]
	_send_in(s, b, 3)
	_send_in(s, b, 2)
	var a2 := OverworldBattles.arrival_area(b, [])
	var a3 := OverworldBattles.arrival_area(b, [a2])
	OverworldBattles.reinforce(s, b)  # no plan_arrivals (a save from before C12)
	assert_eq(_side_area(b, 2), a2["deploy"])
	assert_eq(_side_area(b, 3), a3["deploy"])


func test_a_placed_reinforcement_spawns_where_placed() -> void:
	var sb := _battle()
	var s: OverworldState = sb[0]
	var b: OverworldBattle = sb[1]
	var a := Commanders.at(s, P(11, 3))[0]
	var spare: int = OverworldArmies.of(s, a)[2]
	var r := _side_area(b, 1)
	var place := {"x": r[0] + r[2] / 4, "y": r[1] + r[3] / 4, "facing": 1234}
	assert_eq(OverworldBattles.place_error(s, b, 1, spare, place), "")
	assert_eq(OverworldBattles.place_error(s, b, 1, spare, {"x": r[0] - Fixed.ONE, "y": r[1], "facing": 0}),
		"outside the arrival area")
	assert_eq(OverworldBattles.place_error(s, b, 1, spare, {"x": r[0], "y": r[1]}), "facing must be an int")
	assert_eq(OverworldOrders.reinforce(s, 1, a, spare, 2), "")
	b.places[spare] = place
	OverworldBattles.reinforce(s, b)
	var row := b.state.squads.row_of(_bid_of(b, spare))
	var st := b.state.squads.tmpl[row]
	var want := BattleDeploy.open_point_in(b.rules, st, place["x"], place["y"], r)
	want = BattleSetup.open_point(b.rules, st, want[0], want[1])
	assert_eq([b.state.squads.ax[row], b.state.squads.ay[row]], [want[0], want[1]])
	assert_eq(b.state.squads.facing[row], 1234)


func test_an_unplaced_reinforcement_spawns_at_the_centre_as_before() -> void:
	var sb := _battle()
	var s: OverworldState = sb[0]
	var b: OverworldBattle = sb[1]
	var a := Commanders.at(s, P(11, 3))[0]
	var spare: int = OverworldArmies.of(s, a)[2]
	assert_eq(OverworldOrders.reinforce(s, 1, a, spare, 2), "")
	OverworldBattles.reinforce(s, b)
	var row := b.state.squads.row_of(_bid_of(b, spare))
	var r := _side_area(b, 1)
	var want := BattleSetup.open_point(b.rules, b.state.squads.tmpl[row], r[0] + r[2] / 2, r[1] + r[3] / 2)
	assert_eq([b.state.squads.ax[row], b.state.squads.ay[row]], [want[0], want[1]])


# --- Session -----------------------------------------------------------------


func _to_planning(s: OverworldSession) -> void:
	var n := 0
	while s.clock.phase != PulseClock.Phase.PLANNING and n < 6:
		n += 1
		s.ready(1)
		s.ready(2)


## A running battle and player 2's commander whose battleforce arrives at the
## next Reveal, in Planning: [session, eid, late commander].
func _session_joiner() -> Array:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var a := Commanders.spawn(s.state, 1, "field_commander", P(12, 4))
	assert_eq(s.set_route(1, a, PackedInt64Array([P(11, 3)])), "")
	s.ready(1)
	s.ready(2)
	_to_planning(s)
	var eid: int = s.battles.keys()[0]
	var late := Commanders.spawn(s.state, 2, "field_commander", P(12, 4))
	assert_eq(s.set_route(2, late, PackedInt64Array([P(11, 3)])), "")
	var steps := 0
	while steps < 4 and s.battles.has(eid) and s.arrival(2, eid).is_empty():
		steps += 1
		s.ready(1)
		s.ready(2)
		_to_planning(s)
	return [s, eid, late]


func test_the_joiner_sees_its_area_in_planning_and_arrives_there() -> void:
	var x := _session_joiner()
	var s: OverworldSession = x[0]
	var eid: int = x[1]
	assert_true(s.battles.has(eid), "the battle is still running")
	var arr := s.arrival(2, eid)
	assert_false(arr.is_empty(), "player 2's battleforce is on the way")
	if arr.is_empty():
		return
	assert_true(arr["joining"])
	assert_eq((arr["squads"] as Array).size(), 2)
	var b: OverworldBattle = s.battles[eid]
	assert_false(b.state.players.has(2), "not a side until Reveal")
	# Fog: nobody else is told where it lands.
	assert_eq(s.arrival(1, eid), {}, "player 1 has nothing arriving")
	for ar: Dictionary in s.observe_battle(1, eid)["areas"]:
		assert_ne(int(ar["player"]), 2, "the joiner's area is not in player 1's observation")
	var first: Dictionary = arr["squads"][0]
	var second: Dictionary = arr["squads"][1]
	var r := PackedInt64Array(arr["area"])
	var place := {"squad": first["squad"], "x": r[0] + r[2] / 3, "y": r[1] + r[3] / 3, "facing": 512}
	assert_eq(s.submit_arrival(1, eid, [place]), PackedStringArray(["nothing of yours arrives in that battle"]))
	var bad := {"squad": second["squad"], "x": r[0] + r[2] + Fixed.ONE, "y": r[1], "facing": 0}
	assert_eq(s.submit_arrival(2, eid, [place, bad]).size(), 1, "the bad placement is refused")
	assert_true(s.arrival(2, eid)["squads"][0]["placed"])
	assert_false(s.arrival(2, eid)["squads"][1]["placed"])
	var planned := s.arrival(2, eid)
	var saved := s.save()
	s.ready(1)
	s.ready(2)
	assert_true(b.state.players.has(2), "joined at Reveal")
	var side := PackedInt64Array()
	for sd in b.rules.sides:
		if sd["player"] == 2:
			side = sd["deploy"]
	assert_eq(Array(side), arr["area"], "the area shown in Planning is the one used at Reveal")
	var row := -1
	var row2 := -1
	for bid: int in b.links:
		if b.links[bid] == first["squad"]:
			row = b.state.squads.row_of(bid)
		if b.links[bid] == second["squad"]:
			row2 = b.state.squads.row_of(bid)
	assert_gt(row, -1)
	assert_gt(row2, -1)
	var st := b.state.squads.tmpl[row]
	var want := BattleDeploy.open_point_in(b.rules, st, place["x"], place["y"], side)
	want = BattleSetup.open_point(b.rules, st, want[0], want[1])
	assert_eq([b.state.squads.ax[row], b.state.squads.ay[row]], [want[0], want[1]], "spawned where placed")
	assert_eq(b.state.squads.facing[row], 512)
	var auto := BattleSetup.open_point(b.rules, b.state.squads.tmpl[row2], second["x"], second["y"])
	assert_eq([b.state.squads.ax[row2], b.state.squads.ay[row2]], [auto[0], auto[1]], "the unplaced one at its shown place")
	# A save in Planning keeps the plan and the placements.
	var loaded := OverworldSession.load_save(saved, _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.arrival(2, eid), planned, "the plan and placements survive a save")
	loaded.ready(1)
	loaded.ready(2)
	assert_eq(loaded.state_hash_hex(), s.state_hash_hex())
	_to_planning(s)
	_to_planning(loaded)
	assert_eq(loaded.state_hash_hex(), s.state_hash_hex(), "a loaded save plays on the same")
	var logged := s.input_log.filter(func(i: Dictionary) -> bool: return i["kind"] == "arrival")
	assert_eq(logged.size(), 1)
	assert_eq((logged[0]["payload"]["placements"] as Array).size(), 1, "only the kept placement is logged")


func test_session_reinforce_with_a_place() -> void:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var a := Commanders.spawn(s.state, 1, "field_commander", P(12, 4))
	assert_eq(s.set_route(1, a, PackedInt64Array([P(11, 3)])), "")
	s.ready(1)
	s.ready(2)
	_to_planning(s)
	var eid: int = s.battles.keys()[0]
	var b: OverworldBattle = s.battles[eid]
	var spare: int = OverworldArmies.of(s.state, a)[2]
	var r := _side_area(b, 1)
	assert_eq(s.reinforce(1, a, spare, {"x": r[0] - Fixed.ONE, "y": r[1], "facing": 0}), "outside the arrival area")
	assert_eq(s.state.squads.get_value(spare, &"deployed"), -1, "a bad place refuses the whole order")
	var place := {"x": r[0] + r[2] / 4, "y": r[1] + r[3] / 4, "facing": 2048}
	assert_eq(s.reinforce(1, a, spare, place), "")
	var arr := s.arrival(1, eid)
	assert_false(arr["joining"])
	assert_true(arr["squads"][0]["placed"])
	s.ready(1)
	s.ready(2)
	var row := b.state.squads.row_of(_bid_of(b, spare))
	assert_gt(row, -1)
	assert_eq(b.state.squads.facing[row], 2048)
	var st := b.state.squads.tmpl[row]
	var want := BattleDeploy.open_point_in(b.rules, st, place["x"], place["y"], r)
	want = BattleSetup.open_point(b.rules, st, want[0], want[1])
	assert_eq([b.state.squads.ax[row], b.state.squads.ay[row]], [want[0], want[1]])
	var logged := s.input_log.filter(func(i: Dictionary) -> bool: return i["kind"] == "reinforce")
	assert_eq(logged.size(), 1, "the refused order is not logged")
	assert_eq(logged[0]["payload"]["place"], place)
	# The input log replays it: the same spawn, then every logged input.
	var r2 := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	Commanders.spawn(r2.state, 1, "field_commander", P(12, 4))
	r2.replay_inputs(s.input_log.duplicate(true))
	assert_eq(r2.state_hash_hex(), s.state_hash_hex(), "replayed from the log")
	var rb: OverworldBattle = r2.battles[eid]
	var rrow := rb.state.squads.row_of(_bid_of(rb, spare))
	assert_eq(rb.state.squads.facing[rrow], 2048)
