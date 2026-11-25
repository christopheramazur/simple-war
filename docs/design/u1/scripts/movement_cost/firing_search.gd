extends SimSystem
## U1Q29 firing-position search prototype (sw-txnj.3, scratch; not shipped).
## Every armed unit of an attack-move / attack squad looks for the first
## point with a shot at a unit of its target squad (the engaged one, else the
## nearest living enemy squad, so every attacker searches: the worst case):
## its own spot, then its slot, then rings of `rings` x `step` m around the
## slot, `angles` points per ring spread over the half circle facing the
## target, in order 0, +1, -1, +2, -2 ... Candidates outside coherency
## (formation half-width + 4 m of the anchor) or on a cell the unit can't
## enter are skipped.
## - cadence N: unit row r is due on ticks where (tick + r) % N == 0.
## - nearest: per candidate, line of fire is traced only to the nearest
##   target unit in [min range, range] (else to each in turn until one is
##   clear, the literal per-unit shot gate).
## - cap K > 0: at most K due units search per tick, round robin by unit row
##   from where the last tick stopped; the rest wait (deterministic).
## - reach prefilter: a unit whose slot is farther from the target centroid
##   than range + ring reach + 10 m can have no position; it is skipped
##   without a search (it doesn't hold the anchor, U1Q29).
## - memo: a unit holding a position re-checks only that point (1 candidate)
##   and searches the rings only when it lost the shot; a unit whose last
##   search failed is skipped until its anchor or its target's centroid has
##   moved at least one ring step since (U1Q29: "a unit that loses its shot
##   seeks a new firing position").
## Results (fx, fy; -1 = none) persist between searches; they are not
## applied to movement (timing only).

var cadence: int
var step: int
var rings: int
var angles: int
var nearest: bool
var cap: int
var memo: bool
var fail_ax := PackedInt64Array()
var fail_ay := PackedInt64Array()
var fail_tx := PackedInt64Array()
var fail_ty := PackedInt64Array()
var memo_skips := 0
var memo_holds := 0
var cursor := -1
var fx := PackedInt64Array()
var fy := PackedInt64Array()
var us := 0
var max_us := 0
var ticks := 0
var due_total := 0
var searches := 0
var held := 0
var unreachable := 0
var candidates := 0
var los_calls := 0
var found := 0


func _init(c: int, step_m: int, ring_count: int, angle_count: int, near: bool, cap_per_tick: int, use_memo: bool = false) -> void:
	memo = use_memo
	cadence = c
	step = step_m * Fixed.ONE
	rings = ring_count
	angles = angle_count
	nearest = near
	cap = cap_per_tick


func system_name() -> StringName:
	return &"firing_search"


func stats() -> String:
	var t := float(maxi(ticks, 1))
	if searches == 0:
		return "no searches"
	return "memo skips/t %.1f, memo holds/t %.1f, due/t %.1f, searched/t %.1f, deferred/t %.1f, unreachable/t %.1f, cand/search %.2f, los/search %.2f, found %.0f%%, worst tick %.2f ms" % [
		memo_skips / t, memo_holds / t, due_total / t, searches / t, held / t, unreachable / t, candidates / float(searches),
		los_calls / float(searches), 100.0 * found / searches, max_us / 1000.0]


func fold_hash(h: HashingContext) -> void:
	h.update(fail_ax.to_byte_array())
	h.update(fx.to_byte_array())
	h.update(fy.to_byte_array())


func run(ctx: SimContext) -> void:
	var t0 := Time.get_ticks_usec()
	_run(ctx as BattleState)
	var dt := Time.get_ticks_usec() - t0
	us += dt
	max_us = maxi(max_us, dt)
	ticks += 1


func _run(state: BattleState) -> void:
	var sq := state.squads
	var u := state.units
	if fx.size() != u.count():
		fx.resize(u.count())
		fy.resize(u.count())
		fx.fill(-1)
		fy.fill(-1)
		fail_ax.resize(u.count())
		fail_ay.resize(u.count())
		fail_tx.resize(u.count())
		fail_ty.resize(u.count())
		fail_ax.fill(-1)
	# Who is due this tick, with its target squad.
	var due := PackedInt64Array()
	var due_target := {}
	for srow in sq.count():
		if not sq.is_active(srow) or sq.alive[srow] == 0:
			continue
		var order := sq.order[srow]
		if order != BattleSquads.Order.ATTACK_MOVE and order != BattleSquads.Order.ATTACK:
			continue
		var trow := _target(state, srow)
		if trow < 0:
			continue
		for urow in Centroids.units_of(state, srow):
			if u.hp[urow] <= 0 or u.weapon[urow] < 0:
				continue
			if cadence > 1 and (state.tick + urow) % cadence != 0:
				continue
			if memo and _memo(state, urow, srow, trow):
				continue
			due.append(urow)
			due_target[urow] = trow
	due.sort()
	var n := due.size()
	due_total += n
	if n == 0:
		return
	# Round robin from the cursor.
	var first := 0
	while first < n and due[first] <= cursor:
		first += 1
	var take := n if cap <= 0 else mini(cap, n)
	held += n - take
	for i in take:
		var urow := due[(first + i) % n]
		cursor = urow
		_search(state, urow, due_target[urow])


func _search(state: BattleState, urow: int, trow: int) -> void:
	var r := state.rules
	var sq := state.squads
	var u := state.units
	var srow := sq.row_of(u.squad[urow])
	var max_x := Fixed.from_int(r.width) - 1
	var max_y := Fixed.from_int(r.height) - 1
	var st := sq.tmpl[srow]
	var members := sq.form_size[srow]
	if members <= 0:
		members = r.sq_members[st].size()
	var w := u.weapon[urow]
	var off := Formation.offset(r.sq_shape[st], u.slot[urow], members, r.sq_spacing[st], sq.facing[srow])
	var gx := Fixed.clamp_fixed(sq.ax[srow] + off[0], 0, max_x)
	var gy := Fixed.clamp_fixed(sq.ay[srow] + off[1], 0, max_y)
	if Fixed.distance(gx, gy, sq.cx[trow], sq.cy[trow]) > r.wp_range[w] + rings * step + 10 * Fixed.ONE:
		unreachable += 1
		_miss(state, urow, srow, trow)
		return
	searches += 1
	var targets := Centroids.units_of(state, trow)
	var ind := r.indirect(w)
	var profile := r.ut_movement[u.tmpl[urow]]
	var coh := _half_width(r, st, members) + 4 * Fixed.ONE
	var toward := Fixed.atan2(sq.cy[trow] - gy, sq.cx[trow] - gx)
	var spread := Fixed.ANGLE_HALF / maxi(angles - 1, 1)
	# Ring 0: where it stands, then its slot.
	candidates += 1
	if _shot(r, u, w, ind, u.x[urow], u.y[urow], targets):
		_hit(urow, u.x[urow], u.y[urow])
		return
	candidates += 1
	if _shot(r, u, w, ind, gx, gy, targets):
		_hit(urow, gx, gy)
		return
	for k in range(1, rings + 1):
		var rad := k * step
		for j in angles:
			# 0, +1, -1, +2, -2 ... across the forward half circle.
			var idx := (j + 1) / 2
			var sgn := 1 if j % 2 == 1 else -1
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
			if _shot(r, u, w, ind, px, py, targets):
				_hit(urow, px, py)
				return
	_miss(state, urow, srow, trow)


## True if the memo settles this unit without a ring search.
func _memo(state: BattleState, urow: int, srow: int, trow: int) -> bool:
	var sq := state.squads
	if fx[urow] >= 0:
		var w := state.units.weapon[urow]
		candidates += 1
		if _shot(state.rules, state.units, w, state.rules.indirect(w), fx[urow], fy[urow], Centroids.units_of(state, trow)):
			memo_holds += 1
			return true
		return false
	if fail_ax[urow] >= 0 and Fixed.distance(fail_ax[urow], fail_ay[urow], sq.ax[srow], sq.ay[srow]) < step 			and Fixed.distance(fail_tx[urow], fail_ty[urow], sq.cx[trow], sq.cy[trow]) < step:
		memo_skips += 1
		return true
	return false


func _miss(state: BattleState, urow: int, srow: int, trow: int) -> void:
	fx[urow] = -1
	fy[urow] = -1
	if memo:
		var sq := state.squads
		fail_ax[urow] = sq.ax[srow]
		fail_ay[urow] = sq.ay[srow]
		fail_tx[urow] = sq.cx[trow]
		fail_ty[urow] = sq.cy[trow]


func _hit(urow: int, x: int, y: int) -> void:
	found += 1
	fx[urow] = x
	fy[urow] = y


## The squad it engages, else the nearest living enemy squad.
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


## The per-unit shot gate (CombatSystem.shot_gate) from a point: some living
## target unit within [min range, range], and line of fire unless the weapon
## has an indirect mode.
func _shot(r: BattleRules, u: BattleUnits, w: int, ind: bool, px: int, py: int, targets: PackedInt64Array) -> bool:
	var rng := r.wp_range[w]
	var mn := r.wp_min_range[w]
	var best := -1
	var best_d := 1 << 62
	for t in targets:
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(px, py, u.x[t], u.y[t])
		if d > rng or d < mn:
			continue
		if ind:
			return true
		if nearest:
			if d < best_d:
				best_d = d
				best = t
			continue
		los_calls += 1
		if r.los(px, py, u.x[t], u.y[t]):
			return true
	if best < 0:
		return false
	los_calls += 1
	return r.los(px, py, u.x[best], u.y[best])


static func _half_width(r: BattleRules, st: int, members: int) -> int:
	var best := 0
	for i in members:
		var off := Formation.offset(r.sq_shape[st], i, members, r.sq_spacing[st], 0)
		best = maxi(best, Fixed.length(off[0], off[1]))
	return best
