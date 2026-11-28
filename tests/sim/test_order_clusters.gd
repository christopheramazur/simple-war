extends GutTest
## Order clusters (sw-txnj.14, GDD 02 §2.14 Clusters): squads given one
## shared order (the same "cluster" key in one order list) share one route
## plan and keep their offsets from the cluster's lead, its lowest row.

const ONE := Fixed.ONE
## A wall across the field at x = 40 with a 16 m doorway at y 17 to 33, just
## wider than one rifle line (14 m): the three squads file through it.
## (Units have no routes of their own, so a narrower door strands the units
## of any squad behind the wall; sw-txnj.14 notes.)
const DOOR := [{"feature": "wall", "x": 40, "y": 0, "h": 17}, {"feature": "wall", "x": 40, "y": 33, "h": 17}]

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## Rules for an 80 x 50 field with `cells` painted on it.
func _rules(cells: Array = []) -> BattleRules:
	var defs := _l().defs.duplicate(true)
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 80, "height": 50, "base": "open", "cells": cells}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


## Spawns rifle squads for player 1 at the (x, y) metre pairs; returns ids.
func _spawn(s: BattleState, at: Array) -> Array:
	var ids := []
	for p: Vector2i in at:
		ids.append(BattleSetup.spawn_squad(s, 1, s.rules.squad_index("rifle_squad"), p.x * ONE, p.y * ONE, 0))
	Centroids.update(s)
	return ids


func _moves(ids: Array, to: Array, cluster: Variant = 7) -> Array:
	var o := []
	for i in ids.size():
		var m := {"squad": ids[i], "type": "move", "x": to[i].x * ONE, "y": to[i].y * ONE}
		if cluster != null:
			m["cluster"] = cluster
		o.append(m)
	return o


## Largest distance from the anchor of any living unit of the squad.
func _worst_unit(s: BattleState, row: int) -> int:
	var worst := 0
	for urow in Centroids.units_of(s, row):
		if s.units.hp[urow] > 0:
			worst = maxi(worst, Fixed.length(s.units.x[urow] - s.squads.ax[row], s.units.y[urow] - s.squads.ay[row]))
	return worst


## Farthest any living member's anchor stands from its place by the lead.
func _worst_member(s: BattleState) -> int:
	var leads := MovementSystem.cluster_leads(s)
	var worst := 0
	for row in s.squads.count():
		var c := s.squads.cluster[row]
		if c < 0 or not leads.has(c) or leads[c] == row or not s.squads.is_active(row):
			continue
		var lead: int = leads[c]
		var place := MovementSystem.cluster_place(s, row, lead, s.squads.ax[lead], s.squads.ay[lead])
		worst = maxi(worst, Fixed.distance(s.squads.ax[row], s.squads.ay[row], place[0], place[1]))
	return worst


## Farthest any of `rows` stands from its place by `lead` (offsets are the
## differences of their order points), cluster or not.
func _worst_offset(s: BattleState, lead: int, rows: Array) -> int:
	var sq := s.squads
	var worst := 0
	for row: int in rows:
		var px := sq.ax[lead] + sq.tx[row] - sq.tx[lead]
		var py := sq.ay[lead] + sq.ty[row] - sq.ty[lead]
		worst = maxi(worst, Fixed.distance(sq.ax[row], sq.ay[row], px, py))
	return worst


func _arrived(s: BattleState, row: int) -> bool:
	return Fixed.distance(s.squads.ax[row], s.squads.ay[row], s.squads.tx[row], s.squads.ty[row]) <= MovementSystem.ARRIVE


func test_apply_forms_a_cluster_led_by_the_lowest_row() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var ids := _spawn(s, [Vector2i(10, 10), Vector2i(10, 25), Vector2i(10, 40)])
	# Listed out of row order: the lead is still the lowest row.
	var o := _moves([ids[2], ids[0], ids[1]], [Vector2i(60, 40), Vector2i(60, 10), Vector2i(60, 25)])
	assert_eq(BattleOrders.apply(s, 1, o), PackedStringArray())
	for id: int in ids:
		assert_eq(s.squads.cluster[s.squads.row_of(id)], ids[0], "cluster value is the lead's squad id")
	assert_eq(MovementSystem.cluster_leads(s), {ids[0]: s.squads.row_of(ids[0])})


func test_a_cluster_of_one_and_a_new_order_leave_no_cluster() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var ids := _spawn(s, [Vector2i(10, 10), Vector2i(10, 25), Vector2i(10, 40)])
	assert_eq(BattleOrders.apply(s, 1, _moves(ids, [Vector2i(60, 10), Vector2i(60, 25), Vector2i(60, 40)])), PackedStringArray())
	# Squad 2 alone gets a new order without a key; squad 1 a cluster of one.
	assert_eq(BattleOrders.apply(s, 1, [{"squad": ids[1], "type": "hold"}] + _moves([ids[0]], [Vector2i(50, 10)], 3)), PackedStringArray())
	assert_eq(s.squads.cluster[s.squads.row_of(ids[0])], -1, "a cluster of one is no cluster")
	assert_eq(s.squads.cluster[s.squads.row_of(ids[1])], -1, "a new order leaves the cluster")
	assert_eq(s.squads.cluster[s.squads.row_of(ids[2])], ids[0], "an untouched member keeps its order")
	# A new cluster under the same lead id: the old member leaves it.
	assert_eq(BattleOrders.apply(s, 1, _moves([ids[0], ids[1]], [Vector2i(50, 10), Vector2i(50, 25)], 1)), PackedStringArray())
	assert_eq(s.squads.cluster[s.squads.row_of(ids[2])], -1, "an old member leaves a re-formed cluster")
	assert_eq(s.squads.cluster[s.squads.row_of(ids[1])], ids[0])


func test_a_non_integer_cluster_key_is_an_error() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var ids := _spawn(s, [Vector2i(10, 10)])
	var errs := BattleOrders.apply(s, 1, _moves(ids, [Vector2i(60, 10)], "a"))
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "cluster must be an integer")


## Runs three squads at x 15 (y 10, 25, 40) through the doorway to x 65 for
## 20 turns. Returns {"state", "ids", "arrived": tick each squad first
## arrived, "at_first": the worst unit or cluster straggle (m, fixed) on the
## tick the first squad arrives}.
func _through_the_door(cluster: bool) -> Dictionary:
	var s := BattleState.new(1, _rules(DOOR), 1)
	var ids := _spawn(s, [Vector2i(15, 10), Vector2i(15, 25), Vector2i(15, 40)])
	var to := [Vector2i(65, 10), Vector2i(65, 25), Vector2i(65, 40)]
	assert_eq(BattleOrders.apply(s, 1, _moves(ids, to, 7 if cluster else null)), PackedStringArray())
	var rows := []
	for id: int in ids:
		rows.append(s.squads.row_of(id))
	# Lambdas capture locals by value: the hook writes into a dictionary.
	var out := {"state": s, "ids": ids, "arrived": [-1, -1, -1], "at_first": -1}
	var hook := func(st: BattleState) -> void:
		for i in 3:
			if out["arrived"][i] < 0 and _arrived(st, rows[i]):
				out["arrived"][i] = st.tick
				if out["at_first"] < 0:
					out["at_first"] = _worst_offset(st, rows[i], rows)
	var sim := BattleSim.new()
	sim.tick_hook = hook
	for _t in 20:
		sim.execute_turn(s)
	return out


func _spread(ticks: Array) -> int:
	return (ticks.max() as int) - (ticks.min() as int)


## Acceptance: a three-squad cluster through a doorway arrives with no
## straggler beyond its coherency radius, units or squads.
func test_three_squad_cluster_through_a_doorway_arrives_together() -> void:
	var run := _through_the_door(true)
	var s: BattleState = run["state"]
	var radius := MovementSystem.coherency_m(s, s.squads.row_of(run["ids"][0]))
	for id: int in run["ids"]:
		var row := s.squads.row_of(id)
		assert_true(_arrived(s, row), "squad %d arrived" % id)
		assert_true(_worst_unit(s, row) <= radius, "no unit straggler: %d" % _worst_unit(s, row))
	assert_false(run["arrived"].has(-1), "all arrived: %s" % [run["arrived"]])
	assert_true(run["at_first"] <= radius, "every squad within %d m of its place when the first arrives: %.1f m" % [radius / ONE, run["at_first"] / float(ONE)])


## Without the cluster the same three squads race: the middle one, with the
## straight line through the door, gets there well before the others.
func test_without_a_cluster_the_squads_race() -> void:
	var alone := _through_the_door(false)
	var together := _through_the_door(true)
	var s: BattleState = alone["state"]
	var radius := MovementSystem.coherency_m(s, s.squads.row_of(alone["ids"][0]))
	assert_eq(alone["arrived"].find(alone["arrived"].min()), 1, "the middle squad arrives first on its own: %s" % [alone["arrived"]])
	assert_true(alone["at_first"] > radius, "the others straggle when it does: %.1f m" % (alone["at_first"] / float(ONE)))
	assert_lt(_spread(together["arrived"]), _spread(alone["arrived"]), "the cluster arrives closer together: %s vs %s" % [together["arrived"], alone["arrived"]])


## Offsets from the lead are kept along a route round a block, and a member
## that dies hands the lead on without breaking the plan.
func test_offsets_are_kept_and_a_dead_lead_hands_on_the_plan() -> void:
	# A block in the cluster's path, so the lead walks waypoint legs.
	var r := _rules([{"feature": "wall", "x": 36, "y": 14, "w": 8, "h": 12}])
	var s := BattleState.new(1, r, 1)
	var ids := _spawn(s, [Vector2i(15, 20), Vector2i(15, 35), Vector2i(10, 5)])
	var to := [Vector2i(65, 20), Vector2i(65, 35), Vector2i(60, 5)]
	assert_eq(BattleOrders.apply(s, 1, _moves(ids, to)), PackedStringArray())
	var lead := s.squads.row_of(ids[0])
	var radius := MovementSystem.coherency_m(s, lead)
	var sim := BattleSim.new()
	var seen := {"worst": 0, "legs": 0}
	var hook := func(st: BattleState) -> void:
		seen["worst"] = maxi(seen["worst"], _worst_member(st))
		if st.squads.route[lead] == 1 and st.squads.is_active(lead):
			seen["legs"] += 1
	sim.tick_hook = hook
	sim.execute_turn(s)
	assert_true(seen["legs"] > 0, "the lead walks round the block")
	assert_true(seen["worst"] <= radius, "members keep their places by the lead: %d" % seen["worst"])
	# The lead is destroyed mid-route: the next row leads.
	var destroyed: PackedByteArray = s.squads.take_column(&"destroyed")
	destroyed[lead] = 1
	s.squads.put_column(&"destroyed", destroyed)
	assert_eq(MovementSystem.cluster_leads(s), {ids[0]: s.squads.row_of(ids[1])}, "the next row leads")
	seen["worst"] = 0
	for _t in 20:
		sim.execute_turn(s)
	for id: int in [ids[1], ids[2]]:
		assert_true(_arrived(s, s.squads.row_of(id)), "squad %d arrived" % id)
	assert_true(seen["worst"] <= radius, "the survivors keep their places: %d" % seen["worst"])


## A cluster member walks at the cluster's pace: with the lead running, a
## member that walks holds the lead back to its pace.
func test_the_cluster_walks_at_its_slowest_members_pace() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var ids := _spawn(s, [Vector2i(10, 10), Vector2i(10, 25)])
	var o := _moves(ids, [Vector2i(60, 10), Vector2i(60, 25)])
	o[0]["run"] = true
	assert_eq(BattleOrders.apply(s, 1, o), PackedStringArray())
	var a := s.squads.row_of(ids[0])
	var b := s.squads.row_of(ids[1])
	var a0 := s.squads.ax[a]
	var b0 := s.squads.ax[b]
	MovementSystem.new().run(s)
	assert_gt(s.squads.ax[b] - b0, 0)
	assert_eq(s.squads.ax[a] - a0, s.squads.ax[b] - b0, "the runner keeps the walker's pace")


## The forecast runs the same cluster plan: its ghosts end where the turn
## really ends.
func test_forecast_matches_execution_for_a_cluster() -> void:
	var r := _rules(DOOR)
	var s := BattleState.new(1, r, 1)
	var ids := _spawn(s, [Vector2i(15, 10), Vector2i(15, 25), Vector2i(15, 40)])
	var orders := _moves(ids, [Vector2i(65, 10), Vector2i(65, 25), Vector2i(65, 40)])
	var f := IntentForecast.run(s, BattleSim.new(), 1, orders)
	assert_eq(f["errors"], PackedStringArray())
	BattleOrders.apply(s, 1, orders)
	BattleSim.new().execute_turn(s)
	for id: int in ids:
		var pts: PackedInt64Array = f["ghosts"][id]
		var row := s.squads.row_of(id)
		assert_eq(pts[pts.size() - 2], s.squads.cx[row], "ghost end x of %d" % id)
		assert_eq(pts[pts.size() - 1], s.squads.cy[row], "ghost end y of %d" % id)


func test_cluster_runs_are_deterministic() -> void:
	var hashes := []
	for _i in 2:
		var s := BattleState.new(1, _rules(DOOR), 1)
		var ids := _spawn(s, [Vector2i(15, 10), Vector2i(15, 25), Vector2i(15, 40)])
		BattleOrders.apply(s, 1, _moves(ids, [Vector2i(65, 10), Vector2i(65, 25), Vector2i(65, 40)]))
		var sim := BattleSim.new()
		for _t in 3:
			sim.execute_turn(s)
		hashes.append(s.state_hash_hex())
	assert_eq(hashes[0], hashes[1])
