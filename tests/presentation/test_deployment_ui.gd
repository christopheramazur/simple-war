extends GutTest
## Deployment in the battle view (sw-bafi.12, U1 C11): the planner's
## placement drafts (drag, group drag keeping offsets, clamping a drop outside
## the area to its edge, snapping to a cell the squad can enter, facing
## snapped to eight directions, nudge, reset), and the war room submitting
## them through submit_battle_deployment only, with its banner, hints, reset
## button and overlay.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const ONE := Fixed.ONE


## A planner fed a hand-made observation: a 100 x 100 m field, player 1's
## area x 0-40, player 2's x 60-100; two own squads and an enemy.
func _planner() -> BattlePlanner:
	var pl := BattlePlanner.new(1)
	pl.sync({"width": 100, "height": 100, "deploying": true,
		"area": [0, 0, 40 * ONE, 100 * ONE],
		"areas": [{"player": 1, "facing": 0, "deploy": [0, 0, 40 * ONE, 100 * ONE]},
			{"player": 2, "facing": 32768, "deploy": [60 * ONE, 0, 40 * ONE, 100 * ONE]}],
		"squads": [
			{"id": 1, "player": 1, "template": "rifle_squad", "x": 20 * ONE, "y": 40 * ONE, "facing": 0},
			{"id": 2, "player": 1, "template": "rifle_squad", "x": 30 * ONE, "y": 50 * ONE, "facing": 0},
			{"id": 9, "player": 2, "template": "rifle_squad", "x": 80 * ONE, "y": 50 * ONE, "facing": 32768}],
		"units": [{"id": 11, "squad": 1, "x": 21 * ONE, "y": 40 * ONE}]})
	return pl


func _m(p: Dictionary) -> Vector2:
	return Vector2(float(p["x"]) / ONE, float(p["y"]) / ONE)


func test_a_drag_places_the_squad_inside_the_area() -> void:
	var pl := _planner()
	assert_true(pl.can_deploy())
	assert_eq(pl.area, Rect2(0, 0, 40, 100))
	assert_eq(pl.areas.size(), 2)
	watch_signals(pl)
	pl.drag([1], 1, Vector2(-10, 5))
	assert_signal_emitted(pl, "deploy_changed")
	assert_signal_not_emitted(pl, "changed", "a placement is not an order draft")
	var list := pl.deployment()
	assert_eq(list.size(), 1)
	assert_eq(int(list[0]["squad"]), 1)
	assert_eq(_m(list[0]), Vector2(10, 45))
	assert_true(pl.area.has_point(_m(list[0])))
	assert_true(pl.drafts.is_empty(), "no orders drafted")


func test_a_drop_outside_the_area_is_clamped_to_its_edge() -> void:
	var pl := _planner()
	pl.place(1, Vector2(75, 40))
	assert_eq(_m(pl.placements[1]), Vector2(40, 40), "clamped to the near edge")
	pl.place(1, Vector2(-20, 130))
	assert_eq(_m(pl.placements[1]), Vector2(0, 100), "a corner")
	assert_false(pl.drop_ok(1, Vector2(75, 40)), "the ghost marks the refused drop")
	assert_true(pl.drop_ok(1, Vector2(10, 10)))


func test_a_group_drag_keeps_the_offsets() -> void:
	var pl := _planner()
	pl.select([1, 2])
	pl.drag(pl.selection, 1, Vector2(-15, 10))
	var a := _m(pl.placements[1])
	var b := _m(pl.placements[2])
	assert_eq(a, Vector2(5, 50))
	assert_eq(b - a, Vector2(10, 10), "the group keeps its shape")
	# A second drag starts from the placed positions.
	pl.drag(pl.selection, 2, Vector2(0, -20))
	assert_eq(_m(pl.placements[1]), Vector2(5, 30))
	assert_eq(_m(pl.placements[2]), Vector2(15, 40))


func test_rotate_and_the_facing_handle_snap_to_eight_directions() -> void:
	var pl := _planner()
	var step := BattlePlanner.FACING_STEP
	assert_eq(step, 8192)
	pl.rotate([1], 1)
	assert_eq(int(pl.placements[1]["facing"]), step)
	pl.rotate([1], -3)
	assert_eq(int(pl.placements[1]["facing"]), (-2 * step) & Fixed.ANGLE_MASK, "wraps")
	assert_eq(_m(pl.placements[1]), Vector2(20, 40), "turning keeps the place")
	pl.face([2], Vector2(30, 50) + Vector2(10, 4))  # ~22°: east
	assert_eq(int(pl.placements[2]["facing"]), 0)
	pl.face([2], Vector2(30, 50) + Vector2(10, 7))  # ~35°: south-east
	assert_eq(int(pl.placements[2]["facing"]), step)
	for a in [0, 3000, 5000, 60000, 65535]:
		assert_eq(BattlePlanner.snap_facing(a) % step, 0, "%d snaps to a multiple of an eighth" % a)


func test_nudge_reset_and_the_drawn_view() -> void:
	var pl := _planner()
	pl.select([1])
	pl.nudge(Vector2.RIGHT)
	assert_eq(_m(pl.placements[1]), Vector2(20 + BattlePlanner.NUDGE, 40))
	pl.rotate([1], 2)
	var view := pl.deploy_view({"width": 100, "height": 100,
		"squads": [{"id": 1, "player": 1, "x": 20 * ONE, "y": 40 * ONE, "facing": 0}],
		"units": [{"id": 11, "squad": 1, "x": 21 * ONE, "y": 40 * ONE}]})
	var sq: Dictionary = view["squads"][0]
	assert_true(sq["placed"])
	assert_eq(int(sq["x"]), roundi((20 + BattlePlanner.NUDGE) * ONE))
	var u: Dictionary = view["units"][0]
	assert_almost_eq(float(u["x"]) / ONE, 20 + BattlePlanner.NUDGE, 0.01, "the unit turns with the squad")
	assert_almost_eq(float(u["y"]) / ONE, 41.0, 0.01)
	watch_signals(pl)
	pl.reset_deployment()
	assert_signal_emitted(pl, "deploy_changed")
	assert_true(pl.deployment().is_empty(), "back to the automatic places")
	# Move orders drafted while deploying start from the placed position.
	pl.place(1, Vector2(10, 40))
	pl.move_to(Vector2(30, 40))
	assert_eq(int(pl.drafts[1]["x"]), 30 * ONE)


func test_not_deploying_drops_the_placements_and_refuses_new_ones() -> void:
	var pl := _planner()
	pl.place(1, Vector2(10, 10))
	pl.sync({"width": 100, "height": 100, "deploying": false, "area": [0, 0, 40 * ONE, 100 * ONE],
		"squads": [{"id": 1, "player": 1, "template": "rifle_squad", "x": 20 * ONE, "y": 40 * ONE}]})
	assert_false(pl.can_deploy())
	assert_true(pl.placements.is_empty())
	pl.place(1, Vector2(10, 10))
	assert_true(pl.placements.is_empty())


## With the battle's rules, a drop snaps to a cell the squad can enter, and
## every placement the planner makes passes the simulation's check.
func test_placements_snap_to_enterable_cells_the_sim_accepts() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleSetup.create(1, r, 5)
	s.deploying = r.deployment_open
	assert_true(s.deploying)
	var pl := BattlePlanner.new(1)
	pl.rules = r
	pl.sync(BattleSession.observe_state(s, 1))
	var ids := pl.own_squads()
	assert_false(ids.is_empty())
	var a := pl.area
	for p: Vector2 in [a.position, a.end, a.get_center(), a.end + Vector2(50, 50), Vector2(-5, a.get_center().y)]:
		pl.place(ids[0], p)
		assert_eq(BattleDeploy.validate(s, 1, pl.placements[ids[0]]), "", "the drop at %s is accepted" % p)
	pl.select(ids)
	pl.drag(ids, ids[0], Vector2(1000, 0))
	assert_eq(BattleDeploy.check(s, 1, pl.deployment())["errors"], PackedStringArray(), "a group dragged far off is clamped")


# --- the war room --------------------------------------------------------------

func _room() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	return w


## The demo room focused on a battle that is deploying.
func _deploying_room() -> WarRoom:
	var w := _room()
	assert_true(w.contexts.tab_in())
	var pl := w.planner(w.contexts.focus)
	pl.sync(w.session.observe_battle(1, w.contexts.focus))
	assert_true(w.deploying_now(pl), "the demo battle deploys in its first Planning")
	return w


func test_the_war_room_submits_placements_through_submit_battle_deployment_only() -> void:
	var w := _deploying_room()
	var eid := w.contexts.focus
	var pl := w.planner(eid)
	var b: OverworldBattle = w.session.battles[eid]
	var orders_before: Variant = b.orders.get(1, []).duplicate(true)
	var logged := w.session.input_log.size()
	var id: int = pl.own_squads()[0]
	w._on_deploy_dragged([id], id, Vector2(3, 3))
	var draft: Array = b.deploys.get(1, [])
	assert_eq(draft.size(), 1, "the drag reached the battle's deployment draft")
	assert_eq(int(draft[0]["squad"]), id)
	assert_eq(BattleDeploy.validate(b.state, 1, draft[0]), "")
	assert_eq(b.orders.get(1, []), orders_before, "no orders were submitted for it")
	var kinds := []
	for i in range(logged, w.session.input_log.size()):
		kinds.append(w.session.input_log[i]["kind"])
	assert_eq(kinds, ["battle_deploy"])
	# Rotate key, facing handle and reset go the same way.
	pl.select([id])
	w._on_command(&"rotate", 1)
	assert_eq(int((b.deploys[1] as Array)[0]["facing"]) % BattlePlanner.FACING_STEP, 0)
	w._on_deploy_faced([id], Vector2.ZERO)
	w.reset_deployment()
	assert_eq(b.deploys.get(1, ["x"]), [], "reset to automatic submits an empty draft")


func test_the_war_room_shows_the_deployment_banner_hints_and_reset() -> void:
	var w := _deploying_room()
	var pl := w.planner(w.contexts.focus)
	w._refresh()
	assert_true(w._phase_banner.visible)
	assert_eq(w._phase_text.text, WarRoom.DEPLOY_BANNER)
	assert_string_contains(w.hints(), "Deployment: drag")
	assert_true(w._main._overlay.has("deploy"))
	assert_false((w._main._overlay["deploy"] as Dictionary).is_empty(), "the view draws the areas")
	var reset: Button = w._orders_box.find_child("ResetDeployment", true, false)
	assert_not_null(reset, "Reset to automatic is offered")
	assert_true(reset.disabled, "nothing placed yet")
	pl.select([pl.own_squads()[0]])
	assert_string_contains(w.hints(), "E / Shift+E")
	# Arrows nudge the deploying selection instead of panning.
	w._on_pan(Vector2.RIGHT)
	assert_eq(pl.placements.size(), 1)
	w._refresh()
	reset = w._orders_box.find_child("ResetDeployment", true, false)
	assert_false(reset.disabled)


## A drag in the view itself: press on an own squad, move, release.
func test_dragging_a_squad_in_the_view_emits_a_placement() -> void:
	var w := _deploying_room()
	var pl := w.planner(w.contexts.focus)
	w._refresh()
	await get_tree().process_frame
	var v: ContextView = w._main
	var id: int = pl.own_squads()[0]
	var at := Vector2.ZERO
	for d: Dictionary in v._shown:
		if d["id"] == id:
			at = v.to_view(d["c"])
	assert_ne(at, Vector2.ZERO)
	watch_signals(v)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	v._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = at + Vector2(-40, 0)
	v._gui_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at + Vector2(-40, 0)
	v._gui_input(up)
	assert_signal_emitted(v, "deploy_dragged")
	assert_signal_not_emitted(v, "battle_box", "a squad drag is not a box")
	assert_true(pl.placements.has(id), "the drag placed the squad")
	assert_true(pl.area.has_point(_m(pl.placements[id])) or pl.clamp_to_area(_m(pl.placements[id])) == _m(pl.placements[id]))
