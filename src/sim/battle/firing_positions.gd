class_name FiringPositions
extends RefCounted
## Per-unit firing positions under attack orders (GDD 02 §2.15 Closing to
## fire, U1Q28, U1Q29, sw-txnj.5). Run by MovementSystem before the anchors
## move. Writes BattleUnits.fpos / fx / fy and BattleSquads.fp_stop / fp_lack;
## nothing else writes them.
##
## - A squad *engages for positions* under Attack-move while it has an
##   engaged squad, and under Attack while it engages its ordered target.
##   The engaged squad must be seen by the side (fog: only seen units count).
## - Each living armed unit of such a squad has a firing position (HAS), lacks
##   one (LACKS), or can't have one from inside coherency (UNACHIEVABLE: no
##   standing mode, or every target unit is inside its minimum range plus the
##   stand-off). NONE: not evaluated yet, or the order no longer engages (the
##   unit returns to its slot).
## - Search (deterministic): the unit's own spot, then its slot, then rings
##   of STEP m around the slot up to MAX_RINGS or the coherency radius, ANGLES points over
##   the forward half circle toward the target centroid (0, +30, -30, ... 90
##   degrees); candidates outside coherency of the anchor or on a cell the
##   unit can't enter are skipped. The first candidate with a shot wins.
## - Shot from a point: some living unit of the engaged squad within range and
##   outside minimum range (+ STAND_OFF when the weapon has one), by squared
##   distance; an indirect standing mode needs nothing more, else one line of
##   fire trace to the nearest such unit (sw-txnj.3: ~same find rate as tracing
##   every unit, 2.3x cheaper).
## - Cost (sw-txnj.3 recommendations): a unit is re-evaluated every CADENCE
##   ticks, staggered by row. A unit holding a position re-checks only that
##   point. At most SEARCH_CAP full searches per tick per battle, taken from
##   the due list rotated by the tick (stateless round robin). A unit whose
##   slot is beyond range + coherency + REACH_SLACK of the target centroid
##   lacks a position without a search. The own spot and the slot are tried
##   uncapped (a unit's first evaluation among them, so a squad that engages
##   standing doesn't step forward first); only ring searches are capped.
## - Anchor (fp_stop): stops once no armed unit is NONE or LACKS; once stopped
##   it moves again only after some unit has lacked a position for
##   HYSTERESIS_S (fp_lack = the tick the lack began, -1 none).
## - Per squad behaviour (sw-txnj.10, GDD 02 §2.15 Squad behaviours): the
##   coherency radius, stand-off, cadence and hysteresis come from the
##   squad's behaviour for its current order (BattleRules.bh_*); the
##   constants below are the defaults those arrays compile to. A behaviour
##   with stand_while(firing = false) takes no firing positions: its units
##   keep their slots and fire on the move.

enum { NONE, HAS, LACKS, UNACHIEVABLE }

const STEP: int = 2 * Fixed.ONE
const MAX_RINGS: int = 3
const ANGLES: int = 7
const CADENCE: int = BattleRules.BH_CADENCE
const SEARCH_CAP: int = 2
const STAND_OFF: int = BattleRules.BH_STAND_OFF
const REACH_SLACK: int = 10 * Fixed.ONE
const HYSTERESIS_S: int = BattleRules.BH_HYSTERESIS_S


## Index into the BattleRules.bh_* arrays of squad `row`'s behaviour under
## its current order.
static func bh(state: BattleState, row: int) -> int:
	return state.rules.bh_at(state.squads.tmpl[row], state.squads.order[row])


## The squad row whose units squad `row` takes firing positions against, or
## -1 when its order doesn't engage (Hold, Move, no engagement, Attack on a
## squad other than its target), or when its behaviour takes no positions
## now: stand_while firing = false, or the anchor is outside its
## keep_distance band (it walks in formation until it is back inside).
## `closing` skips the behaviour tests: the squad it closes on regardless.
static func engaging(state: BattleState, row: int, closing: bool = false) -> int:
	var sq := state.squads
	if not sq.is_active(row) or sq.alive[row] == 0 or sq.engaged[row] < 0:
		return -1
	match sq.order[row]:
		BattleSquads.Order.ATTACK_MOVE:
			pass
		BattleSquads.Order.ATTACK:
			if sq.engaged[row] != sq.target[row]:
				return -1
		_:
			return -1
	var r := state.rules
	var i := bh(state, row)
	if not closing and r.bh_stand_firing[i] == 0:
		return -1
	var trow := sq.row_of(sq.engaged[row])
	if trow < 0 or not sq.is_active(trow) or sq.alive[trow] == 0:
		return -1
	if sq.seen_by[trow] & BattleSquads.bit(sq.player[row]) == 0:
		return -1
	if not closing and (r.bh_keep_min[i] >= 0 or r.bh_keep_max[i] >= 0):
		var d := Fixed.distance(sq.ax[row], sq.ay[row], sq.cx[trow], sq.cy[trow])
		if d < r.bh_keep_min[i] or (r.bh_keep_max[i] >= 0 and d > r.bh_keep_max[i]):
			return -1
	return trow


## engaging(state, row) for every squad row at once, from columns read once
## (sw-0jm5: the per-row version reads a dozen properties per call). Must
## agree with engaging() row for row (test_engaging_rows_matches_engaging).
static func _engaging_rows(state: BattleState) -> PackedInt64Array:
	var sq := state.squads
	var r := state.rules
	var n := sq.count()
	var out := PackedInt64Array()
	out.resize(n)
	out.fill(-1)
	var destroyed := sq.destroyed
	var withdrawn := sq.withdrawn
	var alive := sq.alive
	var engaged := sq.engaged
	var order := sq.order
	var target := sq.target
	var tmpl := sq.tmpl
	var seen_by := sq.seen_by
	var player := sq.player
	var stand_firing := r.bh_stand_firing
	var keep_min := r.bh_keep_min
	var keep_max := r.bh_keep_max
	for row in n:
		var e := engaged[row]
		if e < 0 or alive[row] == 0 or destroyed[row] != 0 or withdrawn[row] != 0:
			continue
		var o := order[row]
		if o == BattleSquads.Order.ATTACK:
			if e != target[row]:
				continue
		elif o != BattleSquads.Order.ATTACK_MOVE:
			continue
		var i := r.bh_at(tmpl[row], o)
		if stand_firing[i] == 0:
			continue
		var trow := sq.row_of(e)
		if trow < 0 or destroyed[trow] != 0 or withdrawn[trow] != 0 or alive[trow] == 0:
			continue
		if seen_by[trow] & (1 << player[row]) == 0:
			continue
		if keep_min[i] >= 0 or keep_max[i] >= 0:
			var d := Fixed.distance(sq.ax[row], sq.ay[row], sq.cx[trow], sq.cy[trow])
			if d < keep_min[i] or (keep_max[i] >= 0 and d > keep_max[i]):
				continue
		out[row] = trow
	return out


static func update(state: BattleState) -> void:
	var sq := state.squads
	var u := state.units
	var r := state.rules
	var tick := state.tick
	var fpos: PackedByteArray = u.take_column(&"fpos")
	var fx: PackedInt64Array = u.take_column(&"fx")
	var fy: PackedInt64Array = u.take_column(&"fy")
	# Columns read once per tick (sw-0jm5): a property read per unit per tick
	# was the cost of this pass, not the rules it applies.
	var hp := u.hp
	var weapon := u.weapon
	var ux := u.x
	var uy := u.y
	var fired := u.fired_tick
	var uslot := u.slot
	var stand := _standing_modes(r)
	var shots := {}
	var due := PackedInt64Array()
	var due_r := PackedInt64Array()
	var due_t := PackedInt64Array()
	var targets := {}
	var engage := _engaging_rows(state)
	for row in sq.count():
		var trow := engage[row]
		var units := Centroids.units_of(state, row)
		if trow < 0:
			for urow in units:
				fpos[urow] = NONE
			continue
		targets[row] = trow
		var tgt: PackedInt64Array = shots.get(trow, PackedInt64Array())
		if tgt.is_empty():
			tgt = _living(state, trow)
			shots[trow] = tgt
		var bhi := bh(state, row)
		var radius := r.bh_coherency[bhi]
		var r2 := radius * radius
		var cadence := maxi(r.bh_cadence[bhi], 1)
		var stand_off := r.bh_stand_off[bhi]
		var ax := sq.ax[row]
		var ay := sq.ay[row]
		var frame := PackedInt64Array()
		for urow in units:
			var w := weapon[urow]
			if hp[urow] <= 0 or w < 0:
				fpos[urow] = NONE
				continue
			var m := stand[w]
			if m < 0:
				fpos[urow] = UNACHIEVABLE
				continue
			var p := fpos[urow]
			var on_cadence := (tick + urow) % cadence == 0
			if p == HAS:
				var dx := fx[urow] - ax
				var dy := fy[urow] - ay
				if dx * dx + dy * dy > r2:
					p = LACKS
				elif on_cadence and fired[urow] < tick - cadence:
					# A unit that fired within the cadence has its shot: the
					# fire pass just checked it (no trace needed).
					var sh := _shooter(r, w, m, stand_off)
					if not _shot(r, tgt, sh, fx[urow], fy[urow]):
						p = LACKS
			if p == NONE or (p != HAS and on_cadence):
				var sh := _shooter(r, w, m, stand_off)
				if frame.is_empty():
					frame = _slot_frame(state, row)
				var slot := _slot_at(frame, uslot[urow])
				var odx := ux[urow] - ax
				var ody := uy[urow] - ay
				var reach := r.wp_range[w] + radius + REACH_SLACK
				var cdx := sq.cx[trow] - slot[0]
				var cdy := sq.cy[trow] - slot[1]
				if cdx * cdx + cdy * cdy > reach * reach + reach:
					# Too far for any ring to reach: Fixed.distance(slot,
					# centroid) > reach, without the square root (it rounds to
					# nearest, so it exceeds reach exactly when the squared
					# length exceeds reach * reach + reach).
					p = LACKS
				elif odx * odx + ody * ody <= r2 and _shot(r, tgt, sh, ux[urow], uy[urow]):
					# The own spot, inside coherency.
					fx[urow] = ux[urow]
					fy[urow] = uy[urow]
					p = HAS
				elif _shot(r, tgt, sh, slot[0], slot[1]):
					fx[urow] = slot[0]
					fy[urow] = slot[1]
					p = HAS
				elif _min_blocked(tgt, sh, slot):
					p = UNACHIEVABLE
				else:
					if p == NONE:
						p = LACKS
					due.append(urow)
					due_r.append(row)
					due_t.append(trow)
			fpos[urow] = p
	var n := due.size()
	if n > 0:
		var start := tick % n
		for i in mini(SEARCH_CAP, n):
			var k := (start + i) % n
			var urow := due[k]
			var row := due_r[k]
			var trow := due_t[k]
			var w := weapon[urow]
			var sh := _shooter(r, w, stand[w], r.bh_stand_off[bh(state, row)])
			fpos[urow] = _search(state, urow, row, trow, shots[trow], sh, fx, fy)
	u.put_column(&"fpos", fpos)
	u.put_column(&"fx", fx)
	u.put_column(&"fy", fy)
	_anchors(state, targets)


## Hysteresis per squad: fp_stop = 1 holds the anchor for firing positions.
static func _anchors(state: BattleState, targets: Dictionary) -> void:
	var sq := state.squads
	var u := state.units
	var hp := u.hp
	var weapon := u.weapon
	var fpos := u.fpos
	var stop: PackedByteArray = sq.take_column(&"fp_stop")
	var lack: PackedInt64Array = sq.take_column(&"fp_lack")
	for row in sq.count():
		if not targets.has(row):
			stop[row] = 0
			lack[row] = -1
			continue
		var lacking := false
		for urow in Centroids.units_of(state, row):
			var p := fpos[urow]
			if (p == NONE or p == LACKS) and hp[urow] > 0 and weapon[urow] >= 0:
				lacking = true
				break
		if not lacking:
			stop[row] = 1
			lack[row] = -1
			continue
		if lack[row] < 0:
			lack[row] = state.tick
		if stop[row] == 1 and state.tick - lack[row] < state.rules.bh_hysteresis[bh(state, row)]:
			continue
		stop[row] = 0
	sq.put_column(&"fp_stop", stop)
	sq.put_column(&"fp_lack", lack)


## What MovementSystem.slot_point needs of squad `row`, read once: [shape,
## members, spacing, cos and sin of its facing, anchor x, y, map max x, y].
static func _slot_frame(state: BattleState, row: int) -> PackedInt64Array:
	var r := state.rules
	var sq := state.squads
	var st := sq.tmpl[row]
	var members := sq.form_size[row]
	if members <= 0:
		members = r.sq_members[st].size()
	var facing := sq.facing[row]
	return PackedInt64Array([r.sq_shape[st], members, r.sq_spacing[st], Fixed.fcos(facing), Fixed.fsin(facing),
		sq.ax[row], sq.ay[row], Fixed.from_int(r.width) - 1, Fixed.from_int(r.height) - 1])


## MovementSystem.slot_point for formation slot `slot` of the squad `frame`
## (see _slot_frame) describes.
static func _slot_at(frame: PackedInt64Array, slot: int) -> PackedInt64Array:
	var off := Formation.offset_cs(frame[0], slot, frame[1], frame[2], frame[3], frame[4])
	return PackedInt64Array([mini(maxi(frame[5] + off[0], 0), frame[7]), mini(maxi(frame[6] + off[1], 0), frame[8])])


## True if the unit's slot is too far from the target for any ring to reach.
static func _too_far(state: BattleState, urow: int, row: int, trow: int) -> bool:
	var sq := state.squads
	var slot := MovementSystem.slot_point(state, urow, row)
	var reach := state.rules.wp_range[state.units.weapon[urow]] + MovementSystem.coherency_m(state, row) + REACH_SLACK
	return Fixed.distance(slot[0], slot[1], sq.cx[trow], sq.cy[trow]) > reach


## The ring search (own spot and slot already tried); writes fx, fy on
## success. Returns the new fpos code. `tgt` and `sh` as for _shot.
static func _search(state: BattleState, urow: int, row: int, trow: int, tgt: PackedInt64Array, sh: PackedInt64Array, fx: PackedInt64Array, fy: PackedInt64Array) -> int:
	var r := state.rules
	var sq := state.squads
	var radius := MovementSystem.coherency_m(state, row)
	var r2 := radius * radius
	var ax := sq.ax[row]
	var ay := sq.ay[row]
	# Exact prune (sw-0jm5): a candidate lies within coherency of the anchor
	# and shoots only at a target unit within range of it, so when every
	# target unit is farther than range + coherency from the anchor, every
	# candidate fails.
	var reach := radius + r.wp_range[state.units.weapon[urow]]
	var reach2 := reach * reach
	var any := false
	for i in range(0, tgt.size(), 2):
		var tdx := tgt[i] - ax
		var tdy := tgt[i + 1] - ay
		if tdx * tdx + tdy * tdy <= reach2:
			any = true
			break
	if not any:
		return LACKS
	var slot := _slot_at(_slot_frame(state, row), state.units.slot[urow])
	var gx := slot[0]
	var gy := slot[1]
	var max_x := Fixed.from_int(r.width) - 1
	var max_y := Fixed.from_int(r.height) - 1
	var profile := r.ut_movement[state.units.tmpl[urow]]
	# MovementSystem._blocked, read once: the cost row of the unit's profile.
	var cost_row := profile * r.feature_count()
	var mv_cost := r.mv_cost
	var terrain := r.terrain
	var width := r.width
	var height := r.height
	var rng2 := sh[0]
	var mn2 := sh[1]
	var toward := Fixed.atan2(sq.cy[trow] - gy, sq.cx[trow] - gx)
	var spread := Fixed.ANGLE_HALF / (ANGLES - 1)
	# The directions are the same on every ring: their cos and sin once.
	var dir_x := PackedInt64Array()
	var dir_y := PackedInt64Array()
	for j in ANGLES:
		# 0, +1, -1, +2, -2 ... across the forward half circle.
		var idx := (j + 1) / 2
		var sgn := 1 if j % 2 == 1 else -1
		var ang := (toward + sgn * idx * spread) & Fixed.ANGLE_MASK
		dir_x.append(Fixed.fcos(ang))
		dir_y.append(Fixed.fsin(ang))
	for k in range(1, MAX_RINGS + 1):
		var rad := k * STEP
		if rad > radius:
			break
		for j in ANGLES:
			var px := gx + Fixed.mul(rad, dir_x[j])
			var py := gy + Fixed.mul(rad, dir_y[j])
			if px < 0 or py < 0 or px > max_x or py > max_y:
				continue
			var cdx := px - ax
			var cdy := py - ay
			if cdx * cdx + cdy * cdy > r2:
				continue
			# _shot, its range test first (cheap; the conditions are all
			# required, so the order doesn't change the answer).
			var best := -1
			var best_d := 1 << 62
			for i in range(0, tgt.size(), 2):
				var tdx := tgt[i] - px
				var tdy := tgt[i + 1] - py
				var d := tdx * tdx + tdy * tdy
				if d > rng2 or d < mn2:
					continue
				if d < best_d:
					best_d = d
					best = i
			if best < 0:
				continue
			var cell := clampi(py >> Fixed.FRAC_BITS, 0, height - 1) * width + clampi(px >> Fixed.FRAC_BITS, 0, width - 1)
			if mv_cost[cost_row + terrain[cell]] <= 0:
				continue
			if sh[2] != 0 or r.los(px, py, tgt[best], tgt[best + 1]):
				fx[urow] = px
				fy[urow] = py
				return HAS
	# No candidate: the anchor has to close.
	return LACKS


## True if every living target unit is inside the unit's minimum range (plus
## its squad's stand-off) from its slot: advancing can't help, so it has no
## achievable position and doesn't hold the anchor.
static func _min_blocked(tgt: PackedInt64Array, sh: PackedInt64Array, slot: PackedInt64Array) -> bool:
	var mn2 := sh[1]
	if mn2 <= 0:
		return false
	var near := 1 << 62
	for i in range(0, tgt.size(), 2):
		var ddx := tgt[i] - slot[0]
		var ddy := tgt[i + 1] - slot[1]
		near = mini(near, ddx * ddx + ddy * ddy)
	return near < mn2


static func _min_range(state: BattleState, urow: int) -> int:
	var mn := state.rules.wp_min_range[state.units.weapon[urow]]
	if mn <= 0:
		return 0
	var row := state.squads.row_of(state.units.squad[urow])
	return mn + (state.rules.bh_stand_off[bh(state, row)] if row >= 0 else STAND_OFF)


## Whether unit `urow` would have a standing shot at squad `trow` from the
## point (px, py): a living target unit within range and outside minimum range
## plus the stand-off, and an indirect standing mode or a clear line to the
## nearest such unit.
static func point_shot(state: BattleState, urow: int, trow: int, px: int, py: int) -> bool:
	var r := state.rules
	var w := state.units.weapon[urow]
	if w < 0:
		return false
	var m := r.pick_mode(w, false)
	if m < 0:
		return false
	var mn := _min_range(state, urow)
	var rng := r.wp_range[w]
	var sh := PackedInt64Array([rng * rng, mn * mn, r.md_indirect[m]])
	return _shot(r, _living(state, trow), sh, px, py)


## Standing fire mode per weapon (BattleRules.pick_mode(w, false)), -1 none.
static func _standing_modes(r: BattleRules) -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(r.wp_range.size())
	for w in out.size():
		out[w] = r.pick_mode(w, false)
	return out


## What a standing shot by weapon `w` (standing mode `m`) of a squad with
## `stand_off` needs: [range squared, minimum range (stand-off included)
## squared, 1 if the mode is indirect].
static func _shooter(r: BattleRules, w: int, m: int, stand_off: int) -> PackedInt64Array:
	var rng := r.wp_range[w]
	var mn := r.wp_min_range[w]
	if mn > 0:
		mn += stand_off
	else:
		mn = 0
	return PackedInt64Array([rng * rng, mn * mn, 1 if r.md_indirect[m] != 0 else 0])


## Positions of squad `trow`'s living units, x and y interleaved, in unit
## order: read once per tick per target squad.
static func _living(state: BattleState, trow: int) -> PackedInt64Array:
	var u := state.units
	var hp := u.hp
	var ux := u.x
	var uy := u.y
	var out := PackedInt64Array()
	for t in Centroids.units_of(state, trow):
		if hp[t] > 0:
			out.append(ux[t])
			out.append(uy[t])
	return out


## point_shot against the living target positions `tgt` (see _living) for a
## shooter `sh` (see _shooter): by squared distance, the first nearest unit
## within range and outside minimum range; any one for an indirect mode, else
## one line of fire trace to it.
static func _shot(r: BattleRules, tgt: PackedInt64Array, sh: PackedInt64Array, px: int, py: int) -> bool:
	var rng2 := sh[0]
	var mn2 := sh[1]
	var best := -1
	var best_d := 1 << 62
	for i in range(0, tgt.size(), 2):
		var dx := tgt[i] - px
		var dy := tgt[i + 1] - py
		var d := dx * dx + dy * dy
		if d > rng2 or d < mn2:
			continue
		if sh[2] != 0:
			return true
		if d < best_d:
			best_d = d
			best = i
	return best >= 0 and r.los(px, py, tgt[best], tgt[best + 1])
