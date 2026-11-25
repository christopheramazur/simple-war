class_name CombatSystem
extends SimSystem
## Target selection and fire. GDD 02 §2.6, R3Q7, R5Q5, R6Q1, R6Q8.
##
## - A squad engages its ordered attack target if visible, else the nearest
##   visible enemy squad within its longest weapon range. Squads falling back
##   or withdrawing hold fire.
## - Each armed unit picks a fire mode (moving or standing), the nearest living
##   unit of the engaged squad in range and line of sight, and fires. An
##   indirect mode (mortars) needs no line of sight: the engaged squad is
##   already seen by its side, so a spotter's vision is enough.
## - Reload and cooldown run in real time (GDD 02 §2.6, R6Q8): every living
##   armed unit ticks both timers each tick, engaged or not, concurrently.
##   Emptying a magazine sets both at once, so the gap to the next shot is
##   max(reload, cooldown), not their sum.
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
	_tick_timers(state)
	for row in sq.count():
		var target := sq.engaged[row]
		if target < 0:
			continue
		var trow := sq.row_of(target)
		if trow < 0 or not sq.is_active(trow):
			continue
		_fire_squad(state, row, trow)


## The squad row's engaged target this tick (a squad id), or -1. Ordered
## attack target when visible and in reach; else the sticky previous target
## while it stays valid; else the nearest visible enemy in reach. Pure: reads
## state only, so the read model can ask without running a tick.
static func pick_target(state: BattleState, row: int) -> int:
	var sq := state.squads
	var prev := sq.engaged[row]
	var chosen := -1
	if sq.is_active(row) and sq.alive[row] > 0 and not (sq.order[row] in [BattleSquads.Order.FALL_BACK, BattleSquads.Order.WITHDRAW]):
		var me := sq.player[row]
		if sq.order[row] == BattleSquads.Order.ATTACK:
			var trow := sq.row_of(sq.target[row])
			if trow >= 0 and sq.is_active(trow) and sq.seen_by[trow] & BattleSquads.bit(me) != 0 \
					and in_reach(state, row, trow):
				chosen = sq.target[row]
		# Sticky targeting: keep the current target while it stays valid.
		if chosen < 0 and prev >= 0:
			var prow := sq.row_of(prev)
			if prow >= 0 and sq.is_active(prow) and sq.alive[prow] > 0 and sq.seen_by[prow] & BattleSquads.bit(me) != 0 					and in_reach(state, row, prow):
				chosen = prev
		if chosen < 0:
			var best_d := 1 << 62
			for t in sq.count():
				if sq.player[t] == me or not sq.is_active(t) or sq.alive[t] == 0 or sq.seen_by[t] & BattleSquads.bit(me) == 0:
					continue
				var d := Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[t], sq.cy[t])
				if d < best_d and in_reach(state, row, t):
					best_d = d
					chosen = sq.id_at(t)
	return chosen


## Whether squad `row` can reach squad `t` (sw-txnj.5, U1Q28): some living
## armed unit of `row` has some living unit of `t` within its weapon range,
## unit to unit, so a squad engages as its first unit comes into range and
## its units open fire one by one, not when the centroids meet the longest
## range. Broadphase: centroids within reach plus both coherency radii.
static func in_reach(state: BattleState, row: int, t: int) -> bool:
	var sq := state.squads
	var r := state.rules
	var broad := sq.reach[row] + r.sq_coherency[sq.tmpl[row]] + r.sq_coherency[sq.tmpl[t]]
	if Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[t], sq.cy[t]) > broad:
		return false
	var u := state.units
	var theirs := Centroids.units_of(state, t)
	for a in Centroids.units_of(state, row):
		var w := u.weapon[a]
		if u.hp[a] <= 0 or w < 0:
			continue
		var rng := r.wp_range[w]
		var rng2 := rng * rng
		for b in theirs:
			if u.hp[b] <= 0:
				continue
			var dx := u.x[b] - u.x[a]
			var dy := u.y[b] - u.y[a]
			if dx * dx + dy * dy <= rng2:
				return true
	return false


func _engage(state: BattleState, row: int) -> void:
	var r := state.rules
	var sq := state.squads
	var prev := sq.engaged[row]
	var chosen := pick_target(state, row)
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
		# Readiness gate: the timer pass already ticked this tick; a timer
		# that reached 0 means the unit may fire now. Never tick here too.
		if u.reload[urow] > 0 or u.cooldown[urow] > 0:
			continue
		var is_moving := u.moving[urow] == 1
		var m := r.pick_mode(w, is_moving)
		if m < 0:
			continue
		var victim := TargetPolicy.pick(state, urow, targets, w, m, pending)
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
			if TargetPolicy.covered(u, victim, pending):
				var next := TargetPolicy.pick(state, urow, targets, w, m, pending)
				if next >= 0:
					victim = next
			shots_total += 1
			if state.fx_listening.has("attack"):
				Effects.on_event(state, "attack", sq.id_at(row), u.id_at(urow), sq.id_at(trow), u.id_at(victim), Fixed.ONE)
			var hit := _roll_hit(u, urow, acc)
			if state.trace_shots:
				state.shot_trace.append_array(PackedInt64Array([state.tick, u.id_at(urow), u.id_at(victim), 1 if hit else 0]))
			if not hit:
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


## Real-time weapon timers (GDD 02 §2.6): every living armed unit's reload
## and cooldown tick down once per tick, concurrently, whether or not its
## squad is engaged (holding fire or moving included). A reload reaching 0
## refills the magazine. Row order and integer math keep it deterministic.
func _tick_timers(state: BattleState) -> void:
	var u := state.units
	var r := state.rules
	var rl: PackedInt64Array = u.take_column(&"reload")
	var cd: PackedInt64Array = u.take_column(&"cooldown")
	var ammo: PackedInt64Array = u.take_column(&"ammo")
	for urow in u.count():
		if u.hp[urow] <= 0 or u.weapon[urow] < 0:
			continue
		if rl[urow] > 0:
			rl[urow] -= 1
			if rl[urow] == 0:
				ammo[urow] = r.wp_magazine[u.weapon[urow]]
		if cd[urow] > 0:
			cd[urow] -= 1
	u.put_column(&"reload", rl)
	u.put_column(&"cooldown", cd)
	u.put_column(&"ammo", ammo)


## Range and line-of-fire gate for one target at distance d, shared by the
## fire pass and the hold-fire reasons (BattleActivity) so they can never
## disagree (sw-ll4.27.2).
enum { GATE_OK, GATE_OUT_OF_RANGE, GATE_MIN_RANGE, GATE_NO_LOS }


static func shot_gate(state: BattleState, urow: int, t: int, w: int, m: int, d: int) -> int:
	var r := state.rules
	var u := state.units
	if d > r.wp_range[w]:
		return GATE_OUT_OF_RANGE
	if d < r.wp_min_range[w]:
		return GATE_MIN_RANGE
	if r.md_indirect[m] == 0 and not r.los(u.x[urow], u.y[urow], u.x[t], u.y[t]):
		return GATE_NO_LOS
	return GATE_OK


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
