extends GutTest
## SquadRelation (sw-bafi.3, U1 C3): pair facts from the sim's own functions,
## one test per kind on a multi-squad fixture, plus the fog rules (hidden
## enemies give [], enemy facts are behaviour only), dead / self pairs and
## read-only-ness.

const ONE := Fixed.ONE

static var _loader: PackageLoader
static var _rules_cache: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## An open 200 x 100 field (no terrain, no zones) on duel_crossroads' sides.
func _rules() -> BattleRules:
	if _rules_cache == null:
		var defs := _l().defs.duplicate()
		defs.append({"id": "open_m", "kind": "battle_map", "values": {"width": 200, "height": 100, "base": "open", "cells": []}})
		var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
		sc["map"] = "open_m"
		sc["zones"] = []
		defs.append({"id": "open_t", "kind": "scenario", "values": sc})
		_rules_cache = BattleRules.compile(TemplateTable.build(defs), "open_t")
		assert_eq(_rules_cache.errors, PackedStringArray())
	return _rules_cache


func _empty() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	return ScenarioBuilder.place(s, player, squad, x * ONE, y * ONE)


func _row(s: BattleState, sid: int) -> int:
	return s.squads.row_of(sid)


## Lets `player` see squad `sid` (seen_by is the side's fog).
func _see(s: BattleState, sid: int, player: int) -> void:
	s.squads.seen_by[_row(s, sid)] |= BattleSquads.bit(player)


## The multi-squad fixture: own rifles A (50, 50) and mortar M (50, 85)
## against enemy rifles B (80, 50), 30 m from A, and far rifles C (160, 50).
## Everyone sees A, M and B; C is unseen by player 1.
func _fixture() -> Dictionary:
	var s := _empty()
	var f := {"s": s,
		"a": _place(s, 1, "rifle_squad", 50, 50),
		"m": _place(s, 1, "mortar_team", 50, 85),
		"b": _place(s, 2, "rifle_squad", 80, 50),
		"c": _place(s, 2, "rifle_squad", 160, 50)}
	for k in ["a", "m", "b"]:
		_see(s, f[k], 1)
		_see(s, f[k], 2)
	_see(s, f["c"], 2)
	return f


## The facts of `kind` about `from` (to the other squad of the pair).
func _of(facts: Array, kind: String, from: int) -> Array:
	return facts.filter(func(d: Dictionary) -> bool: return d["kind"] == kind and d["from"] == from)


func _one(facts: Array, kind: String, from: int) -> Dictionary:
	var hits := _of(facts, kind, from)
	assert_eq(hits.size(), 1, "one %s fact about %d" % [kind, from])
	return hits[0] if hits.size() == 1 else {}


func test_fact_shape() -> void:
	var f := _fixture()
	var facts := SquadRelation.facts(f["s"], 1, f["a"], f["b"])
	assert_gt(facts.size(), 0)
	for d: Dictionary in facts:
		for k in ["kind", "value", "from", "to", "rule", "data"]:
			assert_true(d.has(k), "fact has " + k)
		assert_true([f["a"], f["b"]].has(d["from"]))
		assert_ne(d["from"], d["to"])


func test_self_dead_and_unknown_give_nothing() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	assert_eq(SquadRelation.facts(s, 0, f["a"], f["a"]), [])
	assert_eq(SquadRelation.facts(s, 0, f["a"], 9999), [])
	s.squads.destroyed[_row(s, f["b"])] = 1
	assert_eq(SquadRelation.facts(s, 0, f["a"], f["b"]), [], "destroyed squad")
	assert_eq(SquadRelation.facts(s, 0, f["b"], f["a"]), [])
	s.squads.destroyed[_row(s, f["b"])] = 0
	s.squads.alive[_row(s, f["b"])] = 0
	assert_eq(SquadRelation.facts(s, 1, f["a"], f["b"]), [], "no living units")


func test_hidden_enemy_gives_nothing() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	assert_eq(SquadRelation.facts(s, 1, f["a"], f["c"]), [], "C is unseen by player 1")
	assert_eq(SquadRelation.facts(s, 1, f["c"], f["a"]), [])
	assert_gt(SquadRelation.facts(s, 0, f["a"], f["c"]).size(), 0, "viewer 0 sees all")
	assert_gt(SquadRelation.facts(s, 2, f["a"], f["c"]).size(), 0, "player 2 owns C and sees A")


func test_range_in_range_counts_units() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	var r := _one(SquadRelation.facts(s, 1, f["a"], f["b"]), "range", f["a"])
	assert_eq(r["value"], "in_range")
	assert_eq(r["data"]["armed"], 8)
	assert_eq(r["data"]["shot"], 8)
	assert_eq(r["data"]["share"], 1000)
	assert_eq(r["data"]["check"], LineOfFire.SHOT)
	assert_eq(r["rule"], SquadRelation.RULE_RANGE)


func test_range_out_of_range_with_gap_and_not_spotted() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	var r := _one(SquadRelation.facts(s, 0, f["a"], f["c"]), "range", f["a"])
	assert_eq(r["value"], "not_spotted", "player 1's side does not see C")
	_see(s, f["c"], 1)
	r = _one(SquadRelation.facts(s, 1, f["a"], f["c"]), "range", f["a"])
	assert_eq(r["value"], "out_of_range")
	assert_gt(r["data"]["gap"], 30 * ONE, "about 110 m apart, 40 m rifles")
	assert_lt(r["data"]["gap"], 80 * ONE)


func test_range_min_range() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	ScenarioBuilder.move_squad(s, f["b"], 52 * ONE, 85 * ONE)
	Centroids.update(s)
	var r := _one(SquadRelation.facts(s, 1, f["m"], f["b"]), "range", f["m"])
	assert_eq(r["value"], "min_range", "mortar inside its 20 m minimum")
	assert_eq(r["data"]["min_range"], 3)


func test_enemy_range_is_public_reach_only() -> void:
	var f := _fixture()
	var r := _one(SquadRelation.facts(f["s"], 1, f["a"], f["b"]), "range", f["b"])
	assert_eq(r["value"], "in_range")
	assert_eq(r["data"].keys(), ["check", "gap"], "no per-unit shot counts for an enemy")


func test_sight_own_and_allies() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	assert_eq(_one(SquadRelation.facts(s, 1, f["a"], f["b"]), "sight", f["a"])["value"], "own")
	# The mortar (sight 40) is ~46 m from B: it sees B only through A.
	assert_eq(_one(SquadRelation.facts(s, 1, f["m"], f["b"]), "sight", f["m"])["value"], "allies")
	assert_eq(_one(SquadRelation.facts(s, 0, f["a"], f["c"]), "sight", f["a"])["value"], "unseen")
	assert_eq(_of(SquadRelation.facts(s, 1, f["a"], f["b"]), "sight", f["b"]), [], "what an enemy sees stays hidden")


func test_targeting_firing_then_aiming() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	BattleSim.new().runner.step(s)
	var arow := _row(s, f["a"])
	assert_eq(s.squads.engaged[arow], f["b"])
	assert_eq(_one(SquadRelation.facts(s, 1, f["a"], f["b"]), "targeting", f["a"])["value"], "firing")
	assert_eq(_one(SquadRelation.facts(s, 2, f["a"], f["b"]), "targeting", f["a"])["value"], "firing",
		"firing is behaviour the enemy sees")
	# Engaged but not firing: every unit is cooling down.
	s.squads.fired_tick[arow] = -1
	for urow in Centroids.units_of(s, arow):
		s.units.fired_tick[urow] = -1
		s.units.cooldown[urow] = 5
	var t := _one(SquadRelation.facts(s, 1, f["a"], f["b"]), "targeting", f["a"])
	assert_eq(t["value"], "aiming")
	assert_eq(t["data"]["hold"], BattleActivity.Hold.COOLDOWN)
	assert_eq(_of(SquadRelation.facts(s, 2, f["a"], f["b"]), "targeting", f["a"]), [],
		"an enemy's target before it fires stays hidden")


func test_ordered_attack() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	assert_eq(BattleOrders.apply(s, 1, [{"squad": f["a"], "type": "attack", "target": f["b"]}]).size(), 0)
	var o := _one(SquadRelation.facts(s, 1, f["a"], f["b"]), "ordered", f["a"])
	assert_eq(o["value"], "attack")
	assert_true(o["data"].has("closing"))
	assert_eq(_of(SquadRelation.facts(s, 2, f["a"], f["b"]), "ordered", f["a"]), [], "orders stay hidden")


func test_would_engage_is_likely_and_distinct_from_engaged() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	var facts := SquadRelation.facts(s, 1, f["a"], f["b"])
	var w := _one(facts, "would_engage", f["a"])
	assert_eq(w["value"], "likely")
	assert_eq(_of(facts, "targeting", f["a"]), [], "not engaged yet")
	assert_eq(_of(SquadRelation.facts(s, 2, f["a"], f["b"]), "would_engage", f["a"]), [])
	# Matches what the next tick engages.
	BattleSim.new().runner.step(s)
	assert_eq(s.squads.engaged[_row(s, f["a"])], f["b"])
	facts = SquadRelation.facts(s, 1, f["a"], f["b"])
	assert_eq(_of(facts, "would_engage", f["a"]), [], "engaged now: no would_engage")
	assert_eq(_of(facts, "targeting", f["a"]).size(), 1)


func test_under_fire_within_the_window() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	BattleSim.new().runner.step(s)
	var u := _one(SquadRelation.facts(s, 1, f["a"], f["b"]), "under_fire", f["a"])
	assert_eq(u["to"], f["b"], "A is under fire from B")
	assert_eq(u["data"]["ticks_ago"], 0)
	# Only the turn log remains (the squad stopped firing): still recent.
	s.squads.fired_tick[_row(s, f["b"])] = -1
	s.tick += 3
	assert_eq(_one(SquadRelation.facts(s, 1, f["a"], f["b"]), "under_fire", f["a"])["data"]["ticks_ago"], 3)
	s.tick += s.rules.recent_fire_ticks
	assert_eq(_of(SquadRelation.facts(s, 1, f["a"], f["b"]), "under_fire", f["a"]), [], "too long ago")


func test_fleeing_own_order_and_enemy_behaviour() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	var sim := BattleSim.new()
	sim.runner.step(s)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": f["a"], "type": "fall_back"}]).size(), 0)
	# Ordered but not yet moving: the owner sees the order, the enemy nothing.
	var own := _one(SquadRelation.facts(s, 1, f["a"], f["b"]), "fleeing", f["a"])
	assert_eq(own["value"], "falling_back")
	assert_eq(own["to"], f["b"], "B is the threat it runs from")
	assert_eq(_of(SquadRelation.facts(s, 2, f["a"], f["b"]), "fleeing", f["a"]), [],
		"an enemy's fleeing is never read from its order")
	sim.runner.step(s)
	assert_eq(s.squads.moving[_row(s, f["a"])], 1)
	var seen := _one(SquadRelation.facts(s, 2, f["a"], f["b"]), "fleeing", f["a"])
	assert_eq(seen["value"], "retreating", "moving away from B after B fired")
	# Moving away but not fired upon: no retreat.
	s.turn_log.clear()
	s.squads.fired_tick[_row(s, f["b"])] = -1
	assert_eq(_of(SquadRelation.facts(s, 2, f["a"], f["b"]), "fleeing", f["a"]), [])


func test_moving_heading() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	var arow := _row(s, f["a"])
	assert_eq(_of(SquadRelation.facts(s, 1, f["a"], f["b"]), "moving", f["a"]), [], "standing")
	s.squads.moving[arow] = 1
	for pair in [[0, "toward"], [Fixed.ANGLE_HALF, "away"], [Fixed.ANGLE_QUARTER, "across"]]:
		s.squads.facing[arow] = pair[0]
		assert_eq(_one(SquadRelation.facts(s, 2, f["a"], f["b"]), "moving", f["a"])["value"], pair[1])
	# Friendly pairs carry movement only.
	var friendly := SquadRelation.facts(s, 1, f["a"], f["m"])
	assert_gt(friendly.size(), 0)
	for d: Dictionary in friendly:
		assert_eq(d["kind"], "moving")


## An enemy squad that is attack-ordered, engaged without firing and
## reloading: nothing about it leaks order, engagement, holds or reload.
func test_enemy_facts_are_behaviour_only() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	assert_eq(BattleOrders.apply(s, 2, [{"squad": f["b"], "type": "attack", "target": f["a"]}]).size(), 0)
	var brow := _row(s, f["b"])
	s.squads.engaged[brow] = f["a"]
	for urow in Centroids.units_of(s, brow):
		s.units.reload[urow] = 7
	var own_view := SquadRelation.facts(s, 2, f["a"], f["b"])
	assert_eq(_one(own_view, "ordered", f["b"])["value"], "attack")
	assert_eq(_one(own_view, "targeting", f["b"])["value"], "aiming")
	for d: Dictionary in SquadRelation.facts(s, 1, f["a"], f["b"]):
		if d["from"] != f["b"]:
			continue
		assert_true(d["kind"] in ["range", "targeting", "under_fire", "fleeing", "moving"], "behaviour kind: " + d["kind"])
		assert_ne(d["value"], "aiming")
		assert_ne(d["value"], "falling_back")
		for key in ["hold", "holds", "reload", "order", "activity", "shot", "share"]:
			assert_false((d["data"] as Dictionary).has(key), "enemy fact hides " + key)


func test_read_only() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	BattleSim.new().runner.step(s)
	var before := s.state_hash()
	for viewer in [0, 1, 2]:
		for x in ["a", "m", "b", "c"]:
			for y in ["a", "m", "b", "c"]:
				SquadRelation.facts(s, viewer, f[x], f[y])
	assert_eq(s.state_hash(), before)


func test_nearest_visible_enemy() -> void:
	var f := _fixture()
	var s: BattleState = f["s"]
	assert_eq(BattleOrders.nearest_visible_enemy(s, _row(s, f["a"])), _row(s, f["b"]))
	assert_eq(BattleOrders.nearest_visible_enemy(s, _row(s, f["c"])), _row(s, f["a"]), "C sees A and M; A is nearer")
	s.squads.seen_by[_row(s, f["b"])] = 0
	assert_eq(BattleOrders.nearest_visible_enemy(s, _row(s, f["a"])), -1, "C is unseen too")
