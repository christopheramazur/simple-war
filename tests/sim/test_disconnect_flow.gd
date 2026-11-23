extends GutTest
## Disconnect flow (sw-5x6.3, GDD 02 §2.12).

var P := PackedInt32Array([1, 2, 3, 4])


func _flow(ranked := false) -> DisconnectFlow:
	return DisconnectFlow.new(1, 1, P, ranked, {1: "a", 2: "a", 3: "b", 4: "b"})


func _to_vote(f: DisconnectFlow, drop := 4) -> void:
	f.peer_dropped(drop, 0)
	f.update(DisconnectFlow.COUNTDOWN_MSEC)


func test_pause_and_countdown() -> void:
	var f := _flow()
	f.peer_dropped(4, 100)
	assert_true(f.is_paused())
	assert_true(f.chat_allowed())
	assert_eq(f.status(4), "disconnected")
	assert_eq(f.countdown_left_msec(10100), 20000)
	f.update(29999)
	assert_eq(f.phase, DisconnectFlow.Phase.COUNTDOWN)


func test_reconnect_resumes() -> void:
	var f := _flow()
	f.peer_dropped(4, 0)
	f.peer_reconnected(4)
	assert_false(f.is_paused())
	assert_eq(f.status(4), "connected")


func test_drop_vote_relaxes_to_simple_majority() -> void:
	var f := _flow()
	_to_vote(f)  # 3 live voters: need 3, 2 after 30 s more
	f.cast_vote(1, DisconnectFlow.Vote.DROP)
	f.cast_vote(2, DisconnectFlow.Vote.DROP)
	assert_eq(f.phase, DisconnectFlow.Phase.VOTING)
	f.update(DisconnectFlow.COUNTDOWN_MSEC + DisconnectFlow.RELAX_MSEC)
	assert_false(f.is_paused())
	assert_eq(f.resolution["action"], "drop")
	assert_eq(f.status(4), "ai")


func test_unanimous_drop_resolves_at_once() -> void:
	var f := _flow()
	_to_vote(f)
	for p in [1, 2, 3]:
		f.cast_vote(p, DisconnectFlow.Vote.DROP)
	assert_eq(f.resolution["action"], "drop")


func test_end_and_lobby_both_count_toward_ending() -> void:
	var f := _flow()
	_to_vote(f)
	f.cast_vote(1, DisconnectFlow.Vote.END)
	f.cast_vote(2, DisconnectFlow.Vote.LOBBY)
	f.cast_vote(3, DisconnectFlow.Vote.LOBBY)
	assert_eq(f.resolution["action"], "lobby")
	assert_eq(f.phase, DisconnectFlow.Phase.DONE)


func test_wait_vote_blocks() -> void:
	var f := _flow()
	_to_vote(f)
	f.cast_vote(1, DisconnectFlow.Vote.END)
	f.cast_vote(2, DisconnectFlow.Vote.WAIT)
	f.cast_vote(3, DisconnectFlow.Vote.WAIT)
	assert_true(f.resolution.is_empty())


func test_ranked_refuses_drop_and_forfeits() -> void:
	var f := _flow(true)
	_to_vote(f)
	assert_false(f.cast_vote(1, DisconnectFlow.Vote.DROP))
	for p in [1, 2, 3]:
		f.cast_vote(p, DisconnectFlow.Vote.END)
	assert_eq(f.resolution["ranked"], "forfeit")
	assert_eq(f.resolution["forfeit"], ["b"])


func test_ranked_void_when_everyone_dropped() -> void:
	var f := _flow(true)
	for p in [2, 3, 4, 1]:
		f.peer_dropped(p, 0)
	assert_true(f.everyone_gone())
	assert_eq(f._ranked_result()["ranked"], "void")


func test_only_host_votes_and_non_host_applies() -> void:
	var f := DisconnectFlow.new(2, 1, P)
	f.peer_dropped(4, 0)
	f.update(DisconnectFlow.COUNTDOWN_MSEC)
	assert_false(f.cast_vote(2, DisconnectFlow.Vote.END))
	f.apply_resolution({"action": "end"})
	assert_eq(f.phase, DisconnectFlow.Phase.DONE)


func test_host_migration_restarts_countdown() -> void:
	var f := DisconnectFlow.new(2, 1, P)
	f.peer_dropped(1, 0)
	f.host_migrated(2, 5000)
	assert_true(f.is_host())
	f.update(DisconnectFlow.COUNTDOWN_MSEC)
	assert_eq(f.phase, DisconnectFlow.Phase.COUNTDOWN)
	f.update(5000 + DisconnectFlow.COUNTDOWN_MSEC)
	assert_eq(f.phase, DisconnectFlow.Phase.VOTING)
