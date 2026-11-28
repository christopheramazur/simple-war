class_name TargetPolicy
extends RefCounted
## Which unit a shot goes to, and whether queued damage already covers a unit
## (GDD 02 §2.6 Fire distribution, sw-txnj.1). Static only: the fire pass, the
## read model and the workshop probes ask the same question the same way.
## Range and sight come from CombatSystem.shot_gate, so this file never
## re-derives them.
##
## The policy is data: the ruleset's fire.policy (DataSchema.FIRE_POLICIES),
## which a squad's fire_policy column may override (sw-pd2l.4).
## - nearest (default): the nearest unit in reach. Spread: a target whose
##   queued damage already covers its HP is skipped while another is in
##   reach; a covered target is only the fallback.
## - focus: kill priority. Remaining HP = HP minus the expected damage queued
##   this volley. A hit that can finish a unit goes to the one it overshoots
##   least (best fit); otherwise to the lowest remaining HP; ties go to the
##   lowest unit ID, so the whole squad agrees. A fire mode with an area
##   picks the victim whose radius holds the most units the hit would finish,
##   then the most useful damage (damage up to each unit's remaining HP).
##   With nothing uncovered in reach it falls back to nearest.
##
## Area plan (focus): one splash finishing five units can strand a tougher
## unit that needs two. So at the start of a volley the squad's ready
## area-mode shooters are planned together: greedy in row order, then each
## shot is moved to the best victim given the others' splashes while that
## raises the volley's kills (then useful damage), at most PLAN_PASSES rounds.
## The plan assumes every planned shot hits (a miss changes nothing).
##
## Cost per shooter: one pass over the targets (a second, in-radius pass for
## area modes), the shot gate (and its line of sight) only for a candidate
## that beats the best so far. Expected damage is memoised in the Volley (one
## per squad per tick), so DamagePipeline.preview runs once per target and
## hit size, not once per shooter.

const NEAREST: int = 0
const FOCUS: int = 1
const PLAN_PASSES: int = 2
## Area score: kills above this bit, useful damage (fixed) below it.
const _KILL_SHIFT: int = 40


## One squad's volley this tick: its policy, the expected-damage memo and the
## area plan (shooter unit row -> victim unit row). Built by begin_volley.
class Volley extends RefCounted:
	var policy: int = NEAREST
	var expected: Dictionary = {}
	var plan: Dictionary = {}
	## radius -> {victim row: PackedInt64Array of the living target rows its
	## splash reaches, itself first}. Hits apply after fire, so the set of
	## living targets is fixed for the volley.
	var near: Dictionary = {}


## The targeting policy of the squad at row: its fire_policy override, else
## the ruleset's fire.policy.
static func squad_policy(state: BattleState, row: int) -> int:
	var p := state.squads.fire_policy[row]
	return p if p >= 0 else state.rules.fire_policy


## Starts the volley of the squad at row against `targets` (the engaged
## squad's unit rows; nothing queued yet).
static func begin_volley(state: BattleState, row: int, targets: PackedInt64Array) -> Volley:
	var v := Volley.new()
	v.policy = squad_policy(state, row)
	if v.policy == FOCUS:
		_plan_area(state, row, targets, v)
	return v


## The victim for the shooter at urow among `targets` (unit rows of one
## squad), or -1 if none is in reach. Without a volley the shooter's squad
## policy is resolved and nothing is memoised or planned (read models, tests).
static func pick(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary, volley: Volley = null) -> int:
	var policy := volley.policy if volley != null else squad_policy(state, state.squads.row_of(state.units.squad[urow]))
	if policy != FOCUS:
		return nearest(state, urow, targets, w, m, pending)
	var memo: Dictionary = volley.expected if volley != null else {}
	var r := state.rules
	if r.md_aoe[m] <= 0:
		return _focus(state, urow, targets, w, m, pending, memo)
	var dmg := hit_damage(state, urow, m)
	var reach := _reach(state, volley, targets, r.md_aoe[m])
	if volley != null and volley.plan.has(urow):
		var pv: int = volley.plan[urow]
		if reach.has(pv) and _area_score(state, reach[pv], dmg, r.wp_type[w], pending, memo) > 0:
			return pv
	var best := _best_area(state, urow, targets, w, m, dmg, pending, memo, reach)
	return best if best >= 0 else nearest(state, urow, targets, w, m, pending)


## Nearest living target in range and sight, preferring ones whose queued
## damage doesn't already cover their HP. -1 if none in reach. The shot gate
## (and its line of sight) runs only for a target nearer than the best so far
## (sw-arse): both tests must pass for a target to be taken, so testing the
## cheap one first picks the same unit with fewer traces.
static func nearest(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary) -> int:
	var u := state.units
	var best := -1
	var best_d := 1 << 62
	var fallback := -1
	var fallback_d := 1 << 62
	for t in targets:
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		var is_covered := covered(u, t, pending)
		if (is_covered and d >= fallback_d) or (not is_covered and d >= best_d):
			continue
		if CombatSystem.shot_gate(state, urow, t, w, m, d) != CombatSystem.GATE_OK:
			continue
		if is_covered:
			fallback_d = d
			fallback = t
		else:
			best_d = d
			best = t
	return best if best >= 0 else fallback


## True when the expected damage already queued on the unit covers its HP.
## `pending` holds each queued hit through the victim's defences without
## evasion and block (DamagePipeline.preview), so armour counts (sw-pd2l.3).
static func covered(u: BattleUnits, t: int, pending: Dictionary) -> bool:
	return int(pending.get(t, 0)) >= u.hp[t]


## The shooter's next hit, fixed: the mode's damage after modifiers, plus the
## crit bonus when its next hit is the every-Nth crit (predictable, R5Q5).
## The same sum CombatSystem._fire_squad queues.
static func hit_damage(state: BattleState, urow: int, m: int) -> int:
	var r := state.rules
	var dmg := Stats.unit(state, urow, &"weapon.modes.*.damage", r.md_damage[m])
	if r.md_crit_every[m] > 0 and (state.units.hits[urow] + 1) % r.md_crit_every[m] == 0:
		dmg += Fixed.round_div(dmg * r.md_crit_bonus[m], 100)
	return dmg


## Kill priority with the best-fit tie-break (single-target modes).
static func _focus(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary, memo: Dictionary) -> int:
	var u := state.units
	var dmg := hit_damage(state, urow, m)
	var dtype := state.rules.wp_type[w]
	var best := -1
	var best_fin := false
	var best_key := 0
	var best_id := 0
	for t in targets:
		if u.hp[t] <= 0:
			continue
		var rem := u.hp[t] - int(pending.get(t, 0))
		if rem <= 0:
			continue
		var e := _expected(state, t, dmg, dtype, memo)
		if e <= 0:
			continue
		var fin := e >= rem
		# Lower is better: the overshoot of a finishing hit, else what is left.
		var key := e - rem if fin else rem
		var id := u.id_at(t)
		if best >= 0:
			if best_fin and not fin:
				continue
			if fin == best_fin and (key > best_key or (key == best_key and id >= best_id)):
				continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		if CombatSystem.shot_gate(state, urow, t, w, m, d) != CombatSystem.GATE_OK:
			continue
		best = t
		best_fin = fin
		best_key = key
		best_id = id
	return best if best >= 0 else nearest(state, urow, targets, w, m, pending)


## Area modes: the victim whose radius holds the most units the hit would
## finish, then the most useful damage, then the lowest unit ID; -1 if no
## victim in reach does useful damage. The splash set is the one
## CombatSystem._fire_squad queues: every living target within the radius of
## the victim, the victim included.
static func _best_area(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, dmg: int, pending: Dictionary, memo: Dictionary, reach: Dictionary) -> int:
	var u := state.units
	var dtype := state.rules.wp_type[w]
	var best := -1
	var best_score := 0
	var best_id := 0
	for v in targets:
		if u.hp[v] <= 0:
			continue
		var score := _area_score(state, reach[v], dmg, dtype, pending, memo)
		if score <= 0:
			continue
		var id := u.id_at(v)
		if best >= 0 and (score < best_score or (score == best_score and id >= best_id)):
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[v], u.y[v])
		if CombatSystem.shot_gate(state, urow, v, w, m, d) != CombatSystem.GATE_OK:
			continue
		best = v
		best_score = score
		best_id = id
	return best


## (kills << _KILL_SHIFT) + useful damage of one hit on victim v: kills are
## the units in the radius the hit finishes, useful damage its expected
## damage on each uncovered unit, up to that unit's remaining HP.
static func _area_score(state: BattleState, splash: PackedInt64Array, dmg: int, dtype: int, pending: Dictionary, memo: Dictionary) -> int:
	var u := state.units
	var kills := 0
	var useful := 0
	for o in splash:
		var rem := u.hp[o] - int(pending.get(o, 0))
		if rem <= 0:
			continue
		var e := _expected(state, o, dmg, dtype, memo)
		useful += mini(e, rem)
		if e >= rem:
			kills += 1
	return (kills << _KILL_SHIFT) + useful


## Adds (sign 1) or removes (sign -1) one hit's splash on victim v in `planned`.
static func _splash(state: BattleState, splash: PackedInt64Array, dmg: int, dtype: int, planned: Dictionary, memo: Dictionary, sign: int) -> void:
	for o in splash:
		planned[o] = int(planned.get(o, 0)) + sign * _expected(state, o, dmg, dtype, memo)


## Each living target's splash set for one radius (see Volley.near), built
## once per volley and radius; without a volley, built for the call.
static func _reach(state: BattleState, volley: Volley, targets: PackedInt64Array, radius: int) -> Dictionary:
	if volley != null and volley.near.has(radius):
		return volley.near[radius]
	var u := state.units
	var out := {}
	for v in targets:
		if u.hp[v] <= 0:
			continue
		var set := PackedInt64Array([v])
		for o in targets:
			if o != v and u.hp[o] > 0 and Fixed.distance(u.x[v], u.y[v], u.x[o], u.y[o]) <= radius:
				set.append(o)
		out[v] = set
	if volley != null:
		volley.near[radius] = out
	return out


## The area plan (see the file header): the squad's ready area-mode shooters
## (the readiness test CombatSystem._fire_squad makes), greedy, then
## coordinate descent on (kills, useful damage). Only for two or more such
## shooters: a lone shooter's greedy pick is already its best.
static func _plan_area(state: BattleState, row: int, targets: PackedInt64Array, volley: Volley) -> void:
	var u := state.units
	var r := state.rules
	var shooters := PackedInt64Array()
	var ws := PackedInt64Array()
	var ms := PackedInt64Array()
	for urow in Centroids.units_of(state, row):
		if u.hp[urow] <= 0 or u.weapon[urow] < 0 or u.reload[urow] > 0 or u.cooldown[urow] > 0:
			continue
		var m := CombatSystem.fire_mode(state, urow, CombatSystem.fires_moving(state, urow))
		if m < 0 or r.md_aoe[m] <= 0:
			continue
		shooters.append(urow)
		ws.append(u.weapon[urow])
		ms.append(m)
	var n := shooters.size()
	if n < 2:
		return
	var memo := volley.expected
	var dmgs := PackedInt64Array()
	var choice := PackedInt64Array()
	var planned := {}
	for i in n:
		dmgs.append(hit_damage(state, shooters[i], ms[i]))
		var reach := _reach(state, volley, targets, r.md_aoe[ms[i]])
		choice.append(_best_area(state, shooters[i], targets, ws[i], ms[i], dmgs[i], planned, memo, reach))
		if choice[i] >= 0:
			_splash(state, reach[choice[i]], dmgs[i], r.wp_type[ws[i]], planned, memo, 1)
	for _pass in PLAN_PASSES:
		var changed := false
		for i in n:
			if choice[i] < 0:
				continue
			var reach := _reach(state, volley, targets, r.md_aoe[ms[i]])
			var dtype := r.wp_type[ws[i]]
			_splash(state, reach[choice[i]], dmgs[i], dtype, planned, memo, -1)
			var alt := _best_area(state, shooters[i], targets, ws[i], ms[i], dmgs[i], planned, memo, reach)
			if alt >= 0 and alt != choice[i] and _area_score(state, reach[alt], dmgs[i], dtype, planned, memo) \
					> _area_score(state, reach[choice[i]], dmgs[i], dtype, planned, memo):
				choice[i] = alt
				changed = true
			_splash(state, reach[choice[i]], dmgs[i], dtype, planned, memo, 1)
		if not changed:
			break
	for i in n:
		if choice[i] >= 0:
			volley.plan[shooters[i]] = choice[i]


## Expected effective damage of one hit on unit row t (DamagePipeline.preview),
## memoised per volley by target, damage type and hit size.
static func _expected(state: BattleState, t: int, dmg: int, dtype: int, memo: Dictionary) -> int:
	var key := t | (dtype << 20) | (dmg << 24)
	var e: Variant = memo.get(key)
	if e == null:
		e = DamagePipeline.preview(state, t, dmg, dtype)
		memo[key] = e
	return e
