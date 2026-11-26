extends GutTest
## Playback relations at a frame (sw-bafi.5, U1 C5): SquadRelation.facts at
## the state a playback frame shows, read through the turn's BattleCursor.
## A frame equals a tick-hook capture of the real run at the same tick, the
## fog holds, and a record with no snapshot (or no frame) gives [] quietly.

const W := 16
const VIEWERS := [0, 1, 2]

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## A skirmish-like session with a commander marching on the battle (the same
## set-up as test_battle_cursor's session test), keep_playback on.
func _session() -> OverworldSession:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	s.keep_playback = true
	var a := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(12, 4, W))
	assert_eq(s.set_route(1, a, PackedInt64Array([Hex.plot(11, 3, W)])), "")
	return s


## Orders for player 1 in the first battle, then both players ready.
func _turn(s: OverworldSession, fighter: ZoneController) -> void:
	if s.clock.phase == PulseClock.Phase.PLANNING and not s.battles.is_empty():
		var eid0: int = s.battles.keys()[0]
		s.submit_battle_orders(1, eid0, fighter.orders(s.observe_battle(1, eid0)))
	for p in s.players():
		s.ready(p)


func _squad_ids(st: BattleState) -> Array:
	var out := []
	for row in st.squads.count():
		out.append(st.squads.id_at(row))
	return out


## Every viewer's facts for every ordered pair of the given squads at `st`:
## {viewer: {"a-b": facts}}.
func _all_facts(st: BattleState, ids: Array) -> Dictionary:
	var out := {}
	for v: int in VIEWERS:
		var d := {}
		for a: int in ids:
			for b: int in ids:
				if a != b:
					d["%d-%d" % [a, b]] = SquadRelation.facts(st, v, a, b)
		out[v] = d
	return out


## Plays turns until a battle turn is recorded with squads on both sides.
## Returns [session, engagement ID, squad IDs], or [session, -1, []].
func _recorded_battle() -> Array:
	var s := _session()
	var fighter := ZoneController.new(1)
	for i in 40:
		_turn(s, fighter)
		for eid: int in s._playback:
			var at: Dictionary = s.playback(0)[eid]["frames"][0]
			var sides := {}
			for sq: int in at:
				sides[int(at[sq]["player"])] = true
			if sides.size() >= 2 and sides.has(1):
				return [s, eid, at.keys()]
	return [s, -1, []]


## Every recorded frame of a battle turn equals what the real run had at the
## same tick: a tick-hook on the battle sim captures the state after each
## tick and after the end of the turn (frame i is tick i), for every viewer
## and every ordered pair of its squads; playback_relation must match them.
func test_relations_at_each_frame_match_a_tick_hook_capture() -> void:
	var s := _session()
	var fighter := ZoneController.new(1)
	var targets := {}  # engagement -> BattleState at the start of the turn
	var ids_of := {}   # engagement -> squad IDs at the start of the turn
	var captured := {}  # engagement -> per tick: _all_facts
	s.battle_sim().tick_hook = func(st: BattleState) -> void:
		for eid: int in targets:
			if targets[eid] == st:
				(captured[eid] as Array).append(_all_facts(st, ids_of[eid]))
	var checked := 0
	var non_empty := 0
	for i in 40:
		targets.clear()
		captured.clear()
		ids_of.clear()
		if s.clock.phase == PulseClock.Phase.PLANNING:
			for eid: int in s.battles:
				var st: BattleState = (s.battles[eid] as OverworldBattle).state
				targets[eid] = st
				ids_of[eid] = _squad_ids(st)
				captured[eid] = []
		_turn(s, fighter)
		for eid: int in s._playback:
			if not captured.has(eid):
				continue
			var frames: Array = s._playback[eid]["frames"]
			var ticks: Array = captured[eid]
			# Frame 0 is the start; frame f is the hook after tick f. The hook
			# runs once more after the turn resolves, which no frame shows.
			assert_eq(ticks.size(), frames.size(), "one capture per tick, and the resolved end")
			var ids: Array = ids_of[eid]
			for f in range(1, frames.size()):
				var want: Dictionary = ticks[f - 1]
				for v: int in VIEWERS:
					for a: int in ids:
						for b: int in ids:
							if a == b:
								continue
							var got := s.playback_relation(v, eid, f, a, b)
							assert_eq(got, want[v]["%d-%d" % [a, b]], "viewer %d frame %d pair %d-%d" % [v, f, a, b])
							non_empty += int(not got.is_empty())
			checked += 1
		if checked >= 2:
			break
	assert_gt(checked, 0, "some battle turn was recorded")
	assert_gt(non_empty, 0, "some relation was shown")


## The fog: a squad a player cannot see gives no facts about it, and a
## player sees nothing of a battle it did not fight in.
func test_hidden_enemies_give_nothing() -> void:
	var made := _recorded_battle()
	var s: OverworldSession = made[0]
	var eid: int = made[1]
	assert_ne(eid, -1, "a battle turn with both sides was recorded")
	if eid == -1:
		return
	var ids: Array = made[2]
	var hidden := 0
	var frames: Array = s._playback[eid]["frames"]
	var seen_by_one: Array = s.playback(1)[eid]["frames"]
	for f in frames.size():
		var visible: Dictionary = seen_by_one[f]
		for a: int in ids:
			for b: int in ids:
				if a == b or not visible.has(a) or visible.has(b):
					continue
				hidden += 1
				assert_eq(s.playback_relation(1, eid, f, a, b), [], "frame %d: %d sees nothing of hidden %d" % [f, a, b])
	assert_gt(hidden, 0, "some squad was hidden from player 1")
	assert_eq(s.playback_relation(3, eid, 0, ids[0], ids[1]), [], "a player who did not fight here gets nothing")


## Frames map to ticks explicitly: frame i is tick i, and anything past the
## last tick is the resolved end.
func test_frame_maps_to_tick() -> void:
	assert_eq(OverworldSession.tick_of_frame(0, 5), 0)
	assert_eq(OverworldSession.tick_of_frame(3, 5), 3)
	assert_eq(OverworldSession.tick_of_frame(5, 5), 5)
	assert_eq(OverworldSession.tick_of_frame(6, 5), 5, "the resolved end")
	assert_eq(OverworldSession.tick_of_frame(-2, 5), 0)


## Old or missing records give [] with no error: no snapshot, an unknown
## frame, no record at all, or a battle that was not recorded.
func test_no_snapshot_or_frame_gives_nothing() -> void:
	var made := _recorded_battle()
	var s: OverworldSession = made[0]
	var eid: int = made[1]
	assert_ne(eid, -1, "a battle turn with both sides was recorded")
	if eid == -1:
		return
	var a: int = made[2][0]
	var b: int = made[2][1]
	assert_gt((s.playback(0)[eid]["frames"] as Array).size(), 1)
	assert_eq(s.playback_relation(0, 12345, 1, a, b), [], "no battle this turn")
	assert_eq(s.playback_relation(0, eid, -1, a, b), [], "before the start")
	assert_eq(s.playback_relation(0, eid, 9999, a, b), [], "past the last frame")
	var rec: Dictionary = s._playback[eid]
	rec.erase("cursor")
	rec["start"] = {}
	assert_eq(s.playback_relation(0, eid, 2, a, b), [], "no start snapshot")
	rec["start"] = null
	assert_eq(s.playback_relation(0, eid, 2, a, b), [], "a null snapshot")
	rec.erase("start")
	assert_eq(s.playback_relation(0, eid, 2, a, b), [], "an old record without a snapshot")
	assert_false(s.turn_cursor(eid).available(), "and its cursor says so")


## The replay viewer reads the same answers through MatchReplay.
func test_match_replay_gives_the_session_answers() -> void:
	var made := _recorded_battle()
	var s: OverworldSession = made[0]
	var eid: int = made[1]
	assert_ne(eid, -1, "a battle turn with both sides was recorded")
	if eid == -1:
		return
	var r := MatchReplay.new()
	r.session = s
	var ids: Array = made[2]
	var f := (s._playback[eid]["frames"] as Array).size() - 1
	assert_eq(r.playback_relation(0, eid, f, ids[0], ids[1]), s.playback_relation(0, eid, f, ids[0], ids[1]))
	assert_eq(r.playback_relation(0, 12345, f, ids[0], ids[1]), [])
