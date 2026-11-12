class_name OverworldPath
extends RefCounted
## Cheapest routes between plots, for drafting commander routes (GDD 02
## §2.9). Dijkstra on movement cost with ties broken by plot index, so the
## same query always gives the same path. Guards are not avoided: the player
## can see the feature but never what its forces will do (R5Q9). A battle
## tile may only be the destination (R4Q13). Costs are what `player` knows
## under fog of war (OverworldVision.known_costs); player 0 knows the truth.


## Plots to enter from `from` to `to` (start excluded, `to` included), or
## empty if unreachable or `from == to`. Plots marked 1 in `avoid` are
## never entered, except `to`.
static func find(s: OverworldState, from: int, to: int, player: int = 0, avoid: PackedByteArray = PackedByteArray()) -> PackedInt64Array:
	var r := s.rules
	var n := r.plot_count()
	if from == to or from < 0 or to < 0 or from >= n or to >= n:
		return PackedInt64Array()
	var costs := OverworldVision.known_costs(s, player)
	if costs[to] < 0:
		return PackedInt64Array()
	var dist := PackedInt64Array()
	dist.resize(n)
	dist.fill(-1)
	var prev := PackedInt64Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	var heap := PackedInt64Array()  # keys: cost * n + plot
	dist[from] = 0
	heap = _push(heap, from)
	while not heap.is_empty():
		var key := heap[0]
		heap = _pop(heap)
		var p := key % n
		if done[p] == 1:
			continue
		done[p] = 1
		if p == to:
			break
		if p != from and s.engagement_at(p) >= 0:
			continue  # a battle tile ends movement: nothing continues past it
		for q in Hex.neighbours(p, r.width, r.height):
			var c := costs[q]
			if c < 0 or done[q] == 1 or (q != to and not avoid.is_empty() and avoid[q] == 1):
				continue
			var d := dist[p] + c
			if dist[q] < 0 or d < dist[q]:
				dist[q] = d
				prev[q] = p
				heap = _push(heap, d * n + q)
	if dist[to] < 0:
		return PackedInt64Array()
	var path := PackedInt64Array()
	var at := to
	while at != from:
		path.append(at)
		at = prev[at]
	path.reverse()
	return path


## Movement points to walk `plots` in order from `from`, or -1 if a step is
## not to a neighbour or enters an impassable plot.
static func cost(s: OverworldState, from: int, plots: PackedInt64Array) -> int:
	var total := 0
	var at := from
	for p in plots:
		if p < 0 or p >= s.rules.plot_count() or not Hex.adjacent(at, p, s.rules.width):
			return -1
		var c := s.move_cost(p)
		if c < 0:
			return -1
		total += c
		at = p
	return total


# Binary min-heap on a packed array (deterministic, no floats).
static func _push(h: PackedInt64Array, v: int) -> PackedInt64Array:
	h.append(v)
	var i := h.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if h[parent] <= h[i]:
			break
		var t := h[parent]
		h[parent] = h[i]
		h[i] = t
		i = parent
	return h


static func _pop(h: PackedInt64Array) -> PackedInt64Array:
	var last := h[h.size() - 1]
	h.resize(h.size() - 1)
	if h.is_empty():
		return h
	h[0] = last
	var i := 0
	while true:
		var l := 2 * i + 1
		var m := i
		if l < h.size() and h[l] < h[m]:
			m = l
		if l + 1 < h.size() and h[l + 1] < h[m]:
			m = l + 1
		if m == i:
			break
		var t := h[m]
		h[m] = h[i]
		h[i] = t
		i = m
	return h
