class_name OverworldBattles
extends RefCounted
## Battles fought for overworld engagements (GDD 02 §2.2-2.4, R2Q1, R3Q3).
##
## Building: the battlefield is the first feature's `battlefield` on the hex,
## else the map's `battle_scenario`. Each player with squads deployed in the
## engagement is a side, ascending; the hex's neutral guards (if any) are the
## last side, as battle player NEUTRAL. Sides take the scenario's deployment
## areas in order. Overworld squads keep their losses (fewer units spawn).
## Reinforcing: any squad deployed in the engagement but not yet in the
## battle (a reinforcement planned this turn) is spawned at its side's
## deployment area before the next battle turn.
## Finishing: survivors carry their units alive back to their armies (those
## of a commander that left form a convoy rallied to it, R8Q3); the
## destroyed and the scattered are gone. A commander whose own squad is gone
## is defeated, and the rest of its army scatters. A detachment on the
## losing side of a decided battle scatters; one with no squads left is
## gone. A win over guards clears them for good. The engagement ends, and winners on the hex take its
## features and caches. An engagement with only one side is won unopposed.

## Battle player ID of neutral guards.
const NEUTRAL: int = 30


## The battlefield scenario for a battle on plot p.
static func battlefield(s: OverworldState, p: int) -> String:
	for row in s.features_at(p):
		var b := s.rules.hf_battlefield[s.features.tmpl[row]]
		if not b.is_empty():
			return b
	return s.rules.battle_scenario


## Builds the battle for engagement eid, or returns null when it has fewer
## than two sides (then `finish_unopposed` applies). Errors go to `errors`.
static func build(t: TemplateTable, hash_hex: String, s: OverworldState, eid: int, context_id: int, seed_value: int, errors: PackedStringArray) -> OverworldBattle:
	var e := s.engagements
	var p := e.plot[e.row_of(eid)]
	var groups := _groups(s, eid)
	var guards := s.guard_at(p)
	if groups.size() + (0 if guards.is_empty() else 1) < 2:
		return null
	var scenario := battlefield(s, p)
	var br := BattleRules.compile(t, scenario, hash_hex)
	if not br.is_valid():
		errors.append("battlefield '%s': %s" % [scenario, "; ".join(br.errors)])
		return null
	var areas := br.sides.duplicate()
	var sides: Array[Dictionary] = []
	var owned := []
	var players: Array = groups.keys()
	players.sort()
	for pl: int in players:
		var sq := PackedInt64Array()
		var alive := PackedInt64Array()
		for id: int in groups[pl]:
			sq.append(br.squad_index(s.rules.squad_ids[s.squads.get_value(id, &"tmpl")]))
			alive.append(s.squads.get_value(id, &"alive"))
		sides.append(_side(areas, sides.size(), pl, sq, alive))
		owned.append(groups[pl])
	if not guards.is_empty():
		var sq := PackedInt64Array()
		for g in guards:
			sq.append(br.squad_index(g))
		sides.append(_side(areas, sides.size(), NEUTRAL, sq, PackedInt64Array()))
		owned.append([])
	br.sides = sides
	var b := OverworldBattle.new()
	b.engagement = eid
	b.plot = p
	b.context_id = context_id
	b.scenario = scenario
	b.rules = br
	b.state = BattleState.new(context_id, br, seed_value)
	for i in sides.size():
		var ids := BattleSetup.deploy_side(b.state, sides[i])
		var mine: Array = owned[i]
		for j in ids.size():
			b.links[ids[j]] = mine[j] if j < mine.size() else -1
	Centroids.update(b.state)
	VisionSystem.new().run(b.state)
	b.state.turn_log.append_array(b.state.events.drain())
	s.events.push(&"battle_started", {"engagement": eid, "plot": p, "scenario": scenario}, s.tick)
	return b


static func _side(areas: Array, i: int, player: int, squads: PackedInt64Array, alive: PackedInt64Array) -> Dictionary:
	var a: Dictionary = areas[i % areas.size()]
	return {"player": player, "facing": a["facing"], "deploy": (a["deploy"] as PackedInt64Array).duplicate(),
		"squads": squads, "alive": alive}


## Overworld squads deployed in eid, by owning player (through their
## commander or detachment).
static func _groups(s: OverworldState, eid: int) -> Dictionary:
	var out := {}
	for id in OverworldBattleforce.deployed_in(s, eid):
		var pl := OverworldArmies.player_of(s, id)
		if not out.has(pl):
			out[pl] = []
		(out[pl] as Array).append(id)
	return out


## Spawns reinforcements: squads deployed in the engagement but not yet in
## the battle, at their side's deployment area.
static func reinforce(s: OverworldState, b: OverworldBattle) -> void:
	var linked := {}
	for bid: int in b.links:
		linked[b.links[bid]] = true
	for id in OverworldBattleforce.deployed_in(s, b.engagement):
		if linked.has(id):
			continue
		var pl := OverworldArmies.player_of(s, id)
		var side := {}
		for sd in b.rules.sides:
			if sd["player"] == pl:
				side = sd
		if side.is_empty():
			continue  # a side that was not in the battle cannot join it mid-way
		var d: PackedInt64Array = side["deploy"]
		var st := b.rules.squad_index(s.rules.squad_ids[s.squads.get_value(id, &"tmpl")])
		var bid := BattleSetup.spawn_squad(b.state, pl, st, d[0] + d[2] / 2, d[1] + d[3] / 2, side["facing"], s.squads.get_value(id, &"alive"))
		b.links[bid] = id
		s.events.push(&"squad_reinforced", {"engagement": b.engagement, "squad": id, "player": pl}, s.tick)
	Centroids.update(b.state)


## Applies a finished battle's result to the overworld and ends the
## engagement.
static func finish(s: OverworldState, b: OverworldBattle) -> void:
	var res := b.state.result
	var bq := b.state.squads
	var winner: int = res["winner"]
	var bids: Array = b.links.keys()
	bids.sort()
	var left := {}  # commander that left the battle -> its surviving squads
	for bid: int in bids:
		var id: int = b.links[bid]
		if id < 0 or s.squads.row_of(id) < 0:
			continue
		var row := bq.row_of(bid)
		if row < 0 or bq.destroyed[row] == 1 or bq.alive[row] <= 0:
			s.squads.despawn(id)
			continue
		s.squads.set_value(id, &"alive", bq.alive[row])
		var holder := s.squads.get_value(id, &"holder")
		if holder >= 0 and s.commanders.get_value(holder, &"engagement") != b.engagement:
			var mine: PackedInt64Array = left.get(holder, PackedInt64Array())
			mine.append(id)
			left[holder] = mine
	var holders: Array = left.keys()
	holders.sort()
	for cid: int in holders:
		Convoys.rally_survivors(s, cid, b.plot, left[cid])
	_end(s, b.engagement, b.plot, 0 if winner == NEUTRAL else winner, String(res["reason"]), winner != 0)


## Ends an engagement nobody opposes: its one side wins.
static func finish_unopposed(s: OverworldState, eid: int) -> void:
	var e := s.engagements
	var p := e.plot[e.row_of(eid)]
	var groups := _groups(s, eid)
	var winner := 0
	if groups.size() == 1:
		winner = groups.keys()[0]
	else:
		for cid in Commanders.at(s, p):
			if s.commanders.get_value(cid, &"engagement") == eid:
				winner = s.commanders.get_value(cid, &"player")
	_end(s, eid, p, winner, "unopposed", winner > 0)


## Ends engagement eid on plot p. `winner` is the winning player (0 =
## neutral guards or nobody); `decided` is false for a draw.
static func _end(s: OverworldState, eid: int, p: int, winner: int, reason: String, decided: bool) -> void:
	var c := s.commanders
	var engaged := []
	for row in c.count():
		if c.engagement[row] == eid:
			engaged.append(c.id_at(row))
	engaged.sort()
	for cid: int in engaged:
		_check_defeat(s, cid)
	var d := s.detachments
	var held := []
	for row in d.count():
		if d.engagement[row] == eid:
			held.append(d.id_at(row))
	held.sort()
	for did: int in held:
		if Detachments.squads_of(s, did).is_empty():
			Detachments.disband(s, did, "destroyed")
		elif decided and (winner == 0 or s.hostile(winner, d.get_value(did, &"player"))):
			Detachments.disband(s, did, "defeated")
	if winner > 0 and (s.engagements.get_value(eid, &"kinds") & OverworldEngagements.GUARD) != 0:
		for row in s.features_at(p):
			if not s.rules.hf_guard[s.features.tmpl[row]].is_empty() and s.features.cleared[row] == 0:
				s.features.set_value(s.features.id_at(row), &"cleared", 1)
				s.events.push(&"guard_cleared", {"plot": p, "feature": s.features.id_at(row), "player": winner}, s.tick)
	OverworldMovement.end_engagement(s, eid)
	s.events.push(&"battle_resolved", {"engagement": eid, "plot": p, "winner": winner, "reason": reason}, s.tick)
	if winner > 0:
		for cid in Commanders.at(s, p):
			var row := c.row_of(cid)
			if c.player[row] == winner and c.engagement[row] < 0:
				OverworldMovement.arrive(s, row, p)


## A commander whose own squad is gone is defeated; its army scatters.
static func _check_defeat(s: OverworldState, cid: int) -> void:
	var q := s.squads
	for row in q.count():
		if q.holder[row] == cid and q.own[row] == 1:
			return
	var c := s.commanders
	var row := c.row_of(cid)
	if s.rules.cm_own_squad[c.tmpl[row]] < 0:
		return  # a commander without a squad of its own cannot fall in battle
	var player := c.player[row]
	var p := c.plot[row]
	for id in OverworldArmies.of(s, cid):
		q.despawn(id)
	c.despawn(cid)
	s.routes.erase(cid)
	s.activities.erase(cid)
	s.battleforces.erase(cid)
	s.events.push(&"commander_defeated", {"commander": cid, "player": player, "plot": p}, s.tick)


## Plain data for saves.
static func to_dict(b: OverworldBattle) -> Dictionary:
	var sides := []
	for sd in b.rules.sides:
		sides.append(sd.duplicate(true))
	return {"engagement": b.engagement, "plot": b.plot, "context": b.context_id, "scenario": b.scenario,
		"sides": sides, "state": b.state.snapshot(), "links": b.links.duplicate(), "orders": b.orders.duplicate(true)}


static func from_dict(t: TemplateTable, hash_hex: String, d: Dictionary) -> OverworldBattle:
	var b := OverworldBattle.new()
	b.engagement = d["engagement"]
	b.plot = d["plot"]
	b.context_id = d["context"]
	b.scenario = d["scenario"]
	b.rules = BattleRules.compile(t, b.scenario, hash_hex)
	var sides: Array[Dictionary] = []
	for sd: Dictionary in d["sides"]:
		sides.append(sd)
	b.rules.sides = sides
	b.state = BattleState.new(b.context_id, b.rules, 0)
	b.state.restore(d["state"])
	Centroids.update(b.state)
	b.links = d["links"]
	b.orders = d["orders"]
	return b
