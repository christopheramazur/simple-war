class_name RouteGates
extends RefCounted
## The coarse layer of the battle router (sw-ll4.29: hierarchical A* over
## region gates, the sw-ll4.14 decision).
##
## The cells are cut into SECTOR x SECTOR squares. Where two neighbouring
## sectors touch, each run of passable cells along the border is a gate: a
## node on each side, at the middle of the run. Runs never cross a sector
## corner, so every gate belongs to one sector on each side.
##
## Baked once per route class and planning frame (BattleRoute._gates_of):
## every node's shortest in-sector paths to the other nodes of its sector, as
## a sector-local search tree. A plan is then:
##   1. a Dijkstra over the gate nodes (start and goal are searched inside
##      their own sectors first), which picks the gate path;
##   2. the cell path stitched from the baked in-sector trees, the gate
##      crossings, and a short in-sector search at each end.
## No cell-level search over the whole map runs per plan.
##
## Integers only. Ties break by node and cell index, so the bake and the
## search are the same on every machine and in the mirrored planning frame
## (sw-0nl). `plan` returns an empty path when it finds no gate route; the
## caller then runs the full cell search.

const SECTOR: int = 16

var w: int
var h: int
var sx: int
var sy: int
## Per node: its cell, its sector, the node across its gate, and the cost of
## the step across the gate.
var node_cell: PackedInt32Array = PackedInt32Array()
var node_sector: PackedInt32Array = PackedInt32Array()
var node_partner: PackedInt32Array = PackedInt32Array()
var node_cross_cost: PackedInt32Array = PackedInt32Array()
## Per node: the sector-local search tree rooted at the node (tree[local] is
## the step before local on the way from the root; -1 at the root).
var node_tree: Array = []
## Per sector: its node ids.
var sector_nodes: Array = []
## Per node: the other nodes of its sector, and the in-sector cost to each.
var intra_to: Array = []
var intra_cost: Array = []


static func build(costs: PackedInt32Array, width: int, height: int) -> RouteGates:
	var g := RouteGates.new()
	g.w = width
	g.h = height
	g.sx = (width + SECTOR - 1) / SECTOR
	g.sy = (height + SECTOR - 1) / SECTOR
	# Gate pairs as a * n + b (a on the lower-index side), sorted below, so the
	# node ids follow the cell order and equal routes break the way the cell
	# search does (lowest cell index first).
	var n := width * height
	var pairs := PackedInt64Array()
	# Gates across vertical borders: between column bx-1 and bx. A run is a
	# stretch of rows with the same pair of costs, so a road or a wall edge
	# gets its own gate instead of hiding inside a longer one.
	for bx in range(SECTOR, width, SECTOR):
		var y := 0
		while y < height:
			var a := costs[y * width + bx - 1]
			var b := costs[y * width + bx]
			if a > 0 and b > 0:
				var run_start := y
				y += 1
				while y < height and y % SECTOR != 0 and costs[y * width + bx - 1] == a and costs[y * width + bx] == b:
					y += 1
				var mid := run_start + (y - 1 - run_start) / 2
				pairs.append((mid * width + bx - 1) * n + mid * width + bx)
			else:
				y += 1
	# Gates across horizontal borders: between row by-1 and by.
	for by in range(SECTOR, height, SECTOR):
		var x := 0
		while x < width:
			var a := costs[(by - 1) * width + x]
			var b := costs[by * width + x]
			if a > 0 and b > 0:
				var run_start := x
				x += 1
				while x < width and x % SECTOR != 0 and costs[(by - 1) * width + x] == a and costs[by * width + x] == b:
					x += 1
				var mid := run_start + (x - 1 - run_start) / 2
				pairs.append(((by - 1) * width + mid) * n + by * width + mid)
			else:
				x += 1
	pairs.sort()
	var cells := PackedInt32Array()
	var partner := PackedInt32Array()
	for key in pairs:
		_add_pair(cells, partner, int(key / n), int(key % n))
	g.node_cell = cells
	g.node_partner = partner
	var nn := cells.size()
	g.node_sector.resize(nn)
	g.node_cross_cost.resize(nn)
	g.sector_nodes = []
	for s in g.sx * g.sy:
		g.sector_nodes.append(PackedInt32Array())
	for i in nn:
		var s := g.sector_of(cells[i])
		g.node_sector[i] = s
		g.node_cross_cost[i] = BattleRoute.STRAIGHT * costs[cells[partner[i]]]
		var members: PackedInt32Array = g.sector_nodes[s]
		members.append(i)
		g.sector_nodes[s] = members
	# In-sector trees, and the distances between every pair of gate nodes.
	g.node_tree = []
	g.intra_to = []
	g.intra_cost = []
	for i in nn:
		var found := g.search(costs, cells[i])
		var dist: PackedInt32Array = found[0]
		var to := PackedInt32Array()
		var cost := PackedInt32Array()
		for j: int in g.sector_nodes[g.node_sector[i]]:
			if j == i:
				continue
			var d := dist[g.local_of(cells[j])]
			if d >= 0:
				to.append(j)
				cost.append(d)
		g.node_tree.append(found[1])
		g.intra_to.append(to)
		g.intra_cost.append(cost)
	return g


static func _add_pair(cells: PackedInt32Array, partner: PackedInt32Array, a: int, b: int) -> void:
	var ia := cells.size()
	cells.append(a)
	cells.append(b)
	partner.append(ia + 1)
	partner.append(ia)


func sector_of(cell: int) -> int:
	@warning_ignore("integer_division")
	var y := cell / w
	return (y / SECTOR) * sx + (cell % w) / SECTOR


func _x0(s: int) -> int:
	return (s % sx) * SECTOR


func _y0(s: int) -> int:
	@warning_ignore("integer_division")
	return (s / sx) * SECTOR


func _sw(s: int) -> int:
	return mini(SECTOR, w - _x0(s))


func _sh(s: int) -> int:
	return mini(SECTOR, h - _y0(s))


## Index of a cell within its own sector.
func local_of(cell: int) -> int:
	var s := sector_of(cell)
	@warning_ignore("integer_division")
	var y := cell / w
	return (y - _y0(s)) * _sw(s) + (cell % w - _x0(s))


func cell_of(s: int, local: int) -> int:
	var sw := _sw(s)
	@warning_ignore("integer_division")
	var ly := local / sw
	return (_y0(s) + ly) * w + _x0(s) + local % sw


## Dijkstra inside the sector of `src`: [dist, prev], both indexed by the
## sector-local index (dist -1 if unreached). Same step costs and no-corner
## rule as BattleRoute._plan.
func search(costs: PackedInt32Array, src: int) -> Array:
	var s := sector_of(src)
	var sw := _sw(s)
	var sh := _sh(s)
	var size := sw * sh
	var x0 := _x0(s)
	var y0 := _y0(s)
	var dist := PackedInt32Array()
	dist.resize(size)
	dist.fill(-1)
	var prev := PackedInt32Array()
	prev.resize(size)
	prev.fill(-1)
	var heap := PackedInt64Array()
	var root := local_of(src)
	dist[root] = 0
	BattleRoute._push(heap, root)
	while not heap.is_empty():
		var key := BattleRoute._pop(heap)
		var li := int(key % size)
		var d := int(key / size)
		if d != dist[li]:
			continue
		var x := x0 + li % sw
		@warning_ignore("integer_division")
		var y := y0 + li / sw
		for k in 8:
			var nx := x + BattleRoute._DX[k]
			var ny := y + BattleRoute._DY[k]
			if nx < x0 or ny < y0 or nx >= x0 + sw or ny >= y0 + sh:
				continue
			var nc := ny * w + nx
			if costs[nc] == 0:
				continue
			if k >= 4 and (costs[y * w + nx] == 0 or costs[ny * w + x] == 0):
				continue
			var nd := d + (BattleRoute.DIAGONAL if k >= 4 else BattleRoute.STRAIGHT) * costs[nc]
			var nl := (ny - y0) * sw + (nx - x0)
			if dist[nl] < 0 or nd < dist[nl]:
				dist[nl] = nd
				prev[nl] = li
				BattleRoute._push(heap, nd * size + nl)
	return [dist, prev]


## The cell path from `start` to `goal` (both passable, in one region), not
## including `start` and ending at `goal`. Empty if they share a sector (the
## caller searches that sector's cells directly) or no gate route exists.
func plan(costs: PackedInt32Array, start: int, goal: int) -> PackedInt32Array:
	var s_start := sector_of(start)
	var s_goal := sector_of(goal)
	if s_start == s_goal:
		return PackedInt32Array()
	var from_start := search(costs, start)
	var from_goal := search(costs, goal)
	var ds: PackedInt32Array = from_start[0]
	var dg: PackedInt32Array = from_goal[0]
	var nn := node_cell.size()
	# Dijkstra over the gate nodes, seeded from the start's sector.
	var best := PackedInt64Array()
	best.resize(nn)
	best.fill(-1)
	var prev := PackedInt32Array()
	prev.resize(nn)
	prev.fill(-1)
	var heap := PackedInt64Array()
	for v: int in sector_nodes[s_start]:
		var d := ds[local_of(node_cell[v])]
		if d >= 0:
			best[v] = d
			BattleRoute._push(heap, d * nn + v)
	var found := -1
	var found_total := -1
	while not heap.is_empty():
		var key := BattleRoute._pop(heap)
		var v := int(key % nn)
		var d := int(key / nn)
		if d != best[v]:
			continue
		if found_total >= 0 and d >= found_total:
			break
		if node_sector[v] == s_goal and dg[local_of(node_cell[v])] >= 0:
			var total := d + dg[local_of(node_cell[v])]
			if found_total < 0 or total < found_total or (total == found_total and node_cell[v] < node_cell[found]):
				found_total = total
				found = v
		var to: PackedInt32Array = intra_to[v]
		var cost: PackedInt32Array = intra_cost[v]
		for i in to.size():
			_relax(heap, best, prev, to[i], d + cost[i], v, nn)
		_relax(heap, best, prev, node_partner[v], d + node_cross_cost[v], v, nn)
	if found < 0:
		return PackedInt32Array()
	# The gate nodes in order, from the start sector to the goal's.
	var chain := PackedInt32Array()
	var at := found
	while at >= 0:
		chain.append(at)
		at = prev[at]
	chain.reverse()
	# Stitch: start to the first node, node to node, last node to the goal.
	var path := PackedInt32Array()
	path.append_array(_back_to_root(from_start[1], s_start, local_of(node_cell[chain[0]])))
	for i in range(1, chain.size()):
		var u := chain[i - 1]
		var v := chain[i]
		if node_partner[u] == v:
			path.append(node_cell[v])
		else:
			path.append_array(_back_to_root(node_tree[u], node_sector[v], local_of(node_cell[v]), local_of(node_cell[u])))
	var tree_goal: PackedInt32Array = from_goal[1]
	var l := local_of(node_cell[chain[chain.size() - 1]])
	while tree_goal[l] >= 0:
		l = tree_goal[l]
		path.append(cell_of(s_goal, l))
	return path


## Cells on the tree path from `local` back towards its root, root excluded,
## in path order (the root's side first). `root` is the root's local index,
## or -1 to walk to the root itself.
func _back_to_root(tree: PackedInt32Array, s: int, local: int, root: int = -1) -> PackedInt32Array:
	var seg := PackedInt32Array()
	var l := local
	while l != root and tree[l] >= 0:
		seg.append(cell_of(s, l))
		l = tree[l]
	seg.reverse()
	return seg


static func _relax(heap: PackedInt64Array, best: PackedInt64Array, prev: PackedInt32Array, u: int, nd: int, via: int, nn: int) -> void:
	if best[u] < 0 or nd < best[u]:
		best[u] = nd
		prev[u] = via
		BattleRoute._push(heap, nd * nn + u)

