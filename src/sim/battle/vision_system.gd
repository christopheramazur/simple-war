class_name VisionSystem
extends SimSystem
## Who sees whom. GDD 02 §2.7, R7Q4, R8Q1, R8Q2.
##
## - Sight: every squad sees enemies within its sight radius and line of sight.
## - Concealment (the squad.concealment_pct stat, raised by Concealment
##   abilities' bundles) shrinks the range at which plain Sight spots the
##   squad: effective = sight * (100 - concealment%) / 100. While the squad
##   is concealed at all, its Instinct relative to Neutral shifts the
##   percentage; the result is clamped to 0..95.
## - Detection (the squad.detection_radius stat, raised by Detection
##   abilities' bundles) spots concealed squads inside its radius, which
##   scales with the detector's Instinct efficacy.
## Toggle upkeep and auto-off belong to Abilities (AbilitySystem).
## Results: squads.seen_by bitmasks, plus squad_revealed / squad_hidden events.

const CONCEAL: StringName = &"squad.concealment_pct"
const DETECT: StringName = &"squad.detection_radius"


func system_name() -> StringName:
	return &"vision"


func run(ctx: SimContext) -> void:
	_compute(ctx as BattleState)


func concealment_pct(state: BattleState, row: int) -> int:
	var sq := state.squads
	var base := state.rules.sq_concealment[sq.tmpl[row]]
	if base == 0 and not Stats.squad_has_mods(state, row, CONCEAL):
		return 0
	var pct := Fixed.to_int_round(Stats.squad(state, row, CONCEAL, base))
	var cap := Pools.capacity(state, row, BattleSquads.INSTINCT)
	var shift := Fixed.round_div((Pools.value(state, row, BattleSquads.INSTINCT) - Pools.neutral(state, row, BattleSquads.INSTINCT)) * 50, cap)
	return clampi(pct + shift, 0, 95)


func _compute(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	var n := sq.count()
	var conceal := PackedInt64Array()
	conceal.resize(n)
	for row in n:
		if sq.is_active(row):
			conceal[row] = concealment_pct(state, row)
	var seen: PackedInt64Array = sq.take_column(&"seen_by")
	var old := seen.duplicate()
	for t in n:
		if not sq.is_active(t):
			seen[t] = 0
			continue
		var mask := BattleSquads.bit(sq.player[t])
		for o in n:
			if o == t or not sq.is_active(o) or sq.alive[o] == 0 or sq.player[o] == sq.player[t]:
				continue
			var pbit := BattleSquads.bit(sq.player[o])
			if mask & pbit != 0:
				continue
			if _sees(state, o, t, conceal[t]):
				mask |= pbit
		seen[t] = mask
	sq.put_column(&"seen_by", seen)
	for t in n:
		var gained := seen[t] & ~old[t]
		var lost := old[t] & ~seen[t]
		for p in state.players:
			var b := BattleSquads.bit(p)
			if gained & b != 0:
				state.events.push(&"squad_revealed", {"squad": sq.id_at(t), "player": p}, state.tick)
				_scout_float(state, p, t)
			if lost & b != 0 and sq.is_active(t):
				state.events.push(&"squad_hidden", {"squad": sq.id_at(t), "player": p}, state.tick)


func _sees(state: BattleState, o: int, t: int, conceal: int) -> bool:
	var r := state.rules
	var sq := state.squads
	var d := Fixed.distance(sq.cx[o], sq.cy[o], sq.cx[t], sq.cy[t])
	var reach := Fixed.round_div(Stats.squad(state, o, &"squad.sight", r.sq_sight[sq.tmpl[o]]) * (100 - conceal), 100)
	if conceal > 0:
		var det := Stats.squad(state, o, DETECT, r.sq_detection[sq.tmpl[o]])
		if det > 0:
			var eff := Pools.efficacy(state, o, BattleSquads.INSTINCT, Fixed.ONE / 2, Fixed.ONE)
			reach = maxi(reach, Fixed.mul(det, eff))
	if d > reach:
		return false
	return r.los(sq.cx[o], sq.cy[o], sq.cx[t], sq.cy[t])


## Legend: scouts revealing (R5Q6). The nearest scout-archetype squad of the
## player gets the float.
func _scout_float(state: BattleState, player: int, t: int) -> void:
	var r := state.rules
	var sq := state.squads
	var amount := Fixed.from_int(r.flt("legend_scout_reveal"))
	if amount == 0:
		return
	var best := -1
	var best_d := 1 << 62
	for o in sq.count():
		if sq.player[o] != player or not sq.is_active(o) or BattleRules.ARCHETYPES[r.sq_archetype[sq.tmpl[o]]] != "scout":
			continue
		var d := Fixed.distance(sq.cx[o], sq.cy[o], sq.cx[t], sq.cy[t])
		if d <= Stats.squad(state, o, &"squad.sight", r.sq_sight[sq.tmpl[o]]) and d < best_d:
			best_d = d
			best = o
	if best >= 0:
		Pools.flow(state, best, BattleSquads.LEGEND, amount, &"scout_reveal")
