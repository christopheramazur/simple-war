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
	# Per observer, once per tick (sw-arse): its sight and its detection
	# reach (-1 none), and a grid of observers by centroid with cells as wide
	# as the longest reach, so a squad only tests observers in the 3 x 3
	# cells around it. The old pair loop read both stats for every pair of
	# squads: quadratic, and most of a 160-squad battle's tick. Each pair
	# still gets the same test, so seen_by is the same.
	var sight := PackedInt64Array()
	sight.resize(n)
	var detect := PackedInt64Array()
	detect.resize(n)
	detect.fill(-1)
	var far := Fixed.ONE
	var observers := PackedInt64Array()
	for o in n:
		if not sq.is_active(o) or sq.alive[o] == 0:
			continue
		observers.append(o)
		sight[o] = Stats.squad(state, o, &"squad.sight", r.sq_sight[sq.tmpl[o]])
		far = maxi(far, sight[o])
		var det := Stats.squad(state, o, DETECT, r.sq_detection[sq.tmpl[o]])
		if det > 0:
			detect[o] = Fixed.mul(det, Pools.efficacy(state, o, BattleSquads.INSTINCT, Fixed.ONE / 2, Fixed.ONE))
			far = maxi(far, detect[o])
	var cx := sq.cx
	var cy := sq.cy
	var player := sq.player
	var gw := maxi(1, (r.width * Fixed.ONE + far - 1) / far)
	var gh := maxi(1, (r.height * Fixed.ONE + far - 1) / far)
	var grid := {}
	for o in observers:
		var k := clampi(cy[o] / far, 0, gh - 1) * gw + clampi(cx[o] / far, 0, gw - 1)
		var bucket: PackedInt64Array = grid.get(k, PackedInt64Array())
		bucket.append(o)
		grid[k] = bucket
	for t in n:
		if not sq.is_active(t):
			seen[t] = 0
			continue
		var mask := BattleSquads.bit(player[t])
		var tx := clampi(cx[t] / far, 0, gw - 1)
		var ty := clampi(cy[t] / far, 0, gh - 1)
		var ct := conceal[t]
		for gy in range(maxi(ty - 1, 0), mini(ty + 2, gh)):
			for gx in range(maxi(tx - 1, 0), mini(tx + 2, gw)):
				var bucket: PackedInt64Array = grid.get(gy * gw + gx, PackedInt64Array())
				for o in bucket:
					if o == t or player[o] == player[t]:
						continue
					var pbit := BattleSquads.bit(player[o])
					if mask & pbit != 0:
						continue
					var reach := Fixed.round_div(sight[o] * (100 - ct), 100)
					if ct > 0 and detect[o] >= 0:
						reach = maxi(reach, detect[o])
					# Fixed.distance(o, t) <= reach without the square root:
					# it rounds to nearest, so it is <= A exactly when the
					# squared length is <= A * A + A.
					var dx := cx[t] - cx[o]
					var dy := cy[t] - cy[o]
					if reach < 0 or dx * dx + dy * dy > reach * reach + reach:
						continue
					if r.los(cx[o], cy[o], cx[t], cy[t]):
						mask |= pbit
		mask |= _revealed(state, t)
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


## Bits of players whose scripted reveal covers squad row t (and who are not
## its own side).
func _revealed(state: BattleState, t: int) -> int:
	var sq := state.squads
	var bits := 0
	for rv: Array in state.reveals:
		if int(rv[4]) >= 0 and state.turn >= int(rv[4]) or int(rv[0]) == sq.player[t]:
			continue
		if Fixed.distance(sq.cx[t], sq.cy[t], int(rv[1]), int(rv[2])) <= int(rv[3]):
			bits |= BattleSquads.bit(int(rv[0]))
	return bits


## Whether squad o sees squad t (t's concealment `conceal`), pair by pair:
## the rule _compute applies with its per-tick observer columns and grid
## (test_vision_grid_matches_the_pair_rule).
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
