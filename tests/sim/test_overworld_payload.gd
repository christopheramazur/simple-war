extends GutTest
## Band payload (sw-63wt.3, U1Q27): squads and equipped items add their
## overworld stats to the band they are in, capped by the band kind's caps.
## The caravan's payload_stats is ["sight"] with a cap of 2; the garrison
## lists none, so it is unaffected. test_vale (fixture): scout_team and
## marksman_team carry overworld sight 1 (core too); scout_glass (fixture
## item) carries sight 1 per copy.

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


## A caravan of player 1 at p, with no squads yet.
func _caravan(s: OverworldState, p: int) -> int:
	return s.detachments.spawn({&"player": 1, &"plot": p, &"band": _rules().band_caravan})


## Puts a squad of template `tmpl` into detachment did. Returns its ID.
func _squad(s: OverworldState, did: int, tmpl: String) -> int:
	var t := _rules().squad_ids.find(tmpl)
	var size := _rules().sq_size[t]
	return s.squads.spawn({&"detachment": did, &"tmpl": t, &"alive": size, &"size": size})


func _sight(s: OverworldState, did: int) -> Dictionary:
	return OverworldStats.sight(s, OverworldStats.BAND, did)


func _term(source: String, name: String, amount: int) -> Dictionary:
	return {"source": source, "name": name, "amount": amount, "payload": true}


func _base_term() -> Dictionary:
	return {"source": "band_caravan", "name": "Caravan", "amount": 3}


func test_core_squads_and_items_compile_their_overworld_stats() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := OverworldRules.compile(l.templates, "test_vale", l.data_hash)
	assert_true(r.is_valid(), str(r.errors))
	var si := OverworldRules.BAND_STATS.find("sight")
	assert_eq(r.sq_ow[r.squad_ids.find("scout_team")][si], 1)
	assert_eq(r.sq_ow[r.squad_ids.find("marksman_team")][si], 1)
	assert_eq(r.sq_ow[r.squad_ids.find("rifle_squad")][si], 0, "squads without the field add nothing")


func test_zero_scouts_keeps_the_caravans_base_sight() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	_squad(s, did, "rifle_squad")
	var sight := _sight(s, did)
	assert_eq(sight["value"], 3)
	assert_eq(sight["terms"], [_base_term()])


func test_one_scout_adds_one_sight() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	_squad(s, did, "scout_team")
	var sight := _sight(s, did)
	assert_eq(sight["value"], 4)
	assert_eq(sight["terms"], [_base_term(), _term("scout_team", "Scout team", 1)])


func test_three_scouts_are_capped_at_two() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	for _i in 3:
		_squad(s, did, "scout_team")
	assert_eq(_sight(s, did)["value"], 5, "3 + the cap of 2")
	var p := OverworldStats.payload(s, s.detachments.row_of(did), _rules().band_caravan, "sight")
	assert_eq(p["value"], 2)
	assert_eq((p["terms"] as Array).size(), 3, "the terms still show every scout")


func test_a_garrison_is_unaffected_by_scouts() -> void:
	var s := _s()
	var did := s.detachments.spawn({&"player": 1, &"plot": P(8, 10), &"band": _rules().band_garrison})
	for _i in 3:
		_squad(s, did, "scout_team")
	var sight := _sight(s, did)
	assert_eq(sight["value"], 1)
	assert_eq(sight["terms"], [{"source": "band_garrison", "name": "Garrison", "amount": 1}])


func test_an_equipped_item_adds_its_sight() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	var sid := _squad(s, did, "rifle_squad")
	WarChest.add(s, _rules().item_ids.find("scout_glass"), 1, -1, -1, sid)
	var sight := _sight(s, did)
	assert_eq(sight["value"], 4)
	assert_eq(sight["terms"], [_base_term(), _term("scout_glass", "Scout glass", 1)])


func test_each_equipped_copy_counts_and_the_cap_holds() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	var sid := _squad(s, did, "rifle_squad")
	WarChest.add(s, _rules().item_ids.find("scout_glass"), 2, -1, -1, sid)
	_squad(s, did, "scout_team")
	assert_eq(_sight(s, did)["value"], 5, "2 glasses + 1 scout = 3, capped at 2")


func test_terms_follow_squad_id_order() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	var sid := _squad(s, did, "rifle_squad")
	WarChest.add(s, _rules().item_ids.find("scout_glass"), 1, -1, -1, sid)
	_squad(s, did, "scout_team")
	var sources: Array = []
	for t: Dictionary in _sight(s, did)["terms"]:
		sources.append(t["source"])
	assert_eq(sources, ["band_caravan", "scout_glass", "scout_team"])


func test_leaving_the_band_drops_its_payload() -> void:
	var s := _s()
	var did := _caravan(s, P(8, 10))
	var sid := _squad(s, did, "scout_team")
	assert_eq(_sight(s, did)["value"], 4)
	s.squads.set_value(sid, &"detachment", -1)
	assert_eq(_sight(s, did)["value"], 3)


func test_vision_uses_the_payload() -> void:
	var s := _s()
	var at := P(8, 10)
	var did := _caravan(s, at)
	_squad(s, did, "scout_team")
	var mask := OverworldVision.sight(s, 1)
	var radius_4 := Hex.within(at, 4, W, _rules().height)
	for q in radius_4:
		assert_eq(mask[q], 1, "a caravan with a scout sees %d" % q)


func test_enemy_observation_does_not_reveal_the_terms() -> void:
	var s := _s()
	var at := P(12, 5)
	var did := _caravan(s, at)
	_squad(s, did, "scout_team")
	var sid := _squad(s, did, "rifle_squad")
	WarChest.add(s, _rules().item_ids.find("scout_glass"), 1, -1, -1, sid)
	Commanders.spawn(s, 2, "field_commander", at)
	var seen: Dictionary = {}
	for x: Dictionary in OverworldVision.observe(s, 2)["detachments"]:
		if x["id"] == did:
			seen = x
	assert_false(seen.is_empty(), "player 2 sees the caravan")
	assert_false(seen.has("sight"), "no sight, so no terms")
	assert_false(seen.has("squads"), "no squads")
	assert_false(seen.has("items"), "no equipped items")
	assert_false(str(seen).contains("scout"), "nothing names the scouts or the glass")
	var own: Dictionary = {}
	for x: Dictionary in OverworldVision.observe(s, 1)["detachments"]:
		if x["id"] == did:
			own = x
	assert_eq(own["sight"]["value"], 5, "the owner sees the terms")
	assert_eq((own["sight"]["terms"] as Array).size(), 3)


func test_the_band_card_lists_the_terms() -> void:
	var sight := {"value": 4, "terms": [_base_term(), _term("scout_team", "Scout team", 1)]}
	assert_eq(CommandPanel.sight_text(sight), "Sight 4 (caravan 3, scout team +1).")
	assert_eq(CommandPanel.sight_text({"value": 1, "terms": [{"source": "band_garrison", "name": "Garrison", "amount": 1}]}),
		"Sight 1 (garrison 1).")
