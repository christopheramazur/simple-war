extends GutTest
## The War Chest: items, equipping valid units, pickups, trading, item
## production and seizure (GDD 02 §2.9, R3Q7, R4Q10, R7Q9). Task sw-o1m.2.6.
## test_vale: an arms cache at (13,10) holds 2 light machine guns and 4
## carapace plates; the barracks (8,7) makes 2 carapace plates every 2
## turns for 1 Value as its third option; bandit camp (11,3) is guarded.
## A rifle squad is a sergeant and 7 troopers.

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_rules_cache = OverworldRules.compile(_l().templates, "test_vale", _l().data_hash)
	return _rules_cache


func _s() -> OverworldState:
	var s := OverworldState.create(1, _rules(), 7)
	var cache := _rules().feature_index("hex_supply_cache")
	for id in s.features.ids():
		if s.features.get_value(id, &"tmpl") == cache:
			s.remove_feature(id)
	return s


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _it(id: String) -> int:
	return _rules().item_index(id)


func _of(events: Array, type: StringName) -> Array:
	return events.filter(func(e: Variant) -> bool:
		return (e.type if e is SimEvent else StringName(e["type"])) == type)


## A field commander's first non-own squad (a rifle squad).
func _rifles(s: OverworldState, cid: int) -> int:
	return OverworldArmies.of(s, cid)[1]


func test_items_compile() -> void:
	var r := _rules()
	assert_true(r.is_valid(), "; ".join(r.errors))
	assert_eq(r.it_slot[_it("lmg_kit")], OverworldRules.SLOT_WEAPON)
	assert_eq(r.it_slot[_it("carapace_plates")], OverworldRules.SLOT_DEFENSE)
	assert_eq(r.it_slot[_it("camo_netting")], OverworldRules.SLOT_KIT)
	assert_eq(r.production_count(r.feature_index("hex_barracks")), 3)
	assert_eq(r.sq_member_keys[r.squad_index("rifle_squad")].size(), 8)


func test_a_cache_is_picked_up() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(13, 9))
	OverworldOrders.set_route(s, 1, c, PackedInt64Array([P(13, 10)]))
	var ev := OverworldTurn.resolve(s)
	var got := _of(ev, &"items_picked")
	assert_eq(got.size(), 1)
	assert_eq(WarChest.count_of(s, _it("lmg_kit"), c, -1, -1), 2)
	assert_eq(WarChest.count_of(s, _it("carapace_plates"), c, -1, -1), 4)
	assert_eq(s.feature_row(P(13, 10), _rules().feature_index("hex_arms_cache")), -1, "the cache is gone")


func test_equipping_valid_units() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	var sid := _rifles(s, c)
	var plates := WarChest.add(s, _it("carapace_plates"), 10, c, -1, -1)
	assert_eq(WarChest.room_for(s, _it("carapace_plates"), sid), 8, "one per unit")
	assert_eq(WarChest.equip(s, 2, c, plates, sid, 1), "not your commander")
	assert_eq(WarChest.equip(s, 1, c, plates, sid, 9), "only 8 more units can carry it")
	assert_eq(WarChest.equip(s, 1, c, plates, sid, 5), "")
	assert_eq(WarChest.equip(s, 1, c, plates, sid, 3), "")
	assert_eq(WarChest.count_of(s, _it("carapace_plates"), -1, -1, sid), 8, "merged into one stack")
	assert_eq(WarChest.count_of(s, _it("carapace_plates"), c, -1, -1), 2)
	assert_eq(WarChest.room_for(s, _it("carapace_plates"), sid), 0)
	assert_eq(WarChest.room_for(s, _it("camo_netting"), sid), 8, "kits fill another slot")
	var lmgs := WarChest.add(s, _it("lmg_kit"), 8, c, -1, -1)
	assert_eq(WarChest.equip(s, 1, c, lmgs, sid, 8), "")
	var rifles := WarChest.add(s, _it("marksman_rifle_kit"), 1, c, -1, -1)
	assert_eq(WarChest.equip(s, 1, c, rifles, sid, 1), "no unit in that squad can carry it")
	var other := Commanders.spawn(s, 1, "field_commander", P(5, 5))
	assert_eq(WarChest.equip(s, 1, c, rifles, _rifles(s, other), 1), "not in this commander's army")
	var worn := WarChest.on_squad(s, sid)
	assert_eq(worn.size(), 2)
	assert_eq(WarChest.unequip(s, 1, c, worn[0], 2), "")
	var view: Array = OverworldArmies.view(s, c)[1]["items"]
	assert_eq(view.size(), 2, "the equipped tab lists what the squad carries")
	var chest := WarChest.chest_view(s, c)
	assert_gt(chest.size(), 0)
	assert_true(chest[0].has("squads"))


func test_gear_reaches_the_battle() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	var sid := _rifles(s, c)
	WarChest.equip(s, 1, c, WarChest.add(s, _it("lmg_kit"), 2, c, -1, -1), sid, 2)
	WarChest.equip(s, 1, c, WarChest.add(s, _it("carapace_plates"), 3, c, -1, -1), sid, 3)
	OverworldOrders.set_route(s, 1, c, PackedInt64Array([P(11, 3)]))
	OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	var errs := PackedStringArray()
	var b := OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 5, errs)
	assert_not_null(b, "; ".join(errs))
	var bid := -1
	for k: int in b.links:
		if b.links[k] == sid:
			bid = k
	assert_ne(bid, -1, "the squad is in the battle")
	var br := b.rules
	var u := b.state.units
	var lmg := 0
	var carapace := 0
	for row in u.count():
		if u.squad[row] == bid:
			lmg += 1 if u.weapon[row] == br.weapon_index["lmg"] else 0
			carapace += 1 if u.defense[row] == br.defense_index["carapace"] else 0
	assert_eq(lmg, 2)
	assert_eq(carapace, 3)
	assert_eq(b.state.squads.get_value(bid, &"reach"), br.wp_range[br.weapon_index["lmg"]], "reach follows its gear")


func test_casualties_keep_items_and_destroyed_squads_are_scavenged() -> void:
	var s := _s()
	var c := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	var sid := _rifles(s, c)
	WarChest.equip(s, 1, c, WarChest.add(s, _it("lmg_kit"), 3, c, -1, -1), sid, 3)
	var g := WarChest.gear(s, sid, 2)
	assert_eq(g.size(), 2)
	assert_eq(g[0]["weapon"], "lmg")
	assert_eq(g[1]["weapon"], "lmg")
	assert_eq(WarChest.count_of(s, _it("lmg_kit"), -1, -1, sid), 3, "a refit squad carries them again")
	WarChest.scavenge(s, sid)
	s.squads.despawn(sid)
	assert_eq(WarChest.count_of(s, _it("lmg_kit"), c, -1, -1), 3, "survivors pick them up")


func test_trading_and_taking() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	var b := Commanders.spawn(s, 1, "field_commander", P(0, 0))
	var far := Commanders.spawn(s, 1, "field_commander", P(5, 5))
	var lmgs := WarChest.add(s, _it("lmg_kit"), 3, a, -1, -1)
	assert_eq(WarChest.give(s, 1, a, lmgs, 1, far), "the commanders must share a hex")
	assert_eq(WarChest.give(s, 1, a, lmgs, 1, b), "")
	assert_eq(WarChest.count_of(s, _it("lmg_kit"), b, -1, -1), 1)
	assert_eq(WarChest.count_of(s, _it("lmg_kit"), a, -1, -1), 2)
	var did := s.detachments.spawn({&"player": 1, &"plot": P(0, 0)})
	assert_eq(WarChest.take(s, 1, b, did), "its War Chest is empty")
	WarChest.add(s, _it("camo_netting"), 4, -1, did, -1)
	assert_eq(WarChest.take(s, 2, b, did), "not your commander")
	assert_eq(WarChest.take(s, 1, b, did), "")
	assert_eq(WarChest.count_of(s, _it("camo_netting"), b, -1, -1), 4)
	assert_false(s.detachments.is_alive(did), "an empty detachment is disbanded")


func test_item_production_and_seizure() -> void:
	var s := _s()
	var row := s.feature_row(P(8, 7), _rules().feature_index("hex_barracks"))
	var fid := s.features.id_at(row)
	s.features.set_value(fid, &"owner", 1)
	s.add_value(1, 20, &"test")
	assert_eq(Convoys.set_output(s, 1, fid, 2), "")
	var ev := []
	for i in 2:
		ev.append_array(OverworldTurn.resolve(s))
	assert_eq(_of(ev, &"item_produced").size(), 1)
	var dets := Detachments.at(s, P(8, 7))
	assert_eq(dets.size(), 1)
	assert_eq(WarChest.count_of(s, _it("carapace_plates"), -1, dets[0], -1), 2)
	var b := Commanders.spawn(s, 2, "field_commander", P(9, 7))
	OverworldOrders.set_route(s, 2, b, PackedInt64Array([P(8, 7)]))
	ev = OverworldTurn.resolve(s)
	assert_eq(_of(ev, &"items_seized").size(), 1, "a chest without squads cannot fight")
	assert_eq(s.engagement_at(P(8, 7)), -1)
	assert_eq(WarChest.count_of(s, _it("carapace_plates"), b, -1, -1), 2)
	assert_false(s.detachments.is_alive(dets[0]))


func test_items_travel_by_convoy() -> void:
	var s := _s()
	var row := s.feature_row(P(8, 7), _rules().feature_index("hex_barracks"))
	var fid := s.features.id_at(row)
	s.features.set_value(fid, &"owner", 1)
	s.add_value(1, 20, &"test")
	var a := Commanders.spawn(s, 1, "field_commander", P(8, 4))
	Convoys.set_output(s, 1, fid, 2)
	assert_eq(Convoys.set_line(s, 1, fid, -1, a), "")
	var ev := []
	for i in 3:
		ev.append_array(OverworldTurn.resolve(s))
	assert_eq(_of(ev, &"convoy_delivered").size(), 1)
	assert_eq(WarChest.count_of(s, _it("carapace_plates"), a, -1, -1), 2)
	assert_eq(s.detachments.count(), 0)


func test_session_and_fog() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var s := x.state
	var c := -1
	for id in s.commanders.ids():
		if s.commanders.get_value(id, &"player") == 1 and s.commanders.get_value(id, &"tmpl") == _rules().commander_index("field_commander"):
			c = id
	var plates := WarChest.add(s, _it("carapace_plates"), 4, c, -1, -1)
	assert_eq(x.equip(1, c, plates, _rifles(s, c), 2), "")
	var worn := WarChest.on_squad(s, _rifles(s, c))
	assert_eq(x.unequip(1, c, worn[0], 1), "")
	var o := x.observe(1)
	for d: Dictionary in o["commanders"]:
		if d["id"] == c:
			assert_eq((d["chest"] as Array).size(), 1)
	x.ready(1)
	x.ready(2)
	var loaded := OverworldSession.load_save(x.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	assert_eq(loaded.state_hash_hex(), x.state_hash_hex())
	var kinds := x.input_log.map(func(i: Dictionary) -> String: return i["kind"])
	assert_true(kinds.has("equip") and kinds.has("unequip"))
