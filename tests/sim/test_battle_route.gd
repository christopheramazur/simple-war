extends GutTest
## Battle routing (GDD 02 §2.14, O1Q8, sw-ll4.4): squads walk around what
## they can't enter, prefer cheaper ground, and never stall.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## Rules for a 60 x 40 open field with `cells` painted on it.
func _rules(cells: Array) -> BattleRules:
	var defs := _l().defs.duplicate()
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 60, "height": 40, "base": "open", "cells": cells}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


## A wall across the field at x = 30 from y = 5 down to the bottom edge, so
## the only way round is over the top.
const WALL := [{"feature": "wall", "x": 30, "y": 5, "h": 35}]


func _squad(r: BattleRules, x: int, y: int, player: int = 1, squad: String = "rifle_squad") -> Array:
	var s := BattleState.new(1, r, 1)
	var sid := BattleSetup.spawn_squad(s, player, r.squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return [s, sid]


## Runs turns until the squad's anchor is within a metre of x, y. Returns the
## anchor's cell at every tick, and fails if any is impassable.
func _walk(s: BattleState, sid: int, turns: int) -> Array:
	var sim := BattleSim.new()
	var trail := []
	var hook := func(st: BattleState) -> void:
		var row := st.squads.row_of(sid)
		trail.append(Vector2i(Fixed.to_int_floor(st.squads.ax[row]), Fixed.to_int_floor(st.squads.ay[row])))
	sim.tick_hook = hook
	for _t in turns:
		sim.execute_turn(s)
	return trail


func _anchor(s: BattleState, sid: int) -> Vector2i:
	var row := s.squads.row_of(sid)
	return Vector2i(Fixed.to_int_floor(s.squads.ax[row]), Fixed.to_int_floor(s.squads.ay[row]))


func test_open_ground_is_one_straight_leg() -> void:
	var r := _rules([])
	var leg := r.routes.next_waypoint(r, 0, 5 * ONE, 5 * ONE, 50 * ONE + 7, 30 * ONE + 3)
	assert_eq(Array(leg), [50 * ONE + 7, 30 * ONE + 3, 1], "the destination itself, to the fixed-point unit")
	var diagonal := r.routes.next_waypoint(r, 0, 5 * ONE, 5 * ONE, 35 * ONE, 35 * ONE)
	assert_eq(diagonal[2], 1, "a pure diagonal is still one leg")


func test_a_squad_walks_round_a_wall() -> void:
	var r := _rules(WALL)
	var made: Array = _squad(r, 20, 30)
	var s: BattleState = made[0]
	var sid: int = made[1]
	assert_eq(BattleOrders.apply(s, 1, [{"squad": sid, "type": "move", "x": 40 * ONE, "y": 30 * ONE}]).size(), 0)
	var trail := _walk(s, sid, 4)
	assert_eq(_anchor(s, sid), Vector2i(40, 30), "it arrives on the far side")
	var wall := r.feature_ids.find("wall")
	var highest := 40
	for cell: Vector2i in trail:
		assert_ne(r.terrain[cell.y * r.width + cell.x], wall, "anchor on the wall at %s" % cell)
		highest = mini(highest, cell.y)
	assert_lt(highest, 5, "it went over the top of the wall")


func test_routes_are_the_same_whatever_was_planned_before() -> void:
	var cold := _rules(WALL)
	var warm := _rules(WALL)
	# Fill the warm cache with other routes first.
	for y in range(6, 38, 4):
		warm.routes.next_waypoint(warm, 0, 10 * ONE, y * ONE, 50 * ONE, (40 - y) * ONE)
	var trails := []
	for r: BattleRules in [cold, warm]:
		var made: Array = _squad(r, 20, 30)
		BattleOrders.apply(made[0], 1, [{"squad": made[1], "type": "move", "x": 40 * ONE, "y": 30 * ONE}])
		_walk(made[0], made[1], 4)
		trails.append((made[0] as BattleState).state_hash_hex())
	assert_eq(trails[0], trails[1])


func test_cheaper_ground_is_preferred() -> void:
	# A wide forest between the squad and its goal, with a road through it
	# further up. Infantry pay 150% in forest and 80% on the road.
	var r := _rules([
		{"feature": "forest", "x": 20, "y": 0, "w": 20, "h": 40},
		{"feature": "road", "x": 20, "y": 10, "w": 20, "h": 1}])
	var cls := r.sq_route_class[r.squad_index("rifle_squad")]
	assert_eq(r.rt_cost[cls][r.feature_ids.find("forest")], 150)
	var leg := r.routes.next_waypoint(r, cls, 10 * ONE, 14 * ONE, 50 * ONE, 14 * ONE)
	assert_eq(leg[2], 0, "not straight through the forest")
	assert_lt(leg[1], 14 * ONE, "it heads up to the road")


func test_an_order_onto_a_wall_goes_to_the_nearest_cell() -> void:
	var r := _rules(WALL)
	var leg := r.routes.next_waypoint(r, 0, 20 * ONE, 30 * ONE, 30 * ONE + ONE / 2, 30 * ONE + ONE / 2)
	assert_eq(Array(leg), [29 * ONE + ONE / 2, 30 * ONE + ONE / 2, 1], "the cell beside the wall, lowest index first")
	var made: Array = _squad(r, 20, 30)
	var s: BattleState = made[0]
	BattleOrders.apply(s, 1, [{"squad": made[1], "type": "move", "x": 30 * ONE, "y": 30 * ONE}])
	_walk(s, made[1], 2)
	assert_eq(_anchor(s, made[1]), Vector2i(29, 30))
	var before: int = r.routes.plans
	_walk(s, made[1], 1)
	assert_eq(r.routes.plans, before, "it stands there without planning again")


func test_a_walled_off_goal_goes_to_the_nearest_reachable_cell() -> void:
	# A closed box: nothing inside can be reached from outside.
	var r := _rules([
		{"feature": "wall", "x": 40, "y": 10, "w": 10, "h": 10},
		{"feature": "open", "x": 41, "y": 11, "w": 8, "h": 8}])
	var leg := PackedInt64Array([20 * ONE, 15 * ONE, 0])
	var legs := 0
	while leg[2] == 0 and legs < 10:
		leg = r.routes.next_waypoint(r, 0, leg[0], leg[1], 45 * ONE, 15 * ONE)
		legs += 1
	# The nearest ring of cells with one it can reach is 5 out; (50, 15) is the
	# closest of those, on the far side of the box.
	assert_eq(Array(leg), [50 * ONE + ONE / 2, 15 * ONE + ONE / 2, 1])
	assert_gt(legs, 1, "it walks round the box to get there")


func test_a_squad_inside_a_wall_steps_out() -> void:
	var r := _rules(WALL)
	var made: Array = _squad(r, 30, 20)
	var s: BattleState = made[0]
	BattleOrders.apply(s, 1, [{"squad": made[1], "type": "move", "x": 10 * ONE, "y": 20 * ONE}])
	_walk(s, made[1], 3)
	assert_eq(_anchor(s, made[1]), Vector2i(10, 20), "the old rule left it standing in the wall forever")


func test_an_attacker_plans_again_only_when_its_target_has_moved_far() -> void:
	var r := _rules([])
	var s := BattleState.new(1, r, 1)
	var a := BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), 5 * ONE, 20 * ONE, 0)
	var b := BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), 55 * ONE, 20 * ONE, 0)
	Centroids.update(s)
	var arow := s.squads.row_of(a)
	var brow := s.squads.row_of(b)
	BattleOrders.set_order(s, arow, BattleSquads.Order.ATTACK, 0, 0, b, 0)
	var mv := MovementSystem.new()
	mv._plan_routes(s)
	assert_eq([s.squads.rx[arow], s.squads.route[arow]], [55 * ONE, 2])
	var cx: PackedInt64Array = s.squads.take_column(&"cx")
	cx[brow] = 50 * ONE
	s.squads.put_column(&"cx", cx)
	mv._plan_routes(s)
	assert_eq(s.squads.rx[arow], 55 * ONE, "5 m is inside the 8 m allowance")
	cx = s.squads.take_column(&"cx")
	cx[brow] = 45 * ONE
	s.squads.put_column(&"cx", cx)
	mv._plan_routes(s)
	assert_eq(s.squads.rx[arow], 45 * ONE, "10 m is not")


func test_impassable_features_compile_to_cost_zero() -> void:
	var r := _rules([])
	var wall := r.feature_ids.find("wall")
	for cls in r.rt_cost.size():
		assert_eq(r.rt_cost[cls][wall], 0)
	assert_eq(r.rt_cost[0][r.feature_ids.find("open")], 100)


## Deployment (§2.14, sw-ll4.15): nothing starts on a cell it can't enter.
func test_a_squad_never_deploys_inside_a_wall() -> void:
	var r := _rules([{"feature": "wall", "x": 8, "y": 0, "w": 6, "h": 40}])
	var st := r.squad_index("rifle_squad")
	var costs: PackedInt32Array = r.rt_cost[r.sq_route_class[st]]
	assert_eq(BattleSetup.open_point(r, st, 20 * ONE, 20 * ONE), PackedInt64Array([20 * ONE, 20 * ONE]), "open ground is left alone")
	# x = 9.5 is one cell from the wall's left edge and four from its right.
	assert_eq(BattleSetup.open_point(r, st, 9 * ONE + ONE / 2, 20 * ONE), PackedInt64Array([7 * ONE + ONE / 2, 20 * ONE + ONE / 2]))
	var made := _squad(r, 10, 20)
	var s: BattleState = made[0]
	var row := s.squads.row_of(made[1])
	assert_gt(costs[r.terrain[Fixed.to_int_floor(s.squads.ay[row]) * r.width + Fixed.to_int_floor(s.squads.ax[row])]], 0, "the anchor is on open ground")
	assert_eq(s.units.count(), 8)
	for u in s.units.count():
		var cell := Fixed.to_int_floor(s.units.y[u]) * r.width + Fixed.to_int_floor(s.units.x[u])
		assert_gt(costs[r.terrain[cell]], 0, "unit %d stands on a cell it can enter" % u)
	# A deployment area wholly inside the wall still fields the side.
	var side := {"player": 1, "facing": 0, "deploy": PackedInt64Array([9 * ONE, 5 * ONE, 3 * ONE, 30 * ONE]),
		"squads": PackedInt64Array([st, st])}
	var s2 := BattleState.new(2, r, 1)
	for sid in BattleSetup.deploy_side(s2, side):
		var srow := s2.squads.row_of(sid)
		assert_gt(costs[r.terrain[Fixed.to_int_floor(s2.squads.ay[srow]) * r.width + Fixed.to_int_floor(s2.squads.ax[srow])]], 0)


## sw-0nl: a central block with equal detours north and south (rows 15..23,
## five rows either way from row 19). Frame 0 breaks the tie towards the low
## cell indices (north); the 180° frame breaks it the other way.
func test_equal_detours_mirror_with_the_frame() -> void:
	var r := _rules([{"feature": "wall", "x": 28, "y": 15, "w": 4, "h": 9}])
	var fx := 10 * ONE + ONE / 2
	var fy := 19 * ONE + ONE / 2
	var tx := 50 * ONE + ONE / 2
	var ty := 19 * ONE + ONE / 2
	var north := r.routes.next_waypoint(r, 0, fx, fy, tx, ty)
	assert_lt(north[1], fy, "frame 0 detours north")
	# The same cells in the flipped frame: the cache must not hand back the
	# north leg, and the tie goes south.
	var south := r.routes.next_waypoint(r, 0, fx, fy, tx, ty, Fixed.ANGLE_HALF)
	assert_gt(south[1], fy, "the 180° frame detours south")


## sw-0nl: on an asymmetric map the flipped plan runs on the rotated grid, so
## a mirrored start/goal pair on the mirrored map gets the mirrored waypoint.
func test_a_flipped_plan_mirrors_on_any_map() -> void:
	var a := _rules(WALL)
	var b := _rules([{"feature": "wall", "x": 29, "y": 0, "h": 35}])
	var leg_a := a.routes.next_waypoint(a, 0, 20 * ONE + ONE / 2, 30 * ONE + ONE / 2, 40 * ONE + ONE / 2, 30 * ONE + ONE / 2)
	var leg_b := b.routes.next_waypoint(b, 0, 39 * ONE + ONE / 2, 9 * ONE + ONE / 2, 19 * ONE + ONE / 2, 9 * ONE + ONE / 2, Fixed.ANGLE_HALF)
	assert_eq(Array(leg_b), [60 * ONE - leg_a[0], 40 * ONE - leg_a[1], leg_a[2]])


## sw-0nl: a forecast job shares the rules' route caches with the caller's
## battle, so the caller thread fills both frames before the job runs.
## Building them lazily from two threads at once races: a reader can see the
## costs of a class before its regions exist, and walks off an empty array.
func test_a_forecast_job_warms_the_route_caches_on_the_caller_thread() -> void:
	var r := _rules(WALL)
	var made := _squad(r, 20, 30)
	var job := IntentForecast.job(made[0], 1, [])
	assert_true(job.is_valid())
	assert_eq(r.routes._costs.size(), r.rt_cost.size(), "costs for every class")
	assert_eq(r.routes._regions.size(), r.rt_cost.size(), "regions for every class")
	assert_eq(r.routes._costs_flipped.size(), r.rt_cost.size(), "flipped costs for every class")
	assert_eq(r.routes._regions_flipped.size(), r.rt_cost.size(), "flipped regions too: never costs without regions")
	var costs: PackedInt32Array = (r.routes._costs[0] as PackedInt32Array).duplicate()
	costs.reverse()
	assert_eq(r.routes._costs_flipped[0], costs, "the flipped frame is the rotated grid")


## Unit collision with terrain (§2.14, sw-ll4.16): a squad skirting a wall
## with a wide formation never has a unit inside the wall, and still arrives.
func test_units_never_enter_a_wall_while_the_squad_skirts_it() -> void:
	var r := _rules(WALL)
	var made: Array = _squad(r, 26, 30)
	var s: BattleState = made[0]
	BattleOrders.apply(s, 1, [{"squad": made[1], "type": "move", "x": 40 * ONE, "y": 30 * ONE}])
	var wall := r.feature_ids.find("wall")
	var inside := []
	var sim := BattleSim.new()
	sim.tick_hook = func(st: BattleState) -> void:
		for u in st.units.count():
			if r.feature_at(st.units.x[u], st.units.y[u]) == wall:
				inside.append(u)
	for _t in 5:
		sim.execute_turn(s)
	assert_eq(inside.size(), 0, "a unit stood in the wall %d times" % inside.size())
	assert_eq(_anchor(s, made[1]), Vector2i(40, 30))
