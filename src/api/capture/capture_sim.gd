class_name CaptureSim
extends BattleSim
## The capture runner's recorder (sw-tho3.9, U1 B9): a BattleSim that keeps
## every turn it executes as an OverworldSession.record_turn record (the
## format ContextView.show_playback draws), per battle, and takes truth at
## the frames asked for. Whatever drives the battle (a BattleSession, a
## WorkshopRun, an OverworldSession's battles) runs on it unchanged: the
## driver's own tick hook still runs first, every tick.
##
## Read-only: recording and truth only read the state, so the state hash is
## the same as on a plain BattleSim (tested).
##
## Frame k of a turn is the state after k ticks of it, before the turn
## resolves (frame 0 its start, orders applied), as in playback.

## Battle (BattleState.id) -> Array of record_turn records, in turn order.
## Each also has "first_tick" (the state's tick at the turn's start).
var turns: Dictionary = {}
## Battle -> {Vector2i(turn index, frame): true}: where to take truth.
var want: Dictionary = {}
## Viewers to take truth for (0 = all-seeing; a player not in the battle is
## skipped).
var viewers: PackedInt64Array = PackedInt64Array([0])
## Also take a WorkshopDebug frame (the control render's overlay).
var debug: bool = false
## Battle -> {Vector2i(turn index, frame): {"probe": {viewer: BattleProbe
## snapshot}, "obs": {viewer: BattleSession.observe_state}, "debug":
## WorkshopDebug frame (when debug)}}.
var truth: Dictionary = {}

var _inside: bool = false
var _routes: BattleRoute
var _bid: int = 0
var _ti: int = 0
var _k: int = 0


func execute_turn(state: BattleState) -> void:
	if _inside:  # record_turn runs the turn on this sim: the real Execute
		super(state)
		return
	_inside = true
	var list: Array = turns.get(state.id, [])
	_bid = state.id
	_ti = list.size()
	_k = 0
	var first := state.tick
	var ticks := state.rules.ticks_per_turn
	_take(state, 0)
	var outer := tick_hook
	tick_hook = func(st: BattleState) -> void:
		if outer.is_valid():
			outer.call(st)
		_k += 1
		if _k <= ticks:
			_take(st, _k)
	var rec := OverworldSession.record_turn(self, state)
	tick_hook = outer
	rec["first_tick"] = first
	list.append(rec)
	turns[state.id] = list
	_inside = false


func _take(st: BattleState, frame: int) -> void:
	var key := Vector2i(_ti, frame)
	if not (want.get(_bid, {}) as Dictionary).has(key):
		return
	var probes := {}
	var obs := {}
	for v in viewers:
		if v > 0 and not st.players.has(v):
			continue
		probes[v] = BattleProbe.snapshot(st, v)
		obs[v] = BattleSession.observe_state(st, v)
	var entry := {"probe": probes, "obs": obs}
	if debug:
		if _routes == null:
			_routes = BattleRoute.new()
		entry["debug"] = WorkshopDebug.capture(st, _routes)
	var per: Dictionary = truth.get(_bid, {})
	per[key] = entry
	truth[_bid] = per
