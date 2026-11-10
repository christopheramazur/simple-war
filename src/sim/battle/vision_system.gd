class_name VisionSystem
extends SimSystem
## Who sees whom. GDD 02 §2.7, R7Q4, R8Q1, R8Q2.
##
## - Sight: every squad sees enemies within its sight radius and line of sight.
## - Concealment (an ability, when on) shrinks the range at which plain Sight
##   spots the squad: effective = sight * (100 - concealment%) / 100.
##   Concealment% = base + terrain + moving/firing modifiers, shifted by the
##   squad's Instinct relative to Neutral, clamped to 0..95.
## - Detection (an ability, when on) spots concealed squads inside its radius,
##   which scales with the detector's Instinct efficacy.
## - Active abilities sink Instinct each tick; when Instinct falls to the
##   source's auto-off band (default Broken) the ability switches off.
## Results: squads.seen_by bitmasks, plus squad_revealed / squad_hidden events.

## Firing within this many seconds counts as "firing" for concealment.
const FIRING_WINDOW_S: int = 2


func system_name() -> StringName:
	return &"vision"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	_upkeep(state)
	_compute(state)


func _upkeep(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	for row in sq.count():
		if not sq.is_active(row):
			continue
		var st := sq.tmpl[row]
		for kind in [&"detect_on", &"conceal_on"]:
			var on: PackedByteArray = sq.get(kind)
			if on[row] == 0:
				continue
			var ab: int = r.sq_detection[st] if kind == &"detect_on" else r.sq_concealment[st]
			if ab < 0:
				continue
			if r.ab_cost[ab] > 0:
				Pools.flow(state, row, BattleSquads.INSTINCT, -r.ab_cost[ab], StringName("ability_" + r.ab_ids[ab]))
				if Pools.band(state, row, BattleSquads.INSTINCT) <= r.ab_auto_off_band[ab]:
					var col: PackedByteArray = sq.take_column(kind)
					col[row] = 0
					sq.put_column(kind, col)
					state.events.push(&"ability_auto_off", {"squad": sq.id_at(row), "ability": r.ab_ids[ab]}, state.tick)


func concealment_pct(state: BattleState, row: int) -> int:
	var r := state.rules
	var sq := state.squads
	var ab := r.sq_concealment[sq.tmpl[row]]
	if ab < 0 or sq.conceal_on[row] == 0:
		return 0
	var pct := r.ab_base[ab] + r.ab_terrain[ab * r.feature_count() + r.feature_at(sq.cx[row], sq.cy[row])]
	if sq.moving[row] == 1:
		pct += r.ab_moving[ab]
	if sq.fired_tick[row] >= 0 and state.tick - sq.fired_tick[row] <= FIRING_WINDOW_S * r.tps:
		pct += r.ab_firing[ab]
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
	var reach := Fixed.round_div(r.sq_sight[sq.tmpl[o]] * (100 - conceal), 100)
	var det := r.sq_detection[sq.tmpl[o]]
	if conceal > 0 and det >= 0 and sq.detect_on[o] == 1:
		var eff := Pools.efficacy(state, o, BattleSquads.INSTINCT, Fixed.ONE / 2, Fixed.ONE)
		reach = maxi(reach, Fixed.mul(r.ab_radius[det], eff))
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
		if d <= r.sq_sight[sq.tmpl[o]] and d < best_d:
			best_d = d
			best = o
	if best >= 0:
		Pools.flow(state, best, BattleSquads.LEGEND, amount, &"scout_reveal")
