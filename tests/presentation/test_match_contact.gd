extends GutTest
## sw-tho3.21: a match log that reaches a battle. Both sides march their
## commanders at the nearest enemy commander (a scripted route, not the AI),
## so the recording contains battles. The match source must replay it
## hash-checked, leave the log untouched, and give the same answer twice.
## (The capture side - stages, fog views - waits for sw-tho3.9 on main.)

const MAX_TURNS: int = 40


## Routes every commander toward the nearest hostile commander, for each player.
func _march(s: OverworldSession) -> void:
	var st := s.state
	for p: int in s.players():
		for row in st.commanders.count():
			if st.commanders.player[row] != p:
				continue
			var cid := st.commanders.id_at(row)
			var here := st.commanders.plot[row]
			var best := -1
			var best_d := 1 << 30
			for other in st.commanders.count():
				if st.commanders.player[other] == p:
					continue
				var target := st.commanders.plot[other]
				var d := absi(target - here)
				if d < best_d:
					best_d = d
					best = target
			if best < 0:
				continue
			var route := s.path(p, cid, best)
			if not route.is_empty():
				s.set_route(p, cid, route)


## Plays a scripted march until a battle starts (or MAX_TURNS). Returns
## [log folder, session, first turn with a battle (0 if none)].
func _record() -> Array:
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 5)
	add_child_autofree(w)
	assert_not_null(w.match_log)
	var first := 0
	for i in MAX_TURNS:
		_march(w.session)
		w.end_turn_requested.emit()
		if first == 0 and not w.session.battles.is_empty():
			first = i + 1
			break
	return [w.match_log.dir, w.session, first]


func test_a_scripted_march_reaches_a_battle() -> void:
	var made := _record()
	assert_gt(int(made[2]), 0, "no battle in %d turns" % MAX_TURNS)
	var played: OverworldSession = made[1]
	assert_false(played.battles.is_empty())


func test_the_battle_match_replays_hash_checked_and_log_is_untouched() -> void:
	var made := _record()
	var dir: String = made[0]
	var played: OverworldSession = made[1]
	var bytes := FileAccess.get_file_as_bytes(dir + "/match.sav")
	var r := MatchReplay.open(dir)
	assert_not_null(r, MatchReplay.last_error)
	assert_eq(r.turns(), played.turns_resolved())
	var seen_battle := false
	for i in r.turns():
		assert_true(r.step())
		assert_eq(r.session.turn_hashes[i], played.turn_hashes[i], "turn %d hash" % (i + 1))
		if not r.session.battles.is_empty():
			seen_battle = true
	assert_eq(r.diverged_turn, -1)
	assert_true(seen_battle, "the replay shows the battle")
	assert_eq(FileAccess.get_file_as_bytes(dir + "/match.sav"), bytes, "the match log is untouched")


func test_the_same_march_gives_the_same_match() -> void:
	var a := _record()
	var b := _record()
	assert_eq(int(a[2]), int(b[2]), "first battle turn")
	var pa: OverworldSession = a[1]
	var pb: OverworldSession = b[1]
	assert_eq(pa.turn_hashes, pb.turn_hashes)
	assert_eq(pa.state.state_hash_hex(), pb.state.state_hash_hex())
