class_name Triggers
extends RefCounted
## Runs compiled triggers (TriggerRules) against one step's events, for the
## overworld (end of OverworldTurn.resolve) or a battle (end of
## BattleSim.execute_turn). Deterministic: events in order, triggers in ID
## order per event, actions in order. Variables and fire counts live in the
## state (`vars`, `fired`), so they are saved, hashed and replayed.

## Runs compiled triggers (TriggerRules.triggers / by_event) over `events`
## (SimEvents of this step) plus "turn_resolved". Called through
## TriggerRules.run.
static func fire(state: SimContext, triggers: Array[Dictionary], by_event: Dictionary, events: Array, turn_end: bool = true) -> void:
	var list := events.duplicate()
	if turn_end:
		list.append(SimEvent.new(&"turn_resolved", {"turn": state.get("turn")}))
	for e: SimEvent in list:
		for i: int in by_event.get(e.type, []):
			var trg: Dictionary = triggers[i]
			var fired: Dictionary = state.get("fired")
			var n: int = fired.get(trg["id"], 0)
			if trg["max"] > 0 and n >= trg["max"]:
				continue
			if not _where(state, trg["where"], e.data) or not _all(state, trg["if"], e.data):
				continue
			fired[trg["id"]] = n + 1
			if trg["after"] > 0:
				var vars: Dictionary = state.get("vars")
				vars["%s%s.%d" % [DUE, trg["id"], n]] = int(state.get("turn")) + trg["after"]
				continue
			for a: Dictionary in trg["do"]:
				_act(state, a, trg["id"], e.data)
	if turn_end:
		_run_due(state, triggers)


## Variable prefix of a delayed run: "~due.<trigger>.<fire number>" = the turn
## it runs on (at that turn's end).
const DUE := "~due."


static func _run_due(state: SimContext, triggers: Array[Dictionary]) -> void:
	var vars: Dictionary = state.get("vars")
	var keys: Array = vars.keys().filter(func(k: String) -> bool: return k.begins_with(DUE))
	keys.sort()
	for k: String in keys:
		if int(vars[k]) > int(state.get("turn")):
			continue
		vars.erase(k)
		var tid := k.substr(DUE.length()).rsplit(".", true, 1)[0]
		for trg: Dictionary in triggers:
			if trg["id"] == tid:
				for a: Dictionary in trg["do"]:
					_act(state, a, tid, {})


static func _where(state: SimContext, where: Dictionary, data: Dictionary) -> bool:
	for k: String in where:
		if k == "col" or k == "row":
			continue
		if not data.has(k) or not _matches(data[k], where[k]):
			return false
	if where.has("col") and where.has("row") and state is OverworldState:
		var s := state as OverworldState
		if int(data.get("plot", -1)) != Hex.plot(int(where["col"]), int(where["row"]), s.rules.width):
			return false
	return true


static func _matches(value: Variant, expected: Variant) -> bool:
	if expected is Array:
		for x: Variant in expected:
			if str(value) == str(x):
				return true
		return false
	return str(value) == str(expected)


## A field of a check or action: a "$<key>" string reads the triggering
## event's data (e.g. "player": "$player").
static func _v(d: Dictionary, key: String, default: Variant, data: Dictionary) -> Variant:
	var v: Variant = d.get(key, default)
	if v is String and (v as String).begins_with("$"):
		return data.get((v as String).substr(1), default)
	return v


static func _plot(s: OverworldState, d: Dictionary, data: Dictionary) -> int:
	if d.has("plot"):
		return int(_v(d, "plot", -1, data))
	return Hex.plot(int(_v(d, "col", 0, data)), int(_v(d, "row", 0, data)), s.rules.width)


## The commander a gift goes to: "target" (an ID or "$field"), else the
## first commander of "player" on the plot.
static func _target(s: OverworldState, a: Dictionary, data: Dictionary) -> int:
	if a.has("target"):
		var cid := int(_v(a, "target", -1, data))
		return cid if s.commanders.row_of(cid) >= 0 else -1
	var player := int(_v(a, "player", 1, data))
	for cid in Commanders.at(s, _plot(s, a, data)):
		if s.commanders.get_value(cid, &"player") == player:
			return cid
	return -1


static func _all(state: SimContext, checks: Array, data: Dictionary) -> bool:
	for c: Dictionary in checks:
		if _check(state, c, data) == bool(c.get("not", false)):
			return false
	return true


static func _cmp(a: int, c: Dictionary, data: Dictionary = {}) -> bool:
	var b := int(_v(c, "value", 1, data))
	match String(c.get("op", ">=")):
		"==":
			return a == b
		"!=":
			return a != b
		"<":
			return a < b
		"<=":
			return a <= b
		">":
			return a > b
	return a >= b


static func _check(state: SimContext, c: Dictionary, data: Dictionary) -> bool:
	match String(c["check"]):
		"var":
			return _cmp(int((state.get("vars") as Dictionary).get(String(c.get("name", "")), 0)), c, data)
		"turn":
			return _cmp(int(state.get("turn")), c, data)
		"fired":
			return _cmp(int((state.get("fired") as Dictionary).get(String(c.get("trigger", "")), 0)), c, data)
		"any":
			for sub: Dictionary in c.get("of", []):
				if _check(state, sub, data) != bool(sub.get("not", false)):
					return true
			return false
		"value":
			return _cmp((state as OverworldState).value_of(int(_v(c, "player", 1, data))), c, data)
		"owns":
			var s := state as OverworldState
			var t := s.rules.feature_index(String(c["feature"]))
			var n := 0
			for row in s.features.count():
				if s.features.tmpl[row] == t and s.features.owner[row] == int(_v(c, "player", 1, data)):
					n += 1
			return _cmp(n, c, data)
		"feature_at":
			var s := state as OverworldState
			return s.feature_row(_plot(s, c, data), s.rules.feature_index(String(c["feature"]))) >= 0
		"commander_at":
			var s := state as OverworldState
			var p := _plot(s, c, data)
			var n := 0
			for cid in Commanders.at(s, p):
				var row := s.commanders.row_of(cid)
				if c.has("player") and s.commanders.player[row] != int(_v(c, "player", 1, data)):
					continue
				if c.has("commander") and s.commanders.tmpl[row] != s.rules.commander_index(String(c["commander"])):
					continue
				n += 1
			return _cmp(n, c, data)
		"zone_owner":
			var b := state as BattleState
			var owner := b.zone_owner[b.rules.zone_ids.find(String(c["zone"]))]
			return owner == int(_v(c, "player", 0, data)) if c.has("player") else owner > 0
		"zone_locked":
			var b := state as BattleState
			return b.zone_locked[b.rules.zone_ids.find(String(c["zone"]))] == 1
		"squad_alive":
			var b := state as BattleState
			return _cmp(_squad_rows(b, String(c["squad"]), int(_v(c, "player", 0, data))).size(), c, data)
		"strength":
			var b := state as BattleState
			var n := 0
			for row in b.squads.count():
				if b.squads.is_active(row) and b.squads.player[row] == int(_v(c, "player", 1, data)):
					n += b.squads.alive[row]
			return _cmp(n, c, data)
		"squads_in_zone":
			var b := state as BattleState
			var z := b.rules.zone_ids.find(String(c["zone"]))
			var r2 := b.rules.zn_radius[z]
			var want := String(c.get("squad", ""))
			var n := 0
			for row in b.squads.count():
				if not b.squads.is_active(row) or b.squads.alive[row] == 0:
					continue
				if c.has("player") and b.squads.player[row] != int(_v(c, "player", 0, data)):
					continue
				if not want.is_empty() and b.rules.squad_ids[b.squads.tmpl[row]] != want:
					continue
				var dx := (b.squads.cx[row] - b.rules.zn_x[z]) / Fixed.ONE
				var dy := (b.squads.cy[row] - b.rules.zn_y[z]) / Fixed.ONE
				var r := r2 / Fixed.ONE
				if dx * dx + dy * dy <= r * r:
					n += 1
			return _cmp(n, c, data)
	return false


static func _act(state: SimContext, a: Dictionary, tid: String, data: Dictionary) -> void:
	var vars: Dictionary = state.get("vars")
	match String(a["do"]):
		"set_var":
			vars[String(a["name"])] = int(_v(a, "value", 0, data))
		"add_var":
			vars[String(a["name"])] = int(vars.get(String(a["name"]), 0)) + int(_v(a, "value", 1, data))
		"message":
			_message(state, a, tid, data)
		"start_dialogue":
			var d := {"rule": tid, "dialogue": String(a["dialogue"]), "player": int(_v(a, "player", 0, data))}
			state.events.push(&"dialogue_started", d, state.tick)
		"add_value":
			(state as OverworldState).add_value(int(_v(a, "player", 1, data)), int(_v(a, "amount", 0, data)), &"trigger")
		"add_feature":
			var s := state as OverworldState
			var p := _plot(s, a, data)
			var t := s.rules.feature_index(String(a["feature"]))
			var fid := s.add_feature(p, t, int(_v(a, "owner", 0, data)))
			s.events.push(&"feature_added", {"plot": p, "feature": fid, "tmpl": t, "rule": tid}, s.tick)
		"remove_feature":
			var s := state as OverworldState
			var p := _plot(s, a, data)
			var t := s.rules.feature_index(String(a["feature"]))
			var row := s.feature_row(p, t)
			if row >= 0:
				var fid := s.features.id_at(row)
				s.remove_feature(fid)
				s.events.push(&"feature_removed", {"plot": p, "feature": fid, "tmpl": t, "rule": tid}, s.tick)
		"end_mission":
			var s := state as OverworldState
			if s.outcome.is_empty():
				s.outcome = {"outcome": String(a["outcome"]), "key": String(a.get("key", "")),
					"text": String(a.get("text", "")), "turn": s.turn}
				s.events.push(&"mission_ended", s.outcome.duplicate(), s.tick)
		"spawn_commander":
			var s := state as OverworldState
			var p := _plot(s, a, data)
			var player := int(_v(a, "player", 1, data))
			var t := s.rules.commander_index(String(a["commander"]))
			var cid := Commanders.spawn_index(s, player, t, p)
			s.events.push(&"commander_spawned", {"commander": cid, "tmpl": t, "plot": p, "player": player, "rule": tid}, s.tick)
		"give_squad":
			var s := state as OverworldState
			var cid := _target(s, a, data)
			if cid >= 0 and OverworldArmies.count(s, cid) < OverworldArmies.cap(s, cid):
				var sq := s.rules.squad_index(String(a["squad"]))
				var sid := OverworldArmies.add(s, cid, sq)
				s.events.push(&"squad_given", {"commander": cid, "squad": sid, "tmpl": sq,
					"player": s.commanders.get_value(cid, &"player"), "rule": tid}, s.tick)
		"give_item":
			var s := state as OverworldState
			var cid := _target(s, a, data)
			if cid >= 0:
				var t := s.rules.item_index(String(a["item"]))
				var n := int(_v(a, "count", 1, data))
				WarChest.add(s, t, n, cid, -1, -1)
				s.events.push(&"item_granted", {"commander": cid, "item": t, "count": n,
					"player": s.commanders.get_value(cid, &"player"), "rule": tid}, s.tick)
		"start_engagement":
			var s := state as OverworldState
			var p := _plot(s, a, data)
			var eid := s.engagement_at(p)
			if eid < 0:
				eid = s.engagements.spawn({&"plot": p, &"kinds": OverworldEngagements.COMMANDERS, &"turn": s.turn})
				s.events.push(&"engagement_started", {"engagement": eid, "plot": p, "kinds": OverworldEngagements.COMMANDERS, "rule": tid}, s.tick)
			for other in Commanders.at(s, p):
				if s.commanders.get_value(other, &"engagement") == eid:
					continue
				s.commanders.set_value(other, &"engagement", eid)
				s.events.push(&"commander_engaged", {"commander": other, "engagement": eid, "plot": p}, s.tick)
				OverworldBattleforce.deploy(s, other, eid)
		"apply_bundle":
			var b := state as BattleState
			var bi := b.rules.fx.index_of(String(a["bundle"]))
			var player := int(_v(a, "player", 0, data))
			var st := b.rules.squad_index(String(a["squad"])) if a.has("squad") else -1
			for row in b.squads.count():
				if not b.squads.is_active(row) or b.squads.alive[row] <= 0:
					continue
				if (player > 0 and b.squads.player[row] != player) or (st >= 0 and b.squads.tmpl[row] != st):
					continue
				Effects.apply(b, bi, b.squads.id_at(row), -1, -1)
		"reveal_area":
			var b := state as BattleState
			var turns := int(_v(a, "turns", 1, data))
			b.reveals.append([int(_v(a, "player", 1, data)), Fixed.from_int(int(_v(a, "x", 0, data))),
				Fixed.from_int(int(_v(a, "y", 0, data))), Fixed.from_int(int(_v(a, "radius", 10, data))),
				-1 if turns <= 0 else b.turn + turns])
		"unlock_zone", "lock_zone":
			var b := state as BattleState
			var z := b.rules.zone_ids.find(String(a["zone"]))
			b.zone_locked[z] = 1 if a["do"] == "lock_zone" else 0
			b.events.push(&"zone_unlocked" if a["do"] == "unlock_zone" else &"zone_locked",
				{"zone": String(a["zone"]), "player": 0, "rule": tid}, b.tick)
		"spawn_squad":
			var b := state as BattleState
			var st := b.rules.squad_index(String(a["squad"]))
			var p := int(_v(a, "player", 1, data))
			var ax := 0
			var ay := 0
			var facing := 0
			for side in b.rules.sides:
				if side["player"] == p:
					var d: PackedInt64Array = side["deploy"]
					ax = d[0] + d[2] / 2
					ay = d[1] + d[3] / 2
					facing = side["facing"]
			if a.has("x") and a.has("y"):
				ax = Fixed.from_int(int(_v(a, "x", 0, data)))
				ay = Fixed.from_int(int(_v(a, "y", 0, data)))
			var sid := BattleSetup.spawn_squad(b, p, st, ax, ay, facing)
			Centroids.update(b)
			b.events.push(&"squad_spawned", {"squad": sid, "tmpl": st, "player": p, "rule": tid}, b.tick)
		"remove_squad":
			var b := state as BattleState
			for row in _squad_rows(b, String(a["squad"]), int(_v(a, "player", 0, data))):
				var sid := b.squads.id_at(row)
				var col: PackedByteArray = b.squads.take_column(&"withdrawn")
				col[row] = 1
				b.squads.put_column(&"withdrawn", col)
				b.events.push(&"squad_removed", {"squad": sid, "player": b.squads.player[row], "rule": tid}, b.tick)
		"order_squad":
			var b := state as BattleState
			for row in _squad_rows(b, String(a["squad"]), int(_v(a, "player", 0, data))):
				var o := {"squad": b.squads.id_at(row), "type": String(a.get("type", "hold")), "run": bool(a.get("run", false))}
				if a.has("x"):
					o["x"] = Fixed.from_int(int(_v(a, "x", 0, data)))
					o["y"] = Fixed.from_int(int(_v(a, "y", 0, data)))
				if BattleOrders.validate(b, b.squads.player[row], o).is_empty():
					BattleOrders._apply_one(b, o)
		"add_score":
			var b := state as BattleState
			var p := int(_v(a, "player", 1, data))
			var amount := int(_v(a, "amount", 0, data))
			if b.players.has(p):
				if String(a.get("score", "value")) == "influence":
					b.influence[p] = int(b.influence[p]) + amount
				else:
					b.value_score[p] = int(b.value_score[p]) + amount
		"set_owner":
			var s := state as OverworldState
			var p := _plot(s, a, data)
			var row := s.feature_row(p, s.rules.feature_index(String(a["feature"])))
			if row >= 0:
				s.features.set_value(s.features.id_at(row), &"owner", int(_v(a, "owner", 0, data)))
		"end_battle":
			var b := state as BattleState
			if not b.is_over():
				TurnResolution._finish(b, int(_v(a, "winner", 0, data)), String(a.get("reason", "scripted")))


## Rows of living squads of template `tid` (a player of 0 = any side).
static func _squad_rows(b: BattleState, tid: String, player: int) -> Array[int]:
	var st := b.rules.squad_index(tid)
	var rows: Array[int] = []
	for row in b.squads.count():
		if b.squads.tmpl[row] == st and b.squads.is_active(row) and (player == 0 or b.squads.player[row] == player):
			rows.append(row)
	return rows


## A message for one player, or every player (0). Overworld messages carry
## "player" (fog filters by it); battle ones carry "to".
static func _message(state: SimContext, a: Dictionary, tid: String, data_in: Dictionary) -> void:
	var to := int(_v(a, "player", 0, data_in))
	var data := {"rule": tid, "key": String(a.get("key", "")), "text": String(a.get("text", ""))}
	if state is OverworldState:
		var s := state as OverworldState
		var players: PackedInt64Array = s.rules.players() if to == 0 else PackedInt64Array([to])
		for p in players:
			var d := data.duplicate()
			d["player"] = p
			s.events.push(&"trigger_message", d, s.tick)
	else:
		data["to"] = to
		state.events.push(&"trigger_message", data, state.tick)
