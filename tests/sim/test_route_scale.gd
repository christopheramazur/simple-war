extends GutTest
## Routing at scale (sw-ll4.14): a 200 x 100 map with many wall combs and 48
## squads ordered across it in the same turn. Prints timings (turn start and
## the planning forecast) so the numbers are in the test log; the assertions
## are generous ceilings that only catch a regression to something unplayable.

const ONE := Fixed.ONE
const SQUADS := 24


var open_ground := false
static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _cells() -> Array:
	var cells := []
	if open_ground:
		return cells
	# Vertical walls every 20 columns, alternating gaps at top and bottom.
	for i in range(1, 10):
		var x := i * 20
		if i % 2 == 0:
			cells.append({"feature": "wall", "x": x, "y": 0, "h": 80})
		else:
			cells.append({"feature": "wall", "x": x, "y": 20, "h": 80})
	return cells


func _rules() -> BattleRules:
	var defs := _l().defs.duplicate()
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 200, "height": 100, "base": "open", "cells": _cells()}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


func _battle(r: BattleRules) -> Array:
	var s := BattleState.new(1, r, 1)
	var ids: Array = [[], []]
	for i in SQUADS:
		for p in [1, 2]:
			var x: int = 5 + (i % 4) * 3 + (0 if p == 1 else 185)
			var y: int = 10 + (i / 4) * 12
			ids[p - 1].append(BattleSetup.spawn_squad(s, p, r.squad_index("rifle_squad"), x * ONE, y * ONE, 0))
	Centroids.update(s)
	return [s, ids]


func _orders(ids: Array, p: int) -> Array:
	var out := []
	for i in ids[p - 1].size():
		var gx: int = (190 - (i % 4) * 3) if p == 1 else 10 + (i % 4) * 3
		out.append({"squad": ids[p - 1][i], "type": "move", "x": gx * ONE, "y": (15 + (i / 4) * 12) * ONE})
	return out


func test_many_squads_across_a_large_comb_map() -> void:
	var r := _rules()
	var made := _battle(r)
	var s: BattleState = made[0]
	var ids: Array = made[1]
	for p in [1, 2]:
		assert_eq(BattleOrders.apply(s, p, _orders(ids, p)).size(), 0)
	r.routes.warm(r)

	var t0 := Time.get_ticks_usec()
	var f := IntentForecast.run(s, BattleSim.new(), 1, [])
	var forecast_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var cold_plans := r.routes.plans
	assert_not_null(f)

	var sim := BattleSim.new()
	var t1 := Time.get_ticks_usec()
	sim.execute_turn(s)
	var turn_cold_ms := (Time.get_ticks_usec() - t1) / 1000.0
	var plans_cold := r.routes.plans
	var t2 := Time.get_ticks_usec()
	sim.execute_turn(s)
	var turn_next_ms := (Time.get_ticks_usec() - t2) / 1000.0
	print("ROUTE_SCALE squads=%d forecast=%.1fms (plans in shared cache after: %d) turn1=%.1fms plans=%d turn2=%.1fms plans=%d" % [
		SQUADS * 2, forecast_ms, cold_plans, turn_cold_ms, plans_cold, turn_next_ms, r.routes.plans])
	var fa := FileAccess.open("user://route_scale.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://route_scale.txt") else FileAccess.WRITE)
	fa.seek_end()
	fa.store_line("open=%s forecast=%.1f turn1=%.1f plans1=%d turn2=%.1f plans2=%d cold_plans=%d" % [str(open_ground), forecast_ms, turn_cold_ms, plans_cold, turn_next_ms, r.routes.plans, cold_plans])
	fa.close()
	assert_lt(turn_cold_ms, 30000.0, "turn start stays playable")
	assert_lt(forecast_ms, 20000.0, "forecast stays playable")


func test_many_squads_on_open_ground_is_the_baseline() -> void:
	open_ground = true
	test_many_squads_across_a_large_comb_map()
