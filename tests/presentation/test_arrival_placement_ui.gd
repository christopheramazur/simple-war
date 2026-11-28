extends GutTest
## Arrival placements in the war room (sw-bafi.18, sw-bafi.19, U1 C12 UI): a joining side
## sees its arrival area and arriving squads in Planning (no battle
## observation before Reveal), drags and turns them with the planner like
## deployment drafting, and submits through submit_arrival only; the squads
## spawn where placed at Reveal. Only its own area and squads are shown.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const ONE := Fixed.ONE


func _m(p: Dictionary) -> Vector2:
	return Vector2(float(p["x"]) / ONE, float(p["y"]) / ONE)


const BASE := 1 << 48


func _arriving(id: int, x: int, y: int) -> Dictionary:
	return {"id": id, "player": 2, "template": "rifle_squad", "x": x * ONE, "y": y * ONE, "facing": 0, "arriving": true}


## A planner fed a joiner's view: a 100 x 100 m field, the arrival area
## x 0-40, two arriving squads (display IDs BASE + 77, BASE + 78), no battle.
func test_a_planner_drafts_arrivals_inside_the_area() -> void:
	var pl := BattlePlanner.new(2)
	pl.sync({"width": 100, "height": 100, "deploying": false, "arrival": true,
		"arrival_area": [0, 0, 40 * ONE, 100 * ONE], "areas": [],
		"squads": [_arriving(BASE + 77, 10, 40), _arriving(BASE + 78, 20, 60)], "units": []})
	assert_true(pl.can_deploy())
	assert_eq(pl.placeable(), [BASE + 77, BASE + 78])
	assert_eq(pl.areas.size(), 1)
	assert_true(pl.areas[0]["arrival"], "the arrival area is marked for the label")
	pl.select([BASE + 77, BASE + 78])
	pl.drag([BASE + 77, BASE + 78], BASE + 77, Vector2(5, 0))
	pl.face([BASE + 78], Vector2(25, 70))  # south of where 78 now stands
	assert_eq(pl.deployment(), [], "no battle squad placements")
	var list := pl.arrival()
	assert_eq(list.size(), 2)
	assert_eq(int(list[0]["squad"]), BASE + 77)
	assert_eq(_m(list[0]), Vector2(15, 40))
	assert_eq(_m(list[1]), Vector2(25, 60))
	assert_eq(int(list[1]["facing"]), BattlePlanner.snap_facing(Fixed.ANGLE_FULL >> 2))
	for p: Dictionary in list:
		assert_true(pl.arrival_area.has_point(_m(p)))
	pl.place(BASE + 77, Vector2(90, 90))
	assert_eq(_m(pl.placements[BASE + 77]), Vector2(40, 90), "a drop outside the area lands on its edge")
	pl.move_to(Vector2(50, 50))
	pl.order("hold")
	assert_eq(pl.orders(), [], "arriving squads take no orders")


## A side already fighting (not deploying) with one squad on its way: the
## battle squad takes orders and stays put on a drag; the arriving one is
## placed inside the arrival area (x 60-100) and takes no orders.
func test_a_planner_keeps_battle_squads_and_reinforcements_apart() -> void:
	var pl := BattlePlanner.new(2)
	var obs := {"width": 100, "height": 100, "deploying": false, "areas": [],
		"arrival_area": [60 * ONE, 0, 40 * ONE, 100 * ONE],
		"squads": [{"id": 3, "player": 2, "template": "rifle_squad", "x": 30 * ONE, "y": 50 * ONE, "facing": 0},
			_arriving(BASE + 3, 80, 50)], "units": []}
	pl.sync(obs)
	assert_eq(pl.own_squads(), [3, BASE + 3], "the same small ID in both spaces stays apart")
	assert_eq(pl.placeable(), [BASE + 3], "only the reinforcement can be placed")
	pl.select([3, BASE + 3])
	pl.drag([3, BASE + 3], BASE + 3, Vector2(-30, 0))
	assert_false(pl.placements.has(3), "the battle squad is not placed")
	assert_eq(_m(pl.placements[BASE + 3]), Vector2(60, 50), "clamped to the arrival area's edge")
	pl.nudge(Vector2(0, 1))
	assert_false(pl.placements.has(3))
	pl.move_to(Vector2(40, 40))
	var orders := pl.orders()
	assert_eq(orders.size(), 1)
	assert_eq(int(orders[0]["squad"]), 3, "orders reach the battle squad only")
	assert_eq(_m(orders[0]), Vector2(40, 40), "the formation centre ignores the reinforcement")
	assert_eq(pl.deployment(), [])
	assert_eq(pl.arrival().size(), 1)
	obs["arrival_area"] = []
	obs["squads"] = [obs["squads"][0]]
	pl.sync(obs)  # the Reveal: it arrived, the view no longer has it
	assert_eq(pl.placements, {}, "its placement leaves with it")
	assert_false(pl.can_deploy())


## The joiner's war room: player 2's field commander walks into the bandit
## camp battle of the demo (as if it had reached the battle tile), so its
## squads arrive at the next Reveal.
func _joiner() -> Array:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	var s := w.session
	var plot := Hex.plot(11, 3, s.rules.width)
	var eid := s.state.engagement_at(plot)
	assert_gt(eid, -1, "the demo fights the bandit camp")
	var c := Commanders.spawn(s.state, 2, "field_commander", plot)
	s.state.commanders.set_value(c, &"engagement", eid)  # as OverworldMovement does on entering the tile
	OverworldBattleforce.deploy(s.state, c, eid)
	w.view_as(2)
	w._refresh()
	w.contexts.focus_battle(eid)
	w._refresh()
	return [w, eid]


func test_a_joiner_sees_only_its_area_and_squads_before_reveal() -> void:
	var r := _joiner()
	var w: WarRoom = r[0]
	var eid: int = r[1]
	var s := w.session
	w._main.queue_redraw()
	await get_tree().process_frame  # the battle view draws the arrival area and squads
	assert_eq(s.observe_battle(2, eid), {}, "no battle observation before Reveal")
	var a := s.arrival(2, eid)
	assert_false(a.is_empty())
	var obs := w._obs_battle(eid)
	assert_true(obs.get("arrival", false))
	assert_eq(obs["arrival_area"], a["area"], "its arrival area")
	assert_eq(obs["areas"], [], "no other side's area")
	assert_eq(w.planner(eid).areas.size(), 1, "the planner shows its arrival area only")
	var ids := []
	for q: Dictionary in obs["squads"]:
		ids.append(q["id"])
		assert_eq(q["player"], 2)
	var want := []
	for q: Dictionary in a["squads"]:
		want.append(WarRoom.ARRIVAL_BASE + int(q["squad"]))
	assert_eq(ids, want, "its arriving squads, at their shown places")
	assert_eq(obs["units"], [], "nothing else of the battle is drawn")


func test_a_joiner_places_its_squads_and_they_spawn_there_at_reveal() -> void:
	var r := _joiner()
	var w: WarRoom = r[0]
	var eid: int = r[1]
	var s := w.session
	var pl := w.planner(eid)
	assert_true(w.deploying_now(pl), "the joiner can place in Planning")
	var a := s.arrival(2, eid)
	var area: PackedInt64Array = a["area"]
	var first: int = a["squads"][0]["squad"]
	var shown := WarRoom.ARRIVAL_BASE + first
	var logged := s.input_log.size()
	pl.select([shown])  # a selection drafts no orders before Reveal
	assert_eq(s.input_log.size(), logged, "selecting logs nothing")
	w._on_deploy_dragged([shown], shown, Vector2(2, 0))
	var placed: Dictionary = pl.placements[shown]
	assert_true(_inside(area, placed), "the drop is inside its area")
	var kinds := []
	for i in range(logged, s.input_log.size()):
		kinds.append(s.input_log[i]["kind"])
	assert_eq(kinds, ["arrival"], "submitted through submit_arrival only")
	var sent: Dictionary = s.arrival(2, eid)["squads"].filter(func(q: Dictionary) -> bool: return q["squad"] == first)[0]
	assert_true(sent["placed"])
	assert_eq(int(sent["x"]), int(placed["x"]))
	assert_eq(int(sent["y"]), int(placed["y"]))
	# Reveal: the squad spawns at the placed point.
	for p in s.players():
		s.ready(p)
	var b: OverworldBattle = s.battles[eid]
	var row := b.state.squads.row_of(_bid_of(b, first))
	assert_gt(row, -1, "the squad is in the battle after Reveal")
	assert_eq(int(b.state.squads.ax[row]), int(placed["x"]))
	assert_eq(int(b.state.squads.ay[row]), int(placed["y"]))


func _bid_of(b: OverworldBattle, id: int) -> int:
	for bid: int in b.links:
		if b.links[bid] == id:
			return bid
	return -1


func _inside(r: PackedInt64Array, p: Dictionary) -> bool:
	return int(p["x"]) >= r[0] and int(p["y"]) >= r[1] and int(p["x"]) <= r[0] + r[2] and int(p["y"]) <= r[1] + r[3]
