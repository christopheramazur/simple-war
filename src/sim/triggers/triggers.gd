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
			for a: Dictionary in trg["do"]:
				_act(state, a, trg["id"], e.data)


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
		"zone_owner":
			var b := state as BattleState
			var owner := b.zone_owner[b.rules.zone_ids.find(String(c["zone"]))]
			return owner == int(_v(c, "player", 0, data)) if c.has("player") else owner > 0
		"zone_locked":
			var b := state as BattleState
			return b.zone_locked[b.rules.zone_ids.find(String(c["zone"]))] == 1
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
		"unlock_zone", "lock_zone":
			var b := state as BattleState
			var z := b.rules.zone_ids.find(String(a["zone"]))
			b.zone_locked[z] = 1 if a["do"] == "lock_zone" else 0
			b.events.push(&"zone_unlocked" if a["do"] == "unlock_zone" else &"zone_locked",
				{"zone": String(a["zone"]), "player": 0, "rule": tid}, b.tick)
		"end_battle":
			var b := state as BattleState
			if not b.is_over():
				TurnResolution._finish(b, int(_v(a, "winner", 0, data)), String(a.get("reason", "scripted")))


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
