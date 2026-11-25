extends SimSystem
## Draft 01 §3.3 separation prototype (sw-txnj.3, scratch; not shipped).
## A unit closer than 2 x SEP_RADIUS to a unit of another squad is pushed
## apart along the line between them, half the overlap each. Pushes are
## computed from start-of-tick positions, summed per unit, capped at the
## unit's speed this tick (at least walk/tps so a standing unit can still be
## nudged), and applied together; a push into a cell the unit can't enter
## slides on one axis (x first) or is dropped. Same point: push along the
## lower unit row's facing. Integer math.
## Broadphase:
## - HASH: the spec's uniform 2 m hash: (cell, row) keys sorted natively, one
##   pass indexes occupied cells, then each occupied cell is tested against
##   itself and its four forward neighbours (half stencil).
## - SQUADS: squads as boxes (centroid + farthest member + radius); only
##   units of overlapping squad pairs are compared.

enum { HASH, SQUADS }

## Medium size class (0.6 m); the data has no size class yet.
const SEP_RADIUS: int = Fixed.ONE * 6 / 10
const CELL: int = 2 * Fixed.ONE

var mode: int
var us := 0
var max_us := 0
var ticks := 0
var pushes := 0
var px := PackedInt64Array()
var py := PackedInt64Array()
var keys := PackedInt64Array()
var cell_start := PackedInt32Array()
var cell_end := PackedInt32Array()
var rad := PackedInt64Array()


func _init(m: int) -> void:
	mode = m


func system_name() -> StringName:
	return &"separation"


func stats() -> String:
	return "pushes/t %.1f, worst tick %.2f ms" % [pushes / float(maxi(ticks, 1)), max_us / 1000.0]


func run(ctx: SimContext) -> void:
	var t0 := Time.get_ticks_usec()
	var state := ctx as BattleState
	var u := state.units
	var n := u.count()
	if px.size() != n:
		px.resize(n)
		py.resize(n)
	px.fill(0)
	py.fill(0)
	if mode == HASH:
		_hash(state)
	else:
		_squads(state)
	_apply(state)
	var dt := Time.get_ticks_usec() - t0
	us += dt
	max_us = maxi(max_us, dt)
	ticks += 1


func _hash(state: BattleState) -> void:
	var u := state.units
	var cols := (Fixed.from_int(state.rules.width) + CELL - 1) / CELL
	var rows := (Fixed.from_int(state.rules.height) + CELL - 1) / CELL
	if cell_start.size() != cols * rows:
		cell_start.resize(cols * rows)
		cell_start.fill(-1)
		cell_end.resize(cols * rows)
	keys.resize(0)
	for row in u.count():
		if u.hp[row] <= 0:
			continue
		var cell := (u.y[row] / CELL) * cols + u.x[row] / CELL
		keys.append((cell << 20) | row)
	keys.sort()
	var m := keys.size()
	# Index occupied cells into the dense grid (reset after use).
	var cells := PackedInt64Array()
	var i := 0
	while i < m:
		var c := keys[i] >> 20
		var j := i + 1
		while j < m and keys[j] >> 20 == c:
			j += 1
		cell_start[c] = i
		cell_end[c] = j
		cells.append(c)
		i = j
	var ncell := cols * rows
	for c in cells:
		var s0 := cell_start[c]
		var s1 := cell_end[c]
		for a in range(s0, s1):
			var ra := keys[a] & 0xFFFFF
			var qa := u.squad[ra]
			for b in range(a + 1, s1):
				var rb := keys[b] & 0xFFFFF
				if qa != u.squad[rb]:
					_pair(u, mini(ra, rb), maxi(ra, rb))
		# Forward neighbours: E, SW, S, SE (half stencil; x wrap guarded).
		var cx := c % cols
		for k in 4:
			var nc: int
			match k:
				0:
					if cx == cols - 1:
						continue
					nc = c + 1
				1:
					if cx == 0:
						continue
					nc = c + cols - 1
				2:
					nc = c + cols
				_:
					if cx == cols - 1:
						continue
					nc = c + cols + 1
			if nc >= ncell or cell_start[nc] < 0:
				continue
			var n0 := cell_start[nc]
			var n1 := cell_end[nc]
			for a in range(s0, s1):
				var ra := keys[a] & 0xFFFFF
				var qa := u.squad[ra]
				for b in range(n0, n1):
					var rb := keys[b] & 0xFFFFF
					if qa != u.squad[rb]:
						_pair(u, mini(ra, rb), maxi(ra, rb))
	for c in cells:
		cell_start[c] = -1


func _squads(state: BattleState) -> void:
	var u := state.units
	var sq := state.squads
	var ns := sq.count()
	rad.resize(ns)
	for s in ns:
		var best := 0
		for urow in Centroids.units_of(state, s):
			best = maxi(best, maxi(absi(u.x[urow] - sq.cx[s]), absi(u.y[urow] - sq.cy[s])))
		rad[s] = best + SEP_RADIUS
	for a in ns:
		if sq.alive[a] == 0:
			continue
		for b in range(a + 1, ns):
			if sq.alive[b] == 0:
				continue
			var lim := rad[a] + rad[b]
			if absi(sq.cx[a] - sq.cx[b]) > lim or absi(sq.cy[a] - sq.cy[b]) > lim:
				continue
			var ub := Centroids.units_of(state, b)
			for ra in Centroids.units_of(state, a):
				if u.hp[ra] <= 0:
					continue
				for rb in ub:
					if u.hp[rb] > 0:
						_pair(u, mini(ra, rb), maxi(ra, rb))


func _pair(u: BattleUnits, a: int, b: int) -> void:
	var dx := u.x[b] - u.x[a]
	var dy := u.y[b] - u.y[a]
	var lim := 2 * SEP_RADIUS
	if absi(dx) >= lim or absi(dy) >= lim:
		return
	var d := Fixed.length(dx, dy)
	if d >= lim:
		return
	var over := (lim - d) / 2
	if d == 0:
		var f := u.facing[mini(a, b)]
		dx = Fixed.fcos(f)
		dy = Fixed.fsin(f)
		d = Fixed.ONE
	var ox := Fixed.mul_ratio(dx, over, d)
	var oy := Fixed.mul_ratio(dy, over, d)
	px[a] -= ox
	py[a] -= oy
	px[b] += ox
	py[b] += oy
	pushes += 1


func _apply(state: BattleState) -> void:
	var r := state.rules
	var u := state.units
	var x: PackedInt64Array = u.take_column(&"x")
	var y: PackedInt64Array = u.take_column(&"y")
	var max_x := Fixed.from_int(r.width) - 1
	var max_y := Fixed.from_int(r.height) - 1
	for row in u.count():
		var dx := px[row]
		var dy := py[row]
		if dx == 0 and dy == 0:
			continue
		var profile := r.ut_movement[u.tmpl[row]]
		var cap := maxi(u.speed[row], Fixed.round_div(r.mv_walk_s[profile], r.tps))
		var len := Fixed.length(dx, dy)
		if len > cap:
			dx = Fixed.mul_ratio(dx, cap, len)
			dy = Fixed.mul_ratio(dy, cap, len)
		var nx := Fixed.clamp_fixed(x[row] + dx, 0, max_x)
		var ny := Fixed.clamp_fixed(y[row] + dy, 0, max_y)
		if MovementSystem._blocked(r, profile, nx, ny):
			if not MovementSystem._blocked(r, profile, nx, y[row]):
				ny = y[row]
			elif not MovementSystem._blocked(r, profile, x[row], ny):
				nx = x[row]
			else:
				continue
		x[row] = nx
		y[row] = ny
	u.put_column(&"x", x)
	u.put_column(&"y", y)
