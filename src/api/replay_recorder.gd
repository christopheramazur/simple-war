class_name ReplayRecorder
extends RefCounted
## Turns a replay (a save: initial snapshot + input log) into per-tick frames
## for playback, by re-simulating it with a read-only tick hook (R5Q19, R8Q5).
## The viewer only ever sees these frames, never the live state.

## Unit fields per frame entry, in order.
const STRIDE: int = 6
const F_ID: int = 0
const F_PLAYER: int = 1
const F_X: int = 2
const F_Y: int = 3
const F_HP: int = 4
const F_SQUAD: int = 5

var rules: BattleRules
## One PackedInt64Array per recorded tick: STRIDE ints per living unit.
var frames: Array[PackedInt64Array] = []
## Events per frame (Array of SimEvent dicts), same length as frames.
var events: Array[Array] = []
## Turn number per frame (the turn being executed).
var frame_turn: PackedInt64Array = PackedInt64Array()
## Zone owner/amount per frame.
var zone_owner: Array[PackedInt64Array] = []
var zone_amount: Array[PackedInt64Array] = []
## Scores per frame: [p1 influence, p1 value, p2 influence, p2 value, ...].
var scores: Array[PackedInt64Array] = []
var result: Dictionary = {}
var players: PackedInt64Array = PackedInt64Array()

var _last_tick: int = -1


## Re-simulates a save and records every tick. Null if the save can't be
## rebuilt with this content.
static func from_save(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> ReplayRecorder:
	var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var data: Variant = bytes_to_var(raw) if not raw.is_empty() else null
	if typeof(data) != TYPE_DICTIONARY or data.get("data_hash") != hash_hex:
		return null
	var session := BattleSession.create(templates, hash_hex, data["scenario"], data["seed"], BattleSession._config_from(data["clock_config"]))
	var rec := ReplayRecorder.new()
	rec._attach(session)
	session.replay_inputs(data["inputs"])
	rec.result = session.state.result.duplicate(true)
	return rec


## Plays a fresh battle with the given controllers and records it.
static func from_duel(templates: TemplateTable, hash_hex: String, scenario: String, seed_value: int, controllers: Dictionary) -> ReplayRecorder:
	var session := BattleSession.create(templates, hash_hex, scenario, seed_value)
	var rec := ReplayRecorder.new()
	rec._attach(session)
	HeadlessDuel.play(session, controllers)
	rec.result = session.state.result.duplicate(true)
	rec.save_bytes = session.save()
	return rec


## The replay as a save, when recorded from a live duel.
var save_bytes: PackedByteArray = PackedByteArray()


func _attach(session: BattleSession) -> void:
	rules = session.rules
	players = session.players()
	_capture(session.state)
	session.sim.tick_hook = _capture


func _capture(state: BattleState) -> void:
	var u := state.units
	var sq := state.squads
	var f := PackedInt64Array()
	f.resize(u.count() * STRIDE)
	for row in u.count():
		var srow := sq.row_of(u.squad[row])
		var o := row * STRIDE
		f[o + F_ID] = u.id_at(row)
		f[o + F_PLAYER] = sq.player[srow] if srow >= 0 else 0
		f[o + F_X] = u.x[row]
		f[o + F_Y] = u.y[row]
		f[o + F_HP] = u.hp[row]
		f[o + F_SQUAD] = u.squad[row]
	frames.append(f)
	var evs := []
	if state.tick != _last_tick:
		# Events of the tick that just ended carry tick == state.tick - 1.
		var i := state.turn_log.size() - 1
		while i >= 0 and state.turn_log[i].tick == state.tick - 1:
			i -= 1
		for j in range(i + 1, state.turn_log.size()):
			evs.append(state.turn_log[j].to_dict())
		_last_tick = state.tick
	events.append(evs)
	frame_turn.append(state.turn + 1)
	zone_owner.append(state.zone_owner.duplicate())
	zone_amount.append(state.zone_amount.duplicate())
	var sc := PackedInt64Array()
	for p in state.players:
		sc.append(int(state.influence[p]))
		sc.append(int(state.value_score[p]))
	scores.append(sc)
