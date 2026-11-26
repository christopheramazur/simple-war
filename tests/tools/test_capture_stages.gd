extends GutTest
## CaptureStages (src/api/capture/capture_stages.gd): the battle stages found
## from synthetic turn records. No simulation runs here.

const ENGAGED: int = BattleActivity.Squad.ENGAGED
const FALLING_BACK: int = BattleActivity.Squad.FALLING_BACK
const IDLE: int = BattleActivity.Squad.IDLE


## One unit in a playback frame: 16 ints, squad id at o+1, activity at o+12.
func _unit(squad: int, activity: int) -> PackedInt64Array:
	var u := PackedInt64Array()
	u.resize(OverworldSession.PLAYBACK_STRIDE)
	u.fill(0)
	u[1] = squad
	u[12] = activity
	return u


## A frame holding several units, each given as [squad, activity].
func _frame(units: Array) -> PackedInt64Array:
	var f := PackedInt64Array()
	for pair: Array in units:
		f.append_array(_unit(int(pair[0]), int(pair[1])))
	return f


func _turn(first_tick: int, frames: Array, log: Array) -> Dictionary:
	return {"first_tick": first_tick, "frames": frames, "start": {"log": log}}


func _ev(type: String, tick: int, data: Dictionary = {}) -> Dictionary:
	return {"type": type, "tick": tick, "data": data}


func _all_missing(result: Dictionary, reason: String) -> void:
	assert_true((result["stages"] as Dictionary).is_empty(), "no stages")
	for n in CaptureStages.ORDER:
		assert_true((result["missing"] as Dictionary).has(n), n + " is missing")
		assert_eq(result["missing"][n], reason, n)


func test_empty_turns_have_no_squads() -> void:
	_all_missing(CaptureStages.find([]), "no squads")


func test_empty_frames_have_no_squads() -> void:
	var turns := [_turn(0, [PackedInt64Array(), PackedInt64Array()], [_ev("engagement", 1)])]
	_all_missing(CaptureStages.find(turns), "no squads")


func test_no_engagement_means_no_contact() -> void:
	var frames := [_frame([[1, ENGAGED]]), _frame([[1, IDLE]])]
	var turns := [_turn(0, frames, [_ev("unit_killed", 1)])]
	_all_missing(CaptureStages.find(turns), "no contact")


func test_two_turn_battle_stages() -> void:
	var idle := _frame([[1, IDLE], [2, IDLE]])
	var t1 := []
	for k in 11:
		t1.append(idle)
	var t2 := []
	for k in 11:
		t2.append(idle)
	var turns := [
		_turn(0, t1, [_ev("engagement", 3)]),
		_turn(10, t2, [_ev("unit_killed", 12)]),
	]
	var r := CaptureStages.find(turns)
	var s: Dictionary = r["stages"]
	assert_eq(s["deploy"], {"turn": 1, "frame": 0, "tick": 0})
	assert_eq(s["contact"], {"turn": 1, "frame": 4, "tick": 4})
	assert_eq(s["blood"], {"turn": 2, "frame": 3, "tick": 13})
	assert_eq(s["end"], {"turn": 2, "frame": 10, "tick": 20})
	assert_eq(s.has("mid"), false, "nobody is engaged, so no mid")
	assert_eq(r["missing"]["mid"], "no squad engaged")
	assert_eq(r["missing"]["rout"], "no break or fall-back")


func test_mid_is_the_lower_tick_of_a_tie_and_ignores_pre_contact() -> void:
	var f_pre := _frame([[1, ENGAGED], [2, ENGAGED], [3, ENGAGED]])
	var f_one := _frame([[1, ENGAGED]])
	var f_two := _frame([[1, ENGAGED], [2, ENGAGED]])
	var f_idle := _frame([[1, IDLE]])
	# Contact at tick 3 shows at frame 4; frames 0..3 hold more engaged squads
	# but come before contact, so they must not count.
	var frames := [f_pre, f_pre, f_pre, f_pre, f_one, f_two, f_two, f_idle]
	var turns := [_turn(0, frames, [_ev("engagement", 3)])]
	var r := CaptureStages.find(turns)
	assert_eq(r["stages"]["mid"], {"turn": 1, "frame": 5, "tick": 5})


func test_rout_from_morale_break_wins() -> void:
	var idle := _frame([[1, IDLE]])
	var fb := _frame([[1, FALLING_BACK]])
	var frames := [idle, idle, fb, idle, idle, idle, idle, idle, idle, idle]
	var log := [_ev("engagement", 1), _ev("pool_break", 6, {"pool": "morale"})]
	var r := CaptureStages.find([_turn(0, frames, log)])
	assert_eq(r["stages"]["rout"], {"turn": 1, "frame": 7, "tick": 7}, "the morale break beats the earlier fall-back")


func test_stamina_break_is_ignored() -> void:
	var idle := _frame([[1, IDLE]])
	var fb := _frame([[1, FALLING_BACK]])
	var frames := [idle, idle, fb, idle, idle, idle, idle, idle, idle, idle]
	var log := [_ev("engagement", 1), _ev("pool_break", 3, {"pool": "stamina"})]
	var r := CaptureStages.find([_turn(0, frames, log)])
	assert_eq(r["stages"]["rout"], {"turn": 1, "frame": 2, "tick": 2}, "falls back to the first fall-back frame")


func test_rout_falls_back_to_first_fall_back_frame() -> void:
	var idle := _frame([[1, IDLE]])
	var fb := _frame([[1, FALLING_BACK]])
	var frames := [idle, idle, fb, fb, idle, idle, idle, idle, idle, idle]
	var log := [_ev("engagement", 1)]
	var r := CaptureStages.find([_turn(0, frames, log)])
	assert_eq(r["stages"]["rout"], {"turn": 1, "frame": 2, "tick": 2})


func test_rout_missing_without_break_or_fall_back() -> void:
	var idle := _frame([[1, IDLE]])
	var frames := [idle, idle, idle, idle]
	var log := [_ev("engagement", 1), _ev("pool_break", 2, {"pool": "stamina"})]
	var r := CaptureStages.find([_turn(0, frames, log)])
	assert_false((r["stages"] as Dictionary).has("rout"))
	assert_eq(r["missing"]["rout"], "no break or fall-back")


func test_no_casualty_and_no_engaged_after_contact_are_missing() -> void:
	var idle := _frame([[1, IDLE], [2, IDLE]])
	var frames := [idle, idle, idle, idle, idle]
	var r := CaptureStages.find([_turn(0, frames, [_ev("engagement", 2)])])
	assert_eq(r["missing"]["blood"], "no casualty")
	assert_eq(r["missing"]["mid"], "no squad engaged")
	assert_false((r["stages"] as Dictionary).has("blood"))
	assert_false((r["stages"] as Dictionary).has("mid"))
	assert_eq(r["stages"]["contact"], {"turn": 1, "frame": 3, "tick": 3})


func test_find_is_deterministic() -> void:
	var idle := _frame([[1, IDLE]])
	var eng := _frame([[1, ENGAGED], [2, ENGAGED]])
	var fb := _frame([[2, FALLING_BACK]])
	var t1 := [idle, idle, eng, eng, fb, idle]
	var t2 := [eng, idle, eng, idle]
	var turns := [
		_turn(0, t1, [_ev("engagement", 1), _ev("unit_killed", 4)]),
		_turn(5, t2, [_ev("pool_break", 7, {"pool": "morale"})]),
	]
	var a := CaptureStages.find(turns)
	var b := CaptureStages.find(turns)
	assert_eq(a, b)
	assert_eq(a["stages"]["mid"], {"turn": 1, "frame": 2, "tick": 2})
