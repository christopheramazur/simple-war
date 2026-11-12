extends GutTest
## Battleforces: caps, auto-fill strongest-until-cap, archetype and player
## presets, hand-picked squads, deploying on engagement (GDD 02 §2.3, R2Q1).
## Task sw-o1m.2.2. test_vale caps a battleforce at 3 squads and 250
## strength; a rifle squad is worth 100 (8 units), a scout team 80 (4).
## field_commander: own rifle squad + 2 rifle squads.

const W := 16

static var _loader: PackageLoader
static var _rules_cache: OverworldRules


func _rules() -> OverworldRules:
	if _rules_cache == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = OverworldRules.compile(_loader.templates, "test_vale", _loader.data_hash)
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


func _of(events: Array[SimEvent], type: StringName) -> Array:
	return events.filter(func(e: SimEvent) -> bool: return e.type == type)


## A field commander with [own, rifle, rifle, scouts] at (4,8).
func _army(s: OverworldState) -> Array:
	var a := Commanders.spawn(s, 1, "field_commander", P(4, 8))
	OverworldArmies.add(s, a, _rules().squad_index("scout_team"))
	var ids := OverworldArmies.of(s, a)
	return [a, ids[0], ids[1], ids[2], ids[3]]


func test_rules_compile() -> void:
	var r := _rules()
	assert_eq([r.bf_cap_squads, r.bf_cap_value], [3, 250])
	assert_true(r.preset_ids.has("preset_recon"))
	assert_true(r.sq_tags[r.squad_index("scout_team")].has("scout"), "legend archetype is a squad feature")


func test_strongest_until_the_cap() -> void:
	var s := _s()
	var x := _army(s)
	var a: int = x[0]
	assert_eq(OverworldBattleforce.pick(s, a), PackedInt64Array([x[1], x[2]]),
		"own 100 + rifles 100 = 200; another 100 or the scouts' 80 would pass 250")
	s.squads.set_value(x[2], &"alive", 4)
	assert_eq(OverworldBattleforce.strength(s, s.squads.row_of(x[2])), 50)
	assert_eq(OverworldBattleforce.pick(s, a), PackedInt64Array([x[1], x[3], x[2]]),
		"the full rifles first, then the weakened ones still fit (250)")
	s.squads.set_value(x[3], &"alive", 0)
	assert_false(OverworldBattleforce.pick(s, a).has(x[3]), "a wiped-out squad never fights")


func test_archetype_presets() -> void:
	var s := _s()
	var x := _army(s)
	var a: int = x[0]
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "preset_recon", PackedInt64Array(), true), "")
	assert_eq(OverworldBattleforce.pick(s, a), PackedInt64Array([x[1], x[4]]), "scouts first: 180, a rifle squad would pass 250")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "preset_assault", PackedInt64Array(), false), "")
	assert_eq(OverworldBattleforce.pick(s, a), PackedInt64Array([x[2], x[3]]), "no scouts, own squad stays out")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "nonsense", PackedInt64Array(), true), "unknown preset 'nonsense'")


func test_player_presets_and_hand_picks() -> void:
	var s := _s()
	var x := _army(s)
	var a: int = x[0]
	assert_eq(OverworldBattleforce.save_preset(s, 1, "preset_recon", PackedStringArray(), PackedStringArray(["scout"])), "")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "preset_recon", PackedInt64Array(), true), "")
	assert_false(OverworldBattleforce.pick(s, a).has(x[4]), "the player's own preset wins the name")
	assert_eq(OverworldBattleforce.set_plan(s, 2, a, "", PackedInt64Array(), true), "not your commander")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "", PackedInt64Array([x[1]]), true), "the commander's own squad is set by 'lead'")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "", PackedInt64Array([x[2], x[3]]), true),
		"the battleforce cap is 250 strength, these have 300")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "", PackedInt64Array([x[4], x[4]]), true), "squad 2 is listed twice")
	assert_eq(OverworldBattleforce.set_plan(s, 1, a, "", PackedInt64Array([x[4]]), true), "")
	assert_eq(OverworldBattleforce.pick(s, a), PackedInt64Array([x[1], x[4]]))
	OverworldTurn.resolve(s)
	assert_eq(OverworldBattleforce.pick(s, a), PackedInt64Array([x[1], x[4]]), "plans persist across turns")


func test_deployed_on_engagement_and_released() -> void:
	var s := _s()
	var a := Commanders.spawn(s, 1, "field_commander", P(12, 4))
	var want := OverworldBattleforce.pick(s, a)
	OverworldOrders.set_route(s, 1, a, PackedInt64Array([P(11, 3)]))
	var ev := OverworldTurn.resolve(s)
	var eid := s.engagement_at(P(11, 3))
	assert_ne(eid, -1)
	assert_eq(OverworldBattleforce.deployed_in(s, eid), want)
	assert_eq(OverworldBattleforce.of(s, a), want)
	var dep: Array = _of(ev, &"battleforce_deployed")
	assert_eq(dep.size(), 1)
	assert_eq(dep[0].data["squads"], want)
	assert_eq(_of(OverworldVision.filter_events(s, 2, ev), &"battleforce_deployed").size(), 0, "hidden from the enemy")
	var obs := OverworldVision.observe(s, 1)
	var me: Dictionary = (obs["commanders"] as Array).filter(func(c: Dictionary) -> bool: return c["id"] == a)[0]
	assert_eq(me["battleforce"], want)
	OverworldMovement.end_engagement(s, eid)
	assert_true(OverworldBattleforce.deployed_in(s, eid).is_empty())
	assert_eq(OverworldBattleforce.pick(s, a), want)


func test_session_logs_battleforce_inputs() -> void:
	var l := _loader
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var fc: int = (s.observe(1)["commanders"] as Array).filter(func(c: Dictionary) -> bool: return c["player"] == 1)[0]["id"]
	assert_eq(s.save_preset(1, "mine", PackedStringArray(["scout"])), "")
	assert_eq(s.set_battleforce(1, fc, "mine", PackedInt64Array(), false), "")
	assert_eq(s.observe(1)["presets"].keys(), ["mine"])
	s.ready(1)
	s.ready(2)
	var r := OverworldSession.rebuild(s.save(), l.templates, l.data_hash)
	assert_not_null(r, OverworldSession.last_error)
	assert_eq(r.state.state_hash_hex(), s.state.state_hash_hex())
	assert_eq(r.state.battleforces[fc]["preset"], "mine")
