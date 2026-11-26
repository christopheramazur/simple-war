class_name Separation
extends RefCounted
## Separation between squads (sw-txnj.12, U1Q10; GDD 02 §2.14 Separation and
## coherency). Run by MovementSystem after units have stepped to their slots.
##
## A living unit closer than the separation distance to a living unit of
## another squad is pushed apart along the line between them, half the
## overlap each. The separation distance of a pair is the larger of the two
## units' separation radii (by size class: ruleset separation_m, compiled
## into BattleRules.ut_sep). Pushes:
## - are computed from the positions at the start of the pass, summed per
##   unit, capped at the unit's speed (at least its walk speed per tick, so a
##   standing unit can still be nudged), and applied together, so row order
##   doesn't matter;
## - never enter a cell the unit can't: the terrain-collision slide rule
##   (x first, then y, else the push is dropped);
## - for two units on the same point, run along the lower unit ID's facing.
## No body blocking: routes and slots ignore other units. Integer math.
## A unit with a unit of another squad within CROWD_PCT of their separation
## distance is marked crowded (BattleUnits.crowded); MovementSystem lets a
## crowded unit stand within its separation radius of its goal, so it stays
## beside the other unit instead of stepping back into it every tick.
##
## Broadphase: a uniform hash of BattleRules.sep_cell (2 m) cells rebuilt
## each pass. (cell, row) keys are sorted natively, one pass indexes the
## occupied cells into a dense grid, and each occupied cell is tested
## against itself and its four forward neighbours (half stencil), so every
## pair is seen once. Measured by the sw-txnj.3 prototype at 0.22 ms/tick
## for 208 units.

## Rows fit in the low 20 bits of a hash key.
const ROW_BITS: int = 20
const ROW_MASK: int = (1 << ROW_BITS) - 1
## A unit is crowded (BattleUnits.crowded) while a unit of another squad is
## within this share of the pair's separation distance.
const CROWD_PCT: int = 150

# Scratch, reset every pass (never state, never hashed).
var _px := PackedInt64Array()
var _py := PackedInt64Array()
var _keys := PackedInt64Array()
var _cells := PackedInt64Array()
var _cell_start := PackedInt32Array()
var _cell_end := PackedInt32Array()
var _cols: int = 0
## The crowded column while a pass runs.
var _crowd := PackedByteArray()
## Pairs pushed in the last pass (tests and profiling).
var pushes: int = 0


func run(state: BattleState) -> void:
	var r := state.rules
	var u := state.units
	var n := u.count()
	if r.ut_sep.is_empty():
		return
	if _px.size() != n:
		_px.resize(n)
		_py.resize(n)
	_px.fill(0)
	_py.fill(0)
	pushes = 0
	_crowd = u.take_column(&"crowded")
	_crowd.fill(0)
	if _pairs(state):
		_apply(state)
	u.put_column(&"crowded", _crowd)
	_crowd = PackedByteArray()


## Fills _px/_py with the summed pushes. False if nothing was pushed.
func _pairs(state: BattleState) -> bool:
	var r := state.rules
	var u := state.units
	var cell_size := r.sep_cell
	var cols := (Fixed.from_int(r.width) + cell_size - 1) / cell_size
	var rows := (Fixed.from_int(r.height) + cell_size - 1) / cell_size
	var ncell := cols * rows
	if _cell_start.size() != ncell or _cols != cols:
		_cell_start.resize(ncell)
		_cell_start.fill(-1)
		_cell_end.resize(ncell)
		_cols = cols
	_keys.resize(0)
	var max_cx := cols - 1
	var max_cy := rows - 1
	for row in u.count():
		if u.hp[row] <= 0:
			continue
		var cx := clampi(u.x[row] / cell_size, 0, max_cx)
		var cy := clampi(u.y[row] / cell_size, 0, max_cy)
		_keys.append(((cy * cols + cx) << ROW_BITS) | row)
	var m := _keys.size()
	if m < 2:
		return false
	_keys.sort()
	_cells.resize(0)
	var i := 0
	while i < m:
		var c := _keys[i] >> ROW_BITS
		var j := i + 1
		while j < m and _keys[j] >> ROW_BITS == c:
			j += 1
		_cell_start[c] = i
		_cell_end[c] = j
		_cells.append(c)
		i = j
	for c in _cells:
		var s0 := _cell_start[c]
		var s1 := _cell_end[c]
		for a in range(s0, s1):
			var ra := _keys[a] & ROW_MASK
			for b in range(a + 1, s1):
				_pair(state, ra, _keys[b] & ROW_MASK)
		# Forward neighbours: E, SW, S, SE.
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
			if nc >= ncell or _cell_start[nc] < 0:
				continue
			var n0 := _cell_start[nc]
			var n1 := _cell_end[nc]
			for a in range(s0, s1):
				var ra := _keys[a] & ROW_MASK
				for b in range(n0, n1):
					_pair(state, ra, _keys[b] & ROW_MASK)
	for c in _cells:
		_cell_start[c] = -1
	return pushes > 0


## Pushes rows a and b apart if they belong to different squads and stand
## closer than the larger of their separation radii; marks both crowded
## within CROWD_PCT of that.
func _pair(state: BattleState, ra: int, rb: int) -> void:
	var u := state.units
	if u.squad[ra] == u.squad[rb]:
		return
	var a := mini(ra, rb)
	var b := maxi(ra, rb)
	var r := state.rules
	var lim := maxi(r.ut_sep[u.tmpl[a]], r.ut_sep[u.tmpl[b]])
	var near := lim * CROWD_PCT / 100
	var dx := u.x[b] - u.x[a]
	var dy := u.y[b] - u.y[a]
	if absi(dx) >= near or absi(dy) >= near:
		return
	var d := Fixed.length(dx, dy)
	if d >= near:
		return
	_crowd[a] = 1
	_crowd[b] = 1
	if d >= lim:
		return
	if d == 0:
		# Same point: along the lower unit ID's facing; that unit steps
		# forward, the other back. (dx, dy) runs from a to b.
		var lo := a if u.id_at(a) < u.id_at(b) else b
		var f := u.facing[lo]
		dx = Fixed.fcos(f)
		dy = Fixed.fsin(f)
		d = Fixed.ONE
		if lo == a:
			dx = -dx
			dy = -dy
	# Half the overlap each, rounded up so the pair ends at least lim apart.
	var over := (lim - d) / 2 + 1
	var ox := Fixed.mul_ratio(dx, over, d)
	var oy := Fixed.mul_ratio(dy, over, d)
	_px[a] -= ox
	_py[a] -= oy
	_px[b] += ox
	_py[b] += oy
	pushes += 1


## Moves each pushed unit.
func _apply(state: BattleState) -> void:
	var r := state.rules
	var u := state.units
	var x: PackedInt64Array = u.take_column(&"x")
	var y: PackedInt64Array = u.take_column(&"y")
	var max_x := Fixed.from_int(r.width) - 1
	var max_y := Fixed.from_int(r.height) - 1
	for row in u.count():
		var dx := _px[row]
		var dy := _py[row]
		if dx == 0 and dy == 0:
			continue
		if u.moving[row] == 1:
			var slid := _slide(dx, dy, u.facing[row])
			dx = slid[0]
			dy = slid[1]
		var profile := r.ut_movement[u.tmpl[row]]
		var cap := maxi(u.speed[row], Fixed.round_div(r.mv_walk_s[profile], r.tps))
		var len := Fixed.length(dx, dy)
		if len > cap:
			dx = Fixed.mul_ratio(dx, cap, len)
			dy = Fixed.mul_ratio(dy, cap, len)
		var nx := Fixed.clamp_fixed(x[row] + dx, 0, max_x)
		var ny := Fixed.clamp_fixed(y[row] + dy, 0, max_y)
		if MovementSystem._blocked(r, profile, nx, ny) and not MovementSystem._blocked(r, profile, x[row], y[row]):
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


## A push on a unit walking along `facing` that opposes its heading turns
## sideways: the part against the heading becomes a slide on the side the
## push already leans to (its right when the push is straight back), so two
## units walking head-on step around each other instead of standing locked.
## The push keeps its length.
static func _slide(px: int, py: int, facing: int) -> PackedInt64Array:
	var hx := Fixed.fcos(facing)
	var hy := Fixed.fsin(facing)
	var along := Fixed.mul(px, hx) + Fixed.mul(py, hy)
	if along >= 0:
		return PackedInt64Array([px, py])
	var qx := px - Fixed.mul(along, hx)
	var qy := py - Fixed.mul(along, hy)
	var perp := Fixed.length(qx, qy)
	var total := Fixed.length(px, py)
	if perp <= 0:
		# Straight back: to the unit's right (y is south, so right of
		# (hx, hy) is (-hy, hx)).
		return PackedInt64Array([Fixed.mul(-hy, total), Fixed.mul(hx, total)])
	return PackedInt64Array([Fixed.mul_ratio(qx, total, perp), Fixed.mul_ratio(qy, total, perp)])
