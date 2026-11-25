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
	keys.resize(0)
	for row in u.count():
		if u.hp[row] <= 0:
			continue
		var cell := (u.y[row] / CELL) * cols + u.x[row] / CELL
		keys.append((cell << 20) | row)
	keys.sort()
	var start := {}
	var m := keys.size()
	var i := 0
	while i < m:
		var c := keys[i] >> 20
		var j := i
		while j < m and keys[j] >> 20 == c:
			j += 1
		start[c] = Vector2i(i, j)
		i = j
	for c: int in start:
		var span: Vector2i = start[c]
		for a in range(span.x, span.y):
			var ra := keys[a] & 0xFFFFF
			for b in range(a + 1, span.y):
				var rb := keys[b] & 0xFFFFF
				if u.squad[ra] != u.squad[rb]:
					_pair(u, ra, rb)
		# Forward neighbours: E, SW, S, SE.
		for nc: int in [c + 1, c + cols - 1, c + cols, c + cols + 1]:
			var other: Variant = start.get(nc)
			if other == null:
				continue
			var sp: Vector2i = other
			for a in range(span.x, span.y):
				var ra := keys[a] & 0xFFFFF
				for b in range(sp.x, sp.y):
					var rb := keys[b] & 0xFFFFF
					if u.squad[ra] != u.squad[rb]:
						_pair(u, ra, rb)


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
