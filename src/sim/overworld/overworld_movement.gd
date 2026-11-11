class_name OverworldMovement
extends RefCounted
## Resolves every planned route at once (GDD 02 §2.9).
##
## Movement runs in movement-point "time": a commander enters each hex of its
## route when it has spent that hex's cumulative cost, so whoever gets there
## first arrives first. Entries are processed in (time, commander ID, step)
## order. A commander stops on entering a hex that:
##   - is already a battle tile (it joins that engagement, R4Q13);
##   - has a neutral guard (an engagement starts, R4Q14, R6Q11);
##   - holds a hostile commander at that moment, including one just about to
##     leave it: both stop and engage. Two commanders swapping hexes at the
##     same instant therefore meet. Full chase and intercept (R3Q22) is still
##     to be specified.
## Every commander on a hex where an engagement starts or is joined stops
## there. A commander that passes through or ends on an unguarded hex takes
## its controllable features (R6Q14, R7Q8).
## Banking (R6Q11): a commander whose route was cut short by an engagement
## banks 50% of its unused points, capped at one turn's worth, for next turn
## only; everyone else's bank expires.

const BANK_PCT: int = 50


static func resolve(s: OverworldState) -> void:
	var c := s.commanders
	var steps := []        # [time, commander ID, step index]
	var moving := {}       # commander ID -> still following its route
	var last := {}         # commander ID -> index of its last reachable step
	var spent := {}        # commander ID -> points spent so far
	var cut := {}          # commander ID -> stopped by an engagement
	var ids: Array = s.routes.keys()
	ids.sort()
	for cid: int in ids:
		var row := c.row_of(cid)
		if row < 0 or c.engagement[row] >= 0:
			continue
		var route: PackedInt64Array = s.routes[cid]
		var budget := Commanders.budget(s, row)
		var t := 0
		var at := c.plot[row]
		for i in route.size():
			var cost := s.move_cost(route[i])
			# Routes were valid when set; stop at a step that no longer is.
			if cost < 0 or not Hex.adjacent(at, route[i], s.rules.width) or t + cost > budget:
				break
			t += cost
			steps.append([t, cid, i])
			last[cid] = i
			at = route[i]
		moving[cid] = last.has(cid)
		spent[cid] = 0
	steps.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	for st: Array in steps:
		var cid: int = st[1]
		if not moving.get(cid, false):
			continue
		var to: int = (s.routes[cid] as PackedInt64Array)[st[2]]
		var row := c.row_of(cid)
		var from := c.plot[row]
		c.set_value(cid, &"plot", to)
		spent[cid] = st[0]
		s.events.push(&"commander_moved", {"commander": cid, "from": from, "to": to}, s.tick)
		if _engages(s, cid, to):
			for other in Commanders.at(s, to):
				if moving.get(other, false):
					moving[other] = false
					# Stopping on the route's last hex is arriving, not a cut plan.
					if other != cid or st[2] < last[cid]:
						cut[other] = true
			continue
		_capture(s, row, to)
		if st[2] == last[cid]:
			moving[cid] = false  # route finished: being engaged later is not a cut plan
	for row in c.count():
		var cid := c.id_at(row)
		var bank := 0
		if cut.has(cid):
			var unused := Commanders.budget(s, row) - int(spent[cid])
			bank = mini(unused * BANK_PCT / 100, s.rules.cm_mp[c.tmpl[row]])
		c.set_value(cid, &"banked", bank)


## Starts or joins an engagement if the commander must stop on plot p, and
## pulls everyone on the hex into it. Returns whether it stopped.
static func _engages(s: OverworldState, cid: int, p: int) -> bool:
	var c := s.commanders
	var player := c.player[c.row_of(cid)]
	var kinds := 0
	if not s.guard_at(p).is_empty():
		kinds |= OverworldEngagements.GUARD
	var here := Commanders.at(s, p)
	for other in here:
		if other != cid and s.hostile(player, c.player[c.row_of(other)]):
			kinds |= OverworldEngagements.COMMANDERS
	var eid := s.engagement_at(p)
	if eid < 0 and kinds == 0:
		return false
	var e := s.engagements
	if eid < 0:
		eid = e.spawn({&"plot": p, &"kinds": kinds, &"turn": s.turn})
		s.events.push(&"engagement_started", {"engagement": eid, "plot": p, "kinds": kinds}, s.tick)
	else:
		e.set_value(eid, &"kinds", e.kinds[e.row_of(eid)] | kinds)
	for other in here:
		var orow := c.row_of(other)
		if c.engagement[orow] != eid:
			c.set_value(other, &"engagement", eid)
			s.events.push(&"commander_engaged", {"commander": other, "engagement": eid, "plot": p}, s.tick)
	return true


## A commander on an unguarded hex takes its controllable features.
static func _capture(s: OverworldState, row: int, p: int) -> void:
	var player := s.commanders.player[row]
	var f := s.features
	for fr in s.features_at(p):
		if s.rules.hf_controllable[f.tmpl[fr]] == 1 and f.owner[fr] != player:
			var fid := f.id_at(fr)
			s.events.push(&"feature_captured", {"feature": fid, "plot": p, "player": player, "from": f.owner[fr]}, s.tick)
			f.set_value(fid, &"owner", player)


## Ends an engagement (its battle is over): commanders on it are free again.
static func end_engagement(s: OverworldState, eid: int) -> void:
	var c := s.commanders
	for row in c.count():
		if c.engagement[row] == eid:
			c.set_value(c.id_at(row), &"engagement", -1)
	if s.engagements.despawn(eid):
		s.events.push(&"engagement_ended", {"engagement": eid}, s.tick)
