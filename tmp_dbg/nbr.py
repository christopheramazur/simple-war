p='src/sim/battle/target_policy.gd'
s=open(p,encoding='utf-8').read()
def rep(a,b,cnt=1):
    global s
    assert s.count(a)>=1, a
    s=s.replace(a,b) if cnt==0 else s.replace(a,b,cnt)
rep('''	var expected: Dictionary = {}
	var plan: Dictionary = {}
''','''	var expected: Dictionary = {}
	var plan: Dictionary = {}
	## radius -> {victim row: PackedInt64Array of the living target rows its
	## splash reaches, itself first}. Hits apply after fire, so the set of
	## living targets is fixed for the volley.
	var near: Dictionary = {}
''')
# pick: plan check and best_area use volley
rep('''		if state.units.hp[pv] > 0 and _area_score(state, pv, targets, r.md_aoe[m], hit_damage(state, urow, m), r.wp_type[w], pending, memo) > 0:
			return pv
	var best := _best_area(state, urow, targets, w, m, pending, memo)''','''		if state.units.hp[pv] > 0 and _area_score(state, _reach(state, volley, targets, r.md_aoe[m])[pv], hit_damage(state, urow, m), r.wp_type[w], pending, memo) > 0:
			return pv
	var best := _best_area(state, urow, targets, w, m, pending, memo, _reach(state, volley, targets, r.md_aoe[m]))''')
rep('''static func _best_area(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary, memo: Dictionary) -> int:''','''static func _best_area(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary, memo: Dictionary, reach: Dictionary) -> int:''')
rep('''		var score := _area_score(state, v, targets, radius, dmg, dtype, pending, memo)''','''		var score := _area_score(state, reach[v], dmg, dtype, pending, memo)''')
rep('''	var radius := state.rules.md_aoe[m]
	var dmg := hit_damage(state, urow, m)
	var dtype := state.rules.wp_type[w]
	var best := -1
	var best_score := 0''','''	var dmg := hit_damage(state, urow, m)
	var dtype := state.rules.wp_type[w]
	var best := -1
	var best_score := 0''')
# area_score
a=s.index('static func _area_score'); b=s.index('## Adds (sign 1)')
s=s[:a]+'''static func _area_score(state: BattleState, splash: PackedInt64Array, dmg: int, dtype: int, pending: Dictionary, memo: Dictionary) -> int:
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


'''+s[b:]
a=s.index('static func _splash'); b=s.index('## The area plan (see')
s=s[:a]+'''static func _splash(state: BattleState, splash: PackedInt64Array, dmg: int, dtype: int, planned: Dictionary, memo: Dictionary, sign: int) -> void:
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


'''+s[b:]
# plan body
rep('''		choice.append(_best_area(state, shooters[i], targets, ws[i], ms[i], planned, memo))
		if choice[i] >= 0:
			_splash(state, choice[i], targets, r.md_aoe[ms[i]], dmgs[i], r.wp_type[ws[i]], planned, memo, 1)''','''		var reach := _reach(state, volley, targets, r.md_aoe[ms[i]])
		choice.append(_best_area(state, shooters[i], targets, ws[i], ms[i], planned, memo, reach))
		if choice[i] >= 0:
			_splash(state, reach[choice[i]], dmgs[i], r.wp_type[ws[i]], planned, memo, 1)''')
open(p,'w',encoding='utf-8',newline='').write(s)
