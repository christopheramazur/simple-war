extends GutTest
## Transport interface, loopback and packet format (sw-5x6.2).


func test_loopback_delivers_in_order() -> void:
	var ts := LoopbackTransport.hub(PackedInt32Array([1, 2, 3]))
	var got := []
	ts[1].packet_received.connect(func(f: int, d: PackedByteArray) -> void: got.append([f, d.size()]))
	ts[0].send(2, PackedByteArray([1]))
	ts[2].send(2, PackedByteArray([1, 2]))
	assert_eq(got, [])
	ts[1].poll()
	assert_eq(got, [[1, 1], [3, 2]])
	assert_eq(ts[0].peers(), PackedInt32Array([2, 3]))
	for t in ts:
		t.close()


func test_broadcast_and_close() -> void:
	var ts := LoopbackTransport.hub(PackedInt32Array([1, 2]))
	var gone := []
	ts[0].peer_disconnected.connect(func(p: int) -> void: gone.append(p))
	ts[0].poll()
	ts[1].close()
	ts[0].poll()
	assert_eq(gone, [2])
	assert_false(ts[0].send(2, PackedByteArray([1])))
	ts[0].close()


func test_packet_roundtrip() -> void:
	var o := NetPacket.decode(NetPacket.orders(4, 1, [{"a": 1}, "x"]))
	assert_eq(o, {"kind": NetPacket.Kind.ORDERS, "turn": 4, "epoch": 1, "orders": [{"a": 1}, "x"]})
	var pkt := {"turn": 2, "epoch": 0, "orders": {1: ["a"], 3: []}}
	var s := NetPacket.decode(NetPacket.sealed(pkt))
	assert_eq(s["orders"], pkt["orders"])
	assert_eq(NetPacket.decode(NetPacket.claim_host(3))["epoch"], 3)
	assert_eq(NetPacket.decode(NetPacket.state_hash(5, "ab12"))["hash"], "ab12")


func test_malformed_packets_rejected() -> void:
	assert_eq(NetPacket.decode(PackedByteArray()), {})
	assert_eq(NetPacket.decode(PackedByteArray([0, 1, 1])), {})
	var good := NetPacket.orders(1, 0, [])
	assert_eq(NetPacket.decode(good.slice(0, 8)), {})


func test_lockstep_over_loopback() -> void:
	var ids := PackedInt32Array([1, 2])
	var ts := LoopbackTransport.hub(ids)
	var ls := [LockstepSession.new(1, ids), LockstepSession.new(2, ids)]
	for l in ls:
		l.begin_turn(0)
	# peer 2 sends orders to host 1
	ts[1].send(1, NetPacket.orders(1, 0, ["move"]))
	ts[0].packet_received.connect(func(from: int, d: PackedByteArray) -> void:
		var p := NetPacket.decode(d)
		ls[0].submit(from, p["turn"], p["epoch"], p["orders"]))
	ts[1].packet_received.connect(func(from: int, d: PackedByteArray) -> void:
		var p := NetPacket.decode(d)
		ls[1].apply_sealed(p, from))
	ts[0].poll()
	ls[0].submit(1, 1, 0, ["hold"])
	var sealed: Dictionary = ls[0].seal(1)
	ts[0].broadcast(NetPacket.sealed(sealed))
	ts[1].poll()
	assert_true(ls[1].is_sealed())
	assert_eq(ls[1].sealed, ls[0].sealed)
	for t in ts:
		t.close()


func test_steam_unavailable_without_singleton() -> void:
	if SteamTransport.is_available():
		pending("Steam present")
		return
	var t := SteamTransport.new()
	assert_false(t.attach_lobby(1))
	assert_false(t.send(1, PackedByteArray()))
	t.poll()
