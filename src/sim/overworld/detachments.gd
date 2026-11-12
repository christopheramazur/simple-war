class_name Detachments
extends RefCounted
## Detachments on the overworld (GDD 02 §2.3, §2.9, R2Q1, R4Q13, R5Q9):
## forces that hold a hex without a commander.
##   - Drop-off: a commander drops its battleforce (planned with its own
##     squad kept out) on its route, or 1 hex off it at a movement cost. The
##     squads leave its army and form a detachment there, or join the
##     player's detachment already on that hex.
##   - Garrison: a detachment stays where it was dropped. It never takes
##     features (only commanders flip control, R7Q8), but a hostile commander
##     entering its hex stops and engages it first.
##   - Battles: dropped onto a guarded hex, or meeting hostile forces, it is
##     pulled into the engagement and its strongest squads fight, within the
##     battleforce caps. Survivors stay; a detachment on the losing side of
##     a decided battle scatters, and one with no squads left is gone.
##   - Pick-up: a commander of the same player on its hex takes squads back
##     during planning (OverworldOrders.transfer_squad).
##   - Sight: each detachment sees the map's `detachment_sight` radius.


## Detachment IDs on a plot, ascending.
static func at(s: OverworldState, p: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var d := s.detachments
	for row in d.count():
		if d.plot[row] == p:
			out.append(d.id_at(row))
	out.sort()
	return out


## Squad IDs a detachment holds, ascending.
static func squads_of(s: OverworldState, did: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var q := s.squads
	for row in q.count():
		if q.detachment[row] == did:
			out.append(q.id_at(row))
	out.sort()
	return out


## Commander cid drops its battleforce (own squad kept out) on plot p.
## Returns the detachment ID, or -1 if there was nothing to drop.
static func drop(s: OverworldState, cid: int, p: int) -> int:
	var ids := OverworldBattleforce.pick(s, cid, true)
	if ids.is_empty():
		return -1
	var player := s.commanders.get_value(cid, &"player")
	var did := -1
	for other in at(s, p):
		if s.detachments.get_value(other, &"player") == player:
			did = other
			break
	if did < 0:
		did = s.detachments.spawn({&"player": player, &"plot": p})
	for id in ids:
		s.squads.set_value(id, &"holder", -1)
		s.squads.set_value(id, &"detachment", did)
	s.events.push(&"battleforce_dropped", {"commander": cid, "detachment": did, "player": player,
		"plot": p, "squads": ids}, s.tick)
	return did


## Pulls detachment did into engagement eid: its strongest squads not yet
## deployed join, within the battleforce caps (counting those already in).
static func deploy(s: OverworldState, did: int, eid: int) -> void:
	s.detachments.set_value(did, &"engagement", eid)
	var q := s.squads
	var r := s.rules
	var count := 0
	var total := 0
	var free := []
	for id in squads_of(s, did):
		var row := q.row_of(id)
		if q.deployed[row] == eid:
			count += 1
			total += OverworldBattleforce.strength(s, row)
		elif q.alive[row] > 0 and q.deployed[row] < 0:
			free.append([-OverworldBattleforce.strength(s, row), id])
	free.sort()
	var ids := PackedInt64Array()
	for f: Array in free:
		if count >= r.bf_cap_squads:
			break
		if r.bf_cap_value > 0 and total - int(f[0]) > r.bf_cap_value:
			continue
		ids.append(f[1])
		count += 1
		total -= int(f[0])
	for id in ids:
		q.set_value(id, &"deployed", eid)
	s.events.push(&"battleforce_deployed", {"detachment": did, "engagement": eid,
		"player": s.detachments.get_value(did, &"player"), "squads": ids}, s.tick)


## Removes a detachment and every squad it still holds.
static func disband(s: OverworldState, did: int, reason: String) -> void:
	var d := s.detachments
	var row := d.row_of(did)
	if row < 0:
		return
	var player := d.player[row]
	var p := d.plot[row]
	for id in squads_of(s, did):
		s.squads.despawn(id)
	d.despawn(did)
	s.events.push(&"detachment_disbanded", {"detachment": did, "player": player, "plot": p, "reason": reason}, s.tick)


## The detachment as plain data, like OverworldArmies.view.
static func view(s: OverworldState, did: int) -> Array:
	return OverworldArmies.view_ids(s, squads_of(s, did))
