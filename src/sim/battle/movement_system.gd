class_name MovementSystem
extends SimSystem
## Moves squads and their units. GDD 02 §2.6, R2Q5, R4Q5, R6Q8.
##
## Each squad has a formation anchor that advances toward its order's
## destination at the pace of its slowest member (terrain-adjusted). It
## follows a route around impassable terrain, one straight leg at a time
## (BattleRoute, §2.14). Units
## then steer toward their formation slots with their own speed, acceleration
## and turn rate. Running uses the run speed, but its bonus over walking
## scales with Stamina relative to Neutral (R4Q5) and running sinks Stamina.

## Units within this distance of their slot count as arrived.
const ARRIVE: int = Fixed.ONE / 8
## A chasing squad at the end of its route plans again once its target has
## moved this far.
const CHASE_STEP: int = Fixed.ONE
## A chasing squad this close to its target walks straight when the line is
## clear, without planning a route.
const CHASE_STRAIGHT: int = 32 * Fixed.ONE


func system_name() -> StringName:
	return &"movement"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	FiringPositions.update(state)
	_plan_routes(state)
	_move_anchors(state)
	_move_units(state)


## Gives every squad that wants to move the leg it walks this tick. A new
## leg is planned when the squad has none, when its destination has changed
## (an attack target must move route_replan first), or when it has walked
## the leg it had.
func _plan_routes(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	# Tie-breaks run in each side's canonical frame (sw-0nl): a side facing
	# 180° plans on the rotated grid, so mirror seats detour mirrored ways.
	var frames := {}
	for side: Dictionary in r.sides:
		frames[int(side["player"])] = Fixed.ANGLE_HALF if int(side["facing"]) == Fixed.ANGLE_HALF else 0
	var route: PackedByteArray = sq.take_column(&"route")
	var wx: PackedInt64Array = sq.take_column(&"wx")
	var wy: PackedInt64Array = sq.take_column(&"wy")
	var rx: PackedInt64Array = sq.take_column(&"rx")
	var ry: PackedInt64Array = sq.take_column(&"ry")
	for row in sq.count():
		if not sq.is_active(row) or sq.alive[row] == 0:
			continue
		var dest := _destination(state, row)
		if dest.is_empty():
			continue
		# Chasing a squad (Attack, or Attack-move closing on its engaged
		# squad) replans only once the target has moved route_replan.
		var chasing := sq.order[row] == BattleSquads.Order.ATTACK 			or (sq.order[row] == BattleSquads.Order.ATTACK_MOVE and sq.engaged[row] >= 0)
		var plan := route[row] == 0
		if not plan:
			var drift := Fixed.distance(dest[0], dest[1], rx[row], ry[row])
			var allowed := r.route_replan if chasing else 0
			plan = drift > allowed
			if not plan and Fixed.distance(sq.ax[row], sq.ay[row], wx[row], wy[row]) <= ARRIVE:
				# A chase that reached its last leg follows its target in 1 m
				# steps: re-planning on every jitter of the target's centroid
				# (a fresh plan each tick, uncached) cost ~1 ms/tick at 200
				# units (sw-txnj.5).
				plan = route[row] == 1 or drift > (CHASE_STEP if chasing else ARRIVE)
		if not plan:
			continue
		if chasing and Fixed.distance(sq.ax[row], sq.ay[row], dest[0], dest[1]) <= CHASE_STRAIGHT 				and r.routes.straight_clear(r, r.sq_route_class[sq.tmpl[row]], sq.ax[row], sq.ay[row], dest[0], dest[1]):
			# A short chase on clear ground walks straight: a fresh plan from
			# a new cell each time is uncached (~2 ms, sw-txnj.5).
			wx[row] = dest[0]
			wy[row] = dest[1]
			route[row] = 2
			rx[row] = dest[0]
			ry[row] = dest[1]
			continue
		var leg := r.routes.next_waypoint(r, r.sq_route_class[sq.tmpl[row]], sq.ax[row], sq.ay[row], dest[0], dest[1], frames.get(sq.player[row], 0))
		wx[row] = leg[0]
		wy[row] = leg[1]
		route[row] = 2 if leg[2] == 1 else 1
		rx[row] = dest[0]
		ry[row] = dest[1]
	sq.put_column(&"route", route)
	sq.put_column(&"wx", wx)
	sq.put_column(&"wy", wy)
	sq.put_column(&"rx", rx)
	sq.put_column(&"ry", ry)


func _move_anchors(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	# Who walks this tick, decided before the anchor columns are taken
	# (_destination reads them).
	var walks := PackedByteArray()
	walks.resize(sq.count())
	for row in sq.count():
		if sq.is_active(row) and sq.alive[row] > 0 and not _destination(state, row).is_empty():
			walks[row] = 1
	var ax: PackedInt64Array = sq.take_column(&"ax")
	var ay: PackedInt64Array = sq.take_column(&"ay")
	var facing: PackedInt64Array = sq.take_column(&"facing")
	var moving: PackedByteArray = sq.take_column(&"moving")
	var withdrawn_rows := PackedInt64Array()
	for row in sq.count():
		moving[row] = 0
		if walks[row] == 0:
			continue
		var dx := sq.wx[row] - ax[row]
		var dy := sq.wy[row] - ay[row]
		var dist := Fixed.length(dx, dy)
		if dist <= ARRIVE:
			if sq.order[row] == BattleSquads.Order.WITHDRAW and sq.route[row] == 2:
				withdrawn_rows.append(row)
			continue
		var speed := _squad_speed(state, row, ax[row], ay[row])
		# sw-txnj.4: the anchor waits for stragglers, at half speed, while any
		# unit is out of coherency, so squads don't string out around corners.
		if out_of_coherency(state, row, ax[row], ay[row]):
			speed = speed / 2
		if speed <= 0:
			continue
		var step := mini(speed, dist)
		ax[row] += Fixed.mul_ratio(dx, step, dist)
		ay[row] += Fixed.mul_ratio(dy, step, dist)
		facing[row] = Fixed.atan2(dy, dx)
		moving[row] = 1
		if sq.run[row] == 1:
			var cost := Fixed.round_div(Fixed.from_int(r.sink("stamina_run_per_s")), r.tps)
			sq.put_column(&"ax", ax)
			sq.put_column(&"ay", ay)
			sq.put_column(&"facing", facing)
			sq.put_column(&"moving", moving)
			Pools.flow(state, row, BattleSquads.STAMINA, -cost, &"running")
			ax = sq.take_column(&"ax")
			ay = sq.take_column(&"ay")
			facing = sq.take_column(&"facing")
			moving = sq.take_column(&"moving")
	sq.put_column(&"ax", ax)
	sq.put_column(&"ay", ay)
	sq.put_column(&"facing", facing)
	sq.put_column(&"moving", moving)
	for row in withdrawn_rows:
		_withdraw(state, row)


## Coherency radius of a squad, fixed metres (sw-txnj.4, U1Q29): data per
## formation, compiled into BattleRules.sq_coherency. Firing positions (A3)
## search within it.
static func coherency_m(state: BattleState, row: int) -> int:
	return state.rules.sq_coherency[state.squads.tmpl[row]]


## True if any living unit stands farther than the squad's coherency radius
## from the anchor at (ax, ay).
static func out_of_coherency(state: BattleState, row: int, ax: int, ay: int) -> bool:
	var radius := coherency_m(state, row)
	var u := state.units
	for urow in Centroids.units_of(state, row):
		if u.hp[urow] > 0 and Fixed.length(u.x[urow] - ax, u.y[urow] - ay) > radius:
			return true
	return false


## Destination of the anchor this tick, or empty to stand still.
## Attack-move and Attack stand while every armed unit has a firing position
## (FiringPositions, GDD 02 §2.15 Closing to fire); weapons cycle per unit.
## Engaged and closing, Attack-move walks its route to its point, and within
## its chase leash of the point heads for the engaged squad, never more than
## the leash from the point; Attack follows its target with no leash.
func _destination(state: BattleState, row: int) -> PackedInt64Array:
	var sq := state.squads
	match sq.order[row]:
		BattleSquads.Order.MOVE, BattleSquads.Order.FALL_BACK, BattleSquads.Order.WITHDRAW:
			return PackedInt64Array([sq.tx[row], sq.ty[row]])
		BattleSquads.Order.ATTACK_MOVE:
			var erow := FiringPositions.engaging(state, row)
			if erow < 0:
				return PackedInt64Array([sq.tx[row], sq.ty[row]])
			if sq.fp_stop[row] == 1:
				return PackedInt64Array()
			# Along its route to the point; within the leash of the point it
			# closes on the engaged squad, never past the leash (U1Q29).
			var leash := state.rules.chase_leash
			if Fixed.distance(sq.ax[row], sq.ay[row], sq.tx[row], sq.ty[row]) > leash:
				return PackedInt64Array([sq.tx[row], sq.ty[row]])
			return leash_point(sq.tx[row], sq.ty[row], sq.cx[erow], sq.cy[erow], leash)
		BattleSquads.Order.ATTACK:
			var trow := sq.row_of(sq.target[row])
			if trow < 0 or not sq.is_active(trow):
				return PackedInt64Array()
			if FiringPositions.engaging(state, row) >= 0 and sq.fp_stop[row] == 1:
				return PackedInt64Array()
			return PackedInt64Array([sq.cx[trow], sq.cy[trow]])
	return PackedInt64Array()


## (tx, ty) moved toward (ex, ey) by at most `leash`: where an engaged
## attack-move closes to (U1Q29 leash).
static func leash_point(px: int, py: int, ex: int, ey: int, leash: int) -> PackedInt64Array:
	var d := Fixed.distance(px, py, ex, ey)
	if d <= leash:
		return PackedInt64Array([ex, ey])
	return PackedInt64Array([px + Fixed.mul_ratio(ex - px, leash, d), py + Fixed.mul_ratio(ey - py, leash, d)])


## The unit's formation slot (fixed x, y), clamped to the map. Slots are laid
## out for the units the squad spawned with, not its full template strength:
## survivors hold the first slots of that line (sw-uyv). 0 = a state without
## the column; fall back to full strength.
static func slot_point(state: BattleState, urow: int, srow: int) -> PackedInt64Array:
	var r := state.rules
	var sq := state.squads
	var st := sq.tmpl[srow]
	var members := sq.form_size[srow]
	if members <= 0:
		members = r.sq_members[st].size()
	var off := Formation.offset(r.sq_shape[st], state.units.slot[urow], members, r.sq_spacing[st], sq.facing[srow])
	return PackedInt64Array([
		Fixed.clamp_fixed(sq.ax[srow] + off[0], 0, Fixed.from_int(r.width) - 1),
		Fixed.clamp_fixed(sq.ay[srow] + off[1], 0, Fixed.from_int(r.height) - 1)])


## Pace of the slowest living member at the anchor's terrain.
func _squad_speed(state: BattleState, row: int, x: int, y: int) -> int:
	var r := state.rules
	var feature := r.feature_at(x, y)
	var slowest := -1
	for urow in Centroids.units_of(state, row):
		var s := _unit_max_speed(state, row, urow, r.ut_movement[state.units.tmpl[urow]], feature)
		if slowest < 0 or s < slowest:
			slowest = s
	return maxi(slowest, 0)


func _unit_max_speed(state: BattleState, srow: int, urow: int, profile: int, feature: int) -> int:
	var r := state.rules
	var cost := r.mv_cost[profile * r.feature_count() + feature]
	if cost <= 0:
		# Routes keep anchors off impassable cells, but units have no
		# collision in v1 (§2.14), so one can cross a corner of them on the
		# way to its slot. It keeps its plain speed rather than stall forever.
		cost = 100
	# Speeds are stats in m/s; per tick only after modifiers.
	var walk := Fixed.round_div(Stats.unit(state, urow, &"movement.walk", r.mv_walk_s[profile]), r.tps)
	var base := walk
	if state.squads.run[srow] == 1:
		var eff := Pools.efficacy(state, srow, BattleSquads.STAMINA)
		var run := Fixed.round_div(Stats.unit(state, urow, &"movement.run", r.mv_run_s[profile]), r.tps)
		base = walk + Fixed.mul(run - walk, eff)
	return Fixed.round_div(base * 100, cost)


func _move_units(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	var u := state.units
	var x: PackedInt64Array = u.take_column(&"x")
	var y: PackedInt64Array = u.take_column(&"y")
	var facing: PackedInt64Array = u.take_column(&"facing")
	var speed: PackedInt64Array = u.take_column(&"speed")
	var moving: PackedByteArray = u.take_column(&"moving")
	var max_x := Fixed.from_int(r.width) - 1
	var max_y := Fixed.from_int(r.height) - 1
	for row in u.count():
		moving[row] = 0
		var srow := sq.row_of(u.squad[row])
		if srow < 0 or not sq.is_active(srow):
			continue
		# Its firing position under attack orders (sw-txnj.5), else its slot.
		var gx: int
		var gy: int
		if u.fpos[row] == FiringPositions.HAS:
			gx = u.fx[row]
			gy = u.fy[row]
		else:
			var slot := slot_point(state, row, srow)
			gx = slot[0]
			gy = slot[1]
		# sw-txnj.4: a unit more than its coherency radius from the anchor
		# heads straight for the anchor until it is back inside.
		if Fixed.length(x[row] - sq.ax[srow], y[row] - sq.ay[srow]) > coherency_m(state, srow):
			gx = Fixed.clamp_fixed(sq.ax[srow], 0, max_x)
			gy = Fixed.clamp_fixed(sq.ay[srow], 0, max_y)
		var at_fpos := u.fpos[row] == FiringPositions.HAS and gx == u.fx[row] and gy == u.fy[row]
		var dx := gx - x[row]
		var dy := gy - y[row]
		var dist := Fixed.length(dx, dy)
		var profile := r.ut_movement[u.tmpl[row]]
		if dist <= ARRIVE:
			if at_fpos:
				# sw-txnj.16: a firing position is validated at the point, so the
				# unit stands on it. Stopping up to ARRIVE short left a shotgun
				# just outside its 15 m range, holding 'o' for good.
				x[row] = gx
				y[row] = gy
			speed[row] = 0
			# Settle facing toward the squad's facing.
			facing[row] = _turn(facing[row], sq.facing[srow], r.mv_turn[profile])
			continue
		var top := _unit_max_speed(state, srow, row, profile, r.feature_at(x[row], y[row]))
		speed[row] = mini(speed[row] + r.mv_accel[profile], top)
		var step := mini(speed[row], dist)
		if step <= 0:
			continue
		var nx := Fixed.clamp_fixed(x[row] + Fixed.mul_ratio(dx, step, dist), 0, max_x)
		var ny := Fixed.clamp_fixed(y[row] + Fixed.mul_ratio(dy, step, dist), 0, max_y)
		if _blocked(r, profile, nx, ny) and not _blocked(r, profile, x[row], y[row]):
			# Terrain collision (§2.14): slide along the wall on one axis if
			# that is open (x first), else stand still. A unit already on an
			# impassable cell is free to leave it.
			if not _blocked(r, profile, nx, y[row]):
				ny = y[row]
			elif not _blocked(r, profile, x[row], ny):
				nx = x[row]
			else:
				speed[row] = 0
				continue
		# sw-txnj.17 (U1Q28): a unit that reaches its firing position this
		# tick stands on it, so it fires in standing mode on the arrival
		# tick. Its moving flag stays 0: a moving volley would start a
		# cooldown the unit does not need.
		if at_fpos and Fixed.distance(nx, ny, gx, gy) <= ARRIVE:
			x[row] = gx
			y[row] = gy
			speed[row] = 0
			facing[row] = _turn(facing[row], Fixed.atan2(dy, dx), r.mv_turn[profile])
			continue
		x[row] = nx
		y[row] = ny
		facing[row] = _turn(facing[row], Fixed.atan2(dy, dx), r.mv_turn[profile])
		moving[row] = 1
	u.put_column(&"x", x)
	u.put_column(&"y", y)
	u.put_column(&"facing", facing)
	u.put_column(&"speed", speed)
	u.put_column(&"moving", moving)


## True if a unit with this movement profile can't enter the cell under a point.
static func _blocked(r: BattleRules, profile: int, x: int, y: int) -> bool:
	return r.mv_cost[profile * r.feature_count() + r.feature_at(x, y)] <= 0


static func _turn(current: int, desired: int, max_step: int) -> int:
	var diff := ((desired - current + Fixed.ANGLE_HALF) & Fixed.ANGLE_MASK) - Fixed.ANGLE_HALF
	return (current + clampi(diff, -max_step, max_step)) & Fixed.ANGLE_MASK


func _withdraw(state: BattleState, row: int) -> void:
	var sq := state.squads
	var col: PackedByteArray = sq.take_column(&"withdrawn")
	col[row] = 1
	sq.put_column(&"withdrawn", col)
	var sid := sq.id_at(row)
	for urow in Centroids.units_of(state, row):
		state.commands.despawn(&"unit", state.units.id_at(urow))
	state.events.push(&"squad_withdrawn", {"squad": sid, "player": sq.player[row]}, state.tick)
