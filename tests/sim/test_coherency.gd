extends GutTest
## Coherency radius (GDD 02 §2.14, U1Q29, sw-txnj.4): data per formation,
## default half-width + 4 m; a unit beyond it heads for the anchor; the
## anchor runs at half speed while any unit is out of coherency.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## Rules for a 60 x 40 field with `cells` painted on it. `squad_values`
## (optional) replaces the rifle squad's formation object for one test.
func _rules(cells: Array = [], formation: Dictionary = {}) -> BattleRules:
	var defs := _l().defs.duplicate(true)
	if not formation.is_empty():
		for d: Dictionary in defs:
			if d["id"] == "humanity_squad":
				d["values"]["formation"] = formation
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 60, "height": 40, "base": "open", "cells": cells}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


func _squad(r: BattleRules, x: int, y: int) -> Array:
	var s := BattleState.new(1, r, 1)
	var sid := BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return [s, sid]


## Largest distance from the anchor of any living unit of the squad.
func _worst(s: BattleState, sid: int) -> int:
	var row := s.squads.row_of(sid)
	var worst := 0
	for urow in Centroids.units_of(s, row):
		worst = maxi(worst, Fixed.length(s.units.x[urow] - s.squads.ax[row], s.units.y[urow] - s.squads.ay[row]))
	return worst


func test_default_radius_is_half_width_plus_four() -> void:
	# Rifle squad: 8 in a line at 2 m spacing, so the far slot is 7 m out.
	var r := _rules()
	var s := BattleState.new(1, r, 1)
	var sid := BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), 10 * ONE, 20 * ONE, 0)
	assert_eq(MovementSystem.coherency_m(s, s.squads.row_of(sid)), 11 * ONE, "7 m half-width + 4 m")
	assert_eq(Formation.half_width(Formation.LINE, 8, 2 * ONE), 7 * ONE)


func test_explicit_coherency_overrides_the_default() -> void:
	var r := _rules([], {"shape": "line", "spacing": 2, "coherency": "6.5"})
	var made := _squad(r, 10, 20)
	assert_eq(MovementSystem.coherency_m(made[0], made[0].squads.row_of(made[1])), 65 * ONE / 10)


func test_negative_or_non_numeric_coherency_fails_validation() -> void:
	for bad: Variant in [-1, "wide"]:
		var defs := _l().defs.duplicate(true)
		for d: Dictionary in defs:
			if d["id"] == "humanity_squad":
				d["values"]["formation"]["coherency"] = bad
		var errs := DataSchema.validate(TemplateTable.build(defs))
		# humanity_squad is abstract: every squad that inherits its formation reports it.
		assert_true(errs.size() > 0, "a bad radius is reported")
		var want := "below minimum 0" if typeof(bad) == TYPE_INT else "must be an integer or decimal string"
		for e: String in errs:
			assert_string_contains(e, "'formation/coherency' " + want)
		assert_string_contains(errs[0], "rifle_squad: ")


func test_squad_routed_round_a_corner_keeps_every_unit_in_coherency() -> void:
	# The wall at x = 30 runs from y = 5 to the bottom edge, so the squad goes
	# over the top, a long way round for its anchor.
	var r := _rules([{"feature": "wall", "x": 30, "y": 5, "h": 35}])
	var made := _squad(r, 20, 30)
	var s: BattleState = made[0]
	var sid: int = made[1]
	var row := s.squads.row_of(sid)
	var radius := MovementSystem.coherency_m(s, row)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": sid, "type": "move", "x": 40 * ONE, "y": 30 * ONE}]).size(), 0)
	var sim := BattleSim.new()
	var worst_while_moving := 0
	var hook := func(st: BattleState) -> void:
		if st.squads.moving[row] == 1 or st.squads.route[row] != 0:
			worst_while_moving = maxi(worst_while_moving, _worst(st, sid))
	sim.tick_hook = hook
	for _t in 10:
		sim.execute_turn(s)
	assert_true(Fixed.distance(s.squads.ax[row], s.squads.ay[row], 40 * ONE, 30 * ONE) <= MovementSystem.ARRIVE, "arrived")
	assert_true(_worst(s, sid) <= radius, "no straggler beyond %d m at arrival: %d" % [radius / ONE, _worst(s, sid)])
	assert_true(worst_while_moving <= radius + ONE * 2, "stragglers stay near coherency on the way: %d" % worst_while_moving)


func test_anchor_runs_at_half_speed_while_a_unit_is_out_of_coherency() -> void:
	var r := _rules()
	var together := _squad(r, 10, 20)
	var apart := _squad(r, 10, 20)
	var a: BattleState = together[0]
	var b: BattleState = apart[0]
	var sa: int = together[1]
	var sb: int = apart[1]
	assert_eq(BattleOrders.apply(a, 1, [{"squad": sa, "type": "move", "x": 50 * ONE, "y": 20 * ONE}]).size(), 0)
	assert_eq(BattleOrders.apply(b, 1, [{"squad": sb, "type": "move", "x": 50 * ONE, "y": 20 * ONE}]).size(), 0)
	# One unit of the second squad is pushed 20 m out of formation.
	var brow := b.squads.row_of(sb)
	var urow: int = Centroids.units_of(b, brow)[0]
	b.units.x[urow] += 20 * ONE
	assert_true(MovementSystem.out_of_coherency(b, brow, b.squads.ax[brow], b.squads.ay[brow]))
	var arow := a.squads.row_of(sa)
	var a0: int = a.squads.ax[arow]
	var b0: int = b.squads.ax[brow]
	MovementSystem.new().run(a)
	MovementSystem.new().run(b)
	var step_a := a.squads.ax[arow] - a0
	var step_b := b.squads.ax[brow] - b0
	assert_true(step_a > 0, "the coherent squad moves")
	assert_eq(step_b, step_a / 2, "half speed while a unit is out of coherency")
