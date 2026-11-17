class_name LineOfFire
extends RefCounted
## Whether a squad has a shot at another (sw-kys.6, sw-kys.7): the target's
## centre within the squad's reach, and a living armed unit that carries an
## indirect weapon or has a clear line to the target's centre. One rule for
## the attack-order movement (stand once you have a shot) and the UI cues
## (in range / no line of fire), so they can't disagree. Read-only.

enum { OUT_OF_RANGE, SHOT, BLOCKED }


static func check(state: BattleState, row: int, trow: int) -> int:
	var sq := state.squads
	if Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[trow], sq.cy[trow]) > sq.reach[row]:
		return OUT_OF_RANGE
	var r := state.rules
	var u := state.units
	for urow in Centroids.units_of(state, row):
		if u.hp[urow] <= 0 or u.weapon[urow] < 0:
			continue
		if r.indirect(u.weapon[urow]) or r.los(u.x[urow], u.y[urow], sq.cx[trow], sq.cy[trow]):
			return SHOT
	return BLOCKED


## Whether squad `row` sees squad `t` with its own eyes: within its sight and
## line of sight, centre to centre (concealment aside: the side's vision,
## seen_by, is the authority; this only tells own sight from allies').
static func own_sight(state: BattleState, row: int, t: int) -> bool:
	var sq := state.squads
	var sight := Stats.squad(state, row, &"squad.sight", state.rules.sq_sight[sq.tmpl[row]])
	return Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[t], sq.cy[t]) <= sight \
		and state.rules.los(sq.cx[row], sq.cy[row], sq.cx[t], sq.cy[t])
