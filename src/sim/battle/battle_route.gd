class_name BattleRoute
extends RefCounted
## Routes a squad's formation anchor over the battlefield's 1 m cells.
## GDD 02 §2.14 (O1Q8), sw-ll4.4.
##
## `next_waypoint` answers one question: from this cell, heading for that
## point, where does the anchor walk in a straight line next? The squad asks
## again when it gets there. The answer depends only on the rules, the route
## class and the two cells, so it is cached here and never saved or hashed:
## a restored or forecast battle recomputes the same answers. The cache is
## not thread-safe: a forecast plans into its own copy of the rules
## (BattleRules.forecast_copy), never into the battle's own cache, and
## callers warm the shared caches before threaded jobs (warm,
## IntentForecast.job) so the copies start from filled caches.
##
## Integers only. Entering a cell costs 10 (14 diagonally) times the cell's
## cost; a cost of 0 is impassable. Equal routes are broken by cell index in
## the planning frame: a side facing 180° plans on the rotated grid, so its
## tie-breaks mirror its rival's instead of favouring one compass corner
## (sw-0nl).
##
## A route class is a set of terrain costs shared by squad templates
## (BattleRules.rt_cost): each feature costs what the slowest member pays, and
## is impassable if any member can't enter it.

const STRAIGHT: int = 10
const DIAGONAL: int = 14
## A straight line may cost this much (percent) of the cell path it replaces.
## Over 100 because 14 understates a diagonal step (14.14).
const SHORTCUT_PCT: int = 103
const CACHE_MAX: int = 8192

const _DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const _DY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]

## ((frame * classes + class) * n + start) * n + goal -> waypoint cell * 2
## + (1 if it is the goal). Cells are in the planning frame, so a flipped
## plan never reuses an unflipped one.
var _cache: Dictionary = {}
## Per route class: cost per cell (0 impassable), and connected region per cell.
var _costs: Dictionary = {}
var _regions: Dictionary = {}
## Per route class: the cheapest passable cell cost (the A* heuristic's scale).
var _min_costs: Dictionary = {}
## The same, reversed: cell c of the 180° frame is cell n-1-c of the map.
var _costs_flipped: Dictionary = {}
var _regions_flipped: Dictionary = {}
## Plans made (cache misses), for tests and profiling.
var plans: int = 0


## [x, y, final] in fixed point. `final` is 1 when x, y is where the squad
## stops: the destination itself, or the nearest cell it can reach.
## `frame` is the side's facing: at ANGLE_HALF the whole plan (costs, start,
## goal, tie-breaks) runs in the 180°-rotated player-canonical frame and the
## answer rotates back, so mirrored seats take mirrored detours (sw-0nl).
## Other facings plan unrotated.
func next_waypoint(r: BattleRules, route_class: int, from_x: int, from_y: int, to_x: int, to_y: int, frame: int = 0) -> PackedInt64Array:
	var w := r.width
	var n := w * r.height
	var flip := frame == Fixed.ANGLE_HALF
	var costs := _costs_of(r, route_class, flip)
	var regions: PackedInt32Array = (_regions_flipped if flip else _regions)[route_class]
	var start := _cell(r, from_x, from_y)
	var goal := _cell(r, to_x, to_y)
	if flip:
		start = n - 1 - start
		goal = n - 1 - goal
	if costs[start] == 0:
		# Standing where it can't be (a map change, a spawn): step out first.
		var out := _nearest(r, costs, PackedInt32Array(), start, -1)
		if out < 0:
			return PackedInt64Array([to_x, to_y, 1])
		return _centre((n - 1 - out) if flip else out, w, 0)
	var exact := true
	if costs[goal] == 0 or regions[goal] != regions[start]:
		goal = _nearest(r, costs, regions, goal, regions[start])
		exact = false
	if goal == start:
		return PackedInt64Array([to_x, to_y, 1]) if exact else _centre((n - 1 - goal) if flip else goal, w, 1)
	var key := (((1 if flip else 0) * r.rt_cost.size() + route_class) * n + start) * n + goal
	var hit: int = _cache.get(key, -1)
	if hit < 0:
		if _cache.size() >= CACHE_MAX:
			_cache.clear()
		hit = _plan(costs, w, r.height, start, goal, _min_costs[route_class])
		_cache[key] = hit
		plans += 1
	if hit & 1 == 1 and exact:
		return PackedInt64Array([to_x, to_y, 1])
	var cell := hit >> 1
	return _centre((n - 1 - cell) if flip else cell, w, hit & 1)


static func _cell(r: BattleRules, x: int, y: int) -> int:
	return clampi(Fixed.to_int_floor(y), 0, r.height - 1) * r.width + clampi(Fixed.to_int_floor(x), 0, r.width - 1)


static func _centre(cell: int, w: int, final: int) -> PackedInt64Array:
	@warning_ignore("integer_division")
	return PackedInt64Array([Fixed.from_int(cell % w) + Fixed.ONE / 2, Fixed.from_int(cell / w) + Fixed.ONE / 2, final])


## Fills the cost and region caches for every route class in both planning
## frames, so a forecast on a worker thread (IntentForecast.job) only ever
## reads them. Call it on the caller's thread, before the job runs; building
## them lazily from two threads at once races (sw-0nl).
func warm(r: BattleRules) -> void:
	for cls in r.rt_cost.size():
		_costs_of(r, cls)
		_costs_of(r, cls, true)


func _costs_of(r: BattleRules, route_class: int, flip: bool = false) -> PackedInt32Array:
	if flip:
		if not _costs_flipped.has(route_class):
			var costs := _costs_of(r, route_class).duplicate()
			costs.reverse()
			var regions: PackedInt32Array = (_regions[route_class] as PackedInt32Array).duplicate()
			regions.reverse()
			# Regions before costs: next_waypoint reads both, so anyone who
			# sees the costs must see the regions too. Threaded callers warm.
			_regions_flipped[route_class] = regions
			_costs_flipped[route_class] = costs
		return _costs_flipped[route_class]
	if _costs.has(route_class):
		return _costs[route_class]
	var by_feature: PackedInt32Array = r.rt_cost[route_class]
	var n := r.width * r.height
	var costs := PackedInt32Array()
	costs.resize(n)
	for c in n:
		costs[c] = by_feature[r.terrain[c]]
	_costs[route_class] = costs
	_regions[route_class] = _label_regions(costs, r.width, r.height)
	var min_cost := 0
	for c in costs:
		if c > 0 and (min_cost == 0 or c < min_cost):
			min_cost = c
	_min_costs[route_class] = min_cost
	return costs


## Numbers each connected passable region (4-neighbour, which is what the
## no-corner-cutting rule for diagonal steps allows). Impassable cells get -1.
static func _label_regions(costs: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var n := w * h
	var regions := PackedInt32Array()
	regions.resize(n)
	regions.fill(-1)
	var stack := PackedInt32Array()
	var next_region := 0
	for seed_cell in n:
		if costs[seed_cell] == 0 or regions[seed_cell] >= 0:
			continue
		regions[seed_cell] = next_region
		stack.append(seed_cell)
		while not stack.is_empty():
			var c := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var x := c % w
			if x > 0 and costs[c - 1] > 0 and regions[c - 1] < 0:
				regions[c - 1] = next_region
				stack.append(c - 1)
			if x < w - 1 and costs[c + 1] > 0 and regions[c + 1] < 0:
				regions[c + 1] = next_region
				stack.append(c + 1)
			if c >= w and costs[c - w] > 0 and regions[c - w] < 0:
				regions[c - w] = next_region
				stack.append(c - w)
			if c < n - w and costs[c + w] > 0 and regions[c + w] < 0:
				regions[c + w] = next_region
				stack.append(c + w)
		next_region += 1
	return regions


## The passable cell nearest to `cell` (in `region`, or any if region < 0):
## the closest ring of cells around it that has one, then the least straight
## distance, then the lowest cell index. -1 if there is none.
static func _nearest(r: BattleRules, costs: PackedInt32Array, regions: PackedInt32Array, cell: int, region: int) -> int:
	var w := r.width
	var h := r.height
	var cx := cell % w
	@warning_ignore("integer_division")
	var cy := cell / w
	for ring in range(1, maxi(w, h)):
		var best := -1
		var best_d := 0
		for y in range(maxi(cy - ring, 0), mini(cy + ring, h - 1) + 1):
			var edge_row := absi(y - cy) == ring
			var x := maxi(cx - ring, 0)
			while x <= mini(cx + ring, w - 1):
				if edge_row or absi(x - cx) == ring:
					var c := y * w + x
					if costs[c] > 0 and (region < 0 or regions[c] == region):
						var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
						if best < 0 or d < best_d:
							best = c
							best_d = d
					x += 1
				else:
					# Inside the ring on this row: jump to its right edge.
					x = cx + ring
		if best >= 0:
			return best
	return -1


## A* from start to goal (both passable, same region), then the farthest
## cell on that path the anchor can walk straight to at no more than the
## path's cost. Returns waypoint cell * 2 + (1 if it is the goal).
func _plan(costs: PackedInt32Array, w: int, h: int, start: int, goal: int, min_cost: int) -> int:
	var n := w * h
	var gx := goal % w
	@warning_ignore("integer_division")
	var gy := goal / w
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(-1)
	var from := PackedInt32Array()
	from.resize(n)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap := PackedInt64Array()
	g[start] = 0
	heap.append(start)
	while not heap.is_empty():
		var c := int(_pop(heap) % n)
		if closed[c] == 1:
			continue
		closed[c] = 1
		if c == goal:
			break
		var x := c % w
		@warning_ignore("integer_division")
		var y := c / w
		for d in 8:
			var nx := x + _DX[d]
			var ny := y + _DY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nc := ny * w + nx
			if closed[nc] == 1 or costs[nc] == 0:
				continue
			# No cutting corners: a diagonal step needs both sides open.
			if d >= 4 and (costs[y * w + nx] == 0 or costs[ny * w + x] == 0):
				continue
			var ng := g[c] + (DIAGONAL if d >= 4 else STRAIGHT) * costs[nc]
			if g[nc] >= 0 and ng >= g[nc]:
				continue
			g[nc] = ng
			from[nc] = c
			var ax := absi(nx - gx)
			var ay := absi(ny - gy)
			var estimate := (STRAIGHT * maxi(ax, ay) + (DIAGONAL - STRAIGHT) * mini(ax, ay)) * min_cost
			_push(heap, (ng + estimate) * n + nc)
	var path := PackedInt32Array()
	var at := goal
	while at != start:
		path.append(at)
		at = from[at]
	# path runs goal -> first step; walk it from the far end.
	for i in path.size() - 1:
		if _straight_ok(costs, w, start, path[i], g[path[i]]):
			return path[i] * 2 + (1 if i == 0 else 0)
	return path[path.size() - 1] * 2 + (1 if path.size() == 1 else 0)


## True if the straight line between two cell centres stays on passable
## cells, cuts no corner, and costs no more than `budget` (the cell path's
## cost) allowing SHORTCUT_PCT.
static func _straight_ok(costs: PackedInt32Array, w: int, a: int, b: int, budget: int) -> bool:
	var ax := a % w
	@warning_ignore("integer_division")
	var ay := a / w
	var dx := b % w - ax
	@warning_ignore("integer_division")
	var dy := b / w - ay
	var steps := 2 * maxi(absi(dx), absi(dy))
	var total := 0
	var px := ax
	var py := ay
	for i in range(1, steps + 1):
		@warning_ignore("integer_division")
		var x := ((2 * ax + 1) * steps + 2 * dx * i) / (2 * steps)
		@warning_ignore("integer_division")
		var y := ((2 * ay + 1) * steps + 2 * dy * i) / (2 * steps)
		var cost := costs[y * w + x]
		if cost == 0:
			return false
		if x != px and y != py and (costs[py * w + x] == 0 or costs[y * w + px] == 0):
			return false
		total += cost
		px = x
		py = y
	# Length in tenths of a metre, times the average cost along the line.
	var length := Fixed.length(Fixed.from_int(dx), Fixed.from_int(dy)) * STRAIGHT / Fixed.ONE
	@warning_ignore("integer_division")
	return length * total / steps * 100 <= budget * SHORTCUT_PCT


# A binary min-heap of ints in a packed array.
static func _push(heap: PackedInt64Array, key: int) -> void:
	var i := heap.size()
	heap.append(key)
	while i > 0:
		@warning_ignore("integer_division")
		var parent := (i - 1) / 2
		if heap[parent] <= key:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = key


static func _pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	var size := heap.size()
	if size == 0:
		return top
	var i := 0
	while true:
		var child := 2 * i + 1
		if child >= size:
			break
		if child + 1 < size and heap[child + 1] < heap[child]:
			child += 1
		if heap[child] >= last:
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return top
