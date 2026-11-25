class_name LineOfFire
extends RefCounted
## Whether a squad has a shot at another (sw-kys.6, sw-kys.7): the target's
## centre within the squad's reach, and a living armed unit that carries an
## indirect weapon or has a clear line to the target's centre. One rule for
## the attack-order movement (stand once you have a shot) and the UI cues
## (in range / no line of fire), so they can't disagree. Read-only.

## check() gives OUT_OF_RANGE, SHOT or BLOCKED. unit_shot() adds MIN_RANGE (a
## direct weapon inside its minimum range) and NO_TARGET (no living unit of
## the target squad that the side sees).
enum { OUT_OF_RANGE, SHOT, BLOCKED, MIN_RANGE, NO_TARGET }


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


## Whether unit `urow` can shoot squad `trow` now, and if not, why (sw-txnj.2).
## Standing fire mode, so the answer doesn't flip with the unit's own
## movement. Runs CombatSystem.shot_gate (range, minimum range, line) against
## the target squad's living units, but only if the attacker's side sees the
## squad (seen_by: units have no fog of their own). Any unit passing the gate
## gives SHOT. Otherwise the gate of the nearest seen living unit, as
## BattleActivity reports holds. No seen living unit: NO_TARGET. A dead or
## unarmed attacker, or a missing squad: BLOCKED, as check() reads it.
static func unit_shot(state: BattleState, urow: int, trow: int) -> int:
	var u := state.units
	var sq := state.squads
	var r := state.rules
	var w := u.weapon[urow]
	if w < 0 or u.hp[urow] <= 0:
		return BLOCKED
	var row := sq.row_of(u.squad[urow])
	if row < 0:
		return BLOCKED
	var m := r.pick_mode(w, false)
	if m < 0:
		return BLOCKED
	if trow < 0 or not sq.is_active(trow) or sq.seen_by[trow] & BattleSquads.bit(sq.player[row]) == 0:
		return NO_TARGET
	var nearest := -1
	var nearest_d := 1 << 62
	var gate := CombatSystem.GATE_OK
	for t in Centroids.units_of(state, trow):
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		var g := CombatSystem.shot_gate(state, urow, t, w, m, d)
		if g == CombatSystem.GATE_OK:
			return SHOT
		if d < nearest_d:
			nearest_d = d
			nearest = t
			gate = g
	if nearest < 0:
		return NO_TARGET
	match gate:
		CombatSystem.GATE_MIN_RANGE:
			return MIN_RANGE
		CombatSystem.GATE_NO_LOS:
			return BLOCKED
	return OUT_OF_RANGE


## A unit's standing damage weight, fixed-point per tick: shots x accuracy
## (with proficiency) x average damage (crit bonus averaged in) over the
## standing mode's cooldown. Same stat hooks as the fire pass. Reload is not
## counted. 0 for a dead or unarmed unit. Used only as a ratio (shot_share).
static func standing_dps(state: BattleState, urow: int) -> int:
	var u := state.units
	var w := u.weapon[urow]
	if w < 0 or u.hp[urow] <= 0:
		return 0
	var r := state.rules
	var m := r.pick_mode(w, false)
	if m < 0:
		return 0
	var accuracy := Stats.unit(state, urow, &"weapon.modes.*.accuracy", r.md_accuracy[m])
	var prof := Stats.unit(state, urow, &"unit.proficiency_pct", Fixed.from_int(r.ut_proficiency[u.tmpl[urow]]))
	var acc := Fixed.mul_ratio(accuracy, prof, 100 * Fixed.ONE)
	var dmg := Stats.unit(state, urow, &"weapon.modes.*.damage", r.md_damage[m])
	if r.md_crit_every[m] > 0:
		dmg += Fixed.round_div(dmg * r.md_crit_bonus[m], 100 * r.md_crit_every[m])
	return Fixed.mul(acc, dmg) * r.md_shots[m] / maxi(r.md_cooldown[m], 1)


## Permille (0..1000) of squad `row`'s standing DPS that sits with units which
## have a shot at squad `trow` (unit_shot == SHOT). 0 when the squad has no
## armed unit (never divides by zero).
static func shot_share(state: BattleState, row: int, trow: int) -> int:
	var total := 0
	var with_shot := 0
	for urow in Centroids.units_of(state, row):
		var dps := standing_dps(state, urow)
		if dps <= 0:
			continue
		total += dps
		if unit_shot(state, urow, trow) == SHOT:
			with_shot += dps
	if total <= 0:
		return 0
	return with_shot * 1000 / total
