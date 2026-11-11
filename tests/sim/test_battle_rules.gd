extends GutTest
## Focused rule checks: damage order, SIMPL governor, zones, concealment,
## reactions. Tasks sw-eo8.3-6, sw-1jy.1-2.

const ONE := Fixed.ONE

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


## An empty battle (no deployment) to place squads by hand.
func _empty() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _unit_of(s: BattleState, sid: int, nth: int = 0) -> int:
	return Centroids.units_of(s, s.squads.row_of(sid))[nth]


func test_damage_order_on_carapace() -> void:
	var s := _empty()
	var sid := _place(s, 1, "chi_operatives", 20, 20)
	var u := _unit_of(s, sid, 1)
	var res := DamagePipeline.apply(s, u, 10 * ONE, 0, 0)
	# 10 kinetic: resist 10% -> 9, flat 1 -> 8, 10% -> 7.2 (fixed-point, E3Q1).
	assert_eq(res["resisted"], ONE)
	assert_eq(res["flat"], ONE)
	assert_eq(res["percent"], Fixed.round_div(8 * ONE * 10, 100))
	assert_eq(Fixed.to_display(res["to_hp"]), "7.2")
	var steps := []
	for t: Array in res["terms"]:
		steps.append(t[0])
	assert_eq(steps, ["incoming", "resistance", "flat", "percentage", "hit_points"])


func test_floor_and_block_accumulator() -> void:
	var s := _empty()
	var sid := _place(s, 1, "chi_operatives", 20, 20)
	var u := _unit_of(s, sid, 1)
	var res := DamagePipeline.apply(s, u, ONE, 0, 0)
	assert_eq(res["floored"], ONE, "flat would zero it; kinetic floor is 1")
	assert_eq(res["to_hp"], ONE)
	# Block chance 10%: exactly the 10th hit is blocked.
	var blocked_on := -1
	for i in range(2, 12):
		s.units.set_value(s.units.id_at(u), &"hp", 100 * ONE)
		if DamagePipeline.apply(s, u, 4 * ONE, 0, 0)["blocked"] > 0:
			blocked_on = i
			break
	assert_eq(blocked_on, 10)


func test_cover_evasion_every_nth() -> void:
	var s := _empty()
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var u := _unit_of(s, sid, 1)
	var pattern := []
	for _i in 4:
		pattern.append(DamagePipeline.apply(s, u, ONE, 0, 25)["evaded"])
	assert_eq(pattern, [false, false, false, true], "flak 5% + cover 25% = every 4th (30,60,90,120)")


func test_pool_flow_clamps_records_and_surges() -> void:
	var s := _empty()
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var row := s.squads.row_of(sid)
	var applied := Pools.flow(s, row, BattleSquads.PROWESS, 1000 * ONE, &"test")
	assert_eq(Pools.value(s, row, BattleSquads.PROWESS), Pools.capacity(s, row, BattleSquads.PROWESS))
	assert_eq(s.ledger["%d|%d|test" % [sid, BattleSquads.PROWESS]], applied)
	assert_eq(s.events.of_type(&"pool_surge").size(), 1)


func test_morale_pays_deficits_weighted() -> void:
	var s := _empty()
	var sid := _place(s, 1, "rifle_squad", 20, 20)
	var row := s.squads.row_of(sid)
	Pools.flow(s, row, BattleSquads.STAMINA, -40 * ONE, &"test")
	var morale_before := Pools.value(s, row, BattleSquads.MORALE)
	var stamina_before := Pools.value(s, row, BattleSquads.STAMINA)
	s.tick = 0
	PoolsSystem.new().run(s)
	assert_gt(Pools.value(s, row, BattleSquads.STAMINA), stamina_before)
	assert_lt(Pools.value(s, row, BattleSquads.MORALE), morale_before + s.rules.morale_gen)
	assert_true(s.ledger.has("%d|%d|morale_pay" % [sid, BattleSquads.STAMINA]))
	assert_false(s.ledger.has("%d|%d|morale_pay" % [sid, BattleSquads.LEGEND]), "Legend is not governed")


func test_zone_capture_buffer_and_contest() -> void:
	var s := _empty()
	var r := _rules()
	var z := Array(r.zone_ids).find("centre")
	var zx := Fixed.to_int_round(r.zn_x[z])
	var zy := Fixed.to_int_round(r.zn_y[z])
	var first := _place(s, 1, "rifle_squad", zx, zy)
	TurnResolution.resolve_zones(s)
	assert_eq(s.zone_owner[z], 1)
	assert_eq(s.zone_amount[z], 10, "CR 10 reaches threshold 10")
	assert_eq(s.influence[1], r.zn_vp[z], "scores the turn it captures")
	TurnResolution.resolve_zones(s)
	assert_eq(s.zone_amount[z], 10, "a lone CR 10 squad against decay 10 holds at the threshold")
	var second := _place(s, 1, "rifle_squad", zx, zy)
	TurnResolution.resolve_zones(s)
	TurnResolution.resolve_zones(s)
	assert_eq(s.zone_amount[z], 20, "surplus CR fills the buffer, capped at threshold + buffer")
	# Both leave; one enemy squad arrives.
	for sid in [first, second]:
		s.squads.set_value(sid, &"cx", 0)
	_place(s, 2, "rifle_squad", zx, zy)
	for sid in [first, second]:
		s.squads.set_value(sid, &"cx", 0)
	TurnResolution.resolve_zones(s)
	assert_eq(s.zone_owner[z], 0, "20 - 10 vacuum - 10 push: neutral again")
	TurnResolution.resolve_zones(s)
	assert_eq(s.zone_owner[z], 2, "then captured by the newcomer")


func test_camo_shrinks_sight_and_detection_reveals() -> void:
	var s := _empty()
	# Marksman team (field camo, on by default) on open ground.
	var hidden := _place(s, 1, "marksman_team", 20, 75)
	var far_rifle := _place(s, 2, "rifle_squad", 20, 37)
	var vis := VisionSystem.new()
	vis.run(s)
	var hrow := s.squads.row_of(hidden)
	assert_eq(vis.concealment_pct(s, hrow), 20)
	assert_eq(s.squads.seen_by[hrow] & BattleSquads.bit(2), 0, "38 away: beyond 45 * 80% = 36")
	assert_ne(s.squads.seen_by[s.squads.row_of(far_rifle)] & BattleSquads.bit(1), 0, "marksmen see the rifles")
	s.squads.set_value(hidden, &"conceal_on", 0)
	vis.run(s)
	assert_ne(s.squads.seen_by[hrow] & BattleSquads.bit(2), 0, "without camo, plain sight spots them")
	s.squads.set_value(hidden, &"conceal_on", 1)
	vis.run(s)
	assert_eq(s.squads.seen_by[hrow] & BattleSquads.bit(2), 0)
	var scout := _place(s, 2, "scout_team", 20, 50)
	var srow := s.squads.row_of(scout)
	# At 90% concealment plain sight reaches 55 * 10% = 5.5; auspex reaches 30.
	assert_true(vis._sees(s, srow, hrow, 90), "auspex detects within its 30 radius")
	s.squads.set_value(scout, &"detect_on", 0)
	assert_false(vis._sees(s, srow, hrow, 90), "detection off: plain sight only")


func test_paid_ability_auto_off_at_broken() -> void:
	var s := _empty()
	var sid := _place(s, 1, "scout_team", 20, 20)
	var row := s.squads.row_of(sid)
	BattleOrders.apply(s, 1, [{"squad": sid, "type": "hold", "concealment": true}])
	assert_eq(s.squads.conceal_on[row], 1)
	Pools.flow(s, row, BattleSquads.INSTINCT, -1000 * ONE, &"test")
	VisionSystem.new().run(s)
	assert_eq(s.squads.conceal_on[s.squads.row_of(sid)], 0)
	assert_eq(s.events.of_type(&"ability_auto_off").size(), 1)


func test_reaction_triggers_on_contact() -> void:
	var s := _empty()
	var sim := BattleSim.new()
	var a := _place(s, 1, "rifle_squad", 60, 50)
	var b := _place(s, 2, "rifle_squad", 140, 50)
	BattleOrders.apply(s, 1, [{"squad": a, "type": "move", "x": 140 * ONE, "y": 50 * ONE}])
	BattleOrders.apply(s, 2, [{"squad": b, "type": "move", "x": 60 * ONE, "y": 50 * ONE}])
	var opportunities := Reactions.forecast(s, sim)
	var mine := opportunities.filter(func(o: Dictionary) -> bool: return o["player"] == 2)
	assert_gt(mine.size(), 0, "contact forecast")
	assert_true("fall_back" in mine[0]["reactions"])
	assert_eq(s.tick, 0, "forecast ran on a copy")
	assert_eq(Reactions.queue(s, b, "fall_back", a), "")
	sim.execute_turn(s)
	var triggered := 0
	for e in s.turn_log:
		if e.type == &"reaction_triggered":
			triggered += 1
	assert_eq(triggered, 1)
	assert_true(s.ledger.has("%d|%d|reacted_to" % [a, BattleSquads.PROWESS]), "provoker floats Prowess")
	assert_true(s.ledger.has("%d|%d|reaction" % [b, BattleSquads.INSTINCT]), "reactor pays Instinct")


func test_vacuum_only_at_or_above_threshold() -> void:
	# The designer's example: CR 10 contested by CR 1 nets 9 a turn.
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	r.sq_cr[r.squad_index("heavy_weapons_team")] = 1
	var s := BattleState.new(1, r, 1)
	var z := Array(r.zone_ids).find("centre")
	for p in [[1, "rifle_squad"], [2, "heavy_weapons_team"]]:
		BattleSetup.spawn_squad(s, p[0], r.squad_index(p[1]), r.zn_x[z], r.zn_y[z], 0)
	Centroids.update(s)
	var amounts := []
	for _t in 5:
		TurnResolution.resolve_zones(s)
		amounts.append(s.zone_amount[z])
	assert_eq(amounts, [9, 18, 17, 16, 15])
	assert_eq(s.zone_owner[z], 1)
