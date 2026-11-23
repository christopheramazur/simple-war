class_name LockstepDriver
extends RefCounted
## Drives a MatchDriver from a LockstepSession (GDD 04 §4.6, sw-5x6.6).
## Transport-free like LockstepSession: the caller sends what these return.
## Each peer plays one player. The local player's orders are applied live as
## the UI issues them; `local_orders` collects them from the session's input
## log for submission. When the host seals a turn, `apply_sealed` replays
## every other peer's orders, readies the humans, resolves the turn and
## reports the end-of-turn state hash. Orders a peer sends for a player that
## is not its own are dropped and flagged.

signal turn_resolved(turn: int, hash_hex: String)

var match_driver: MatchDriver
var lockstep: LockstepSession
## Peer id -> player number.
var players: Dictionary = {}
var _mark: int = 0


func _init(driver: MatchDriver, lock: LockstepSession, peer_players: Dictionary) -> void:
	match_driver = driver
	lockstep = lock
	players = peer_players


func local_player() -> int:
	return int(players[lockstep.local_peer])


## Starts the next lockstep turn; orders issued from now on belong to it.
func begin_turn(now_msec: int) -> void:
	lockstep.begin_turn(now_msec)
	_mark = match_driver.session.input_log.size()


## The local player's orders since the turn began (the "ready" and "advance"
## inputs are the lockstep's job, not an order).
func local_orders() -> Array:
	var out: Array = []
	var log: Array = match_driver.session.input_log
	for i in range(_mark, log.size()):
		var e: Dictionary = log[i]
		if int(e["player"]) == local_player() and e["kind"] != "ready" and e["kind"] != "advance":
			out.append(e.duplicate(true))
	return out


## Submits the local orders to the local sequencer (what the host does for
## itself; other peers send `local_orders()` to the host). Returns the sealed
## packet if that completed the turn, else {}.
func submit_local(now_msec: int) -> Dictionary:
	lockstep.submit(lockstep.local_peer, lockstep.turn, lockstep.epoch, local_orders())
	return lockstep.seal(now_msec)


## Host only: take a remote peer's orders, sealing when all are in. Returns
## the packet to broadcast, or {}.
func receive_orders(peer: int, for_turn: int, for_epoch: int, orders: Array, now_msec: int) -> Dictionary:
	lockstep.submit(peer, for_turn, for_epoch, orders)
	return lockstep.seal(now_msec)


## Host only: seals at the deadline even if some peers are missing.
func seal_if_due(now_msec: int) -> Dictionary:
	return lockstep.seal(now_msec)


## Any peer: take the host's sealed packet. On acceptance, applies the other
## peers' orders in slot order, readies every player, resolves the turn and
## reports the state hash. Returns whether the turn was applied.
func apply_sealed(packet: Dictionary, from_peer: int) -> bool:
	if not lockstep.apply_sealed(packet, from_peer):
		return false
	apply_orders(lockstep.sealed)
	return true


## Also used by the host after `seal` (its own sealing produced the orders).
func apply_orders(sealed: Dictionary) -> void:
	var s := match_driver.session
	for peer: int in lockstep.slots:
		if peer == lockstep.local_peer or not players.has(peer):
			continue
		var accepted: Array = []
		for e: Variant in sealed.get(peer, []):
			if e is Dictionary and int(e.get("player", -1)) == int(players[peer]) \
					and e.get("kind") != "ready" and e.get("kind") != "advance":
				accepted.append(e)
			else:
				lockstep._flag(peer, "foreign_order")
		s.replay_inputs(accepted)
	var turn := lockstep.turn
	match_driver.end_turn()
	var h := s.state_hash_hex()
	lockstep.report_hash(lockstep.local_peer, turn, h)
	turn_resolved.emit(turn, h)
