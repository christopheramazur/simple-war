class_name CaptureStages
extends RefCounted
## The stages of a recorded battle (sw-tho3.9, U1 draft 02 §3.1 / GDD 05
## §5.6 proposal), found from CaptureSim turn records alone, so they are the
## same for the same source every time:
##   deploy   turn 1, frame 0 (the battle's start, orders applied)
##   contact  the first `engagement` event (SimMetrics first_contact_tick)
##   blood    the first `unit_killed` event (first_casualty_tick)
##   mid      the frame with the most squads ENGAGED from contact to the end
##   rout     the first Morale `pool_break` (first_break_tick), or else the
##            first frame a squad is FALLING_BACK
##   end      the last frame of the last turn
## Ties resolve to the lowest tick (mid: the first frame with the most).
## A stage that never happened is reported in "missing" with why, never an
## error. A battle with no squads, or one where nobody ever made contact,
## has no stages at all (every one missing): there is nothing to look at.
##
## An event in tick T of a turn that started at tick F shows from frame
## T - F + 1 (playback: frame i is the state after i ticks).

const ORDER: PackedStringArray = ["deploy", "contact", "blood", "mid", "rout", "end"]


## `turns` is one battle's CaptureSim.turns list. Returns {"stages": name ->
## {"turn" (1-based), "frame", "tick" (ticks run since the battle's start)},
## "missing": {name: reason}}.
static func find(turns: Array) -> Dictionary:
	var stages := {}
	var missing := {}
	if turns.is_empty() or _no_squads(turns):
		for n in ORDER:
			missing[n] = "no squads"
		return {"stages": stages, "missing": missing}
	var contact := _first_event(turns, func(e: Dictionary) -> bool: return e["type"] == "engagement")
	if contact.is_empty():
		for n in ORDER:
			missing[n] = "no contact"
		return {"stages": stages, "missing": missing}
	stages["deploy"] = _at(turns, 0, 0)
	stages["contact"] = contact
	var blood := _first_event(turns, func(e: Dictionary) -> bool: return e["type"] == "unit_killed")
	if blood.is_empty():
		missing["blood"] = "no casualty"
	else:
		stages["blood"] = blood
	var mid := _most_engaged(turns, contact)
	if mid.is_empty():
		missing["mid"] = "no squad engaged"
	else:
		stages["mid"] = mid
	var rout := _first_event(turns, func(e: Dictionary) -> bool:
		return e["type"] == "pool_break" and String((e["data"] as Dictionary).get("pool", "")) == "morale")
	if rout.is_empty():
		rout = _first_frame(turns, BattleActivity.Squad.FALLING_BACK)
	if rout.is_empty():
		missing["rout"] = "no break or fall-back"
	else:
		stages["rout"] = rout
	var last := turns.size() - 1
	stages["end"] = _at(turns, last, (turns[last]["frames"] as Array).size() - 1)
	return {"stages": stages, "missing": missing}


static func _at(turns: Array, ti: int, frame: int) -> Dictionary:
	return {"turn": ti + 1, "frame": frame, "tick": int(turns[ti]["first_tick"]) + frame}


static func _no_squads(turns: Array) -> bool:
	for rec: Dictionary in turns:
		for f: PackedInt64Array in rec["frames"]:
			if not f.is_empty():
				return false
	return true


## The frame where the first event `pred` accepts shows (lowest tick; the
## log is in tick order within a turn, turns in order).
static func _first_event(turns: Array, pred: Callable) -> Dictionary:
	for ti in turns.size():
		var rec: Dictionary = turns[ti]
		var first := int(rec["first_tick"])
		var last := (rec["frames"] as Array).size() - 1
		var best := -1
		for e: Dictionary in (rec["start"] as Dictionary).get("log", []):
			if pred.call(e):
				var f := clampi(int(e["tick"]) - first + 1, 0, last)
				if best < 0 or f < best:
					best = f
		if best >= 0:
			return _at(turns, ti, best)
	return {}


## Squads (by ID) with BattleActivity.Squad `activity` in a raw playback frame.
static func count_squads(f: PackedInt64Array, activity: int) -> int:
	var seen := {}
	for o in range(0, f.size(), OverworldSession.PLAYBACK_STRIDE):
		if f[o + 12] == activity:
			seen[f[o + 1]] = true
	return seen.size()


static func _first_frame(turns: Array, activity: int) -> Dictionary:
	for ti in turns.size():
		var frames: Array = turns[ti]["frames"]
		for k in frames.size():
			if count_squads(frames[k], activity) > 0:
				return _at(turns, ti, k)
	return {}


static func _most_engaged(turns: Array, from: Dictionary) -> Dictionary:
	var best := {}
	var most := 0
	for ti in range(int(from["turn"]) - 1, turns.size()):
		var frames: Array = turns[ti]["frames"]
		var k0 := int(from["frame"]) if ti == int(from["turn"]) - 1 else 0
		for k in range(k0, frames.size()):
			var n := count_squads(frames[k], BattleActivity.Squad.ENGAGED)
			if n > most:  # strictly more: a tie keeps the lowest tick
				most = n
				best = _at(turns, ti, k)
	return best
