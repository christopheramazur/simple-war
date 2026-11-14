class_name ScriptedProcess
extends RefCounted
## A scripted decision process (R7Q15): fixed orders by turn, for tests,
## tutorials and set-piece opponents. Params: {"steps": [...]}, a step
## applying on the turn its "turn" names (the observation's turn: overworld
## turns count from 0, battle turns from 1).
##   Overworld step: {"turn", "commander" (index among own commanders by
##     ID), "to": [col, row], "activity" and "option" (optional)}.
##   Battle step: {"turn", "squad" (index among own active squads by ID),
##     "type" (an order type), "x", "y" (observation units), "run"}.
## Steps naming a commander or squad that no longer exists are skipped.
## With a successor (`then`, built by ProfileController from params.then),
## turns after the last step are the successor's (a scripted opening).

var player: int
var steps: Array = []
var then: Object
var last_turn := -1


func _init(player_id: int, params: Dictionary = {}) -> void:
	player = player_id
	steps = params.get("steps", [])
	for st: Dictionary in steps:
		last_turn = maxi(last_turn, int(st.get("turn", -1)))


func _own(list: Array, active: bool) -> Array:
	var out := []
	for e: Dictionary in list:
		if int(e["player"]) != player:
			continue
		if active and (bool(e.get("destroyed", false)) or bool(e.get("withdrawn", false))):
			continue
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


func plan(obs: Dictionary, session: OverworldSession) -> Array:
	if then != null and int(obs["turn"]) > last_turn:
		return then.plan(obs, session)
	var mine := _own(obs["commanders"], false)
	var out := []
	for st: Dictionary in steps:
		var i := int(st.get("commander", 0))
		if int(st.get("turn", -1)) != int(obs["turn"]) or i >= mine.size():
			continue
		var c: Dictionary = mine[i]
		var to: Array = st.get("to", [])
		var route := PackedInt64Array()
		if to.size() == 2:
			route = session.path(player, int(c["id"]), Hex.plot(int(to[0]), int(to[1]), int(obs["width"])))
		var o := {"commander": c["id"], "route": route}
		if st.has("activity"):
			o["activity"] = String(st["activity"])
			o["option"] = String(st.get("option", ""))
		out.append(o)
	return out


func orders(obs: Dictionary) -> Array:
	if then != null and int(obs["turn"]) > last_turn:
		return then.orders(obs)
	var mine := _own(obs["squads"], true)
	var out := []
	for st: Dictionary in steps:
		var i := int(st.get("squad", 0))
		if int(st.get("turn", -1)) != int(obs["turn"]) or i >= mine.size():
			continue
		var o := {"squad": mine[i]["id"], "type": String(st.get("type", "hold"))}
		for k in ["x", "y", "run"]:
			if st.has(k):
				o[k] = st[k]
		out.append(o)
	return out


func reactions(opportunities: Array) -> Array:
	if then != null and then.has_method("reactions"):
		return then.reactions(opportunities)
	return []
