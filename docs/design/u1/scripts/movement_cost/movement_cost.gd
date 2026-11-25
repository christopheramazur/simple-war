extends SceneTree
## U1 A6 movement spike (sw-txnj.3), throwaway. Scratch only: nothing here
## ships, the prototypes run as extra systems inside this script's runner.
##
## Measures per-tick cost of MovementSystem and CombatSystem and one
## IntentForecast at 4, 20 and 40 squads on Crossroads (duel_crossroads, real
## core data), then adds two prototypes:
##   - the U1Q29 per-unit firing-position search (rings around the slot toward
##     the target, inside coherency, enterable, first with a shot), every tick
##     and on a staggered N-tick re-evaluation;
##   - the draft 01 §3.3 separation pass (2 m spatial hash) and, for
##     comparison, a squad-circle broadphase doing the same pushes.
## Determinism: each variant is run twice from the same start and the state
## hash (plus the search results folded in) must match.
##
## Run: harness/bin/hx godot run docs/design/u1/scripts/movement_cost/movement_cost.gd --tail 200 --timeout 1200

const ONE := Fixed.ONE
const TICKS := 300  # three turns at 10 tps
const SEP_RADIUS := ONE * 6 / 10  # medium size class (no size class in data yet)
const CELL := 2 * ONE

var rules: BattleRules
var mix := PackedStringArray()


func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	Stats.warm(rules)
	rules.routes.warm(rules)
	for side: Dictionary in rules.sides:
		if int(side["player"]) == 1:
			for s in side["squads"]:
				mix.append(String(s))
	print("map %dx%d m, tps %d, ticks/turn %d, squad mix per side %s" % [rules.width, rules.height, rules.tps, rules.ticks_per_turn, mix])
	var args := OS.get_cmdline_user_args()
	var counts := [4, 20, 40]
	if args.has("--quick"):
		counts = [4]
	for n in counts:
		_scenario(n)
	if not args.has("--quick") and not args.has("--no-sweep"):
		_param_sweep(40)
	quit(0)


# --- scenario --------------------------------------------------------------

## n squads, half per side, in two blocks 60 m apart across the centre of
## Crossroads, every squad on attack-move toward its mirror, so they close,
## engage and fight through the terrain in the middle.
func _make_state(n: int) -> BattleState:
	var s := BattleState.new(1, rules, 1)
	var per_side := n / 2
	var cols := 2 if per_side <= 4 else 4
	for i in per_side:
		var c := i % cols
		var rr := i / cols
		var rows := ceili(float(per_side) / cols)
		var y := 50 - (rows - 1) * 7 + rr * 14
		y = clampi(y, 8, rules.height - 8)
		var sq_name := mix[i % mix.size()]
		var a := BattleSetup.spawn_squad(s, 1, rules.squad_index(sq_name), (70 - c * 7) * ONE, y * ONE, 0)
		var b := BattleSetup.spawn_squad(s, 2, rules.squad_index(sq_name), (130 + c * 7) * ONE, y * ONE, Fixed.ANGLE_HALF)
		Centroids.update(s)
		var ra := s.squads.row_of(a)
		var rb := s.squads.row_of(b)
		BattleOrders.set_order(s, ra, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[rb], s.squads.cy[rb], -1, 0)
		BattleOrders.set_order(s, rb, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[ra], s.squads.cy[ra], -1, 0)
	Centroids.update(s)
	return s


## A BattleSim whose "move" phase also runs the given prototype systems after
## MovementSystem (the order draft 01 §3.3 puts separation in).
func _sim(extra: Array[SimSystem]) -> BattleSim:
	var sim := BattleSim.new()
	var runner := SystemRunner.new()
	runner.add_phase(&"effects", [AbilitySystem.new(), EffectSystem.new()] as Array[SimSystem])
	var mv: Array[SimSystem] = [Centroids.new(), MovementSystem.new()]
	mv.append_array(extra)
	runner.add_phase(&"move", mv)
	runner.add_phase(&"sense", [Centroids.new(), VisionSystem.new(), Reactions.new()] as Array[SimSystem])
	runner.add_phase(&"fight", [CombatSystem.new(), HealthSystem.new()] as Array[SimSystem])
	runner.add_phase(&"pressure", [Centroids.new(), PoolsSystem.new()] as Array[SimSystem])
	sim.runner = runner
	return sim


## Runs TICKS ticks; returns per-tick ms for each system, total, and hash.
func _measure(n: int, extra: Array[SimSystem]) -> Dictionary:
	var s := _make_state(n)
	var sim := _sim(extra)
	sim.runner.profiling = true
	sim.runner.profile = {}
	var t0 := Time.get_ticks_usec()
	s.begin_turn()
	for t in TICKS:
		if t > 0 and t % rules.ticks_per_turn == 0:
			s.begin_turn()
		sim.runner.step(s)
	var total := Time.get_ticks_usec() - t0
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.state_hash())
	for x in extra:
		if x.has_method("fold_hash"):
			x.fold_hash(h)
	var alive := 0
	for row in s.units.count():
		if s.units.hp[row] > 0:
			alive += 1
	return {"profile": sim.runner.profile, "total_us": total, "hash": h.finish().hex_encode().substr(0, 16), "alive": alive}


func _forecast_ms(n: int, extra: Array[SimSystem], reps: int) -> float:
	var s := _make_state(n)
	var sim := _sim(extra)
	var best := 1 << 62
	for i in reps:
		var t0 := Time.get_ticks_usec()
		IntentForecast.run(s, sim, 1, [])
		best = mini(best, Time.get_ticks_usec() - t0)
	return best / 1000.0


func _ms(p: Dictionary, key: String) -> float:
	return int(p.get(key, 0)) / 1000.0 / TICKS


func _scenario(n: int) -> void:
	var s0 := _make_state(n)
	var units := s0.units.count()
	print("\n== %d squads, %d units, %d ticks ==" % [n, units, TICKS])
	var variants := [
		["today", func() -> Array[SimSystem]: return [] as Array[SimSystem]],
		["+search every tick", func() -> Array[SimSystem]: return [FiringSearch.new(1, 2, 3, 7)] as Array[SimSystem]],
		["+search every 5 ticks", func() -> Array[SimSystem]: return [FiringSearch.new(5, 2, 3, 7)] as Array[SimSystem]],
		["+separation (2 m hash)", func() -> Array[SimSystem]: return [SeparationHash.new()] as Array[SimSystem]],
		["+separation (squad broadphase)", func() -> Array[SimSystem]: return [SeparationSquads.new()] as Array[SimSystem]],
		["+search/5 +separation(hash)", func() -> Array[SimSystem]: return [FiringSearch.new(5, 2, 3, 7), SeparationHash.new()] as Array[SimSystem]],
	]
	print("variant | movement ms/t | combat ms/t | prototype ms/t | whole tick ms/t | forecast ms | alive end | determinism | search stats")
	for v in variants:
		var mk: Callable = v[1]
		var a := _measure(n, mk.call())
		var b_extra: Array[SimSystem] = mk.call()
		var b := _measure(n, b_extra)
		var p: Dictionary = a["profile"]
		var proto := 0.0
		for k: String in p:
			if k.contains("FiringSearch") or k.contains("Separation"):
				proto += _ms(p, k)
		var fc := _forecast_ms(n, mk.call(), 3)
		var stats := ""
		for x in b_extra:
			if x is FiringSearch:
				stats += (x as FiringSearch).stats()
			if x is SeparationHash or x is SeparationSquads:
				stats += " pushes/t %.1f" % (x.pushes / float(TICKS))
		print("%s | %.3f | %.3f | %.3f | %.3f | %.1f | %d | %s | %s" % [v[0], _ms(p, "move/MovementSystem"), _ms(p, "fight/CombatSystem"), proto,
			a["total_us"] / 1000.0 / TICKS, fc, a["alive"],
			"same %s" % a["hash"] if a["hash"] == b["hash"] else "DIFF %s %s" % [a["hash"], b["hash"]], stats])
	var a2 := _measure(n, [] as Array[SimSystem])
	var keys: Array = a2["profile"].keys()
	keys.sort()
	var parts := PackedStringArray()
	for k: String in keys:
		parts.append("%s %.3f" % [k, _ms(a2["profile"], k)])
	print("today, every system ms/tick: " + ", ".join(parts))


func _param_sweep(n: int) -> void:
	print("\n== search parameter sweep at %d squads (ms/tick of the search alone; stats) ==" % n)
	print("cadence | ring step m | rings | angles | ms/tick | stats")
	for p in [[1, 2, 2, 5], [1, 2, 3, 7], [1, 1, 4, 9], [1, 2, 4, 9], [5, 2, 2, 5], [5, 2, 3, 7], [10, 2, 3, 7], [5, 1, 4, 9], [5, 2, 4, 9]]:
		var fs := FiringSearch.new(p[0], p[1], p[2], p[3])
		var a := _measure(n, [fs] as Array[SimSystem])
		print("%d | %d | %d | %d | %.3f | %s" % [p[0], p[1], p[2], p[3], _ms(a["profile"], "move/FiringSearch"), fs.stats()])


# --- prototype: per-unit firing-position search (U1Q29) --------------------

class FiringSearch:
	extends SimSystem
	## Every armed unit of an attack-move / attack squad looks for the first
	## point with a shot at a unit of its target squad (the engaged one, else
	## the nearest living enemy squad): its own spot, then its slot, then rings
	## of `rings` x `step` m around the slot, `angles` points per ring spread
	## over the half circle facing the target, in order 0, +1, -1, +2, -2...
	## Candidates outside coherency (formation half-width + 4 m of the anchor)
	## or on a cell the unit can't enter are skipped. With cadence N, unit row
	## r searches on ticks where (tick + r) % N == 0; results persist between.
	var cadence: int
	var step: int
	var rings: int
	var angles: int
	var fx := PackedInt64Array()
	var fy := PackedInt64Array()
	var searches := 0
	var candidates := 0
	var los_calls := 0
	var found := 0

	func _init(c: int, step_m: int, ring_count: int, angle_count: int) -> void:
		cadence = c
		step = step_m * Fixed.ONE
		rings = ring_count
		angles = angle_count

	func system_name() -> StringName:
		return &"firing_search"

	func stats() -> String:
		if searches == 0:
			return "no searches"
		return "searches/t %.1f, cand/search %.2f, los/search %.2f, found %.0f%%" % [searches / float(TICKS), candidates / float(searches), los_calls / float(searches), 100.0 * found / searches]

	func fold_hash(h: HashingContext) -> void:
		h.update(fx.to_byte_array())
		h.update(fy.to_byte_array())

	func run(ctx: SimContext) -> void:
		var state := ctx as BattleState
		var r := state.rules
		var sq := state.squads
		var u := state.units
		if fx.size() != u.count():
			fx.resize(u.count())
			fy.resize(u.count())
		var max_x := Fixed.from_int(r.width) - 1
		var max_y := Fixed.from_int(r.height) - 1
		for srow in sq.count():
			if not sq.is_active(srow) or sq.alive[srow] == 0:
				continue
			var order := sq.order[srow]
			if order != BattleSquads.Order.ATTACK_MOVE and order != BattleSquads.Order.ATTACK:
				continue
			var trow := _target(state, srow)
			if trow < 0:
				continue
			var targets := Centroids.units_of(state, trow)
			var st := sq.tmpl[srow]
			var members := sq.form_size[srow]
			if members <= 0:
				members = r.sq_members[st].size()
			var coh := _half_width(r, st, members) + 4 * Fixed.ONE
			var toward := Fixed.atan2(sq.cy[trow] - sq.ay[srow], sq.cx[trow] - sq.ax[srow])
			for urow in Centroids.units_of(state, srow):
				if u.hp[urow] <= 0 or u.weapon[urow] < 0:
					continue
				if cadence > 1 and (state.tick + urow) % cadence != 0:
					continue
				searches += 1
				var w := u.weapon[urow]
				var ind := r.indirect(w)
				var profile := r.ut_movement[u.tmpl[urow]]
				var off := Formation.offset(r.sq_shape[st], u.slot[urow], members, r.sq_spacing[st], sq.facing[srow])
				var gx := Fixed.clamp_fixed(sq.ax[srow] + off[0], 0, max_x)
				var gy := Fixed.clamp_fixed(sq.ay[srow] + off[1], 0, max_y)
				var hit := -1
				# Ring 0: where it stands, then its slot.
				candidates += 1
				if _shot(state, r, w, ind, u.x[urow], u.y[urow], targets):
					hit = 0
					fx[urow] = u.x[urow]
					fy[urow] = u.y[urow]
				if hit < 0:
					candidates += 1
					if _shot(state, r, w, ind, gx, gy, targets):
						hit = 0
						fx[urow] = gx
						fy[urow] = gy
				var k := 1
				while hit < 0 and k <= rings:
					var rad := k * step
					for j in angles:
						# 0, +1, -1, +2, -2 ... across the forward half circle.
						var idx := (j + 1) / 2
						var sgn := 1 if j % 2 == 1 else -1
						var spread := Fixed.ANGLE_HALF / maxi(angles - 1, 1)
						var ang := (toward + sgn * idx * spread) & Fixed.ANGLE_MASK
						var px := gx + Fixed.mul(rad, Fixed.fcos(ang))
						var py := gy + Fixed.mul(rad, Fixed.fsin(ang))
						if px < 0 or py < 0 or px > max_x or py > max_y:
							continue
						if Fixed.distance(px, py, sq.ax[srow], sq.ay[srow]) > coh:
							continue
						if r.mv_cost[profile * r.feature_count() + r.feature_at(px, py)] <= 0:
							continue
						candidates += 1
						if _shot(state, r, w, ind, px, py, targets):
							hit = k
							fx[urow] = px
							fy[urow] = py
							break
					k += 1
				if hit >= 0:
					found += 1
				else:
					fx[urow] = -1
					fy[urow] = -1

	## The squad it engages, else the nearest living enemy squad (worst case:
	## every armed unit of every attacking squad searches).
	func _target(state: BattleState, srow: int) -> int:
		var sq := state.squads
		var t := sq.row_of(sq.engaged[srow]) if sq.engaged[srow] >= 0 else -1
		if t >= 0 and sq.is_active(t) and sq.alive[t] > 0:
			return t
		var best := -1
		var best_d := 1 << 62
		for o in sq.count():
			if sq.player[o] == sq.player[srow] or not sq.is_active(o) or sq.alive[o] == 0:
				continue
			var d := Fixed.distance(sq.cx[srow], sq.cy[srow], sq.cx[o], sq.cy[o])
			if d < best_d:
				best_d = d
				best = o
		return best

	## The per-unit shot gate (CombatSystem.shot_gate) from a point: some
	## living target unit within [min range, range], and line of fire unless
	## the weapon has an indirect mode.
	func _shot(state: BattleState, r: BattleRules, w: int, ind: bool, px: int, py: int, targets: PackedInt64Array) -> bool:
		var u := state.units
		var rng := r.wp_range[w]
		var mn := r.wp_min_range[w]
		for t in targets:
			if u.hp[t] <= 0:
				continue
			var d := Fixed.distance(px, py, u.x[t], u.y[t])
			if d > rng or d < mn:
				continue
			if ind:
				return true
			los_calls += 1
			if r.los(px, py, u.x[t], u.y[t]):
				return true
		return false

	static func _half_width(r: BattleRules, st: int, members: int) -> int:
		var best := 0
		for i in members:
			var off := Formation.offset(r.sq_shape[st], i, members, r.sq_spacing[st], 0)
			best = maxi(best, Fixed.length(off[0], off[1]))
		return best


# --- prototype: separation (draft 01 §3.3) ---------------------------------

## Shared push application: pushes summed per unit from start-of-tick
## positions, capped at the unit's speed this tick (at least walk/tps so a
## standing unit can still be nudged), applied together; a push into a cell
## the unit can't enter slides on one axis (x first) or is dropped.
class SeparationBase:
	extends SimSystem
	var pushes := 0
	var px := PackedInt64Array()
	var py := PackedInt64Array()

	func _pair(u: BattleUnits, a: int, b: int) -> void:
		var dx := u.x[b] - u.x[a]
		var dy := u.y[b] - u.y[a]
		# Cheap reject before the square root.
		var lim := 2 * SEP_RADIUS
		if absi(dx) >= lim or absi(dy) >= lim:
			return
		var d := Fixed.length(dx, dy)
		if d >= lim:
			return
		var over := (lim - d) / 2
		var ux := 0
		var uy := 0
		if d == 0:
			var f := u.facing[mini(a, b)]
			ux = Fixed.fcos(f)
			uy = Fixed.fsin(f)
			d = Fixed.ONE
			dx = ux
			dy = uy
		px[a] -= Fixed.mul_ratio(dx, over, d)
		py[a] -= Fixed.mul_ratio(dy, over, d)
		px[b] += Fixed.mul_ratio(dx, over, d)
		py[b] += Fixed.mul_ratio(dy, over, d)
		pushes += 1

	func _begin(u: BattleUnits) -> void:
		var n := u.count()
		if px.size() != n:
			px.resize(n)
			py.resize(n)
		px.fill(0)
		py.fill(0)

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


## The spec's uniform 2 m hash: units sorted by cell key (native sort), one
## pass to index occupied cells, then each occupied cell against itself and
## its four forward neighbours (half stencil), pairs of different squads only.
class SeparationHash:
	extends SeparationBase
	var keys := PackedInt64Array()

	func system_name() -> StringName:
		return &"separation_hash"

	func run(ctx: SimContext) -> void:
		var state := ctx as BattleState
		var u := state.units
		_begin(u)
		var n := u.count()
		var cols := (Fixed.from_int(state.rules.width) + CELL - 1) / CELL
		keys.resize(0)
		for row in n:
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
			# Within the cell.
			for a in range(span.x, span.y):
				var ra := keys[a] & 0xFFFFF
				for b in range(a + 1, span.y):
					var rb := keys[b] & 0xFFFFF
					if u.squad[ra] != u.squad[rb]:
						_pair(u, ra, rb)
			# Forward neighbours: E, SW, S, SE.
			for nc in [c + 1, c + cols - 1, c + cols, c + cols + 1]:
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
		_apply(state)


## Alternative broadphase: squads as circles (centroid + farthest member +
## separation distance); only pairs of overlapping squads compare units.
class SeparationSquads:
	extends SeparationBase
	var rad := PackedInt64Array()

	func system_name() -> StringName:
		return &"separation_squads"

	func run(ctx: SimContext) -> void:
		var state := ctx as BattleState
		var u := state.units
		var sq := state.squads
		_begin(u)
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
				var ua := Centroids.units_of(state, a)
				var ub := Centroids.units_of(state, b)
				for ra in ua:
					if u.hp[ra] <= 0:
						continue
					for rb in ub:
						if u.hp[rb] > 0:
							_pair(u, ra, rb)
		_apply(state)
