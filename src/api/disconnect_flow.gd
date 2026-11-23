class_name DisconnectFlow
extends RefCounted
## Multiplayer disconnect handling (GDD 02 §2.12, sw-5x6.3). Transport-free and
## clock-free: callers pass a msec timestamp. The host's copy is authoritative;
## other peers take its decision through apply_resolution().
##
## Pause on a drop; 30 s reconnect countdown; then the live players vote
## (Drop = AI takes over, not in ranked; End; Return to lobby; or keep waiting).
## Threshold is majority+1 of the live voters (capped at all of them), falling
## to a simple majority 30 s later. End and Lobby both count toward ending; the
## larger wins (tie: Lobby). Decision recorded in sw-5x6.3 notes.

signal paused(peers: PackedInt32Array)
signal resumed
signal vote_opened
signal resolved(resolution: Dictionary)

enum Phase { RUNNING, COUNTDOWN, VOTING, DONE }
enum Vote { WAIT, DROP, END, LOBBY }

const COUNTDOWN_MSEC := 30000
const RELAX_MSEC := 30000

var local_peer: int
var host: int
var ranked: bool
var sides: Dictionary  ## peer id -> side id (for the ranked forfeit)
var phase: Phase = Phase.RUNNING
var disconnected: Dictionary = {}  ## peer id -> true (waiting for reconnect)
var ai_peers: Dictionary = {}  ## peer id -> true (AI took over)
var resolution: Dictionary = {}
var _all: Array = []
var _countdown_start: int = 0
var _vote_start: int = 0
var _votes: Dictionary = {}  ## voter peer -> Vote


func _init(local: int, host_peer: int, peers: PackedInt32Array, is_ranked: bool = false, peer_sides: Dictionary = {}) -> void:
	local_peer = local
	host = host_peer
	ranked = is_ranked
	sides = peer_sides
	for p in peers:
		_all.append(p)


func is_host() -> bool:
	return host == local_peer


## True while gameplay is locked (turn timers should not run).
func is_paused() -> bool:
	return phase == Phase.COUNTDOWN or phase == Phase.VOTING


## Lobby chat stays available through every phase.
func chat_allowed() -> bool:
	return true


func status(peer: int) -> String:
	if ai_peers.has(peer):
		return "ai"
	return "disconnected" if disconnected.has(peer) else "connected"


func countdown_left_msec(now: int) -> int:
	if phase != Phase.COUNTDOWN:
		return 0
	return maxi(0, _countdown_start + COUNTDOWN_MSEC - now)


func peer_dropped(peer: int, now: int) -> void:
	if phase == Phase.DONE or ai_peers.has(peer) or not _all.has(peer):
		return
	disconnected[peer] = true
	_votes.erase(peer)
	if phase == Phase.RUNNING:
		phase = Phase.COUNTDOWN
		_countdown_start = now
		paused.emit(PackedInt32Array(disconnected.keys()))


func peer_reconnected(peer: int) -> void:
	if phase == Phase.DONE or not disconnected.has(peer):
		return
	disconnected.erase(peer)
	if disconnected.is_empty():
		phase = Phase.RUNNING
		_votes.clear()
		resumed.emit()


## The host dropped and migration picked a new one: the flow carries on from
## the new host with a fresh timer so everyone can re-sync first.
func host_migrated(new_host: int, now: int) -> void:
	host = new_host
	if phase == Phase.COUNTDOWN:
		_countdown_start = now
	elif phase == Phase.VOTING:
		_vote_start = now


func live_voters() -> Array:
	var out := []
	for p in _all:
		if not disconnected.has(p) and not ai_peers.has(p):
			out.append(p)
	return out


## Host only: record a live peer's vote. Drop is refused in ranked.
func cast_vote(peer: int, vote: Vote) -> bool:
	if not is_host() or phase != Phase.VOTING:
		return false
	if disconnected.has(peer) or ai_peers.has(peer) or not _all.has(peer):
		return false
	if vote == Vote.DROP and ranked:
		return false
	_votes[peer] = vote
	_check()
	return true


## Host only: advance timers (call each frame/tick).
func update(now: int) -> void:
	if not is_host():
		return
	if phase == Phase.COUNTDOWN and now >= _countdown_start + COUNTDOWN_MSEC:
		phase = Phase.VOTING
		_vote_start = now
		vote_opened.emit()
		_check(now)
	elif phase == Phase.VOTING:
		_check(now)


func needed(now: int = -1) -> int:
	var n := live_voters().size()
	var simple := n / 2 + 1
	if now >= 0 and now >= _vote_start + RELAX_MSEC:
		return simple
	return mini(n, simple + 1)


func _tally(vote: int) -> int:
	var c := 0
	for v in _votes.values():
		if v == vote:
			c += 1
	return c


func _check(now: int = -1) -> void:
	if phase != Phase.VOTING:
		return
	var need := needed(now)
	if need <= 0:
		return
	var drops := _tally(Vote.DROP)
	var ends := _tally(Vote.END)
	var lobbies := _tally(Vote.LOBBY)
	if drops >= need:
		_resolve({"action": "drop", "ai": PackedInt32Array(disconnected.keys())})
	elif ends + lobbies >= need:
		var res := {"action": "end" if ends > lobbies else "lobby"}
		if ranked:
			res.merge(_ranked_result())
		_resolve(res)


## Forfeit for every side with a disconnected peer; void if nobody is left.
func _ranked_result() -> Dictionary:
	if live_voters().is_empty():
		return {"ranked": "void", "forfeit": []}
	var lost := []
	for p in disconnected:
		var s = sides.get(p, p)
		if not lost.has(s):
			lost.append(s)
	lost.sort()
	return {"ranked": "forfeit", "forfeit": lost}


func _resolve(res: Dictionary) -> void:
	var dropping: bool = res["action"] == "drop"
	if dropping:
		for p in res["ai"]:
			ai_peers[p] = true
		disconnected.clear()
		_votes.clear()
		phase = Phase.RUNNING
	else:
		phase = Phase.DONE
	resolution = res
	resolved.emit(res)
	if dropping:
		resumed.emit()


## Non-host peers: take the host's decision.
func apply_resolution(res: Dictionary) -> void:
	if phase == Phase.DONE:
		return
	_resolve(res)


## Everyone dropped: ranked void, no vote possible.
func everyone_gone() -> bool:
	return live_voters().is_empty() and not _all.is_empty()
