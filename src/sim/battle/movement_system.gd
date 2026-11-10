class_name MovementSystem
extends SimSystem
## Moves squads and their units. GDD 02 §2.6, R2Q5, R4Q5, R6Q8.
##
## Each squad has a formation anchor that advances toward its order's
## destination at the pace of its slowest member (terrain-adjusted). Units
## then steer toward their formation slots with their own speed, acceleration
## and turn rate. Running uses the run speed, but its bonus over walking
## scales with Stamina relative to Neutral (R4Q5) and running sinks Stamina.

## Units within this distance of their slot count as arrived.
const ARRIVE: int = Fixed.ONE / 8


func system_name() -> StringName:
	return &"movement"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	_move_anchors(state)
	_move_units(state)


func _move_anchors(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	var ax: PackedInt64Array = sq.take_column(&"ax")
	var ay: PackedInt64Array = sq.take_column(&"ay")
	var facing: PackedInt64Array = sq.take_column(&"facing")
	var moving: PackedByteArray = sq.take_column(&"moving")
	var withdrawn_rows := PackedInt64Array()
	for row in sq.count():
		moving[row] = 0
		if not sq.is_active(row) or sq.alive[row] == 0:
			continue
		var dest := _destination(state, row)
		if dest.is_empty():
			continue
		var dx := dest[0] - ax[row]
		var dy := dest[1] - ay[row]
		var dist := Fixed.length(dx, dy)
		if dist <= ARRIVE:
			if sq.order[row] == BattleSquads.Order.WITHDRAW:
				withdrawn_rows.append(row)
			continue
		var speed := _squad_speed(state, row, ax[row], ay[row])
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


## Destination of the anchor this tick, or empty to stand still.
func _destination(state: BattleState, row: int) -> PackedInt64Array:
	var sq := state.squads
	match sq.order[row]:
		BattleSquads.Order.MOVE, BattleSquads.Order.FALL_BACK, BattleSquads.Order.WITHDRAW:
			return PackedInt64Array([sq.tx[row], sq.ty[row]])
		BattleSquads.Order.ATTACK_MOVE:
			if sq.engaged[row] >= 0 and _firing(state, row):
				return PackedInt64Array()
			return PackedInt64Array([sq.tx[row], sq.ty[row]])
		BattleSquads.Order.ATTACK:
			var trow := sq.row_of(sq.target[row])
			if trow < 0 or not sq.is_active(trow):
				return PackedInt64Array()
			if sq.engaged[row] == sq.target[row] and _firing(state, row):
				return PackedInt64Array()
			return PackedInt64Array([sq.cx[trow], sq.cy[trow]])
	return PackedInt64Array()


## Engaged squads stop to fight only while they are actually landing fire
## (fired within the last FIRING_HOLD_S); otherwise they keep closing, so a
## squad that sees its target but has no unit-level line of fire never stalls.
const FIRING_HOLD_S: int = 2


func _firing(state: BattleState, row: int) -> bool:
	var ft := state.squads.fired_tick[row]
	return ft >= 0 and state.tick - ft <= FIRING_HOLD_S * state.rules.tps


## Pace of the slowest living member at the anchor's terrain.
func _squad_speed(state: BattleState, row: int, x: int, y: int) -> int:
	var r := state.rules
	var feature := r.feature_at(x, y)
	var slowest := -1
	for urow in Centroids.units_of(state, row):
		var s := _unit_max_speed(state, row, r.ut_movement[state.units.tmpl[urow]], feature)
		if slowest < 0 or s < slowest:
			slowest = s
	return maxi(slowest, 0)


func _unit_max_speed(state: BattleState, srow: int, profile: int, feature: int) -> int:
	var r := state.rules
	var cost := r.mv_cost[profile * r.feature_count() + feature]
	if cost <= 0:
		return 0
	var walk := r.mv_walk[profile]
	var base := walk
	if state.squads.run[srow] == 1:
		var eff := Pools.efficacy(state, srow, BattleSquads.STAMINA)
		base = walk + Fixed.mul(r.mv_run[profile] - walk, eff)
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
		var st := sq.tmpl[srow]
		var members := r.sq_members[st].size()
		var off := Formation.offset(r.sq_shape[st], u.slot[row], members, r.sq_spacing[st], sq.facing[srow])
		var gx := Fixed.clamp_fixed(sq.ax[srow] + off[0], 0, max_x)
		var gy := Fixed.clamp_fixed(sq.ay[srow] + off[1], 0, max_y)
		var dx := gx - x[row]
		var dy := gy - y[row]
		var dist := Fixed.length(dx, dy)
		var profile := r.ut_movement[u.tmpl[row]]
		if dist <= ARRIVE:
			speed[row] = 0
			# Settle facing toward the squad's facing.
			facing[row] = _turn(facing[row], sq.facing[srow], r.mv_turn[profile])
			continue
		var top := _unit_max_speed(state, srow, profile, r.feature_at(x[row], y[row]))
		speed[row] = mini(speed[row] + r.mv_accel[profile], top)
		var step := mini(speed[row], dist)
		if step <= 0:
			continue
		x[row] = Fixed.clamp_fixed(x[row] + Fixed.mul_ratio(dx, step, dist), 0, max_x)
		y[row] = Fixed.clamp_fixed(y[row] + Fixed.mul_ratio(dy, step, dist), 0, max_y)
		facing[row] = _turn(facing[row], Fixed.atan2(dy, dx), r.mv_turn[profile])
		moving[row] = 1
	u.put_column(&"x", x)
	u.put_column(&"y", y)
	u.put_column(&"facing", facing)
	u.put_column(&"speed", speed)
	u.put_column(&"moving", moving)


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
