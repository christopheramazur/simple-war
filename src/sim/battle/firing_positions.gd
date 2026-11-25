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

enum { NONE, HAS, LACKS, UNACHIEVABLE }

const STEP: int = 2 * Fixed.ONE
const MAX_RINGS: int = 3
const ANGLES: int = 7
const CADENCE: int = 5
const SEARCH_CAP: int = 2
const STAND_OFF: int = 5 * Fixed.ONE
const REACH_SLACK: int = 10 * Fixed.ONE
const HYSTERESIS_S: int = 1


## The squad row whose units squad `row` takes firing positions against, or
## -1 when its order doesn't engage (Hold, Move, no engagement, Attack on a
## squad other than its target).
static func engaging(state: BattleState, row: int) -> int:
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
	var trow := sq.row_of(sq.engaged[row])
	if trow < 0 or not sq.is_active(trow) or sq.alive[trow] == 0:
		return -1
	if sq.seen_by[trow] & BattleSquads.bit(sq.player[row]) == 0:
		return -1
	return trow


static func update(state: BattleState) -> void:
	var sq := state.squads
	var u := state.units
	var r := state.rules
	var fpos: PackedByteArray = u.take_column(&"fpos")
	var fx: PackedInt64Array = u.take_column(&"fx")
	var fy: PackedInt64Array = u.take_column(&"fy")
	var due := PackedInt64Array()
	var due_t := PackedInt64Array()
	var targets := {}
	for row in sq.count():
		var trow := engaging(state, row)
		var units := Centroids.units_of(state, row)
		if trow < 0:
			for urow in units:
				fpos[urow] = NONE
			continue
		targets[row] = trow
		var radius := MovementSystem.coherency_m(state, row)
		var r2 := radius * radius
		for urow in units:
			var w := u.weapon[urow]
			if u.hp[urow] <= 0 or w < 0:
				fpos[urow] = NONE
				continue
			if r.pick_mode(w, false) < 0:
				fpos[urow] = UNACHIEVABLE
				continue
			var p := fpos[urow]
			var on_cadence := (state.tick + urow) % CADENCE == 0
			if p == HAS:
				var dx := fx[urow] - sq.ax[row]
				var dy := fy[urow] - sq.ay[row]
				if dx * dx + dy * dy > r2:
					p = LACKS
				elif on_cadence and u.fired_tick[urow] < state.tick - CADENCE 						and not point_shot(state, urow, trow, fx[urow], fy[urow]):
					# A unit that fired within the cadence has its shot: the
					# fire pass just checked it (no trace needed).
					p = LACKS
			if p == NONE or (p != HAS and on_cadence):
				if _too_far(state, urow, row, trow):
					p = LACKS
				elif _near(state, urow, row, trow, fx, fy):
					p = HAS
				else:
					if p == NONE:
						p = LACKS
					due.append(urow)
					due_t.append(trow)
			fpos[urow] = p
	var n := due.size()
	if n > 0:
		var start := state.tick % n
		for i in mini(SEARCH_CAP, n):
			var k := (start + i) % n
			var urow := due[k]
			fpos[urow] = _search(state, urow, sq.row_of(u.squad[urow]), due_t[k], fx, fy)
	u.put_column(&"fpos", fpos)
	u.put_column(&"fx", fx)
	u.put_column(&"fy", fy)
	_anchors(state, targets)


## Hysteresis per squad: fp_stop = 1 holds the anchor for firing positions.
static func _anchors(state: BattleState, targets: Dictionary) -> void:
	var sq := state.squads
	var u := state.units
	var stop: PackedByteArray = sq.take_column(&"fp_stop")
	var lack: PackedInt64Array = sq.take_column(&"fp_lack")
	for row in sq.count():
		if not targets.has(row):
			stop[row] = 0
			lack[row] = -1
			continue
		var lacking := false
		for urow in Centroids.units_of(state, row):
			if u.hp[urow] > 0 and u.weapon[urow] >= 0 and (u.fpos[urow] == NONE or u.fpos[urow] == LACKS):
				lacking = true
				break
		if not lacking:
			stop[row] = 1
			lack[row] = -1
			continue
		if lack[row] < 0:
			lack[row] = state.tick
		if stop[row] == 1 and state.tick - lack[row] < HYSTERESIS_S * state.rules.tps:
			continue
		stop[row] = 0
	sq.put_column(&"fp_stop", stop)
	sq.put_column(&"fp_lack", lack)


## True if the unit's slot is too far from the target for any ring to reach.
static func _too_far(state: BattleState, urow: int, row: int, trow: int) -> bool:
	var sq := state.squads
	var slot := MovementSystem.slot_point(state, urow, row)
	var reach := state.rules.wp_range[state.units.weapon[urow]] + MovementSystem.coherency_m(state, row) + REACH_SLACK
	return Fixed.distance(slot[0], slot[1], sq.cx[trow], sq.cy[trow]) > reach


## The first two candidates, cheap enough to test uncapped: the unit's own
## spot (inside coherency), then its slot. Writes fx, fy on success.
static func _near(state: BattleState, urow: int, row: int, trow: int, fx: PackedInt64Array, fy: PackedInt64Array) -> bool:
	var sq := state.squads
	var u := state.units
	var radius := MovementSystem.coherency_m(state, row)
	var odx := u.x[urow] - sq.ax[row]
	var ody := u.y[urow] - sq.ay[row]
	if odx * odx + ody * ody <= radius * radius and point_shot(state, urow, trow, u.x[urow], u.y[urow]):
		fx[urow] = u.x[urow]
		fy[urow] = u.y[urow]
		return true
	var slot := MovementSystem.slot_point(state, urow, row)
	if point_shot(state, urow, trow, slot[0], slot[1]):
		fx[urow] = slot[0]
		fy[urow] = slot[1]
		return true
	return false


## The ring search (own spot and slot already tried by _near); writes fx, fy
## on success. Returns the new fpos code.
static func _search(state: BattleState, urow: int, row: int, trow: int, fx: PackedInt64Array, fy: PackedInt64Array) -> int:
	var r := state.rules
	var sq := state.squads
	var u := state.units
	var radius := MovementSystem.coherency_m(state, row)
	var r2 := radius * radius
	var ax := sq.ax[row]
	var ay := sq.ay[row]
	var slot := MovementSystem.slot_point(state, urow, row)
	var gx := slot[0]
	var gy := slot[1]
	var max_x := Fixed.from_int(r.width) - 1
	var max_y := Fixed.from_int(r.height) - 1
	var profile := r.ut_movement[u.tmpl[urow]]
	var toward := Fixed.atan2(sq.cy[trow] - gy, sq.cx[trow] - gx)
	var spread := Fixed.ANGLE_HALF / (ANGLES - 1)
	for k in range(1, MAX_RINGS + 1):
		var rad := k * STEP
		if rad > radius:
			break
		for j in ANGLES:
			# 0, +1, -1, +2, -2 ... across the forward half circle.
			var idx := (j + 1) / 2
			var sgn := 1 if j % 2 == 1 else -1
			var ang := (toward + sgn * idx * spread) & Fixed.ANGLE_MASK
			var px := gx + Fixed.mul(rad, Fixed.fcos(ang))
			var py := gy + Fixed.mul(rad, Fixed.fsin(ang))
			if px < 0 or py < 0 or px > max_x or py > max_y:
				continue
			var cdx := px - ax
			var cdy := py - ay
			if cdx * cdx + cdy * cdy > r2:
				continue
			if MovementSystem._blocked(r, profile, px, py):
				continue
			if point_shot(state, urow, trow, px, py):
				fx[urow] = px
				fy[urow] = py
				return HAS
	# No candidate: unachievable when the minimum range is what blocks it
	# (advancing can't help), else the anchor has to close.
	var mn := _min_range(state, urow)
	if mn > 0:
		var near := 1 << 62
		for t in Centroids.units_of(state, trow):
			if u.hp[t] > 0:
				var ddx := u.x[t] - gx
				var ddy := u.y[t] - gy
				near = mini(near, ddx * ddx + ddy * ddy)
		if near < mn * mn:
			return UNACHIEVABLE
	return LACKS


static func _min_range(state: BattleState, urow: int) -> int:
	var mn := state.rules.wp_min_range[state.units.weapon[urow]]
	return mn + STAND_OFF if mn > 0 else 0


## Whether unit `urow` would have a standing shot at squad `trow` from the
## point (px, py): a living target unit within range and outside minimum range
## plus the stand-off, and an indirect standing mode or a clear line to the
## nearest such unit.
static func point_shot(state: BattleState, urow: int, trow: int, px: int, py: int) -> bool:
	var r := state.rules
	var u := state.units
	var w := u.weapon[urow]
	var m := r.pick_mode(w, false)
	if w < 0 or m < 0:
		return false
	var rng := r.wp_range[w]
	var mn := _min_range(state, urow)
	var rng2 := rng * rng
	var mn2 := mn * mn
	var best := -1
	var best_d := 1 << 62
	for t in Centroids.units_of(state, trow):
		if u.hp[t] <= 0:
			continue
		var dx := u.x[t] - px
		var dy := u.y[t] - py
		var d := dx * dx + dy * dy
		if d > rng2 or d < mn2:
			continue
		if r.md_indirect[m] != 0:
			return true
		if d < best_d:
			best_d = d
			best = t
	return best >= 0 and r.los(px, py, u.x[best], u.y[best])
