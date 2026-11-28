extends GutTest
## Band kinds and caravan sight (sw-63wt.2, U1Q26, U1Q27): a garrison sees
## 1 hex, a caravan 3; the kind is a detachment column set at every spawn
## and transition, derived in older saves. test_vale (fixture): its
## convoy_movement 40 overrides the caravan's 30 points.

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


func _s() -> OverworldState:
	return OverworldState.create(1, _rules(), 7)


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _band(s: OverworldState, did: int) -> String:
	return _rules().band_ids[OverworldStats.band_of(s, s.detachments.row_of(did))]


## A garrison of player 1 dropped at p by a fresh field commander.
func _garrison(s: OverworldState, p: int) -> int:
	var cid := Commanders.spawn(s, 1, "field_commander", p)
	return Detachments.drop(s, cid, p)


## Plots in player 1's sight now that were not in `before`.
func _newly_seen(s: OverworldState, before: PackedByteArray) -> Dictionary:
	var after := OverworldVision.sight(s, 1)
	var out := {}
	for p in after.size():
		if after[p] == 1 and before[p] == 0:
			out[p] = true
	return out


func _assert_sees(s: OverworldState, at: int, radius: int, seen: Dictionary, what: String) -> void:
	var ring := {}
	for q in Hex.within(at, radius, W, _rules().height):
		ring[q] = true
	var mask := OverworldVision.sight(s, 1)
	for q: int in ring:
		assert_eq(mask[q], 1, "%s sees %d within radius %d" % [what, q, radius])
	for q: int in seen:
		assert_true(ring.has(q), "%s sees nothing past radius %d (plot %d)" % [what, radius, q])


func test_band_kinds_compile_with_the_map_overrides() -> void:
	var r := _rules()
	assert_true(r.is_valid(), str(r.errors))
	assert_eq(r.band_ids[r.band_garrison], "band_garrison")
	assert_eq(r.band_ids[r.band_caravan], "band_caravan")
	assert_eq(r.bd_sight[r.band_garrison], 1)
	assert_eq(r.bd_sight[r.band_caravan], 3)
	assert_eq(r.bd_mp[r.band_garrison], 30)
	assert_eq(r.bd_mp[r.band_caravan], 40, "the map's convoy_movement overrides the caravan's points")
	assert_eq(r.bd_payload_stats[r.band_caravan], PackedStringArray(["sight"]))
	assert_eq(r.bd_caps[r.band_caravan][OverworldRules.BAND_STATS.find("sight")], 2)
	assert_eq(r.bd_payload_stats[r.band_garrison], PackedStringArray())
	assert_eq(r.detachment_sight, 1)
	assert_eq(r.convoy_mp, 40)


func test_core_caravans_move_30_and_see_3() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := OverworldRules.compile(l.templates, "test_vale", l.data_hash)
	assert_true(r.is_valid(), str(r.errors))
	assert_eq(r.bd_sight[r.band_caravan], 3)
	assert_eq(r.bd_mp[r.band_caravan], 30)
	assert_eq(r.bd_sight[r.band_garrison], 1)


func test_a_garrison_sees_1_and_a_caravan_3() -> void:
	var s := _s()
	var at := P(8, 10)
	var before := OverworldVision.sight(s, 1)
	var did := s.detachments.spawn({&"player": 1, &"plot": at, &"band": _rules().band_garrison})
	var seen := _newly_seen(s, before)
	assert_eq(_band(s, did), "band_garrison")
	assert_eq(OverworldStats.sight_of(s, OverworldStats.BAND, did), 1)
	_assert_sees(s, at, 1, seen, "a garrison")
	var t := _s()
	before = OverworldVision.sight(t, 1)
	var cv := t.detachments.spawn({&"player": 1, &"plot": at, &"band": _rules().band_caravan})
	seen = _newly_seen(t, before)
	assert_eq(OverworldStats.sight_of(t, OverworldStats.BAND, cv), 3)
	_assert_sees(t, at, 3, seen, "a caravan")
	assert_eq(OverworldStats.movement_of(t, OverworldStats.BAND, cv), 40)
	var terms: Array = OverworldStats.sight(t, OverworldStats.BAND, cv)["terms"]
	assert_eq(terms, [{"source": "band_caravan", "name": "Caravan", "amount": 3}])


func test_every_transition_sets_the_band() -> void:
	var s := _s()
	var did := _garrison(s, P(5, 8))
	assert_eq(s.detachments.get_value(did, &"band"), _rules().band_garrison, "drop-off: a garrison")
	assert_eq(Convoys.rally(s, 1, did, P(5, 10), -1), "")
	assert_eq(s.detachments.get_value(did, &"band"), _rules().band_caravan, "rally: a caravan")
	var g2 := _garrison(s, P(3, 9))
	assert_eq(Convoys.set_route(s, 1, g2, PackedInt64Array([P(4, 9)])), "")
	assert_eq(s.detachments.get_value(g2, &"band"), _rules().band_caravan, "set_route: a caravan")
	OverworldTurn.resolve(s)
	OverworldTurn.resolve(s)
	assert_true(s.detachments.is_alive(g2))
	assert_eq(s.detachments.get_value(g2, &"band"), _rules().band_garrison, "arrived: a garrison again")
	var cid := Commanders.spawn(s, 1, "field_commander", P(2, 2))
	var sq := OverworldArmies.of(s, cid)
	Convoys.rally_survivors(s, cid, P(2, 3), sq)
	var rallied := Detachments.at(s, P(2, 3))
	assert_eq(rallied.size(), 1)
	assert_eq(s.detachments.get_value(rallied[0], &"band"), _rules().band_caravan, "rallied survivors: a caravan")
	var fid := s.features.id_at(s.feature_row(P(8, 7), _rules().feature_index("hex_barracks")))
	s.features.set_value(fid, &"owner", 1)
	Convoys._make(s, fid, 1, P(8, 7), _rules().squad_index("rifle_squad"), -1, 0)
	var made := Detachments.at(s, P(8, 7))
	assert_eq(s.detachments.get_value(made[0], &"band"), _rules().band_garrison, "made with no line: a garrison")
	assert_eq(Convoys.set_line(s, 1, fid, P(1, 6), -1), "")
	Convoys._make(s, fid, 1, P(8, 7), _rules().squad_index("rifle_squad"), -1, 0)
	made = Detachments.at(s, P(8, 7))
	assert_eq(made.size(), 2, "the line's squad leaves as its own convoy")
	assert_eq(s.detachments.get_value(made[1], &"band"), _rules().band_caravan, "made on a line: a caravan")


## Draft 05 §3.3: a caravan that halts stays a caravan (its sight, and it can
## be sent on). It holds its hex like any detachment, but it is not the
## hex's garrison: a drop-off there forms or joins the garrison instead.
func test_a_halted_caravan_stays_a_caravan_and_is_not_the_garrison() -> void:
	var s := _s()
	var at := P(8, 10)
	var did := _garrison(s, P(8, 11))
	assert_eq(Convoys.set_route(s, 1, did, PackedInt64Array([at])), "")
	assert_eq(Convoys.rally(s, 1, did, -1, -1), "")
	var row := s.detachments.row_of(did)
	assert_false(Convoys.is_convoy(s, row), "halted: no destination")
	assert_true(OverworldStats.is_caravan(s, row), "a halted caravan stays a caravan")
	assert_eq(OverworldStats.sight_of(s, OverworldStats.BAND, did), 3, "and keeps its sight")
	# Halting the derived kind of a row spawned without one pins it.
	var old := s.detachments.spawn({&"player": 1, &"plot": P(3, 9), &"dest_plot": P(4, 9)})
	assert_eq(Convoys.rally(s, 1, old, -1, -1), "")
	assert_eq(_band(s, old), "band_caravan", "halting pins a derived caravan")
	# Not the hex's garrison: a drop-off on its hex forms one beside it.
	var cid := Commanders.spawn(s, 1, "field_commander", P(8, 11))
	s.detachments.set_value(did, &"plot", P(8, 11))
	var g := Detachments.drop(s, cid, P(8, 11))
	assert_ne(g, did, "a drop-off does not join a halted caravan")
	assert_eq(_band(s, g), "band_garrison")
	assert_eq(Detachments.squads_of(s, g).size() > 0, true)
	# It can be sent on, and on arriving joins the garrison there.
	assert_eq(Convoys.rally(s, 1, did, P(8, 11), -1), "")
	OverworldTurn.resolve(s)
	assert_false(s.detachments.is_alive(did), "arrived on its own hex: it joined the garrison")
	assert_eq(_band(s, g), "band_garrison")


func test_an_old_save_derives_bands_and_plays() -> void:
	var s := _s()
	var fid := s.features.id_at(s.feature_row(P(8, 7), _rules().feature_index("hex_barracks")))
	s.features.set_value(fid, &"owner", 1)
	s.add_value(1, 20, &"test")
	var garrison := _garrison(s, P(8, 7))
	assert_eq(Convoys.set_line(s, 1, fid, P(1, 6), -1), "", "a supply line from the garrison's hex")
	var to_plot := s.detachments.spawn({&"player": 1, &"plot": P(5, 8), &"dest_plot": P(5, 10)})
	var to_cmd := s.detachments.spawn({&"player": 1, &"plot": P(3, 8),
		&"dest_commander": s.commanders.id_at(0)})
	var on_line := s.detachments.spawn({&"player": 1, &"plot": P(9, 8), &"dest_plot": P(1, 6), &"line": fid})
	var snap := s.snapshot()
	(snap["tables"]["detachment"]["columns"] as Dictionary).erase("band")
	var t := _s()
	t.restore(snap)
	for did in [garrison, to_plot, to_cmd, on_line]:
		assert_eq(t.detachments.get_value(did, &"band"), -1, "an old save has no band")
	assert_eq(_band(t, garrison), "band_garrison", "a garrison on a hex with a supply line stays a garrison")
	assert_eq(_band(t, to_plot), "band_caravan", "dest_plot: a caravan")
	assert_eq(_band(t, to_cmd), "band_caravan", "dest_commander: a caravan")
	assert_eq(_band(t, on_line), "band_caravan", "a line convoy: a caravan")
	var u := _s()
	u.restore(snap)
	for i in 4:
		OverworldTurn.resolve(t)
		OverworldTurn.resolve(u)
	assert_eq(t.turn, u.turn)
	assert_eq(t.state_hash(), u.state_hash(), "an old save plays on deterministically")


func test_a_same_seed_rerun_hashes_identically() -> void:
	var hashes := []
	for k in 2:
		var s := _s()
		var did := _garrison(s, P(5, 8))
		Convoys.rally(s, 1, did, P(9, 9), -1)
		var g := _garrison(s, P(3, 9))
		Convoys.set_route(s, 1, g, PackedInt64Array([P(4, 9), P(5, 9)]))
		for i in 5:
			OverworldTurn.resolve(s)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])


func test_a_moving_caravan_glimpses_3_hexes() -> void:
	var s := _s()
	var did := _garrison(s, P(8, 11))
	assert_eq(Convoys.set_route(s, 1, did, PackedInt64Array([P(8, 10)])), "")
	s.memory.erase(1)
	OverworldTurn.resolve(s)
	var mem: Dictionary = s.memory.get(1, {})
	for q in Hex.within(P(8, 10), 3, W, _rules().height):
		assert_true(mem.has(q), "remembers %d within 3 of where it moved" % q)


func test_observe_shows_bands_and_hides_enemy_stats() -> void:
	var s := _s()
	var did := s.detachments.spawn({&"player": 1, &"plot": P(12, 5), &"band": _rules().band_caravan})
	var own: Dictionary = {}
	for x: Dictionary in OverworldVision.observe(s, 1)["detachments"]:
		if x["id"] == did:
			own = x
	assert_eq(own["band"], "band_caravan")
	assert_eq(own["sight"]["value"], 3)
	assert_eq(own["movement"]["value"], 40)
	var seen: Dictionary = {}
	for x: Dictionary in OverworldVision.observe(s, 2)["detachments"]:
		if x["id"] == did:
			seen = x
	assert_false(seen.is_empty(), "player 2 sees it")
	assert_eq(seen["band"], "band_caravan", "enemies see the kind")
	assert_false(seen.has("sight"), "not the stats")
	assert_false(seen.has("movement"))
