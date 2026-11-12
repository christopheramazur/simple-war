class_name CombatSystem
extends SimSystem
## Target selection and fire. GDD 02 §2.6, R3Q7, R5Q5, R6Q1, R6Q8.
##
## - A squad engages its ordered attack target if visible, else the nearest
##   visible enemy squad within its longest weapon range. Squads falling back
##   or withdrawing hold fire.
## - Each armed unit picks a fire mode (moving or standing), the nearest living
##   unit of the engaged squad in range and line of sight, and fires.
## - Hits come from an accuracy accumulator: accuracy * proficiency (* Instinct
##   efficacy when firing on the move). No dice (R2Q6).
## - Every Nth hit is a crit (crit_every / crit_bonus_pct) (R5Q5).
## - Hits are queued; HealthSystem applies the tick's hits together (E2Q2), so
##   fire is simultaneous. Units spread fire: a target whose queued damage
##   already covers its HP is skipped while another is in reach.
## - Floats: Prowess for ambush and intercept on a new engagement (R6Q1);
##   Legend for archetypal actions (R5Q6). Sinks: Instinct for firing on the
##   move (R4Q6). Stamina for HP lost and damage Legend: see HealthSystem.


func system_name() -> StringName:
	return &"combat"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	var sq := state.squads
	for row in sq.count():
		_engage(state, row)
	for row in sq.count():
		var target := sq.engaged[row]
		if target < 0:
			continue
		var trow := sq.row_of(target)
		if trow < 0 or not sq.is_active(trow):
			continue
		_fire_squad(state, row, trow)


func _engage(state: BattleState, row: int) -> void:
	var r := state.rules
	var sq := state.squads
	var prev := sq.engaged[row]
	var chosen := -1
	if sq.is_active(row) and sq.alive[row] > 0 and not (sq.order[row] in [BattleSquads.Order.FALL_BACK, BattleSquads.Order.WITHDRAW]):
		var me := sq.player[row]
		var reach := sq.reach[row]
		if sq.order[row] == BattleSquads.Order.ATTACK:
			var trow := sq.row_of(sq.target[row])
			if trow >= 0 and sq.is_active(trow) and sq.seen_by[trow] & BattleSquads.bit(me) != 0 \
					and Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[trow], sq.cy[trow]) <= reach:
				chosen = sq.target[row]
		# Sticky targeting: keep the current target while it stays valid.
		if chosen < 0 and prev >= 0:
			var prow := sq.row_of(prev)
			if prow >= 0 and sq.is_active(prow) and sq.alive[prow] > 0 and sq.seen_by[prow] & BattleSquads.bit(me) != 0 					and Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[prow], sq.cy[prow]) <= reach:
				chosen = prev
		if chosen < 0:
			var best_d := 1 << 62
			for t in sq.count():
				if sq.player[t] == me or not sq.is_active(t) or sq.alive[t] == 0 or sq.seen_by[t] & BattleSquads.bit(me) == 0:
					continue
				var d := Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[t], sq.cy[t])
				if d <= reach and d < best_d:
					best_d = d
					chosen = sq.id_at(t)
	if chosen == prev:
		return
	var col: PackedInt64Array = sq.take_column(&"engaged")
	col[row] = chosen
	sq.put_column(&"engaged", col)
	if chosen < 0:
		return
	var trow := sq.row_of(chosen)
	var tid := sq.id_at(row)
	state.events.push(&"engagement", {"squad": tid, "target": chosen}, state.tick)
	# Ambush: the target's player cannot see the attacker (R6Q1).
	if sq.seen_by[row] & BattleSquads.bit(sq.player[trow]) == 0:
		Pools.flow(state, row, BattleSquads.PROWESS, Fixed.from_int(r.flt("prowess_ambush")), &"ambush")
		state.events.push(&"ambush", {"squad": tid, "target": chosen}, state.tick)
	# Intercept: charging a squad that is itself charging one of ours (R6Q1).
	if sq.order[row] == BattleSquads.Order.ATTACK and sq.order[trow] == BattleSquads.Order.ATTACK:
		var their := sq.row_of(sq.target[trow])
		if their >= 0 and sq.player[their] == sq.player[row]:
			Pools.flow(state, row, BattleSquads.PROWESS, Fixed.from_int(r.flt("prowess_intercept")), &"intercept")
			state.events.push(&"intercept", {"squad": tid, "target": chosen}, state.tick)


func _fire_squad(state: BattleState, row: int, trow: int) -> void:
	var r := state.rules
	var sq := state.squads
	var u := state.units
	var targets := Centroids.units_of(state, trow)
	var shots_total := 0
	var hits_total := 0
	# unit row -> damage already queued on it this volley
	var pending := {}
	for urow in Centroids.units_of(state, row):
		if u.hp[urow] <= 0:
			continue
		var w := u.weapon[urow]
		if w < 0:
			continue
		if _tick_timers(u, urow, r):
			continue
		var is_moving := u.moving[urow] == 1
		var m := r.pick_mode(w, is_moving)
		if m < 0:
			continue
		var victim := _nearest_target(state, urow, targets, w, pending)
		if victim < 0:
			continue
		var accuracy := Stats.unit(state, urow, &"weapon.modes.*.accuracy", r.md_accuracy[m])
		var prof := Stats.unit(state, urow, &"unit.proficiency_pct", Fixed.from_int(r.ut_proficiency[u.tmpl[urow]]))
		var acc := Fixed.mul_ratio(accuracy, prof, 100 * Fixed.ONE)
		var base_dmg := Stats.unit(state, urow, &"weapon.modes.*.damage", r.md_damage[m])
		if is_moving:
			acc = Fixed.mul(acc, Pools.efficacy(state, row, BattleSquads.INSTINCT, Fixed.ONE / 2, Fixed.ONE))
			Pools.flow(state, row, BattleSquads.INSTINCT, -Fixed.from_int(r.sink("instinct_fire_moving")), &"fire_moving")
		for _s in r.md_shots[m]:
			if _covered(u, victim, pending):
				var next := _nearest_target(state, urow, targets, w, pending)
				if next >= 0:
					victim = next
			shots_total += 1
			if state.fx_listening.has("attack"):
				Effects.on_event(state, "attack", sq.id_at(row), u.id_at(urow), sq.id_at(trow), u.id_at(victim), Fixed.ONE)
			if not _roll_hit(u, urow, acc):
				continue
			hits_total += 1
			var dmg := base_dmg
			var hits_col: PackedInt64Array = u.take_column(&"hits")
			hits_col[urow] += 1
			var nth := hits_col[urow]
			u.put_column(&"hits", hits_col)
			if r.md_crit_every[m] > 0 and nth % r.md_crit_every[m] == 0:
				dmg += Fixed.round_div(dmg * r.md_crit_bonus[m], 100)
			_queue(state, urow, row, trow, victim, dmg, r.wp_type[w], pending)
			if r.md_aoe[m] > 0:
				for other in targets:
					if other == victim or u.hp[other] <= 0:
						continue
					if Fixed.distance(u.x[victim], u.y[victim], u.x[other], u.y[other]) <= r.md_aoe[m]:
						_queue(state, urow, row, trow, other, dmg, r.wp_type[w], pending)
		_after_fire(state, u, urow, row, m, w)
	if shots_total > 0:
		state.events.push(&"squad_fired", {"squad": sq.id_at(row), "target": sq.id_at(trow),
			"shots": shots_total, "hits": hits_total}, state.tick)


func _queue(state: BattleState, urow: int, row: int, trow: int, victim: int, dmg: int, dtype: int, pending: Dictionary) -> void:
	var u := state.units
	var sq := state.squads
	Health.queue(state, u.id_at(urow), sq.id_at(row), u.id_at(victim), sq.id_at(trow), dmg, dtype)
	pending[victim] = int(pending.get(victim, 0)) + dmg


## True when damage already queued on the unit covers its HP (ignoring
## defences, which only lower it).
static func _covered(u: BattleUnits, t: int, pending: Dictionary) -> bool:
	return int(pending.get(t, 0)) >= u.hp[t]


## Advances reload and cooldown; true while the unit can't fire this tick.
func _tick_timers(u: BattleUnits, urow: int, r: BattleRules) -> bool:
	if u.reload[urow] > 0:
		var rl: PackedInt64Array = u.take_column(&"reload")
		rl[urow] -= 1
		var done := rl[urow] == 0
		u.put_column(&"reload", rl)
		if done:
			var ammo: PackedInt64Array = u.take_column(&"ammo")
			ammo[urow] = r.wp_magazine[u.weapon[urow]]
			u.put_column(&"ammo", ammo)
		return true
	if u.cooldown[urow] > 0:
		var cd: PackedInt64Array = u.take_column(&"cooldown")
		cd[urow] -= 1
		u.put_column(&"cooldown", cd)
		return true
	return false


## Nearest living target in range and sight, preferring ones whose queued
## damage doesn't already cover their HP. -1 if none in reach.
func _nearest_target(state: BattleState, urow: int, targets: PackedInt64Array, w: int, pending: Dictionary) -> int:
	var r := state.rules
	var u := state.units
	var best := -1
	var best_d := 1 << 62
	var fallback := -1
	var fallback_d := 1 << 62
	for t in targets:
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		if d > r.wp_range[w] or d < r.wp_min_range[w]:
			continue
		var covered := _covered(u, t, pending)
		if (covered and d >= fallback_d) or (not covered and d >= best_d):
			continue
		if not r.los(u.x[urow], u.y[urow], u.x[t], u.y[t]):
			continue
		if covered:
			fallback_d = d
			fallback = t
		else:
			best_d = d
			best = t
	return best if best >= 0 else fallback


func _roll_hit(u: BattleUnits, urow: int, acc: int) -> bool:
	var col: PackedInt64Array = u.take_column(&"acc_hit")
	col[urow] += acc
	var hit := col[urow] >= Fixed.ONE
	if hit:
		col[urow] -= Fixed.ONE
	u.put_column(&"acc_hit", col)
	return hit


func _after_fire(state: BattleState, u: BattleUnits, urow: int, row: int, m: int, w: int) -> void:
	var r := state.rules
	var cd: PackedInt64Array = u.take_column(&"cooldown")
	cd[urow] = r.md_cooldown[m]
	u.put_column(&"cooldown", cd)
	if r.wp_magazine[w] > 0:
		var ammo: PackedInt64Array = u.take_column(&"ammo")
		ammo[urow] -= r.md_shots[m]
		var empty := ammo[urow] <= 0
		u.put_column(&"ammo", ammo)
		if empty:
			var rl: PackedInt64Array = u.take_column(&"reload")
			rl[urow] = maxi(r.wp_reload[w], 1)
			u.put_column(&"reload", rl)
	var ft: PackedInt64Array = u.take_column(&"fired_tick")
	ft[urow] = state.tick
	u.put_column(&"fired_tick", ft)
	var sft: PackedInt64Array = state.squads.take_column(&"fired_tick")
	sft[row] = state.tick
	state.squads.put_column(&"fired_tick", sft)
