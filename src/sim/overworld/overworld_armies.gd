class_name OverworldArmies
extends RefCounted
## Commanders' armies (GDD 02 §2.3, R2Q1, R7Q9): the commander's own squad
## plus the squads it holds, up to its template's army_cap (the own squad
## does not count). Squads keep their losses between battles until refitted.


## Squad IDs a commander holds, own squad first, then by ID.
static func of(s: OverworldState, cid: int) -> PackedInt64Array:
	var q := s.squads
	var own := PackedInt64Array()
	var rest := PackedInt64Array()
	for row in q.count():
		if q.holder[row] == cid:
			(own if q.own[row] == 1 else rest).append(q.id_at(row))
	rest.sort()
	own.append_array(rest)
	return own


## Squads held besides the commander's own.
static func count(s: OverworldState, cid: int) -> int:
	var n := 0
	for row in s.squads.count():
		if s.squads.holder[row] == cid and s.squads.own[row] == 0:
			n += 1
	return n


static func cap(s: OverworldState, cid: int) -> int:
	return s.rules.cm_army_cap[s.commanders.get_value(cid, &"tmpl")]


## Adds a squad at full strength. Returns its ID.
static func add(s: OverworldState, cid: int, sq: int, own: bool = false) -> int:
	var size := s.rules.sq_size[sq]
	return s.squads.spawn({&"holder": cid, &"tmpl": sq, &"alive": size, &"size": size, &"own": 1 if own else 0})


## The commander's own squad and starting army (on spawning a commander).
static func muster(s: OverworldState, cid: int) -> void:
	var t := s.commanders.get_value(cid, &"tmpl")
	if s.rules.cm_own_squad[t] >= 0:
		add(s, cid, s.rules.cm_own_squad[t], true)
	for sq in s.rules.cm_army[t]:
		add(s, cid, sq)


## Units missing across the army.
static func losses(s: OverworldState, cid: int) -> int:
	var q := s.squads
	var n := 0
	for row in q.count():
		if q.holder[row] == cid:
			n += q.size[row] - q.alive[row]
	return n


## Restores every squad of the army to full strength. Returns units restored.
static func refit(s: OverworldState, cid: int) -> int:
	var q := s.squads
	var n := 0
	for id in of(s, cid):
		var row := q.row_of(id)
		n += q.size[row] - q.alive[row]
		q.set_value(id, &"alive", q.size[row])
	return n


## Moves a squad to another commander's army (R7Q9), out of its army or
## detachment. Checks are the caller's.
static func move(s: OverworldState, squad_id: int, to_cid: int) -> void:
	s.squads.set_value(squad_id, &"holder", to_cid)
	s.squads.set_value(squad_id, &"detachment", -1)


## The player owning a squad, through its commander or detachment (0 if
## neither exists).
static func player_of(s: OverworldState, squad_id: int) -> int:
	var q := s.squads
	var row := q.row_of(squad_id)
	if row < 0:
		return 0
	if q.detachment[row] >= 0:
		var dr := s.detachments.row_of(q.detachment[row])
		return s.detachments.player[dr] if dr >= 0 else 0
	var cr := s.commanders.row_of(q.holder[row])
	return s.commanders.player[cr] if cr >= 0 else 0


## The army as plain data: [{"id", "tmpl", "alive", "size", "own"}].
static func view(s: OverworldState, cid: int) -> Array:
	return view_ids(s, of(s, cid))


static func view_ids(s: OverworldState, ids: PackedInt64Array) -> Array:
	var q := s.squads
	var out := []
	for id in ids:
		var row := q.row_of(id)
		out.append({"id": id, "tmpl": q.tmpl[row], "alive": q.alive[row], "size": q.size[row], "own": q.own[row] == 1})
	return out
