class_name Hex
extends RefCounted
## Hex maths for the overworld (GDD 02 §2.1, §2.9). Integer only.
##
## Hexes are pointy-top. A map is a width x height rectangle in "odd-r"
## offset coordinates (col, row): odd rows sit half a hex to the right. A
## plot is addressed by its index `row * width + col`; maths runs in axial
## coordinates (q, r) = Vector2i(q, r), with cube s = -q - r.

## Axial neighbour offsets, clockwise from east: E, NE, NW, W, SW, SE.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)


## Offset (col, row) of an axial coordinate.
static func to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + (a.y - (a.y & 1)) / 2, a.y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


# --- plots on a width x height map ----------------------------------------

static func plot(col: int, row: int, width: int) -> int:
	return row * width + col


static func in_bounds(col: int, row: int, width: int, height: int) -> bool:
	return col >= 0 and row >= 0 and col < width and row < height


static func axial_of(p: int, width: int) -> Vector2i:
	return to_axial(p % width, p / width)


## Plot index of an axial coordinate, or -1 off the map.
static func plot_of(a: Vector2i, width: int, height: int) -> int:
	var o := to_offset(a)
	return plot(o.x, o.y, width) if in_bounds(o.x, o.y, width, height) else -1


static func plot_distance(a: int, b: int, width: int) -> int:
	return distance(axial_of(a, width), axial_of(b, width))


## On-map neighbours in DIRS order (off-map ones skipped).
static func neighbours(p: int, width: int, height: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var a := axial_of(p, width)
	for d in DIRS:
		var n := plot_of(a + d, width, height)
		if n >= 0:
			out.append(n)
	return out


static func adjacent(a: int, b: int, width: int) -> bool:
	return plot_distance(a, b, width) == 1


## On-map plots within `radius` of p (p included), ascending.
static func within(p: int, radius: int, width: int, height: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var c := axial_of(p, width)
	for dr in range(-radius, radius + 1):
		for dq in range(maxi(-radius, -dr - radius), mini(radius, -dr + radius) + 1):
			var n := plot_of(c + Vector2i(dq, dr), width, height)
			if n >= 0:
				out.append(n)
	out.sort()
	return out


## Plots on the straight line from a to b, both included: every step is to
## a neighbour. Cube lerp with integer rounding; ties break the same way
## everywhere (the usual epsilon nudge, scaled to integers). A step that
## leaves the map's jagged edge is -1.
static func line(a: int, b: int, width: int, height: int) -> PackedInt64Array:
	var pa := axial_of(a, width)
	var pb := axial_of(b, width)
	var n := distance(pa, pb)
	var out := PackedInt64Array([a])
	if n == 0:
		return out
	const K := 1000000
	var ca := [pa.x, pa.y, -pa.x - pa.y]
	var cb := [pb.x, pb.y, -pb.x - pb.y]
	var nudge := [1, 2, -3]
	var scale := K * n
	for i in range(1, n + 1):
		var v := []
		var rnd := []
		for k in 3:
			var x: int = K * (ca[k] * (n - i) + cb[k] * i) + nudge[k] * n
			v.append(x)
			rnd.append(_floor_div(2 * x + scale, 2 * scale))
		var err := []
		for k in 3:
			err.append(absi(rnd[k] * scale - v[k]))
		if err[0] > err[1] and err[0] > err[2]:
			rnd[0] = -rnd[1] - rnd[2]
		elif err[1] > err[2]:
			rnd[1] = -rnd[0] - rnd[2]
		out.append(plot_of(Vector2i(rnd[0], rnd[1]), width, height))
	return out


static func _floor_div(a: int, b: int) -> int:
	var q := a / b
	return q - 1 if (a % b != 0) and ((a < 0) != (b < 0)) else q
