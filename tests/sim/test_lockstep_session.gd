extends GutTest
## Per-turn lockstep, host sequencer, epoch migration (sw-5x6.1).


func _trio() -> Array:
	var s := PackedInt32Array([1, 2, 3])
	return [LockstepSession.new(1, s), LockstepSession.new(2, s), LockstepSession.new(3, s)]


func _begin(ps: Array, t: int) -> void:
	for p in ps:
		p.begin_turn(t)


func test_host_seals_when_all_submit() -> void:
	var ps := _trio()
	_begin(ps, 0)
	var h: LockstepSession = ps[0]
	assert_true(h.is_host())
	assert_true(h.submit(2, 1, 0, ["b"]))
	assert_true(h.submit(1, 1, 0, ["a"]))
	assert_eq(h.seal(10), {})
	assert_false(h.submit(2, 1, 0, ["x"]), "duplicate refused")
	h.submit(3, 1, 0, [])
	var pkt := h.seal(10)
	assert_eq(pkt["orders"].keys(), [1, 2, 3])
	assert_true(ps[1].apply_sealed(pkt, 1))
	assert_eq(ps[1].sealed, h.sealed)


func test_deadline_seals_with_missing_orders() -> void:
	var h: LockstepSession = _trio()[0]
	h.begin_turn(1000)
	h.submit(1, 1, 0, ["a"])
	assert_eq(h.seal(1000 + 59999), {})
	var pkt := h.seal(1000 + 60000)
	assert_eq(pkt["orders"][3], [])


func test_migration_picks_next_live_peer() -> void:
	var ps := _trio()
	_begin(ps, 0)
	assert_eq(ps[1].drop_peer(1), 2)
	assert_eq(ps[1].epoch, 1)
	assert_true(ps[1].is_host())
	ps[2].drop_peer(1)
	assert_eq(ps[2].host, 2, "peers agree on the successor")
	assert_false(ps[1].submit(3, 1, 0, []), "stale epoch refused")
	assert_true(ps[1].submit(3, 1, 1, []))


func test_conflicting_host_claim_flagged() -> void:
	var ps := _trio()
	_begin(ps, 0)
	assert_false(ps[2].claim_host(2, 0))
	assert_eq(ps[2].flags[0], {"peer": 2, "reason": "host_claim"})
	ps[2].apply_sealed({"turn": 1, "epoch": 0, "orders": {1: []}}, 1)
	ps[2].apply_sealed({"turn": 1, "epoch": 0, "orders": {1: ["z"]}}, 1)
	assert_eq(ps[2].flags[1]["reason"], "conflicting_seal")


func test_desync_detected() -> void:
	var h: LockstepSession = _trio()[0]
	h.begin_turn(0)
	var seen := []
	h.desync.connect(func(t, bad): seen.append([t, bad]))
	h.report_hash(1, 1, "aa")
	h.report_hash(2, 1, "aa")
	assert_eq(seen.size(), 0)
	h.report_hash(3, 1, "bb")
	assert_eq(seen.size(), 1)
	assert_eq(Array(seen[0][1]), [3])
