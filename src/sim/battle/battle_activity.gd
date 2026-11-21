class_name BattleActivity
extends RefCounted
## What a squad is doing and why an armed unit is not firing (sw-ll4.27.2,
## GDD 02 §2.6 "Shown"). Read-only: every code comes from the same state and
## rules functions the combat systems use (CombatSystem.shot_gate,
## BattleRules.pick_mode, the same los), so presentation never guesses and
## the reasons cannot disagree with the simulation. Nothing here is
## fog-filtered: the API layers decide what each viewer may see.
##
## Ticks: a tick's events are observed after it ends (state.tick has already
## advanced), so "fired this tick" means fired_tick == state.tick - 1.


## Squad activity. ENGAGED means it fired on the last completed tick; READY
## means it holds an engagement but did not fire (the units' hold reasons
## say why). HOLDING is the hold-position order (which still fires);
## FALLING_BACK / WITHDRAWING hold fire.
enum Squad { IDLE, MOVING, CLOSING_IN, ENGAGED, READY, HOLDING, FALLING_BACK, WITHDRAWING }

## Why an armed unit did not fire on the last completed tick. NONE = it
## fired, or nothing stops it (e.g. its squad has not engaged yet).
enum Hold { NONE, UNARMED, FALLING_BACK, RELOADING, COOLDOWN,
	NO_MOVING_FIRE, MIN_RANGE, OUT_OF_RANGE, NO_LOS, NOT_SPOTTED, NO_TARGET }


static func squad(state: BattleState, row: int) -> int:
	var sq := state.squads
	if not sq.is_active(row) or sq.alive[row] == 0:
		return Squad.IDLE
	match sq.order[row]:
		BattleSquads.Order.FALL_BACK:
			return Squad.FALLING_BACK
		BattleSquads.Order.WITHDRAW:
			return Squad.WITHDRAWING
	if sq.engaged[row] >= 0 and _fired_last_tick(sq.fired_tick[row], state.tick):
		return Squad.ENGAGED
	if sq.moving[row] == 1:
		return Squad.MOVING if sq.order[row] == BattleSquads.Order.MOVE else Squad.CLOSING_IN
	if sq.engaged[row] >= 0:
		return Squad.READY
	return Squad.HOLDING if sq.order[row] == BattleSquads.Order.HOLD else Squad.IDLE


## What any viewer may infer from an enemy's behaviour alone: no orders or
## engagement internals leak. Fired on the last tick, moving, or standing.
static func squad_seen(state: BattleState, row: int) -> int:
	var sq := state.squads
	if not sq.is_active(row) or sq.alive[row] == 0:
		return Squad.IDLE
	if _fired_last_tick(sq.fired_tick[row], state.tick):
		return Squad.ENGAGED
	return Squad.MOVING if sq.moving[row] == 1 else Squad.IDLE


## The same sanitising for playback frames, which carry the raw code and the
## ACT_MOVING bit but no state: hiding an order must not invent movement.
static func squad_public(code: int, moving: bool) -> int:
	match code:
		Squad.HOLDING, Squad.READY:
			return Squad.IDLE
		Squad.CLOSING_IN, Squad.FALLING_BACK, Squad.WITHDRAWING:
			return Squad.MOVING if moving else Squad.IDLE
	return code


## The unit's hold-fire reason, in the order the fire pass checks: the
## hold-fire orders, the weapon timers, the fire mode, then the target
## itself. The hold-position order does not hold fire, so it is no reason.
static func hold(state: BattleState, urow: int) -> int:
	var u := state.units
	var sq := state.squads
	var r := state.rules
	if u.hp[urow] <= 0:
		return Hold.NONE
	var w := u.weapon[urow]
	if w < 0:
		return Hold.UNARMED
	if _fired_last_tick(u.fired_tick[urow], state.tick):
		return Hold.NONE
	var row := sq.row_of(u.squad[urow])
	if row < 0 or not sq.is_active(row):
		return Hold.NONE
	if sq.order[row] in [BattleSquads.Order.FALL_BACK, BattleSquads.Order.WITHDRAW]:
		return Hold.FALLING_BACK
	if u.reload[urow] > 0:
		return Hold.RELOADING
	if u.cooldown[urow] > 0:
		return Hold.COOLDOWN
	var m := r.pick_mode(w, u.moving[urow] == 1)
	if m < 0:
		return Hold.NO_MOVING_FIRE
	var trow := sq.row_of(sq.engaged[row])
	if trow >= 0 and sq.is_active(trow):
		return _target_hold(state, urow, trow, w, m)
	# No engagement: is there anything in weapon reach, and is it spotted?
	var me := BattleSquads.bit(sq.player[row])
	var in_reach := false
	var spotted := false
	for t in sq.count():
		if sq.player[t] == sq.player[row] or not sq.is_active(t) or sq.alive[t] == 0:
			continue
		if Fixed.distance(u.x[urow], u.y[urow], sq.cx[t], sq.cy[t]) > r.wp_range[w]:
			continue
		in_reach = true
		if sq.seen_by[t] & me != 0:
			spotted = true
	if not in_reach:
		return Hold.NO_TARGET
	return Hold.NOT_SPOTTED if not spotted else Hold.NONE


## The unit's current victim: the nearest living unit of its engaged squad
## that range and line of fire allow (what it aims at), or -1.
static func victim(state: BattleState, urow: int) -> int:
	var u := state.units
	var sq := state.squads
	var r := state.rules
	var w := u.weapon[urow]
	if w < 0 or u.hp[urow] <= 0:
		return -1
	var row := sq.row_of(u.squad[urow])
	if row < 0:
		return -1
	var trow := sq.row_of(sq.engaged[row])
	if trow < 0 or not sq.is_active(trow):
		return -1
	var m := r.pick_mode(w, u.moving[urow] == 1)
	if m < 0:
		return -1
	var best := -1
	var best_d := 1 << 62
	for t in Centroids.units_of(state, trow):
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		if d < best_d and CombatSystem.shot_gate(state, urow, t, w, m, d) == CombatSystem.GATE_OK:
			best_d = d
			best = t
	return best


## The own-unit weapon report for observe/inspect: the hold reason, weapon,
## ammo / magazine, reload and cooldown left, current victim and its distance
## (raw fixed). Never shown for enemy units (fog).
static func unit_report(state: BattleState, urow: int) -> Dictionary:
	var u := state.units
	var r := state.rules
	var w := u.weapon[urow]
	var v := victim(state, urow)
	return {
		"hold": hold(state, urow),
		"weapon": String(r.weapon_index.find_key(w)) if w >= 0 else "",
		"ammo": u.ammo[urow], "magazine": r.wp_magazine[w] if w >= 0 else 0,
		"reload": u.reload[urow], "cooldown": u.cooldown[urow],
		"victim": u.id_at(v) if v >= 0 else -1,
		"victim_dist": Fixed.distance(u.x[urow], u.y[urow], u.x[v], u.y[v]) if v >= 0 else 0,
	}


static func _fired_last_tick(fired: int, tick: int) -> bool:
	return tick > 0 and fired == tick - 1


## The engaged squad's nearest blocker: a valid target means nothing holds
## the unit (it fired, or spread fire skipped it); else the nearest living
## target's gate is the reason. No living target: NO_TARGET.
static func _target_hold(state: BattleState, urow: int, trow: int, w: int, m: int) -> int:
	var u := state.units
	var nearest := -1
	var nearest_d := 1 << 62
	var gate := CombatSystem.GATE_OK
	for t in Centroids.units_of(state, trow):
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		var g := CombatSystem.shot_gate(state, urow, t, w, m, d)
		if g == CombatSystem.GATE_OK:
			return Hold.NONE
		if d < nearest_d:
			nearest_d = d
			nearest = t
			gate = g
	if nearest < 0:
		return Hold.NO_TARGET
	match gate:
		CombatSystem.GATE_MIN_RANGE:
			return Hold.MIN_RANGE
		CombatSystem.GATE_NO_LOS:
			return Hold.NO_LOS
	return Hold.OUT_OF_RANGE
