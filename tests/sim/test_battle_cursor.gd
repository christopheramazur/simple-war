extends GutTest
## BattleCursor (sw-tho3.7, U1 B7): lazy re-simulation of one recorded battle
## turn to tick N on a private copy. Ends match the real turn, backward seeks
## restart, bad or missing snapshots report unavailable, and a full-turn seek
## on the 200 x 100 fixture stays inside its budget.

const ONE := Fixed.ONE
const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## duel_crossroads on a w x h open (or walled) map, `per_side` rifle squads
## a side, ordered across; returns [state, rules].
func _battle(w: int, h: int, per_side: int, walls: bool = false) -> Array:
	var defs := _l().defs.duplicate()
	var cells := []
	if walls:
		for i in range(1, w / 20):
			cells.append({"feature": "wall", "x": i * 20, "y": 0 if i % 2 == 0 else 20, "h": h - 20})
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": w, "height": h, "base": "open", "cells": cells}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t", _l().data_hash)
	assert_eq(r.errors, PackedStringArray())
	var s := BattleState.new(1, r, 1)
	var ids: Array = [[], []]
	for i in per_side:
		for p in [1, 2]:
			var x: int = 5 + (i % 4) * 3 + (0 if p == 1 else w - 15)
			var y: int = 10 + (i / 4) * 12
			ids[p - 1].append(BattleSetup.spawn_squad(s, p, r.squad_index("rifle_squad"), x * ONE, y * ONE, 0))
	Centroids.update(s)
	for p in [1, 2]:
		var orders := []
		for i in ids[p - 1].size():
			var gx: int = (w - 10 - (i % 4) * 3) if p == 1 else 10 + (i % 4) * 3
			orders.append({"squad": ids[p - 1][i], "type": "move", "x": gx * ONE, "y": (15 + (i / 4) * 12) * ONE})
		assert_eq(BattleOrders.apply(s, p, orders).size(), 0)
	return [s, r]


## Runs the real turn with a capture around it; returns [record, end hash].
func _record(s: BattleState) -> Array:
	var rec := BattleCursor.capture(s)
	var sim := BattleSim.new()
	var n := [0]
	sim.tick_hook = func(st: BattleState) -> void:
		n[0] += 1
		BattleCursor.keyframe(rec, st, n[0])
	sim.execute_turn(s)
	BattleCursor.seal(rec, s)
	return [rec, s.state_hash_hex()]


func test_last_frame_matches_the_real_end_state() -> void:
	var made := _battle(60, 40, 2)
	var s: BattleState = made[0]
	var start := s.state_hash_hex()
	var out := _record(s)
	var c := BattleCursor.new(out[0], made[1])
	assert_true(c.available(), c.reason)
	assert_eq(c.ticks, (made[1] as BattleRules).ticks_per_turn)
	assert_eq(c.seek(0).state_hash_hex(), start, "tick 0 is the turn's start")
	var end := c.seek(c.ticks)
	assert_not_null(end)
	assert_eq(c.state_hash_hex(), out[1])
	assert_eq(end.turn, s.turn)
	assert_true(c.available(), c.reason)


func test_backward_seek_restarts_and_matches_a_fresh_forward_seek() -> void:
	var made := _battle(60, 40, 2)
	var out := _record(made[0])
	var mid := (made[1] as BattleRules).ticks_per_turn / 2
	var fresh := BattleCursor.new(out[0], made[1])
	var want := fresh.seek(mid).state_hash_hex()
	var c := BattleCursor.new(out[0], made[1])
	c.seek(c.ticks)
	assert_eq(c.at(), c.ticks)
	c.seek(mid)
	assert_eq(c.at(), mid)
	assert_eq(c.state_hash_hex(), want)
	# Forward again, through the resolution, still ends on the real end.
	c.seek(c.ticks)
	assert_eq(c.state_hash_hex(), out[1])


func test_forward_seeks_are_incremental() -> void:
	var made := _battle(60, 40, 2)
	var out := _record(made[0])
	var c := BattleCursor.new(out[0], made[1])
	var st := c.seek(1)
	assert_eq(c.at(), 1)
	assert_same(c.seek(BattleCursor.KEY_EVERY - 1), st, "a forward seek steps on the same copy")
	assert_eq(c.at(), BattleCursor.KEY_EVERY - 1)
	var far := c.ticks - 2
	c.seek(far)
	assert_eq(c.at(), far, "a long jump starts from the nearest keyframe")
	var no_keys: Dictionary = (out[0] as Dictionary).duplicate()
	no_keys["keys"] = []
	var fresh := BattleCursor.new(no_keys, made[1])
	assert_eq(c.state_hash_hex(), fresh.seek(far).state_hash_hex(), "keyframes equal stepping from the start")
	fresh.seek(fresh.ticks)
	assert_eq(fresh.state_hash_hex(), out[1])


func test_the_real_battle_is_untouched() -> void:
	var made := _battle(60, 40, 2)
	var s: BattleState = made[0]
	var out := _record(s)
	var plans := (made[1] as BattleRules).routes.plans
	var c := BattleCursor.new(out[0], made[1])
	c.seek(c.ticks)
	assert_eq(s.state_hash_hex(), out[1])
	assert_eq((made[1] as BattleRules).routes.plans, plans, "routes plan into the cursor's own cache")


func test_no_snapshot_is_unavailable_without_error() -> void:
	var made := _battle(60, 40, 1)
	for snap: Variant in [{}, null]:
		var c := BattleCursor.new(snap, made[1])
		assert_false(c.available())
		assert_ne(c.reason, "")
		assert_null(c.seek(3))
		assert_eq(c.state_hash(), PackedByteArray())
		assert_eq(c.at(), -1)


func test_mismatches_are_detected() -> void:
	var made := _battle(60, 40, 2)
	var r: BattleRules = made[1]
	var rec: Dictionary = _record(made[0])[0]
	var bad_content := rec.duplicate()
	bad_content["data_hash"] = "not-the-content"
	assert_false(BattleCursor.new(bad_content, r).available(), "data-package hash differs")
	var old_format := rec.duplicate()
	old_format["version"] = 0
	assert_false(BattleCursor.new(old_format, r).available())
	var missing := rec.duplicate(true)
	(missing["state"] as Dictionary)["rng"] = PackedInt64Array([1, 2, 3, 4])
	var c := BattleCursor.new(missing, r)
	assert_false(c.available(), "a snapshot that restores differently")
	assert_string_contains(c.reason, "snapshot")
	var no_log := rec.duplicate()
	no_log["log"] = []
	var nl := BattleCursor.new(no_log, r)
	assert_null(nl.seek(nl.ticks - 1), "a keyframe without the turn's log")
	assert_false(nl.available())
	var bad_key := rec.duplicate(true)
	((bad_key["keys"] as Array)[0] as Dictionary)["hash"] = "00"
	var bk := BattleCursor.new(bad_key, r)
	assert_true(bk.available())
	assert_not_null(bk.seek(BattleCursor.KEY_EVERY - 1))
	assert_null(bk.seek(BattleCursor.KEY_EVERY + 1), "stepping past a keyframe that hashes differently")
	assert_string_contains(bk.reason, "diverged")
	assert_false(BattleCursor.new(bad_key, r).verify())
	var good := BattleCursor.new(rec, r)
	assert_true(good.verify(), good.reason)
	var diverged := rec.duplicate()
	diverged["end_hash"] = "00"
	var d := BattleCursor.new(diverged, r)
	assert_true(d.available())
	assert_not_null(d.seek(4))
	assert_null(d.seek(d.ticks), "a diverging end is reported, not shown")
	assert_false(d.available())
	assert_string_contains(d.reason, "diverged")


## Effects that ended last turn still have to return maxima to base on the
## next tick: the snapshot keeps the flag that drives it.
func test_snapshot_keeps_fx_had_mods() -> void:
	var made := _battle(60, 40, 1)
	var s: BattleState = made[0]
	s.fx_had_mods = true
	var copy := BattleState.new(s.id, made[1])
	copy.restore(s.snapshot())
	assert_true(copy.fx_had_mods)


## Every battle turn OverworldSession records: frame i is the cursor's tick
## i, and the cursor's end is the battle's real end of turn.
func test_session_turns_match_playback_frames() -> void:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	s.keep_playback = true
	var a := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(12, 4, W))
	assert_eq(s.set_route(1, a, PackedInt64Array([Hex.plot(11, 3, W)])), "")
	var fighter := ZoneController.new(1)
	var checked := 0
	for i in 40:
		if s.clock.phase == PulseClock.Phase.PLANNING and not s.battles.is_empty():
			var eid0: int = s.battles.keys()[0]
			s.submit_battle_orders(1, eid0, fighter.orders(s.observe_battle(1, eid0)))
		for p in s.players():
			s.ready(p)
		for eid: int in s._playback:
			var rec: Dictionary = s._playback[eid]
			var c := s.turn_cursor(eid)
			assert_true(c.available(), c.reason)
			if not c.available():
				return
			var frames: Array = rec["frames"]
			for t in c.ticks:
				assert_eq(OverworldSession._frame(c.seek(t)), frames[t], "frame %d" % t)
			# The last frame is the last tick before resolution.
			assert_eq(OverworldSession._frame(c.seek_unresolved(c.ticks)), frames[c.ticks], "the last frame is unresolved")
			c.seek(c.ticks)
			assert_eq(c.state_hash_hex(), rec["start"]["end_hash"])
			if s.battles.has(eid):
				assert_eq(c.state_hash_hex(), (s.battles[eid] as OverworldBattle).state.state_hash_hex())
			checked += 1
		s._playback = {}
		if checked >= 3:
			break
	assert_gt(checked, 0, "some battle turn was recorded")
	assert_false(s.turn_cursor(12345).available(), "no record: unavailable")


## Budget (sw-tho3.7): a full-turn forward seek on the 200 x 100 comb with
## 48 squads (user://battle_cursor.txt), under 100 ms from a new cursor.
func test_full_turn_seek_budget_on_200x100() -> void:
	var made := _battle(200, 100, 24, true)
	var r: BattleRules = made[1]
	r.routes.warm(r)
	var out := _record(made[0])
	# Build cost, then a cold and a warm full seek (the second restarts).
	var t0 := Time.get_ticks_usec()
	var c := BattleCursor.new(out[0], r)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	c.seek(c.ticks)
	var cold_ms := (Time.get_ticks_usec() - t1) / 1000.0
	assert_eq(c.state_hash_hex(), out[1])
	c.seek(0)
	var t2 := Time.get_ticks_usec()
	c.seek(c.ticks)
	var warm_ms := (Time.get_ticks_usec() - t2) / 1000.0
	var t3 := Time.get_ticks_usec()
	c.seek(0)
	for t in range(1, c.ticks + 1):
		c.seek(t)
	var stepped_ms := (Time.get_ticks_usec() - t3) / 1000.0
	# The same full turn from the start alone (no keyframes): what one
	# re-simulated turn costs, and what tick-by-tick seeks must stay near.
	var no_keys: Dictionary = (out[0] as Dictionary).duplicate()
	no_keys["keys"] = []
	var whole := BattleCursor.new(no_keys, r)
	whole.seek(0)
	var t4 := Time.get_ticks_usec()
	whole.seek(whole.ticks)
	var whole_ms := (Time.get_ticks_usec() - t4) / 1000.0
	assert_eq(whole.state_hash_hex(), out[1])
	var line := "BATTLE_CURSOR squads=48 ticks=%d build=%.1fms seek_cold=%.1fms seek_warm=%.1fms stepped=%.1fms no_keys=%.1fms" % [
		c.ticks, build_ms, cold_ms, warm_ms, stepped_ms, whole_ms]
	print(line)
	var fa := FileAccess.open("user://battle_cursor.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://battle_cursor.txt") else FileAccess.WRITE)
	fa.seek_end()
	fa.store_line(line)
	fa.close()
	assert_lt(cold_ms, 100.0, "a new cursor's full-turn seek stays inside its budget")
	assert_lt(warm_ms, 100.0, "a full-turn seek stays inside its budget")
	assert_lt(stepped_ms, whole_ms * 1.5 + 50.0, "tick-by-tick forward seeks are incremental")
