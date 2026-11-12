class_name OverworldBattleforce
extends RefCounted
## Battleforces (GDD 02 §2.3, R2Q1): the share of an army that fights in a
## battle, within the map's caps (most squads; most total strength).
##   - Strength: a squad's Value scaled by its units alive.
##   - The commander's own squad leads the battleforce unless the plan says
##     it stays out (a drop-off, sw-o1m.2.4); it counts toward the caps.
##   - Auto-fill: the strongest squads first, adding each that still fits
##     ("strongest until the cap"). A preset ranks squads first by the first
##     of its `prefer` features they have, and never picks `avoid` ones.
##   - Presets: the map data's archetype presets, plus the player's own,
##     saved by name in the state and kept with the game (they win a name
##     clash).
##   - A plan may list squads by hand instead; listed squads still have to
##     fit the caps.
## Plans live on OverworldState.battleforces and persist across turns. When
## a commander is pulled into an engagement, its battleforce is picked from
## the plan and its squads are marked deployed there.


## A squad's Value scaled by units alive (integer).
static func strength(s: OverworldState, row: int) -> int:
	var q := s.squads
	if q.size[row] <= 0:
		return 0
	return s.rules.sq_value[q.tmpl[row]] * q.alive[row] / q.size[row]


## The commander's plan: {"preset": String ("" = strongest), "squads":
## PackedInt64Array (empty = auto-fill), "lead": bool}.
static func plan_of(s: OverworldState, cid: int) -> Dictionary:
	return s.battleforces.get(cid, {"preset": "", "squads": PackedInt64Array(), "lead": true})


## {"prefer", "avoid"} for a preset name as `player` sees it, or {} if
## unknown. "" is plain strongest-first.
static func preset(s: OverworldState, player: int, name: String) -> Dictionary:
	if name.is_empty():
		return {"prefer": PackedStringArray(), "avoid": PackedStringArray()}
	var own: Dictionary = s.presets.get(player, {})
	if own.has(name):
		return own[name]
	var i := s.rules.preset_ids.find(name)
	if i < 0:
		return {}
	return {"prefer": s.rules.pr_prefer[i], "avoid": s.rules.pr_avoid[i]}


## The squads that would fight if the commander were engaged now, in order.
static func pick(s: OverworldState, cid: int) -> PackedInt64Array:
	var q := s.squads
	var r := s.rules
	var c := s.commanders
	var plan := plan_of(s, cid)
	var player := c.player[c.row_of(cid)]
	var out := PackedInt64Array()
	var total := 0
	var free := []
	for id in OverworldArmies.of(s, cid):
		var row := q.row_of(id)
		if q.alive[row] <= 0 or q.deployed[row] >= 0:
			continue
		if q.own[row] == 1:
			if plan["lead"]:
				out.append(id)
				total += strength(s, row)
			continue
		free.append(id)
	var chosen: PackedInt64Array = plan["squads"]
	if chosen.is_empty():
		var pre := preset(s, player, plan["preset"])
		if pre.is_empty():
			pre = preset(s, player, "")
		var keyed := []
		for id: int in free:
			var row := q.row_of(id)
			var tags := r.sq_tags[q.tmpl[row]]
			if _any(tags, pre["avoid"]):
				continue
			var rank: int = (pre["prefer"] as PackedStringArray).size()
			for i in (pre["prefer"] as PackedStringArray).size():
				if tags.has(pre["prefer"][i]):
					rank = i
					break
			keyed.append([rank, -strength(s, row), id])
		keyed.sort_custom(func(a: Array, b: Array) -> bool:
			if a[0] != b[0]:
				return a[0] < b[0]
			if a[1] != b[1]:
				return a[1] < b[1]
			return a[2] < b[2])
		chosen = PackedInt64Array()
		for k: Array in keyed:
			chosen.append(k[2])
	for id in chosen:
		if not free.has(id) or out.size() >= r.bf_cap_squads:
			continue
		var st := strength(s, q.row_of(id))
		if r.bf_cap_value > 0 and total + st > r.bf_cap_value:
			continue
		out.append(id)
		total += st
	return out


static func _any(tags: PackedStringArray, of: PackedStringArray) -> bool:
	for t in of:
		if tags.has(t):
			return true
	return false


## Sets a commander's battleforce plan (planning). `squads` empty = auto-fill
## with `preset`. Returns "" or why it was refused.
static func set_plan(s: OverworldState, player: int, cid: int, preset_name: String, squads: PackedInt64Array, lead: bool) -> String:
	var c := s.commanders
	var row := c.row_of(cid)
	if row < 0:
		return "no such commander"
	if c.player[row] != player:
		return "not your commander"
	if preset(s, player, preset_name).is_empty():
		return "unknown preset '%s'" % preset_name
	var q := s.squads
	var total := 0
	var count := 0
	if lead:
		for id in OverworldArmies.of(s, cid):
			if q.own[q.row_of(id)] == 1:
				total += strength(s, q.row_of(id))
				count += 1
	for i in squads.size():
		var srow := q.row_of(squads[i])
		if srow < 0 or q.holder[srow] != cid:
			return "squad %d is not in this army" % (i + 1)
		if q.own[srow] == 1:
			return "the commander's own squad is set by 'lead'"
		if squads.find(squads[i]) != i:
			return "squad %d is listed twice" % (i + 1)
		total += strength(s, srow)
		count += 1
	if count > s.rules.bf_cap_squads:
		return "the battleforce cap is %d squads" % s.rules.bf_cap_squads
	if s.rules.bf_cap_value > 0 and total > s.rules.bf_cap_value:
		return "the battleforce cap is %d strength, these have %d" % [s.rules.bf_cap_value, total]
	s.battleforces[cid] = {"preset": preset_name, "squads": squads.duplicate(), "lead": lead}
	return ""


## Saves (or replaces) one of the player's own presets. "" or why not.
static func save_preset(s: OverworldState, player: int, name: String, prefer: PackedStringArray, avoid: PackedStringArray) -> String:
	if name.is_empty():
		return "a preset needs a name"
	var own: Dictionary = s.presets.get(player, {})
	own[name] = {"prefer": prefer.duplicate(), "avoid": avoid.duplicate()}
	s.presets[player] = own
	return ""


## Marks the commander's battleforce deployed in engagement eid.
static func deploy(s: OverworldState, cid: int, eid: int) -> void:
	var ids := pick(s, cid)
	for id in ids:
		s.squads.set_value(id, &"deployed", eid)
	var c := s.commanders
	s.events.push(&"battleforce_deployed", {"commander": cid, "engagement": eid,
		"player": c.player[c.row_of(cid)], "squads": ids}, s.tick)


## The commander's battleforce: the squads deployed in its battle, or
## those that would be if it were engaged now.
static func of(s: OverworldState, cid: int) -> PackedInt64Array:
	var eid := s.commanders.get_value(cid, &"engagement")
	if eid < 0:
		return pick(s, cid)
	var out := PackedInt64Array()
	for id in OverworldArmies.of(s, cid):
		if s.squads.get_value(id, &"deployed") == eid:
			out.append(id)
	return out


## Squads deployed in engagement eid return to their armies.
static func release(s: OverworldState, eid: int) -> void:
	var q := s.squads
	for row in q.count():
		if q.deployed[row] == eid:
			q.set_value(q.id_at(row), &"deployed", -1)


## Squad IDs deployed in engagement eid, by holder then ID.
static func deployed_in(s: OverworldState, eid: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for row in s.squads.count():
		if s.squads.deployed[row] == eid:
			out.append(s.squads.id_at(row))
	out.sort()
	return out
