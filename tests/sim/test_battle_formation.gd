extends GutTest
## Formation size (sw-uyv): an under-strength squad keeps the formation it
## deployed with when it moves, so its centroid stays on the line to the
## destination instead of sliding sideways into a full-strength line's slots.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


## Rules for a 60 x 40 open field (the test_battle_route pattern).
func _rules() -> BattleRules:
	var defs := _l().defs.duplicate()
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 60, "height": 40, "base": "open", "cells": []}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


## A rifle squad at 10, 20 facing east, `units` survivors (-1 = full
## strength), ordered straight ahead to 50, 20.
func _march(units: int) -> Array:
	var r := _rules()
	var s := BattleState.new(1, r, 1)
	var sid := BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), 10 * ONE, 20 * ONE, 0, units)
	Centroids.update(s)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": sid, "type": "move", "x": 50 * ONE, "y": 20 * ONE}]).size(), 0)
	return [s, sid]


## Marches 4 turns, returning the squad's centroid y at every tick.
func _centroid_trail(s: BattleState, sid: int) -> Array:
	var sim := BattleSim.new()
	var trail := []
	var hook := func(st: BattleState) -> void:
		trail.append(st.squads.cy[st.squads.row_of(sid)])
	sim.tick_hook = hook
	for _t in 4:
		sim.execute_turn(s)
	return trail


func test_understrength_squad_keeps_its_line() -> void:
	var made: Array = _march(4)
	var s: BattleState = made[0]
	var sid: int = made[1]
	var row := s.squads.row_of(sid)
	assert_eq(s.squads.alive[row], 4)
	assert_eq(s.squads.form_size[row], 4, "formation sized to the survivors, not the template")
	assert_eq(s.squads.cy[row], 20 * ONE, "deployed centred on its anchor")
	var start_x := s.squads.cx[row]
	var trail := _centroid_trail(s, sid)
	assert_gt(trail.size(), 0)
	for cy: int in trail:
		assert_true(absi(cy - 20 * ONE) <= ONE / 4, "centroid left the line to the destination: y=%d" % cy)
	assert_gt(s.squads.cx[row], start_x + 10 * ONE, "advanced east")


func test_full_strength_squad_unchanged() -> void:
	var made: Array = _march(-1)
	var s: BattleState = made[0]
	var sid: int = made[1]
	var row := s.squads.row_of(sid)
	assert_eq(s.squads.alive[row], 8)
	assert_eq(s.squads.form_size[row], 8)
	assert_eq(s.squads.cy[row], 20 * ONE)
	var start_x := s.squads.cx[row]
	var trail := _centroid_trail(s, sid)
	assert_gt(trail.size(), 0)
	for cy: int in trail:
		assert_true(absi(cy - 20 * ONE) <= ONE / 4, "centroid left the line to the destination: y=%d" % cy)
	assert_gt(s.squads.cx[row], start_x + 10 * ONE, "advanced east")
