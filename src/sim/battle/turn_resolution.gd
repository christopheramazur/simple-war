class_name TurnResolution
extends RefCounted
## End-of-turn rules: zone capture and scoring, victory conditions and
## end-of-battle hooks. Runs once after the last Execute tick of each turn.
## GDD 02 §2.4-2.5, R6Q10, R7Q5, R7Q6, R8Q3.


static func resolve(state: BattleState) -> void:
	state.turn += 1
	resolve_zones(state)
	check_victory(state)


## Per zone: vacuum (only at/above threshold) -> faction Capture Rate ->
## net push -> capture -> score.
static func resolve_zones(state: BattleState) -> void:
	var r := state.rules
	var sq := state.squads
	for z in r.zone_ids.size():
		var owner := state.zone_owner[z]
		var amount := state.zone_amount[z]
		# Vacuum applies only while the zone is at or above its threshold
		# (designer correction after R7Q5).
		if amount >= r.zn_threshold[z]:
			amount = maxi(amount - r.zn_decay[z], 0)
		if amount == 0:
			owner = 0
		# Capture Rate per player from squads ending the turn in the zone.
		var cr := {}
		for row in sq.count():
			if not sq.is_active(row) or sq.alive[row] == 0:
				continue
			if Fixed.distance(sq.cx[row], sq.cy[row], r.zn_x[z], r.zn_y[z]) > r.zn_radius[z]:
				continue
			var p := sq.player[row]
			cr[p] = int(cr.get(p, 0)) + r.sq_cr[sq.tmpl[row]]
		var strongest := 0
		var s1 := 0
		var s2 := 0
		for p in state.players:
			var v: int = cr.get(p, 0)
			if v > s1:
				s2 = s1
				s1 = v
				strongest = p
			elif v > s2:
				s2 = v
		var net := s1 - s2
		var cap := r.zn_threshold[z] + r.zn_buffer[z]
		if net > 0:
			if owner == 0 or owner == strongest:
				owner = strongest
				amount = mini(amount + net, cap)
			else:
				amount -= net
				if amount < 0:
					owner = strongest
					amount = mini(-amount, cap)
				elif amount == 0:
					owner = 0
		var was_held := state.zone_owner[z] != 0 and state.zone_amount[z] >= r.zn_threshold[z]
		var was_owner := state.zone_owner[z]
		state.zone_owner[z] = owner
		state.zone_amount[z] = amount
		var held := owner != 0 and amount >= r.zn_threshold[z]
		if held and (not was_held or was_owner != owner):
			state.post(&"zone_captured", {"zone": r.zone_ids[z], "player": owner, "turn": state.turn})
		if held:
			state.influence[owner] = int(state.influence[owner]) + r.zn_vp[z]


## Ends the battle when a victory condition holds. Data-driven (R7Q6).
static func check_victory(state: BattleState) -> void:
	if state.is_over():
		return
	var r := state.rules
	var sq := state.squads
	var fielded := {}
	var withdrew := {}
	for p in state.players:
		fielded[p] = 0
		withdrew[p] = 0
	for row in sq.count():
		var p := sq.player[row]
		if sq.is_active(row) and sq.alive[row] > 0:
			fielded[p] = int(fielded[p]) + 1
		elif sq.withdrawn[row] == 1:
			withdrew[p] = int(withdrew[p]) + 1
	var out := PackedInt64Array()
	var reason := ""
	for p in state.players:
		if int(fielded[p]) == 0:
			if r.withdrawal and int(withdrew[p]) > 0:
				out.append(p)
				reason = "withdrawal"
			elif r.annihilation:
				out.append(p)
				if reason.is_empty():
					reason = "annihilation"
	var winner := 0
	if out.size() > 0:
		var remaining := PackedInt64Array()
		for p in state.players:
			if not out.has(p):
				remaining.append(p)
		winner = remaining[0] if remaining.size() == 1 else 0
		if remaining.size() > 1:
			return
		_finish(state, winner, reason)
		return
	if r.score_target > 0:
		for p in state.players:
			if _primary(state, p) >= r.score_target:
				_finish(state, p, "score_target")
				return
	if state.turn >= r.turn_limit:
		_finish(state, _leader(state), "turn_limit")


static func _primary(state: BattleState, p: int) -> int:
	return int(state.influence[p]) if state.rules.primary_influence else int(state.value_score[p])


static func _secondary(state: BattleState, p: int) -> int:
	return int(state.value_score[p]) if state.rules.primary_influence else int(state.influence[p])


## Highest primary score, ties broken by the secondary; 0 if still tied (draw).
static func _leader(state: BattleState) -> int:
	var best := 0
	var tie := false
	for p in state.players:
		if best == 0:
			best = p
			continue
		var cmp := _compare(state, p, best)
		if cmp > 0:
			best = p
			tie = false
		elif cmp == 0:
			tie = true
	return 0 if tie else best


static func _compare(state: BattleState, a: int, b: int) -> int:
	var pa := _primary(state, a)
	var pb := _primary(state, b)
	if pa != pb:
		return 1 if pa > pb else -1
	var sa := _secondary(state, a)
	var sb := _secondary(state, b)
	if sa != sb:
		return 1 if sa > sb else -1
	return 0


static func _finish(state: BattleState, winner: int, reason: String) -> void:
	var sq := state.squads
	var survivors := {}
	for p in state.players:
		survivors[p] = []
	for row in sq.count():
		if sq.destroyed[row] == 1:
			continue
		var p := sq.player[row]
		var loser := winner != 0 and p != winner
		if loser and state.rules.loser_hook == "scatter" and sq.withdrawn[row] == 0:
			_scatter(state, row)
			continue
		(survivors[p] as Array).append(sq.id_at(row))
	var scores := {}
	for p in state.players:
		scores[p] = {"influence": state.influence[p], "value": state.value_score[p]}
	state.result = {"winner": winner, "reason": reason, "turn": state.turn, "scores": scores, "survivors": survivors}
	state.post(&"battle_ended", state.result.duplicate(true))


## End-of-battle hook "scatter": the loser's remaining squads leave play for
## good (R7Q6). Winners stay for the overworld to collect (R8Q3).
static func _scatter(state: BattleState, row: int) -> void:
	var sq := state.squads
	var col: PackedByteArray = sq.take_column(&"destroyed")
	col[row] = 1
	sq.put_column(&"destroyed", col)
	var u := state.units
	var sid := sq.id_at(row)
	var dead := PackedInt64Array()
	for urow in u.count():
		if u.squad[urow] == sid:
			dead.append(u.id_at(urow))
	for uid in dead:
		u.despawn(uid)
	state.post(&"squad_scattered", {"squad": sid, "player": sq.player[row]})
