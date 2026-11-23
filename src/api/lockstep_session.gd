class_name LockstepSession
extends RefCounted
## Per-turn lockstep bookkeeping for one peer (GDD 04 §4.6, sw-5x6.1).
## Transport-free: a transport feeds it packets and sends what it returns.
## The host sequencer collects each turn's orders and seals them; every peer
## keeps the current turn's sealed orders. Host migration is epoch-based with a
## deterministic successor (next live peer in slot order). Deadlines are a
## turn-start timestamp plus a duration, so peers need no shared clock ticks.
## State hashes are compared at the end of each turn to detect desyncs.

signal turn_sealed(turn: int, orders: Dictionary)
signal host_changed(epoch: int, host: int)
signal desync(turn: int, peers: PackedInt32Array)
signal flagged(peer: int, reason: String)

var local_peer: int
var slots: PackedInt32Array  ## Peer ids in slot order; fixed for the match.
var alive: Dictionary = {}  ## peer id -> true
var epoch: int = 0
var host: int
var turn: int = 0
var turn_start_msec: int = 0
var turn_duration_msec: int = 60000
var sealed: Dictionary = {}  ## sealed orders of the current turn (empty until sealed)
var flags: Array = []  ## [{peer, reason}]
var _orders: Dictionary = {}  ## peer -> Array, this turn's collected orders
var _is_sealed: bool = false
var _hashes: Dictionary = {}  ## turn -> {peer -> hash}


func _init(local: int, peer_slots: PackedInt32Array, duration_msec: int = 60000) -> void:
	local_peer = local
	slots = peer_slots
	turn_duration_msec = duration_msec
	for p in slots:
		alive[p] = true
	host = _next_live(0)


func is_host() -> bool:
	return host == local_peer


## The first live peer at or after slot index `from` (wrapping).
func _next_live(from: int) -> int:
	for i in slots.size():
		var p := slots[(from + i) % slots.size()]
		if alive.has(p):
			return p
	return -1


func begin_turn(now_msec: int) -> void:
	turn += 1
	turn_start_msec = now_msec
	_orders.clear()
	sealed = {}
	_is_sealed = false


func deadline_msec() -> int:
	return turn_start_msec + turn_duration_msec


func past_deadline(now_msec: int) -> bool:
	return now_msec >= deadline_msec()


func is_sealed() -> bool:
	return _is_sealed


## Host only: record a peer's orders for the current turn. Late, stale-epoch or
## duplicate submissions are refused. Returns true when accepted.
func submit(peer: int, for_turn: int, for_epoch: int, orders: Array) -> bool:
	if not is_host() or _is_sealed or for_turn != turn or for_epoch != epoch:
		return false
	if not alive.has(peer) or _orders.has(peer):
		return false
	_orders[peer] = orders
	return true


func all_submitted() -> bool:
	for p in slots:
		if alive.has(p) and not _orders.has(p):
			return false
	return true


## Host only: seal once everyone submitted or the deadline passed. Returns the
## packet to broadcast ({turn, epoch, orders}), or {} when not ready.
func seal(now_msec: int) -> Dictionary:
	if not is_host() or _is_sealed or not (all_submitted() or past_deadline(now_msec)):
		return {}
	var ordered := {}
	for p in slots:  # slot order keeps the packet deterministic
		ordered[p] = _orders.get(p, [])
	_finish_seal(ordered)
	return {"turn": turn, "epoch": epoch, "orders": ordered}


## Any peer: take the host's sealed packet. A packet from a stale epoch or the
## wrong turn is refused; a non-host sender or a conflicting second seal flags it.
func apply_sealed(packet: Dictionary, from_peer: int) -> bool:
	if packet.get("turn", -1) != turn or packet.get("epoch", -1) != epoch:
		return false
	if from_peer != host:
		_flag(from_peer, "host_claim")
		return false
	if _is_sealed:
		if packet["orders"] != sealed:
			_flag(from_peer, "conflicting_seal")
		return false
	_finish_seal(packet["orders"])
	return true


func _finish_seal(ordered: Dictionary) -> void:
	sealed = ordered
	_is_sealed = true
	turn_sealed.emit(turn, sealed)


## A peer dropped (or the host stopped answering). If it was the host, the epoch
## advances and the next live peer takes over. Returns the host.
func drop_peer(peer: int) -> int:
	var was_host := peer == host
	alive.erase(peer)
	if was_host:
		migrate()
	return host


func migrate() -> void:
	epoch += 1
	# Successor: next live peer after the old host in slot order.
	host = _next_live(slots.find(host) + 1)
	host_changed.emit(epoch, host)


## What a new host rebroadcasts after migration: the current turn's sealed
## orders, which every peer keeps. Empty if this turn was not sealed here.
func resend_packet() -> Dictionary:
	if not _is_sealed:
		return {}
	return {"turn": turn, "epoch": epoch, "orders": sealed}


## Another peer claims to be host for an epoch. Anything but the deterministic
## successor is flagged (conflicting host claims, GDD 04 §4.6).
func claim_host(peer: int, for_epoch: int) -> bool:
	if for_epoch == epoch and peer == host:
		return true
	_flag(peer, "host_claim")
	return false


## Record a peer's end-of-turn state hash; emits `desync` with the minority
## peers once every live peer has reported.
func report_hash(peer: int, for_turn: int, hash_hex: String) -> void:
	var m: Dictionary = _hashes.get(for_turn, {})
	m[peer] = hash_hex
	_hashes[for_turn] = m
	for p in slots:
		if alive.has(p) and not m.has(p):
			return
	var counts := {}
	for p in m:
		counts[m[p]] = int(counts.get(m[p], 0)) + 1
	_hashes.erase(for_turn)
	if counts.size() < 2:
		return
	var best := ""
	for h in counts:
		if best == "" or counts[h] > counts[best]:
			best = h
	var bad := PackedInt32Array()
	for p in m:
		if m[p] != best:
			bad.append(p)
	desync.emit(for_turn, bad)


func _flag(peer: int, reason: String) -> void:
	flags.append({"peer": peer, "reason": reason})
	flagged.emit(peer, reason)
