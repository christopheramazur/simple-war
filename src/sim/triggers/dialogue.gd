class_name Dialogue
extends RefCounted
## The dialogue data model (GDD 03 §3.5, 04 §4.9, R3Q18). Dialogic is
## presentation only: a dialogue is data, and what it changes (dispositions,
## relationships) lives in the sim as state variables, saved, hashed and
## replayed with the rest. By convention a disposition is the variable
## "disp.<speaker>" (or "rel.<a>.<b>"), moved with add_var / set_var.
##
## A `dialogue` template: `start` (a node ID), `nodes` {id: node}. A node:
##   speaker:  who talks (free text id; the portrait / name in presentation)
##   key/text: translation key with English fallback
##   do:       state actions run on entering (set_var, add_var)
##   choices:  [{key, text, next, if: [trigger checks], do: [set_var, add_var]}]
##   next:     the node after a node without choices ("" or absent = ends)
## A trigger's `start_dialogue` action ({dialogue, player}) pushes a
## `dialogue_started` event; the presentation then walks the graph with
## `enter` and `choose`.

const ACTIONS: Array[String] = ["set_var", "add_var"]
const NODE_KEYS: Array[String] = ["speaker", "key", "text", "do", "choices", "next"]
const CHOICE_KEYS: Array[String] = ["key", "text", "next", "if", "do"]


## Problems of a dialogue's values (its node graph), as strings.
static func problems(values: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var nodes: Dictionary = values.get("nodes", {})
	if nodes.is_empty():
		errs.append("has no nodes")
		return errs
	var start := String(values.get("start", ""))
	if not nodes.has(start):
		errs.append("start '%s' is not a node" % start)
	for nid: String in nodes:
		var n: Variant = nodes[nid]
		if not n is Dictionary:
			errs.append("node '%s' is not an object" % nid)
			continue
		var node: Dictionary = n
		for k: String in node:
			if not k in NODE_KEYS:
				errs.append("node '%s': unknown field '%s'" % [nid, k])
		_actions(node.get("do", []), "node '%s'" % nid, errs)
		if String(node.get("next", "")) != "" and not nodes.has(String(node["next"])):
			errs.append("node '%s': next '%s' is not a node" % [nid, node["next"]])
		if node.has("choices") and node.has("next"):
			errs.append("node '%s': has both choices and next" % nid)
		var i := 0
		for c: Variant in node.get("choices", []):
			var where := "node '%s' choice %d" % [nid, i]
			i += 1
			if not c is Dictionary:
				errs.append("%s is not an object" % where)
				continue
			for k: String in c:
				if not k in CHOICE_KEYS:
					errs.append("%s: unknown field '%s'" % [where, k])
			if String(c.get("next", "")) != "" and not nodes.has(String(c["next"])):
				errs.append("%s: next '%s' is not a node" % [where, c["next"]])
			_actions(c.get("do", []), where, errs)
			for chk: Variant in c.get("if", []):
				if not chk is Dictionary or String(chk.get("check", "")) not in ["var", "turn", "fired"]:
					errs.append("%s: only var, turn and fired checks are allowed" % where)
	return errs


static func _actions(list: Variant, where: String, errs: PackedStringArray) -> void:
	if not list is Array:
		errs.append("%s: do is not a list" % where)
		return
	for a: Variant in list:
		if not a is Dictionary or String(a.get("do", "")) not in ACTIONS or String(a.get("name", "")).is_empty():
			errs.append("%s: dialogue actions are set_var or add_var with a name" % where)


## The node IDs a node leads to, in order.
static func successors(node: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if node.has("choices"):
		for c: Dictionary in node["choices"]:
			if String(c.get("next", "")) != "":
				out.append(String(c["next"]))
	elif String(node.get("next", "")) != "":
		out.append(String(node["next"]))
	return out


## Enters a node: runs its `do` on the state. Returns the node.
static func enter(state: SimContext, values: Dictionary, node_id: String) -> Dictionary:
	var node: Dictionary = values["nodes"][node_id]
	for a: Dictionary in node.get("do", []):
		Triggers._act(state, a, "dialogue", {})
	return node


## The indices of a node's choices whose checks hold.
static func available(state: SimContext, values: Dictionary, node_id: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var choices: Array = values["nodes"][node_id].get("choices", [])
	for i in choices.size():
		if Triggers._all(state, (choices[i] as Dictionary).get("if", []), {}):
			out.append(i)
	return out


## Picks a choice: runs its `do` and returns the next node ID ("" ends).
## An unavailable or unknown choice returns "" and changes nothing.
static func choose(state: SimContext, values: Dictionary, node_id: String, index: int) -> String:
	if not index in available(state, values, node_id):
		return ""
	var c: Dictionary = values["nodes"][node_id]["choices"][index]
	for a: Dictionary in c.get("do", []):
		Triggers._act(state, a, "dialogue", {})
	return String(c.get("next", ""))
