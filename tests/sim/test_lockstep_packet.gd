extends GutTest
## Lockstep wire format and transport (sw-5x6.7).


func test_roundtrip_each_type() -> void:
	var o := LockstepPacket.decode(LockstepPacket.orders(3, 1, [{"player": 1, "kind": "move"}]))
	assert_eq(o["type"], LockstepPacket.Type.ORDERS)
	assert_eq(o["body"]["orders"], [{"player": 1, "kind": "move"}])
	var pk := {"turn": 2, "epoch": 0, "orders": {1: [], 2: [{"a": 1}]}}
	assert_eq(LockstepPacket.decode(LockstepPacket.sealed(pk))["body"], pk)
	assert_eq(LockstepPacket.decode(LockstepPacket.host_claim(4))["body"]["epoch"], 4)
	assert_eq(LockstepPacket.decode(LockstepPacket.state_hash(5, "ab"))["body"]["hash"], "ab")


func test_not_json() -> void:
	assert_ne(LockstepPacket.orders(1, 0, [])[4], 0x7B)  # '{'


func test_malformed_rejected() -> void:
	assert_eq(LockstepPacket.decode(PackedByteArray()), {})
	assert_eq(LockstepPacket.decode(PackedByteArray([1, 2, 3, 4, 5])), {})
	var bad := LockstepPacket.orders(1, 0, [])
	bad[2] = 99  # version
	assert_eq(LockstepPacket.decode(bad), {})
	var trunc := LockstepPacket.state_hash(1, "abc")
	assert_eq(LockstepPacket.decode(trunc.slice(0, 6)), {})
	var wrong := PackedByteArray([0x53, 0x57, 1, LockstepPacket.Type.HASH])
	wrong.append_array(var_to_bytes({"turn": "x", "hash": 1}))
	assert_eq(LockstepPacket.decode(wrong), {})


func test_objects_refused() -> void:
	var evil := PackedByteArray([0x53, 0x57, 1, LockstepPacket.Type.HOST_CLAIM])
	evil.append_array(var_to_bytes_with_objects(RefCounted.new()))
	assert_eq(LockstepPacket.decode(evil), {})
	assert_eq(LockstepPacket.decode(evil.slice(0, 6)), {})


func test_transport_two_peers() -> void:
	var slots := PackedInt32Array([1, 2])
	var ds: Array = []
	var ts: Array = []
	for peer in [1, 2]:
		var s := MatchDriver.play_session("skirmish_mirror", 7)
		if s == null:
			pending("map unavailable")
			return
		var d := LockstepDriver.new(MatchDriver.new(s, peer), LockstepSession.new(peer, slots), {1: 1, 2: 2})
		ds.append(d)
		ts.append(LockstepTransport.new(d))
	ts[0].links[2] = func(b): ts[1].receive(1, b, 1)
	ts[1].links[1] = func(b): ts[0].receive(2, b, 1)
	for d in ds:
		d.begin_turn(0)
	ts[0].send_local_orders(1)
	ts[1].send_local_orders(1)
	assert_true(ds[0].lockstep.is_sealed())
	assert_true(ds[1].lockstep.is_sealed())
	assert_eq(ds[0].lockstep.sealed, ds[1].lockstep.sealed)
	assert_false(ts[0].receive(9, LockstepPacket.host_claim(0), 1))
	assert_false(ts[0].receive(2, PackedByteArray([1]), 1))
	assert_eq(ds[0].lockstep.flags.back()["reason"], "malformed_packet")
	ts[0].links.clear()  # break the closure cycle
	ts[1].links.clear()
