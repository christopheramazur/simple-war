extends GutTest
## BattleProbe (sw-tho3.2, U1 B2): one read-only truth snapshot. Viewer 0 must
## equal BattleActivity and LineOfFire called directly; viewer > 0 is fog-safe
## per field; the snapshot never changes the state.

const ONE := Fixed.ONE

static var _loader: PackageLoader
static var _rules_cache: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _rules() -> BattleRules:
	if _rules_cache == null:
		_rules_cache = BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	return _rules_cache


func _empty() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	return ScenarioBuilder.place(s, player, squad, x * ONE, y * ONE)


## A stationary enemy that cannot shoot back and cannot die.
func _target(s: BattleState, x: int, y: int) -> int:
	return ScenarioBuilder.target_dummy(s, 2, "rifle_squad", x * ONE, y * ONE)


func _squad_of(snap: Dictionary, sid: int) -> Dictionary:
	for d: Dictionary in snap["squads"]:
		if d["id"] == sid:
			return d
	return {}


func _units_of(snap: Dictionary, sid: int) -> Array:
	return (snap["units"] as Array).filter(func(u: Dictionary) -> bool: return u["squad"] == sid)


func _mentions(list: Array, key: String, sid: int) -> bool:
	for e: Dictionary in list:
		if e.get(key, -2) == sid:
			return true
	return false


## Viewer 0 is the direct sim view: activity, target, hold reasons, victims and
## LineOfFire codes all match the functions they come from.
func test_viewer_zero_matches_direct_calls() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 85, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	sim.runner.step(s)
	var snap := BattleProbe.snapshot(s, 0)
	assert_eq(snap["tick"], s.tick)
	for d: Dictionary in snap["squads"]:
		var row := s.squads.row_of(d["id"])
		assert_eq(d["activity"], BattleActivity.squad(s, row))
		assert_eq(d["target"], s.squads.engaged[row])
		assert_true(d.has("order"))
		assert_true(d.has("pools"), "all-seeing shows pools")
	assert_eq(_squad_of(snap, mortar)["activity"], BattleActivity.Squad.READY)
	assert_eq(_squad_of(snap, mortar)["target"], enemy)
	for ud: Dictionary in _units_of(snap, mortar):
		var urow := s.units.row_of(ud["id"])
		assert_eq(ud["hold"], BattleActivity.hold(s, urow))
		assert_eq(ud["hold"], BattleActivity.Hold.RELOADING)
		var v := BattleActivity.victim(s, urow)
		assert_eq(ud["victim"], s.units.id_at(v) if v >= 0 else -1)
		assert_gt(ud["victim_dist"], 0)
	var found := false
	for f: Dictionary in snap["fire"]:
		var a := s.squads.row_of(f["from"])
		var b := s.squads.row_of(f["to"])
		assert_eq(f["los"], LineOfFire.check(s, a, b))
		if f["from"] == mortar and f["to"] == enemy:
			found = true
	assert_true(found, "the engaged pair is in the fire matrix")


## The snapshot writes nothing: the state hash is the same after every view.
func test_snapshot_leaves_state_hash_unchanged() -> void:
	var s := _empty()
	_place(s, 1, "mortar_team", 50, 70)
	_target(s, 85, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	var before := s.state_hash()
	BattleProbe.snapshot(s, 0)
	BattleProbe.snapshot(s, 1)
	BattleProbe.snapshot(s, 2)
	assert_eq(s.state_hash(), before)


## An unseen enemy squad is absent from every field of the fog-safe view, and
## a seen enemy exposes no order, pools, casualties, hold reason or victim.
func test_fog_hides_unseen_squad_in_every_field() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var seen := _target(s, 70, 70)
	var hidden := _place(s, 2, "rifle_squad", 190, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	# Events that name the unseen squad must not leak through the log.
	var shot := SimEvent.new(&"squad_fired", {"squad": hidden, "target": mortar, "shots": 3, "hits": 2})
	shot.tick = s.tick - 1
	var dmg := SimEvent.new(&"squad_damaged", {"squad": hidden, "target": mortar, "damage": 40, "kills": 1})
	dmg.tick = s.tick - 1
	var kill := SimEvent.new(&"unit_killed", {"unit": 999, "squad": mortar, "by": hidden})
	kill.tick = s.tick - 1
	var own_shot := SimEvent.new(&"squad_fired", {"squad": seen, "target": mortar, "shots": 1, "hits": 0})
	own_shot.tick = s.tick - 1
	s.turn_log.append_array([shot, dmg, kill, own_shot])

	var snap := BattleProbe.snapshot(s, 1)
	assert_true(_squad_of(snap, hidden).is_empty(), "unseen squad is not listed")
	assert_true(_units_of(snap, hidden).is_empty(), "nor are its units")
	assert_false(_mentions(snap["fire"], "from", hidden), "no fire row")
	assert_false(_mentions(snap["fire"], "to", hidden), "no fire column")
	assert_false(_mentions(snap["shots"], "squad", hidden), "no shots")
	assert_false(_mentions(snap["shots"], "target", hidden), "no shots at it")
	assert_false(_mentions(snap["hits"], "squad", hidden), "no hits")
	assert_false(_mentions(snap["hits"], "target", hidden), "no hits on it")
	assert_false(_mentions(snap["casualties"], "by", hidden), "no casualties it caused")
	# The mortar's own shot at the seen enemy stays; the unseen one is gone.
	assert_eq(snap["shots"].size(), 2, "the mortar's shot and the seen squad's shot")
	assert_true(_mentions(snap["shots"], "squad", seen))
	assert_true(_mentions(snap["shots"], "squad", mortar))
	assert_eq(snap["hits"].size(), 0)
	assert_eq(snap["casualties"].size(), 0)

	var es := _squad_of(snap, seen)
	assert_false(es.is_empty(), "the seen enemy is listed")
	assert_eq(es["activity"], BattleActivity.squad_seen(s, s.squads.row_of(seen)))
	assert_false(es.has("target"), "a disarmed enemy shows no target")
	assert_false(es.has("order"), "no order")
	assert_false(es.has("pools"), "no pool bands")
	assert_false(es.has("hp_lost"), "no casualty count")
	for ud: Dictionary in _units_of(snap, seen):
		assert_false(ud.has("hold"), "no hold reason")
		assert_false(ud.has("victim"), "no victim")

	var own := _squad_of(snap, mortar)
	assert_true(own.has("pools") and own.has("order") and own.has("hp_lost"), "own squads in full")
	for f: Dictionary in snap["fire"]:
		assert_eq(f["from"], mortar, "fire rows are own squads only")
		assert_eq(f["to"], seen, "fire columns are seen enemies only")

	var all := BattleProbe.snapshot(s, 0)
	assert_false(_squad_of(all, hidden).is_empty(), "the all-seeing view lists it")
	assert_true(_mentions(all["casualties"], "by", hidden), "and its events")


## Shots, hits and casualties are the last RECENT_TICKS ticks of the turn log.
func test_recent_events_come_from_the_turn_log() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 85, 70)
	var sim := BattleSim.new()
	# The mortar fires on tick 0 and then reloads: a window of RECENT_TICKS
	# ticks after three steps still covers tick 0.
	for _t in BattleProbe.RECENT_TICKS:
		sim.runner.step(s)
	var stale := SimEvent.new(&"squad_fired", {"squad": mortar, "target": enemy, "shots": 9, "hits": 9})
	stale.tick = s.tick - BattleProbe.RECENT_TICKS - 1
	s.turn_log.append(stale)
	var since := s.tick - BattleProbe.RECENT_TICKS
	var expected := 0
	for e in s.turn_log:
		if e.type == &"squad_fired" and e.tick >= since:
			expected += 1
	assert_eq(expected, 1, "the mortar's one volley is inside the window")
	var snap := BattleProbe.snapshot(s, 0)
	assert_eq(snap["shots"].size(), expected, "the stale shot is left out")
	for sh: Dictionary in snap["shots"]:
		assert_eq(sh["squad"], mortar)
		assert_eq(sh["target"], enemy)
		assert_gte(sh["tick"], since)
		assert_eq(sh["shots"], 3, "one shot per mortarman")


## Timing and bounds on a 40-squad battle: the fire matrix only holds pairs
## that are engaged or inside reach, not all pairs.
func test_forty_squad_snapshot_is_bounded() -> void:
	var s := _empty()
	for i in 20:
		_place(s, 1, "rifle_squad", 10 + (i % 5) * 12, 20 + (i / 5) * 25)
	for i in 20:
		_place(s, 2, "rifle_squad", 150 + (i % 5) * 12, 20 + (i / 5) * 25)
	assert_eq(s.squads.count(), 40)
	var sim := BattleSim.new()
	sim.runner.step(s)
	var t0 := Time.get_ticks_usec()
	var snap := BattleProbe.snapshot(s, 0)
	var us := Time.get_ticks_usec() - t0
	print("BattleProbe 40-squad snapshot: %d us, %d fire pairs" % [us, (snap["fire"] as Array).size()])
	assert_lt((snap["fire"] as Array).size(), 20 * 20 + 1)
	for f: Dictionary in snap["fire"]:
		var a := s.squads.row_of(f["from"])
		var b := s.squads.row_of(f["to"])
		var engaged: bool = s.squads.engaged[a] == f["to"]
		var in_reach := Fixed.distance(s.squads.cx[a], s.squads.cy[a], s.squads.cx[b], s.squads.cy[b]) <= s.squads.reach[a]
		assert_true(engaged or in_reach, "only engaged or in-range pairs")


## The engaged pair's relation facts are exactly SquadRelation.facts called
## directly, both directions, and each pair appears once.
func test_relations_match_squad_relation_for_engaged_pair() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 85, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	sim.runner.step(s)
	var snap := BattleProbe.snapshot(s, 0)
	var found := []
	for r: Dictionary in snap["relations"]:
		if (r["a"] == mortar and r["b"] == enemy) or (r["a"] == enemy and r["b"] == mortar):
			found.append(r)
	assert_eq(found.size(), 1, "one entry per engaged pair")
	if found.size() == 1:
		assert_eq(found[0]["facts"], SquadRelation.facts(s, 0, found[0]["a"], found[0]["b"]))
		assert_false((found[0]["facts"] as Array).is_empty(), "the pair has facts")
	var fog := BattleProbe.snapshot(s, 1)
	for r: Dictionary in fog["relations"]:
		if r["a"] == mortar and r["b"] == enemy:
			assert_eq(r["facts"], SquadRelation.facts(s, 1, mortar, enemy), "fog view uses the viewer's facts")


## A pair with a squad the viewer cannot see is left out of the relations, and
## the fog view never names an unseen squad in a relation.
func test_relations_leave_out_unseen_pairs() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var hidden := _place(s, 2, "rifle_squad", 190, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	# Engage the own squad on the unseen one: the pair must not show.
	s.squads.engaged[s.squads.row_of(mortar)] = hidden
	var snap := BattleProbe.snapshot(s, 1)
	for r: Dictionary in snap["relations"]:
		assert_ne(r["a"], hidden, "no relation names the unseen squad")
		assert_ne(r["b"], hidden, "no relation names the unseen squad")
	assert_false(_mentions(snap["relations"], "a", hidden) or _mentions(snap["relations"], "b", hidden))
	# The all-seeing view does show the same pair.
	var all := BattleProbe.snapshot(s, 0)
	assert_true(_mentions(all["relations"], "b", hidden) or _mentions(all["relations"], "a", hidden))


## Relations are read-only: the state hash is unchanged by the snapshot that
## carries them.
func test_relations_do_not_change_state_hash() -> void:
	var s := _empty()
	_place(s, 1, "mortar_team", 50, 70)
	_target(s, 85, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	var before := s.state_hash()
	for v in [0, 1, 2]:
		BattleProbe.snapshot(s, v)
	assert_eq(s.state_hash(), before)
