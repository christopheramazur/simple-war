extends SceneTree
## sw-arse prototypes: line-of-sight implementations replayed over the real
## los() queries that los_scale.gd --save-trace recorded (one battle, every
## caller). Each prototype answers every query that needs a blocker walk (the
## awareness test never needs one); every answer is checked against
## BattleRules._walk_los. Prints us per query and ms per tick for each, plus
## the query statistics that decide whether target-side fields could pay.
## Run: harness/bin/hx godot run docs/design/u1/scripts/fp/los_proto.gd -- <trace dir> [n ...] [--reps 3]

const TICK_COL := 10

var rules: BattleRules
var w := 0
var h := 0
var blk := PackedByteArray()
var sat := PackedInt32Array()
var dist := PackedByteArray()
var cache := PackedInt64Array()
var memo := {}


func _initialize() -> void:
	Fixed.warm()
	var args := OS.get_cmdline_user_args()
	var dir := args[0]
	var ns := []
	var reps := 3
	var i := 1
	while i < args.size():
		if args[i] == "--reps":
			reps = int(args[i + 1])
			i += 1
		else:
			ns.append(int(args[i]))
		i += 1
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	for n in ns:
		var f := FileAccess.open("%s/trace_%d.bin" % [dir, n], FileAccess.READ)
		var d: Dictionary = f.get_var()
		f.close()
		_one(d, reps)
	quit(0)


func _one(d: Dictionary, reps: int) -> void:
	rules.width = d["width"]
	rules.height = d["height"]
	rules.terrain = d["terrain"]
	w = rules.width
	h = rules.height
	var tr: PackedInt64Array = d["trace"]
	var ticks: int = d["ticks"]
	# The queries that need a walk: [x0, y0, x1, y1] cells.
	var q := PackedInt64Array()
	var m := tr.size() / TICK_COL
	for k in m:
		if tr[TICK_COL * k + 5] == 0:
			q.append_array([tr[TICK_COL * k + 1], tr[TICK_COL * k + 2], tr[TICK_COL * k + 3], tr[TICK_COL * k + 4]])
	var nq := q.size() / 4
	var ref := PackedByteArray()
	ref.resize(nq)
	var lens := 0
	for k in nq:
		ref[k] = 1 if rules._walk_los(q[4 * k], q[4 * k + 1], q[4 * k + 2], q[4 * k + 3]) else 0
		lens += maxi(absi(q[4 * k + 2] - q[4 * k]), absi(q[4 * k + 3] - q[4 * k + 1]))
	var clear := 0
	for k in nq:
		clear += ref[k]
	var t0 := Time.get_ticks_usec()
	_build()
	var t_build := Time.get_ticks_usec() - t0
	var blockers := 0
	for c in blk:
		blockers += c
	print("\n== n=%d: %dx%d map, %d blocking cells (%.1f%%), %d los() calls, %d need a walk (%.0f/t), %.0f%% clear, mean length %.1f cells; build %.2f ms, %d bytes" % [
		d["n"], w, h, blockers, 100.0 * blockers / (w * h), m, nq, nq / float(ticks), 100.0 * clear / maxi(nq, 1), lens / float(maxi(nq, 1)),
		t_build / 1000.0, sat.size() * 4 + dist.size() + blk.size()])
	_stats(q, tr, ticks)
	var impls := {
		"walk (today, no memo)": _walk_all,
		"walk + memo (today)": _memo_all,
		"box accept + walk": _box_all,
		"jump walk": _jump_all,
		"box accept + jump walk": _box_jump_all,
		"box + jump + direct-mapped cache": _cached_all,
		"cache + walk": _cache_walk_all,
		"jump + cache 2^12": _jc12,
		"jump + cache 2^13": _jc13,
		"jump + cache 2^14": _jc14,
		"jump + cache 2^16": _jc16,
	}
	for name: String in impls:
		var best := 1 << 62
		var out := PackedByteArray()
		for r in reps:
			memo = {}
			cache = PackedInt64Array()
			cache.resize(1 << 14)
			cache.fill(-1)
			t0 = Time.get_ticks_usec()
			out = impls[name].call(q)
			best = mini(best, Time.get_ticks_usec() - t0)
		var bad := 0
		for k in nq:
			if out[k] != ref[k]:
				bad += 1
		print("  %-34s %6.3f us/query  %6.3f ms/t  %s" % [name, best / float(maxi(nq, 1)), best / 1000.0 / ticks, "exact" if bad == 0 else "%d WRONG" % bad])


## Query statistics: per tick, how many walks share a destination cell or a
## source cell (what a target-side or source-side visibility field shares).
func _stats(q: PackedInt64Array, tr: PackedInt64Array, ticks: int) -> void:
	var nq := q.size() / 4
	var per_tick := maxi(1, nq / ticks)
	var dst := {}
	var src := {}
	var pairs := {}
	for k in nq:
		var c0 := q[4 * k + 1] * w + q[4 * k]
		var c1 := q[4 * k + 3] * w + q[4 * k + 2]
		dst[c1] = int(dst.get(c1, 0)) + 1
		src[c0] = int(src.get(c0, 0)) + 1
		pairs[c0 * w * h + c1] = true
	var box_ok := 0
	for k in nq:
		if _box(q[4 * k], q[4 * k + 1], q[4 * k + 2], q[4 * k + 3]):
			box_ok += 1
	print("  whole run: %d distinct pairs (memo ceiling %.0f%% hits), %d distinct targets (%.1f walks each), %d distinct sources (%.1f each); box accept answers %.0f%%" % [
		pairs.size(), 100.0 - 100.0 * pairs.size() / maxi(nq, 1), dst.size(), nq / float(maxi(dst.size(), 1)), src.size(), nq / float(maxi(src.size(), 1)), 100.0 * box_ok / maxi(nq, 1)])


func _build() -> void:
	var f := rules.f_blocks_los
	var ter := rules.terrain
	blk.resize(w * h)
	for c in w * h:
		blk[c] = f[ter[c]]
	var w1 := w + 1
	sat.resize(w1 * (h + 1))
	sat.fill(0)
	for y in h:
		var run := 0
		for x in w:
			run += blk[y * w + x]
			sat[(y + 1) * w1 + x + 1] = sat[y * w1 + x + 1] + run
	# Chebyshev distance to the nearest blocking cell, two chamfer passes.
	dist.resize(w * h)
	var big := 255
	for c in w * h:
		dist[c] = 0 if blk[c] == 1 else big
	for y in h:
		for x in w:
			var c := y * w + x
			var v := dist[c]
			if v == 0:
				continue
			if x > 0:
				v = mini(v, dist[c - 1] + 1)
			if y > 0:
				v = mini(v, dist[c - w] + 1)
				if x > 0:
					v = mini(v, dist[c - w - 1] + 1)
				if x < w - 1:
					v = mini(v, dist[c - w + 1] + 1)
			dist[c] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var c := y * w + x
			var v := dist[c]
			if v == 0:
				continue
			if x < w - 1:
				v = mini(v, dist[c + 1] + 1)
			if y < h - 1:
				v = mini(v, dist[c + w] + 1)
				if x < w - 1:
					v = mini(v, dist[c + w + 1] + 1)
				if x > 0:
					v = mini(v, dist[c + w - 1] + 1)
			dist[c] = v


func _box(x0: int, y0: int, x1: int, y1: int) -> bool:
	var xa := mini(x0, x1)
	var xb := maxi(x0, x1) + 1
	var ya := mini(y0, y1)
	var yb := maxi(y0, y1) + 1
	var w1 := w + 1
	var n := sat[yb * w1 + xb] - sat[ya * w1 + xb] - sat[yb * w1 + xa] + sat[ya * w1 + xa]
	if n <= BattleRules.LOS_DEPTH:
		return true
	n -= blk[y0 * w + x0]
	if x1 != x0 or y1 != y0:
		n -= blk[y1 * w + x1]
	return n <= BattleRules.LOS_DEPTH


func _jump(x0: int, y0: int, x1: int, y1: int) -> bool:
	var a := absi(x1 - x0)
	var b := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var blocked := 0
	var i := 1
	if a >= b:
		var a2 := 2 * a
		var b2 := 2 * b
		while i < a:
			var d := dist[(y0 + sy * ((b2 * i + a) / a2)) * w + x0 + sx * i]
			if d == 0:
				blocked += 1
				if blocked > BattleRules.LOS_DEPTH:
					return false
				i += 1
			else:
				i += d
	else:
		var a2 := 2 * a
		var b2 := 2 * b
		while i < b:
			var d := dist[(y0 + sy * i) * w + x0 + sx * ((a2 * i + b) / b2)]
			if d == 0:
				blocked += 1
				if blocked > BattleRules.LOS_DEPTH:
					return false
				i += 1
			else:
				i += d
	return true


func _walk_all(q: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	for k in out.size():
		out[k] = 1 if rules._walk_los(q[4 * k], q[4 * k + 1], q[4 * k + 2], q[4 * k + 3]) else 0
	return out


func _memo_all(q: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	var cells := w * h
	for k in out.size():
		var key := (q[4 * k + 1] * w + q[4 * k]) * cells + q[4 * k + 3] * w + q[4 * k + 2]
		var hit: Variant = memo.get(key)
		if hit == null:
			hit = rules._walk_los(q[4 * k], q[4 * k + 1], q[4 * k + 2], q[4 * k + 3])
			memo[key] = hit
		out[k] = 1 if hit else 0
	return out


func _box_all(q: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	for k in out.size():
		var x0 := q[4 * k]
		var y0 := q[4 * k + 1]
		var x1 := q[4 * k + 2]
		var y1 := q[4 * k + 3]
		out[k] = 1 if _box(x0, y0, x1, y1) or rules._walk_los(x0, y0, x1, y1) else 0
	return out


func _jump_all(q: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	for k in out.size():
		out[k] = 1 if _jump(q[4 * k], q[4 * k + 1], q[4 * k + 2], q[4 * k + 3]) else 0
	return out


func _box_jump_all(q: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	for k in out.size():
		var x0 := q[4 * k]
		var y0 := q[4 * k + 1]
		var x1 := q[4 * k + 2]
		var y1 := q[4 * k + 3]
		out[k] = 1 if _box(x0, y0, x1, y1) or _jump(x0, y0, x1, y1) else 0
	return out


func _jc12(q: PackedInt64Array) -> PackedByteArray:
	cache.resize(1 << 12)
	return _cached_all(q, false)


func _jc13(q: PackedInt64Array) -> PackedByteArray:
	cache.resize(1 << 13)
	return _cached_all(q, false)


func _jc14(q: PackedInt64Array) -> PackedByteArray:
	return _cached_all(q, false)


func _jc16(q: PackedInt64Array) -> PackedByteArray:
	cache.resize(1 << 16)
	cache.fill(-1)
	return _cached_all(q, false)


func _cached_all(q: PackedInt64Array, box: bool = true) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	var cells := w * h
	var mask := cache.size() - 1
	for k in out.size():
		var x0 := q[4 * k]
		var y0 := q[4 * k + 1]
		var x1 := q[4 * k + 2]
		var y1 := q[4 * k + 3]
		var key := (y0 * w + x0) * cells + y1 * w + x1
		var slot := (key ^ (key >> 13) ^ (key >> 27)) & mask
		var e := cache[slot]
		if e >= 0 and e >> 1 == key:
			out[k] = e & 1
			continue
		var s := (box and _box(x0, y0, x1, y1)) or _jump(x0, y0, x1, y1)
		cache[slot] = (key << 1) | (1 if s else 0)
		out[k] = 1 if s else 0
	return out


func _cache_walk_all(q: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(q.size() / 4)
	var cells := w * h
	var mask := cache.size() - 1
	for k in out.size():
		var x0 := q[4 * k]
		var y0 := q[4 * k + 1]
		var x1 := q[4 * k + 2]
		var y1 := q[4 * k + 3]
		var key := (y0 * w + x0) * cells + y1 * w + x1
		var slot := (key ^ (key >> 13) ^ (key >> 27)) & mask
		var e := cache[slot]
		if e >= 0 and e >> 1 == key:
			out[k] = e & 1
			continue
		var s := rules._walk_los(x0, y0, x1, y1)
		cache[slot] = (key << 1) | (1 if s else 0)
		out[k] = 1 if s else 0
	return out
