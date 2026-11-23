extends GutTest
## LockstepSession wired to MatchDriver (sw-5x6.6).


func _pair() -> Array:
	var slots := PackedInt32Array([1, 2])
	var out: Array = []
	for peer in [1, 2]:
		var s := MatchDriver.play_session("skirmish_mirror", 7)
		var d := MatchDriver.new(s, peer)
		out.append(LockstepDriver.new(d, LockstepSession.new(peer, slots), {1: 1, 2: 2}))
	return out


func test_two_peers_resolve_a_turn_in_step() -> void:
	var ps := _pair()
	if ps[0].match_driver.session == null:
		pending("map unavailable")
		return
	for p in ps:
		p.begin_turn(0)
	var host: LockstepDriver = ps[0]
	var guest: LockstepDriver = ps[1]
	var pkt := host.submit_local(1)
	assert_eq(pkt, {})
	pkt = host.receive_orders(2, 1, 0, guest.local_orders(), 1)
	assert_false(pkt.is_empty())
	host.apply_orders(host.lockstep.sealed)
	guest.submit_local(1)
	assert_true(guest.apply_sealed(pkt, 1))
	assert_eq(host.match_driver.session.turns_resolved(), guest.match_driver.session.turns_resolved())
	assert_eq(host.match_driver.session.state_hash_hex(), guest.match_driver.session.state_hash_hex())


func test_foreign_orders_are_flagged() -> void:
	var ps := _pair()
	for p in ps:
		p.begin_turn(0)
	var host: LockstepDriver = ps[0]
	var fake := [{"turn": 1, "phase": 0, "player": 1, "kind": "route", "payload": {}}]
	host.apply_orders({1: [], 2: fake})
	assert_eq(host.lockstep.flags.size(), 1)
