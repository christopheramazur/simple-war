class_name PulseClock
extends RefCounted
## The turn clock. One shared clock drives the overworld and every battle by
## default; independent clocks are just more PulseClock instances (R2Q3).
## Deterministic: time only moves through `advance(ms)` from the caller, never
## from the OS. GDD 02 §2.2, R2Q1.
##
## Turn: PLANNING -> REVEAL -> REACTION (optional) -> EXECUTE -> INTERMISSION.
## - PLANNING: each player gets planning_ms + parallel bonus + reserve; time
##   used past planning_ms + bonus is drawn from reserve (R3Q1, R4Q2).
## - REVEAL: instant; orders become visible.
## - REACTION: per-player window, more battles = more time; no reserve (R3Q1).
## - EXECUTE: not timed; ends when the caller reports `execute_finished()` (R3Q2).
## - INTERMISSION: capped; early drop once half the players are ready (R4Q1).
## Pulse points (where the pulse bus flushes): TURN_START, AFTER_EXECUTE.

enum Phase { IDLE, PLANNING, REVEAL, REACTION, EXECUTE, INTERMISSION }

const POINT_TURN_START: StringName = &"turn_start"
const POINT_AFTER_EXECUTE: StringName = &"after_execute"

signal phase_changed(phase: Phase, turn: int)
signal pulse_point(point: StringName, turn: int)

var config: ClockConfig
var phase: Phase = Phase.IDLE
var turn: int = 0
## Milliseconds spent in the current phase.
var elapsed_ms: int = 0

var _players: Array[int] = []
var _battles: Dictionary = {}
var _reserve: Dictionary = {}
var _ready_at: Dictionary = {}
var _intermission_deadline: int = 0


func _init(clock_config: ClockConfig = null) -> void:
	config = clock_config if clock_config != null else ClockConfig.new()


func add_player(player_id: int) -> void:
	assert(not _players.has(player_id), "PulseClock: duplicate player %d" % player_id)
	_players.append(player_id)
	_players.sort()
	_battles[player_id] = 0
	_reserve[player_id] = config.reserve_start_ms


func players() -> Array[int]:
	return _players.duplicate()


## How many battles the player is in this turn (drives bonus time).
func set_battles(player_id: int, battles: int) -> void:
	_battles[player_id] = battles


func reserve_ms(player_id: int) -> int:
	return _reserve[player_id]


func is_ready(player_id: int) -> bool:
	return _ready_at.get(player_id, -1) >= 0


func start() -> void:
	assert(phase == Phase.IDLE, "PulseClock: already started")
	turn = 1
	pulse_point.emit(POINT_TURN_START, turn)
	_enter(Phase.PLANNING)


func mark_ready(player_id: int) -> void:
	assert(_players.has(player_id), "PulseClock: unknown player %d" % player_id)
	if phase == Phase.EXECUTE or phase == Phase.IDLE or is_ready(player_id):
		return
	_ready_at[player_id] = elapsed_ms
	if phase == Phase.INTERMISSION:
		var ready_count := 0
		for p in _players:
			if is_ready(p):
				ready_count += 1
		if ready_count * 2 >= _players.size():
			_intermission_deadline = mini(_intermission_deadline, elapsed_ms + config.intermission_early_ms)
	_check_end()


## Feeds elapsed real time into the clock; may cross several phases.
func advance(ms: int) -> void:
	var left := ms
	while left > 0:
		var deadline := _phase_deadline()
		if deadline < 0:
			elapsed_ms += left
			return
		var step := mini(left, maxi(deadline - elapsed_ms, 0))
		elapsed_ms += step
		left -= step
		if not _check_end():
			return


func execute_finished() -> void:
	assert(phase == Phase.EXECUTE, "PulseClock: not executing")
	pulse_point.emit(POINT_AFTER_EXECUTE, turn)
	_enter(Phase.INTERMISSION)


## Time the player has left in the current phase, or -1 when untimed.
func remaining_ms(player_id: int) -> int:
	var limit := _player_limit(player_id)
	return -1 if limit < 0 else maxi(limit - elapsed_ms, 0)


func _player_limit(player_id: int) -> int:
	if config.untimed:
		return -1
	match phase:
		Phase.PLANNING:
			return config.planning_ms + config.parallel_bonus_ms(_battles[player_id]) + _reserve[player_id]
		Phase.REACTION:
			return config.reaction_ms_for(_battles[player_id])
		Phase.INTERMISSION:
			return _intermission_deadline
		_:
			return -1


## Elapsed time at which the phase ends if nobody else readies, or -1.
func _phase_deadline() -> int:
	if config.untimed or phase in [Phase.IDLE, Phase.EXECUTE, Phase.REVEAL]:
		return -1
	if phase == Phase.INTERMISSION:
		return _intermission_deadline
	var latest := 0
	for p in _players:
		if not is_ready(p):
			latest = maxi(latest, _player_limit(p))
	return latest


## Ends the phase if every player is ready or out of time. Returns true if it ended.
func _check_end() -> bool:
	if phase in [Phase.IDLE, Phase.EXECUTE]:
		return false
	var all_done := true
	for p in _players:
		if is_ready(p):
			continue
		var limit := _player_limit(p)
		if limit < 0 or elapsed_ms < limit:
			all_done = false
			break
	if not all_done:
		return false
	_end_phase()
	return true


func _end_phase() -> void:
	match phase:
		Phase.PLANNING:
			for p in _players:
				var base := config.planning_ms + config.parallel_bonus_ms(_battles[p])
				var used: int = _ready_at[p] if is_ready(p) else elapsed_ms
				if not config.untimed:
					_reserve[p] = maxi(_reserve[p] - maxi(used - base, 0), 0)
			_enter(Phase.REVEAL)
			_enter(Phase.REACTION if config.reaction_enabled else Phase.EXECUTE)
		Phase.REACTION:
			_enter(Phase.EXECUTE)
		Phase.INTERMISSION:
			turn += 1
			for p in _players:
				_reserve[p] = mini(_reserve[p] + config.reserve_topup_ms, config.reserve_cap_ms)
			pulse_point.emit(POINT_TURN_START, turn)
			_enter(Phase.PLANNING)


func _enter(next: Phase) -> void:
	phase = next
	elapsed_ms = 0
	_ready_at.clear()
	if next == Phase.INTERMISSION:
		_intermission_deadline = config.intermission_cap_ms()
	phase_changed.emit(phase, turn)
