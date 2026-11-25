class_name BattleCursor
extends RefCounted
## The exact battle state at any tick of one recorded turn (sw-tho3.7, U1
## B7). Playback frames carry positions and activity but not orders,
## targets, engagement or weapons; the cursor re-simulates the turn from its
## start snapshot to the tick asked for, on a private copy, so tools
## (relations at a playback moment, the behaviour workshop, capture) read the
## full state without a new frame format.
##
## Read-only: the real battle is never touched. The copy plans into its own
## route cache (a fork of the battle's, BattleRoute.fork) and runs on its
## own BattleSim with no tick hook, on the caller's thread. Seeks are lazy: a forward seek steps on from where the copy
## is; a backward one (or a long jump) restarts from the nearest keyframe at
## or before the tick. Keyframes are snapshots the recorder takes every
## KEY_EVERY ticks of the real turn, so a seek steps at most 2 * KEY_EVERY
## - 2 ticks: a real turn on a large battle costs over a second, far past
## the seek budget (100 ms on the 200 x 100 fixture).
##
## The cursor checks itself: every restored snapshot must hash like the real
## state did at that tick, its content (data-package hash) must match the
## rules, a keyframe stepped through and the turn's end must hash like the
## real ones (`verify` checks the whole turn). On any mismatch it
## reports `available() == false` with a `reason` instead of showing a state
## that diverged. A record without a snapshot (an old replay or save) gives
## an unavailable cursor, never an error.

## Snapshot record format (`capture`).
const VERSION: int = 1
## Ticks between keyframes.
const KEY_EVERY: int = 5

## Why the cursor is unavailable ("" while it is available).
var reason: String = ""
## Ticks in the turn: seek(0) is the turn's start, seek(ticks) its end.
var ticks: int = 0

var _rec: Dictionary = {}
var _rules: BattleRules
var _state: BattleState
var _sim: BattleSim
## Ticks run on _state this turn; -1 before the first restore.
var _at: int = -1
var _resolved: bool = false
## Keyframe ticks ascending (0 = the turn's start) -> {"state", "hash", "log"}.
var _keys: Dictionary = {}
var _key_ticks: PackedInt64Array = PackedInt64Array()
## The real turn's log (SimEvent data), restored up to a keyframe's length.
var _log: Array = []


## The turn-start record the cursor needs, taken just before the turn runs
## (after the turn's orders are applied). The recorder calls `keyframe`
## after every tick, then `seal` once the turn has resolved.
static func capture(state: BattleState) -> Dictionary:
	return {"version": VERSION, "state": state.snapshot(), "start_hash": state.state_hash_hex(),
		"data_hash": state.rules.data_hash, "scenario": state.rules.scenario_id,
		"ticks": state.rules.ticks_per_turn, "keys": [], "end_hash": "", "log": []}


## Called by the recorder after tick `t` (1-based) of the turn; keeps a
## keyframe every KEY_EVERY ticks (not the last tick: the end is resolved
## from it anyway). Read-only on the state.
static func keyframe(record: Dictionary, state: BattleState, t: int) -> void:
	if record.is_empty() or t <= 0 or t % KEY_EVERY != 0 or t >= int(record["ticks"]):
		return
	(record["keys"] as Array).append({"tick": t, "state": state.snapshot(),
		"hash": state.state_hash_hex(), "log": state.turn_log.size()})


## Adds the real end state's hash and the turn's log once the turn ran.
static func seal(record: Dictionary, state: BattleState) -> void:
	if record.is_empty():
		return
	record["end_hash"] = state.state_hash_hex()
	var log := []
	for e in state.turn_log:
		log.append(e.to_dict())
	record["log"] = log


## `snapshot` is a `capture` record ({} or null for none); `rules` the
## battle's compiled rules (shared read-only; routes go to a private copy).
func _init(snapshot: Variant, rules: BattleRules) -> void:
	if typeof(snapshot) != TYPE_DICTIONARY or (snapshot as Dictionary).is_empty():
		reason = "no snapshot recorded for this turn"
		return
	_rec = snapshot
	if int(_rec.get("version", 0)) != VERSION or not _rec.has("state"):
		reason = "unknown snapshot format"
		return
	if rules == null:
		reason = "no rules"
		return
	if String(_rec.get("data_hash", "")) != rules.data_hash or String(_rec.get("scenario", "")) != rules.scenario_id:
		reason = "content differs from the recording's (different mods or version)"
		return
	ticks = int(_rec.get("ticks", rules.ticks_per_turn))
	if ticks != rules.ticks_per_turn:
		reason = "turn length differs from the recording's"
		return
	_keys[0] = {"state": _rec["state"], "hash": String(_rec.get("start_hash", "")), "log": 0}
	_key_ticks.append(0)
	for k: Dictionary in _rec.get("keys", []):
		_keys[int(k["tick"])] = k
		_key_ticks.append(int(k["tick"]))
	_key_ticks.sort()
	_log = _rec.get("log", [])
	_rules = rules.forecast_copy()
	# Start from the battle's answers (every plan the turn used), writing
	# into the copy's own cache: same results, without re-planning cold.
	_rules.routes = rules.routes.fork()
	Stats.warm(rules)
	Fixed.warm()
	_sim = BattleSim.new()
	_restore(0)


func available() -> bool:
	return reason == ""


## The state after `tick` ticks of the turn (clamped to 0..ticks); at
## `ticks` the turn is also resolved, so it is the real end state. Null when
## unavailable. Read-only use: the next seek may change or replace it.
func seek(tick: int) -> BattleState:
	return _seek(tick, true)


## The state after `tick` ticks with the turn not yet resolved: exactly what
## the recorder's tick hook saw at that tick, and the last playback frame
## (frame `ticks`). seek(ticks) is the resolved end and differs from it.
## Same copy and checks as seek.
func seek_unresolved(tick: int) -> BattleState:
	return _seek(tick, false)


func _seek(tick: int, resolve: bool) -> BattleState:
	if not available():
		return null
	PerfRecorder.begin(&"battle_cursor")
	var t := clampi(tick, 0, ticks)
	var base := _key_at_or_before(t)
	# Restore when behind (or past the end, or back before the resolution);
	# jump to the keyframe when more than a span behind; from the span just
	# before it, step through so the keyframe's hash checks the re-simulation.
	if t < _at or (_resolved and (t < ticks or not resolve)) or _at < base - KEY_EVERY:
		_restore(base)
	while available() and _at < t:
		_sim.runner.step(_state)
		_at += 1
		if _keys.has(_at) and _state.state_hash_hex() != String(_keys[_at]["hash"]):
			_fail("re-simulation diverged from the recording at tick %d" % _at)
	if available() and resolve and t == ticks and not _resolved:
		BattleSim.resolve_turn(_state)
		_resolved = true
		var want := String(_rec.get("end_hash", ""))
		if want != "" and _state.state_hash_hex() != want:
			_fail("re-simulation diverged from the recorded turn end")
	PerfRecorder.end(&"battle_cursor")
	return _state if available() else null


## Re-simulates the whole turn from its start, checking every keyframe and
## the end against the recording; false (and unavailable) on a mismatch.
## Seeks check what they step through; this checks everything at once.
func verify() -> bool:
	if not available():
		return false
	_restore(0)
	for t in range(1, ticks + 1):
		if seek(t) == null:
			break
	return available()


## Ticks the copy is at (-1 when unavailable).
func at() -> int:
	return _at if available() else -1


## SHA-256 of the cursor's current state (empty when unavailable).
func state_hash() -> PackedByteArray:
	return _state.state_hash() if available() else PackedByteArray()


func state_hash_hex() -> String:
	return state_hash().hex_encode()


func _key_at_or_before(t: int) -> int:
	var best := 0
	for k in _key_ticks:
		if k > t:
			break
		best = k
	return best


func _restore(key_tick: int) -> void:
	var k: Dictionary = _keys[key_tick]
	var snap: Dictionary = k["state"]
	_state = BattleState.new(int(snap["id"]), _rules)
	_state.restore(snap)
	# The ticks before the keyframe logged these; resolution reads them.
	var n := int(k["log"])
	if n > 0:
		if _log.size() < n:
			_fail("snapshot incomplete: the turn's log is missing")
			return
		_state.turn_log = SimContext._events_from_data(_log.slice(0, n))
	Centroids.update(_state)
	_at = key_tick
	_resolved = false
	if _state.state_hash_hex() != String(k["hash"]):
		_fail("snapshot incomplete: the restored state at tick %d hashes differently" % key_tick)


func _fail(why: String) -> void:
	reason = why
	_state = null
	_at = -1
