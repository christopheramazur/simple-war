class_name WorkshopProbes
extends RefCounted
## Probe values and checks for the behaviour workshop (sw-tho3.3, U1 B3,
## synthesis O4). Every number is an int in thousandths ("milli"): metres,
## HP, counts, shares and per-second rates alike, so bounds compare exactly.
## Reads a finished WorkshopRun only.
##
## at (one snapshot):  activity (squad code name), hold ({reason: units}),
##   fire (LineOfFire code name to the target), distance (centroids, m),
##   within (target centroid inside the squad's longest weapon range),
##   spacing (nearest two units of the squad, m; with a target, the nearest
##   unit of the squad to a unit of the target, sw-txnj.12).
## over (a tick window): damage (HP dealt, to the target if given), dps
##   (damage per second), shots, kills, duty (share of armed unit-ticks
##   that fired), victims {distinct, max_per_victim, overkill (hits that
##   landed on a victim already dead that tick)}, spacing (the window's
##   minimum), moved (centroid displacement, m).
## Fire timing and waste (U1 D2, draft 04 §1.3): first_kill, mean_kill and
##   wipe are battle ticks (absolute, 0 = the first tick; mean_kill rounded
##   to a whole tick, half up), null when none;
##   waste is the share of the squad's queued damage that did not reduce HP
##   (raw − dealt) ÷ raw, mitigation included.


## {"value": Variant, "error": String}. value null = not measurable.
static func measure(run: WorkshopRun, p: Dictionary) -> Dictionary:
	if not run.sids.has(p["squad"]):
		return {"value": null, "error": "no squad '%s'" % p["squad"]}
	var sid: int = run.sids[p["squad"]]
	var tid: int = run.sids.get(p["target"], -1) if p["target"] != "" else -1
	if p.has("at"):
		var at: Dictionary = p["at"]
		var f := run.frame_at(at["turn"], at["tick"])
		if f < 0 or not run.snapshots.has(f):
			return {"value": null, "error": "the run has no frame at %s (ran %d turns of %d ticks)" % [
				_at_text(at), run.turns_run, run.rules.ticks_per_turn]}
		return {"value": _at(run.snapshots[f], p["kind"], sid, tid), "error": ""}
	var frames := run.frames_over(p["over"])
	if frames.is_empty():
		return {"value": null, "error": "the window %s holds no ticks" % _over_text(p["over"])}
	return {"value": _over(run, frames, p["kind"], p["squad"], sid, tid), "error": ""}


## Whether `value` meets the probe's expectation (null expectation: true).
static func check(kind: String, expect: Variant, value: Variant) -> bool:
	if expect == null:
		return true
	if value == null:
		return false
	match kind:
		"activity", "fire":
			return value in (expect as PackedStringArray)
		"hold":
			var counts: Dictionary = value
			if counts.is_empty():
				return false
			for reason: String in counts:
				if not reason in (expect as PackedStringArray):
					return false
			return true
		"within":
			return value == expect
		"victims":
			for k: String in expect:
				if not in_range(expect[k], int(value[k])):
					return false
			return true
	return in_range(expect, int(value))


static func in_range(r: Variant, v: int) -> bool:
	if r == null:
		return true
	return (not r.has("min") or v >= int(r["min"])) and (not r.has("max") or v <= int(r["max"]))


## A probe value as JSON: thousandths become decimals (3 places).
static func to_json(kind: String, value: Variant) -> Variant:
	if value == null or kind in ["activity", "fire", "within", "hold"]:
		return value
	if kind == "victims":
		var out := {}
		for k: String in value:
			out[k] = decimal(value[k])
		return out
	return decimal(value)


static func decimal(m: int) -> float:
	return float(m) / 1000.0


static func milli_of_fixed(v: int) -> int:
	return Fixed.round_div(v * 1000, Fixed.ONE)


# --- at -------------------------------------------------------------------------

static func _at(snap: Dictionary, kind: String, sid: int, tid: int) -> Variant:
	var me := _squad(snap, sid)
	var it := _squad(snap, tid)
	match kind:
		"activity":
			return BattleActivity.Squad.keys()[me["activity"]] if not me.is_empty() else "GONE"
		"hold":
			var counts := {}
			for u: Dictionary in snap["units"]:
				if u["squad"] == sid and u["hp"] > 0:
					var n: String = BattleActivity.Hold.keys()[u["hold"]]
					counts[n] = int(counts.get(n, 0)) + 1
			return counts
		"fire":
			if me.is_empty() or it.is_empty():
				return "NO_TARGET"
			for pair: Dictionary in snap["fire"]:
				if pair["from"] == sid and pair["to"] == tid:
					return WorkshopScenario.FIRE_CODES[pair["los"]].to_upper()
			return "OUT_OF_RANGE"
		"distance":
			if me.is_empty() or it.is_empty():
				return null
			return milli_of_fixed(Fixed.distance(me["x"], me["y"], it["x"], it["y"]))
		"within":
			if me.is_empty() or it.is_empty():
				return false
			return Fixed.distance(me["x"], me["y"], it["x"], it["y"]) <= int(me["range"])
		"spacing":
			var xs := PackedInt64Array()
			var ys := PackedInt64Array()
			var txs := PackedInt64Array()
			var tys := PackedInt64Array()
			for u: Dictionary in snap["units"]:
				if u["hp"] <= 0:
					continue
				if u["squad"] == sid:
					xs.append(u["x"])
					ys.append(u["y"])
				elif tid >= 0 and u["squad"] == tid:
					txs.append(u["x"])
					tys.append(u["y"])
			return _min_gap(xs, ys) if tid < 0 else _cross_gap(xs, ys, txs, tys)
	return null


static func _squad(snap: Dictionary, sid: int) -> Dictionary:
	if sid < 0:
		return {}
	for d: Dictionary in snap["squads"]:
		if d["id"] == sid:
			return d
	return {}


static func _min_gap(xs: PackedInt64Array, ys: PackedInt64Array) -> Variant:
	if xs.size() < 2:
		return null
	var best := -1
	for i in xs.size():
		for j in range(i + 1, xs.size()):
			var d := Fixed.distance(xs[i], ys[i], xs[j], ys[j])
			if best < 0 or d < best:
				best = d
	return milli_of_fixed(best)


## Nearest distance from a unit of one set to a unit of the other, m
## (milli); null if either is empty.
static func _cross_gap(xs: PackedInt64Array, ys: PackedInt64Array, txs: PackedInt64Array, tys: PackedInt64Array) -> Variant:
	if xs.is_empty() or txs.is_empty():
		return null
	var best := -1
	for i in xs.size():
		for j in txs.size():
			var d := Fixed.distance(xs[i], ys[i], txs[j], tys[j])
			if best < 0 or d < best:
				best = d
	return milli_of_fixed(best)


# --- over -----------------------------------------------------------------------

static func _over(run: WorkshopRun, frames: PackedInt64Array, kind: String, key: String, sid: int, tid: int) -> Variant:
	match kind:
		"damage", "dps", "shots", "kills":
			var total := 0
			for f in frames:
				for e: Dictionary in run.events[f]:
					var d: Dictionary = e["data"]
					match [kind, String(e["type"])]:
						["damage", "squad_damaged"], ["dps", "squad_damaged"]:
							if d["squad"] == sid and (tid < 0 or d["target"] == tid):
								total += int(d["damage"])
						["shots", "squad_fired"]:
							if d["squad"] == sid and (tid < 0 or d["target"] == tid):
								total += int(d["shots"])
						["kills", "unit_killed"]:
							if d["by"] == sid and (tid < 0 or d["squad"] == tid):
								total += 1
			if kind == "damage":
				return milli_of_fixed(total)
			if kind == "dps":
				return Fixed.round_div(milli_of_fixed(total) * run.rules.tps, frames.size())
			return total * 1000
		"first_shot", "first_shot_ticks", "shooters", "dps_engaged":
			return _shot_value(run, frames, kind, key, sid, tid)
		"first_kill", "mean_kill", "wipe", "waste":
			return _kill_value(run, frames, kind, sid, tid)
		"duty":
			var armed := 0
			var fired := 0
			for f in frames:
				armed += (run.duty_armed[key] as PackedInt64Array)[f]
				fired += (run.duty_fired[key] as PackedInt64Array)[f]
			return Fixed.round_div(fired * 1000, armed) if armed > 0 else null
		"victims":
			return _victims(run, frames, key, tid)
		"spacing":
			var best: Variant = null
			for f in frames:
				var g: Variant = _frame_gap(run.recorder.frames[f], sid, tid)
				if g != null and (best == null or int(g) < int(best)):
					best = g
			return best
		"moved":
			var c0 := _centroid(run.recorder.frames[frames[0] - 1], sid)
			var c1 := _centroid(run.recorder.frames[frames[frames.size() - 1]], sid)
			if c0.is_empty() or c1.is_empty():
				return null
			return milli_of_fixed(Fixed.distance(c0[0], c0[1], c1[0], c1[1]))
	return null


## Kill timing (by the squad on the target, or on any target) and waste.
static func _kill_value(run: WorkshopRun, frames: PackedInt64Array, kind: String, sid: int, tid: int) -> Variant:
	if kind == "waste":
		var raw := 0
		var dealt := 0
		for f in frames:
			for e: Dictionary in run.events[f]:
				if e["type"] == &"squad_damaged":
					var d: Dictionary = e["data"]
					if d["squad"] == sid and (tid < 0 or d["target"] == tid):
						raw += int(d["raw"])
						dealt += int(d["damage"])
		return null if raw <= 0 else Fixed.round_div((raw - dealt) * 1000, raw)
	var ticks: Array[int] = []
	for f in frames:
		for e: Dictionary in run.events[f]:
			if e["type"] == &"unit_killed":
				var d: Dictionary = e["data"]
				if d["by"] == sid and (tid < 0 or d["squad"] == tid):
					ticks.append(run.frame_abs[f])
	if ticks.is_empty():
		return null
	match kind:
		"first_kill":
			return ticks.min() * 1000
		"mean_kill":
			# Whole ticks, half up (the draft 04 table's rounding).
			var sum := 0
			for t: int in ticks:
				sum += t
			var n := ticks.size()
			return (2 * sum + n) / (2 * n) * 1000
		"wipe":
			# The target squad has no living unit left at the window's last tick.
			if tid < 0 or _living(run.recorder.frames[frames[frames.size() - 1]], tid) > 0:
				return null
			return ticks.max() * 1000
	return null


static func _living(frame: PackedInt64Array, sid: int) -> int:
	var n := 0
	for o in range(0, frame.size(), ReplayRecorder.STRIDE):
		if frame[o + ReplayRecorder.F_SQUAD] == sid and frame[o + ReplayRecorder.F_HP] > 0:
			n += 1
	return n


## Firing-start probes, read from the shot trace in the window (sw-tho3.4):
## first_shot = seconds from the window's first tick to the squad's first
## shot at the target (null: no shot); dps_engaged = dps counted from that
## first shot, so approach time does not dilute it; shooters = distinct
## units that fired; first_shot_ticks = distinct ticks on which a unit fired
## its first shot in the window (staggered opening: 1 is lockstep).
static func _shot_value(run: WorkshopRun, frames: PackedInt64Array, kind: String, key: String, sid: int, tid: int) -> Variant:
	var lo := run.frame_abs[frames[0]]
	var hi := run.frame_abs[frames[frames.size() - 1]]
	var shots := _shots_in(run, lo, hi, key, _key_of(run, tid))
	var first_tick := -1
	for s: Array in shots:
		if first_tick < 0 or s[0] < first_tick:
			first_tick = s[0]
	match kind:
		"shooters":
			var who := {}
			for s: Array in shots:
				who[s[1]] = true
			return who.size() * 1000
		"first_shot_ticks":
			var first := {}
			for s: Array in shots:
				first[s[1]] = mini(int(first.get(s[1], s[0])), s[0])
			var ticks := {}
			for t: int in first.values():
				ticks[t] = true
			return ticks.size() * 1000
		"first_shot":
			return null if first_tick < 0 else (first_tick - lo) * 1000 / run.rules.tps
		"dps_engaged":
			if first_tick < 0:
				return null
			var sub := PackedInt64Array()
			for f in frames:
				if run.frame_abs[f] >= first_tick:
					sub.append(f)
			return _over(run, sub, "dps", key, sid, tid)
	return null


## The shot trace rows [tick, shooter unit, victim unit] of the squad `key`
## in ticks lo..hi; victims limited to the squad `tkey` when given.
static func _shots_in(run: WorkshopRun, lo: int, hi: int, key: String, tkey: String) -> Array:
	var out := []
	var t := run.state.shot_trace
	for i in range(0, t.size(), BattleState.SHOT_STRIDE):
		var tick := t[i]
		if tick < lo or tick > hi or run.unit_key.get(t[i + 1]) != key:
			continue
		if tkey != "" and run.unit_key.get(t[i + 2]) != tkey:
			continue
		out.append([tick, t[i + 1], t[i + 2]])
	return out


static func _key_of(run: WorkshopRun, sid: int) -> String:
	if sid < 0:
		return ""
	for k: String in run.sids:
		if run.sids[k] == sid:
			return k
	return ""


## Shots by the squad's units at victims (target squad only when given).
## overkill: hits that dealt nothing, which in this sim means the victim was
## already dead when the hit was applied that tick.
static func _victims(run: WorkshopRun, frames: PackedInt64Array, key: String, tid: int) -> Dictionary:
	var lo := run.frame_abs[frames[0]]
	var hi := run.frame_abs[frames[frames.size() - 1]]
	var tkey := ""
	if tid >= 0:
		for k: String in run.sids:
			if run.sids[k] == tid:
				tkey = k
	var st := run.state
	var per_victim := {}
	var hits := {}
	var t := st.shot_trace
	for i in range(0, t.size(), BattleState.SHOT_STRIDE):
		var tick := t[i]
		if tick < lo or tick > hi or run.unit_key.get(t[i + 1]) != key:
			continue
		var victim := t[i + 2]
		if tkey != "" and run.unit_key.get(victim) != tkey:
			continue
		per_victim[victim] = int(per_victim.get(victim, 0)) + 1
		if t[i + 3] == 1:
			var hk := "%d|%d" % [tick, victim]
			hits[hk] = int(hits.get(hk, 0)) + 1
	var h := st.hit_trace
	for i in range(0, h.size(), BattleState.HIT_STRIDE):
		var hk := "%d|%d" % [h[i], h[i + 1]]
		if hits.has(hk) and run.unit_key.get(h[i + 3]) == key:
			hits[hk] = int(hits[hk]) - 1
	var overkill := 0
	for hk: String in hits:
		overkill += maxi(0, int(hits[hk]))
	var most := 0
	for v: int in per_victim:
		most = maxi(most, int(per_victim[v]))
	return {"distinct": per_victim.size() * 1000, "max_per_victim": most * 1000, "overkill": overkill * 1000}


static func _frame_gap(frame: PackedInt64Array, sid: int, tid: int = -1) -> Variant:
	var xs := PackedInt64Array()
	var ys := PackedInt64Array()
	var txs := PackedInt64Array()
	var tys := PackedInt64Array()
	for o in range(0, frame.size(), ReplayRecorder.STRIDE):
		if frame[o + ReplayRecorder.F_HP] <= 0:
			continue
		var q := frame[o + ReplayRecorder.F_SQUAD]
		if q == sid:
			xs.append(frame[o + ReplayRecorder.F_X])
			ys.append(frame[o + ReplayRecorder.F_Y])
		elif tid >= 0 and q == tid:
			txs.append(frame[o + ReplayRecorder.F_X])
			tys.append(frame[o + ReplayRecorder.F_Y])
	return _min_gap(xs, ys) if tid < 0 else _cross_gap(xs, ys, txs, tys)


## Mean position of the squad's living units in a playback frame ([] none).
static func _centroid(frame: PackedInt64Array, sid: int) -> PackedInt64Array:
	var sx := 0
	var sy := 0
	var n := 0
	for o in range(0, frame.size(), ReplayRecorder.STRIDE):
		if frame[o + ReplayRecorder.F_SQUAD] == sid and frame[o + ReplayRecorder.F_HP] > 0:
			sx += frame[o + ReplayRecorder.F_X]
			sy += frame[o + ReplayRecorder.F_Y]
			n += 1
	if n == 0:
		return PackedInt64Array()
	return PackedInt64Array([Fixed.round_div(sx, n), Fixed.round_div(sy, n)])


static func _at_text(at: Dictionary) -> String:
	if at["turn"] < 0:
		return "end"
	return "t%d" % at["turn"] if at["tick"] < 0 else "t%d:%d" % [at["turn"], at["tick"]]


static func _over_text(w: Dictionary) -> String:
	return "t%d:%d-t%d:%s" % [w["t0"], w["k0"], w["t1"], "end" if w["k1"] < 0 else str(w["k1"])]
