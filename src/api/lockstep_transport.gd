class_name LockstepTransport
extends RefCounted
## Routes encoded LockstepPackets between peers and a LockstepDriver
## (sw-5x6.7). `send` is the only thing a real backend (Steam P2P) overrides;
## `receive` is fed by it with the authenticated sender id.

var driver: LockstepDriver
## Peer id -> Callable(bytes: PackedByteArray); how to reach each remote peer.
var links: Dictionary = {}


func _init(lock_driver: LockstepDriver) -> void:
	driver = lock_driver


func send(peer: int, bytes: PackedByteArray) -> void:
	if links.has(peer):
		links[peer].call(bytes)


func broadcast(bytes: PackedByteArray) -> void:
	for p: int in driver.lockstep.slots:
		if p != driver.lockstep.local_peer and driver.lockstep.alive.has(p):
			send(p, bytes)


## Non-host peers: send the local orders to the host (host submits directly).
func send_local_orders(now_msec: int) -> void:
	var ls := driver.lockstep
	if ls.is_host():
		var sealed_packet := driver.submit_local(now_msec)
		if not sealed_packet.is_empty():
			broadcast(LockstepPacket.sealed(sealed_packet))
			driver.apply_orders(ls.sealed)
	else:
		send(ls.host, LockstepPacket.orders(ls.turn, ls.epoch, driver.local_orders()))


## Host: seal at the deadline if due and broadcast.
func tick(now_msec: int) -> void:
	var p := driver.seal_if_due(now_msec)
	if not p.is_empty():
		broadcast(LockstepPacket.sealed(p))
		driver.apply_orders(driver.lockstep.sealed)


## Handles one packet from `from_peer`. Returns false if it was dropped.
func receive(from_peer: int, bytes: PackedByteArray, now_msec: int) -> bool:
	var ls := driver.lockstep
	if not ls.alive.has(from_peer):
		return false
	var msg := LockstepPacket.decode(bytes)
	if msg.is_empty():
		ls._flag(from_peer, "malformed_packet")
		return false
	var b: Dictionary = msg["body"]
	match int(msg["type"]):
		LockstepPacket.Type.ORDERS:
			if not ls.is_host():
				return false
			var out := driver.receive_orders(from_peer, b["turn"], b["epoch"], b["orders"], now_msec)
			if not out.is_empty():
				broadcast(LockstepPacket.sealed(out))
				driver.apply_orders(ls.sealed)
			return true
		LockstepPacket.Type.SEALED:
			return driver.apply_sealed(b, from_peer)
		LockstepPacket.Type.HOST_CLAIM:
			return ls.claim_host(from_peer, b["epoch"])
		LockstepPacket.Type.HASH:
			ls.report_hash(from_peer, b["turn"], b["hash"])
			return true
	return false
