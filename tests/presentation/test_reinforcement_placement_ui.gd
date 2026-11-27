extends GutTest
## Reinforcement placements in the war room (sw-bafi.19, U1 C12): a player
## already fighting a battle sends a reserve in; in Planning the battle view
## shows the arriving squad (under a display ID apart from the battle squad
## IDs) and the arrival area next to its battle squads, the planner places it
## like deployment, placements go through submit_arrival only, orders still
## reach the battle squads, and the squad spawns where placed at the Reveal.

const ROOM := "res://src/presentation/war_room/war_room.tscn"


func _to_planning(s: OverworldSession) -> void:
	var n := 0
	while s.clock.phase != PulseClock.Phase.PLANNING and n < 8:
		n += 1
		for p in s.players():
			s.ready(p)


## The demo war room, player 1 in its first battle past turn 1 (not
## deploying), with one reserve sent in: [war room, eid, overworld squad ID].
func _reinforcer() -> Array:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	var s := w.session
	var eid := -1
	for e: int in s.battles:
		if s.battles[e].state.players.has(1):
			eid = e
			break
	assert_gt(eid, -1, "the demo has a battle of player 1's")
	for p in s.players():
		s.ready(p)
	_to_planning(s)
	assert_true(s.battles.has(eid), "the battle goes on")
	var sent := -1
	var cid := -1
	for g: Dictionary in s.reserves(1, eid):
		for q: Dictionary in g["squads"]:
			if sent < 0 and String(q["why"]).is_empty() and not q["sent"]:
				sent = int(q["squad"])
				cid = int(g["commander"])
	assert_gt(sent, -1, "player 1 has a reserve to send in")
	w.contexts.focus_battle(eid)
	w._refresh()
	assert_eq(w.send_reserve(cid, sent), "")
	w._refresh()
	return [w, eid, sent]


func test_the_reinforcement_shows_next_to_the_battle_squads() -> void:
	var r := _reinforcer()
	var w: WarRoom = r[0]
	var eid: int = r[1]
	var sent: int = r[2]
	var s := w.session
	var battle := s.observe_battle(1, eid)
	assert_false(battle.is_empty())
	var obs := w._obs_battle(eid)
	assert_false(obs.get("arrival", false), "a side already fighting keeps its orders")
	assert_eq(obs["arrival_area"], s.arrival(1, eid)["area"])
	var shown := WarRoom.ARRIVAL_BASE + sent
	var ids := []
	for q: Dictionary in obs["squads"]:
		ids.append(q["id"])
	for q: Dictionary in battle["squads"]:
		assert_true(ids.has(q["id"]), "the battle squads are still there")
	assert_true(ids.has(shown), "the reinforcement is shown")
	var pl := w.planner(eid)
	assert_false(pl.deploying, "past turn 1")
	assert_true(w.deploying_now(pl), "the reinforcement can be placed in Planning")
	assert_eq(pl.placeable(), [shown], "only the reinforcement")
	assert_eq(w._deploy_overlay(pl)["own"], [shown])
	assert_eq(w._phase_text.text, WarRoom.ARRIVAL_BANNER)
	w._main.queue_redraw()
	await get_tree().process_frame  # the battle view draws the arrival area and squad


func test_the_reinforcement_is_placed_and_spawns_there_at_reveal() -> void:
	var r := _reinforcer()
	var w: WarRoom = r[0]
	var eid: int = r[1]
	var sent: int = r[2]
	var s := w.session
	var pl := w.planner(eid)
	var shown := WarRoom.ARRIVAL_BASE + sent
	var area: PackedInt64Array = s.arrival(1, eid)["area"]
	var logged := s.input_log.size()
	w._on_deploy_dragged([shown], shown, Vector2(3, 2))
	var placed: Dictionary = pl.placements[shown]
	assert_true(int(placed["x"]) >= area[0] and int(placed["x"]) <= area[0] + area[2])
	assert_true(int(placed["y"]) >= area[1] and int(placed["y"]) <= area[1] + area[3])
	var kinds := []
	for i in range(logged, s.input_log.size()):
		kinds.append(s.input_log[i]["kind"])
	assert_eq(kinds, ["arrival"], "submitted through submit_arrival only")
	var q: Dictionary = s.arrival(1, eid)["squads"].filter(func(e: Dictionary) -> bool: return e["squad"] == sent)[0]
	assert_true(q["placed"], "the session holds the placement under the overworld ID")
	assert_eq(int(q["x"]), int(placed["x"]))
	# Orders still reach the battle squads, and never the reinforcement.
	var own: int = pl.own_squads().filter(func(id: int) -> bool: return not pl.arriving(id))[0]
	pl.select([own, shown])
	pl.order("hold")
	assert_eq(pl.orders().map(func(o: Dictionary) -> int: return o["squad"]), [own])
	# The Reveal: the reinforcement spawns at the placed point.
	for p in s.players():
		s.ready(p)
	var b: OverworldBattle = s.battles[eid]
	var bid := -1
	for k: int in b.links:
		if b.links[k] == sent:
			bid = k
	var row := b.state.squads.row_of(bid)
	assert_gt(row, -1, "the squad is in the battle after the Reveal")
	assert_eq(int(b.state.squads.ax[row]), int(placed["x"]))
	assert_eq(int(b.state.squads.ay[row]), int(placed["y"]))
