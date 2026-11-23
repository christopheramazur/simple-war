extends GutTest
## The gate graph behind battle routing (sw-ll4.29): a plan is a real cell
## path over passable ground, the bake is deterministic, and a plan the gate
## graph cannot make falls back to the cell search without losing the route.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## A 200 x 100 field with vertical walls every 20 columns, gaps alternating
## top and bottom (the route scale comb, sw-ll4.14).
func _comb() -> BattleRules:
	var cells := []
	for i in range(1, 10):
		var x := i * 20
		if i % 2 == 0:
			cells.append({"feature": "wall", "x": x, "y": 0, "h": 80})
		else:
			cells.append({"feature": "wall", "x": x, "y": 20, "h": 80})
	var defs := _l().defs.duplicate()
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 200, "height": 100, "base": "open", "cells": cells}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


func test_a_plan_is_a_walkable_cell_path_to_the_goal() -> void:
	var r := _comb()
	var costs: PackedInt32Array = r.routes._costs_of(r, 0)
	var gates := r.routes._gates_of(r, 0)
	var start := 10 * 200 + 5
	var goal := 15 * 200 + 190
	var path := gates.plan(costs, start, goal)
	assert_false(path.is_empty(), "a gate route exists across the comb")
	assert_eq(path[path.size() - 1], goal, "the path ends at the goal")
	var prev := start
	for c in path:
		assert_gt(costs[c], 0, "cell %d is passable" % c)
		var dx := absi(c % 200 - prev % 200)
		@warning_ignore("integer_division")
		var dy := absi(c / 200 - prev / 200)
		assert_true(dx <= 1 and dy <= 1 and dx + dy > 0, "step into %d is one cell" % c)
		prev = c


func test_the_bake_is_deterministic() -> void:
	var a := _comb()
	var b := _comb()
	var ga := a.routes._gates_of(a, 0)
	var gb := b.routes._gates_of(b, 0)
	assert_eq(ga.node_cell, gb.node_cell)
	assert_eq(ga.node_partner, gb.node_partner)
	assert_eq(ga.intra_cost, gb.intra_cost)


func test_same_sector_has_no_gate_plan() -> void:
	var r := _comb()
	var costs: PackedInt32Array = r.routes._costs_of(r, 0)
	var gates := r.routes._gates_of(r, 0)
	assert_true(gates.plan(costs, 2 * 200 + 2, 3 * 200 + 4).is_empty(), "the cell search handles a short leg")


func test_a_routed_leg_matches_the_cell_search_across_the_comb() -> void:
	var r := _comb()
	var leg := r.routes.next_waypoint(r, 0, 5 * ONE, 10 * ONE, 190 * ONE, 15 * ONE)
	assert_eq(leg.size(), 3)
	assert_gt(leg[0], 5 * ONE, "the squad moves east")
