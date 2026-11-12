extends GutTest
## Presentation contexts and camera rules (GDD 04 §4.8, R2Q19, R3Q20,
## R4Q15). Task sw-ip8.2. Observations are hand-built, shaped like
## OverworldSession.observe; the last test uses the war room's demo session.

const A := 11   # own commander fighting battle 100 on plot 5
const B := 12   # own commander fighting battle 200 on plot 9
const C := 13   # own commander on plot 20, not fighting
const E := 21   # enemy commander in battle 200


func _obs(battles: Array = [[100, 5], [200, 9]]) -> Dictionary:
	var cmds := [
		{"id": A, "player": 1, "plot": 5, "engagement": 100},
		{"id": B, "player": 1, "plot": 9, "engagement": 200},
		{"id": C, "player": 1, "plot": 20, "engagement": -1},
		{"id": E, "player": 2, "plot": 9, "engagement": 200},
	]
	var bts := []
	for bt: Array in battles:
		bts.append({"engagement": bt[0], "plot": bt[1], "battle": true})
	bts.append({"engagement": 300, "plot": 40, "battle": true})  # not ours
	return {"commanders": cmds, "detachments": [], "battles": bts}


func _ctx() -> ViewContexts:
	var v := ViewContexts.new(1)
	v.sync(_obs())
	return v


func test_battles_are_the_players_own() -> void:
	var v := _ctx()
	assert_eq(v.battles(), [100, 200] as Array[int])
	assert_eq(v.focus, ViewContexts.OVERWORLD)
	assert_eq(v.camera_plot, 5, "the camera starts on the first own commander")
	assert_eq(v.menu().size(), 2)
	assert_eq(v.menu()[1]["commanders"], [B])


func test_follow_tab_swap_exit_returns_to_followed() -> void:
	var v := _ctx()
	v.follow(C)
	assert_eq(v.camera_plot, 20)
	v.select_commander(B)
	v.follow()
	assert_eq(v.followed, B)
	assert_true(v.tab_in())
	assert_eq(v.focus, 200, "tabs into the followed commander's battle")
	v.cycle(1)
	assert_eq(v.focus, 100, "swaps battles, wrapping")
	v.cycle(-1)
	assert_eq(v.focus, 200)
	v.exit()
	assert_eq(v.focus, ViewContexts.OVERWORLD)
	assert_eq(v.camera_plot, 9, "back on the followed commander")


func test_selecting_another_commander_in_a_battle_exits_to_it() -> void:
	var v := _ctx()
	v.focus_battle(100)
	v.select_commander(A)
	assert_eq(v.focus, 100, "a commander fighting here keeps the battle")
	v.select_commander(C)
	assert_eq(v.focus, ViewContexts.OVERWORLD)
	assert_eq(v.camera_plot, 20)
	assert_eq(v.selected, C)


func test_deselect_all_exits_to_the_battle_hex() -> void:
	var v := _ctx()
	v.follow(C)
	v.focus_battle(200)
	v.deselect_all()
	assert_eq(v.focus, ViewContexts.OVERWORLD)
	assert_eq(v.camera_plot, 9, "the battle's own hex, not the followed commander")
	assert_eq(v.followed, -1)
	assert_eq(v.selected, -1)
	v.deselect_all()
	assert_eq(v.focus, ViewContexts.OVERWORLD, "allowed anywhere")


func test_zooming_in_on_a_battle_hex_enters_it() -> void:
	var v := _ctx()
	v.select_commander(C)
	v.zoom_by(4.0)
	assert_eq(v.focus, ViewContexts.OVERWORLD, "no battle on the hex in context")
	assert_eq(v.zoom, ViewContexts.ZOOM_MAX)
	v.zoom = ViewContexts.ZOOM_DEFAULT
	v.select_hex(9)
	v.zoom_by(2.0)
	assert_eq(v.focus, ViewContexts.OVERWORLD, "below the threshold")
	v.zoom_by(2.0)
	assert_eq(v.focus, 200)
	assert_eq(v.zoom, ViewContexts.ZOOM_DEFAULT, "at the default zoom")


func test_picture_in_picture() -> void:
	var v := _ctx()
	v.focus_battle(100)
	v.pin(100)
	assert_eq(v.pips, [] as Array[int], "the focused battle is not pinned")
	v.pin(200)
	v.pin(300)
	assert_eq(v.pips, [200] as Array[int], "only own battles")
	assert_eq(v.shown(), [100, 200] as Array[int], "two battles at once")
	v.move_pip(200, Vector2(30, 40))
	v.focus_battle(200)
	assert_eq(v.focus, 200)
	assert_eq(v.pips, [100] as Array[int], "swapped places")
	assert_eq(v.pip_offsets[100], Vector2(30, 40), "the view stays where it was moved")


func test_ended_battles_leave_the_view() -> void:
	var v := _ctx()
	v.follow(C)
	v.focus_battle(200)
	v.pin(100)
	v.sync(_obs([[100, 5]]))
	assert_eq(v.focus, ViewContexts.OVERWORLD)
	assert_eq(v.camera_plot, 20, "exits as if by Esc")
	v.sync(_obs([]))
	assert_eq(v.pips, [] as Array[int])


func test_the_war_room_runs_standalone() -> void:
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.demo_view = "pip"
	add_child_autofree(w)
	assert_eq(w.contexts.battles().size(), 2, "the demo has two battles")
	assert_ne(w.contexts.focus, ViewContexts.OVERWORLD)
	assert_eq(w.contexts.pips.size(), 1)
	assert_eq(w._pip_layer.get_child_count(), 1)
	w.contexts.exit()
	await get_tree().process_frame
	assert_eq(w._main.mode, "overworld")
	w.end_turn_requested.emit()
	assert_eq(w.session.turns_resolved(), 2)
