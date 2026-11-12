class_name TriggerGraph
extends RefCounted
## The trigger graph of one overworld map or scenario (GDD 04 §4.9, 03
## §3.5), as the data editor draws it with custom_graph_editor. Nodes: the
## events triggers listen to, the triggers, and what they read and write
## (variables, zones, features); links run the way influence flows:
##   event -> trigger ("on"), trigger -> var / zone / feature (an action
##   writes it), var / zone / feature -> trigger (a check reads it), and
##   trigger -> trigger (a "fired" check).
## `build` returns the graph editor's serialize() shape, laid out in
## columns (events, triggers, state), so it can be loaded directly.

const KINDS: Array[String] = ["event", "trigger", "var", "zone", "feature"]
const COLUMN_X: Dictionary = {"event": 0.0, "trigger": 260.0, "var": 560.0, "zone": 560.0, "feature": 560.0}
const ROW_H: float = 80.0


## {"nodes": {id: {"id", "kind", "name", "position": {x, y}}}, "links":
## {id: {"id", "start_node_id", "end_node_id", "label"}}, "errors"}.
static func build(t: TemplateTable, owner: String) -> Dictionary:
	var errors := PackedStringArray()
	var out := {"nodes": {}, "links": {}, "errors": errors}
	if not t.has(owner) or not (t.kind_of(owner) in ["overworld_map", "scenario"]):
		errors.append("'%s' is not a map or scenario" % owner)
		out["errors"] = errors
		return out
	var ids := PackedStringArray(t.values_of(owner).get("triggers", []))
	ids.sort()
	var keys := {}  # "kind:name" -> node id
	var links := []  # [from key, to key, label]
	for tid in ids:
		if not t.has(tid):
			errors.append("unknown trigger '%s'" % tid)
			out["errors"] = errors
			continue
		var v := t.values_of(tid)
		_node(keys, "trigger", tid)
		_node(keys, "event", String(v["on"]))
		links.append(["event:" + String(v["on"]), "trigger:" + tid, "on"])
		for c: Dictionary in _checks(v.get("if", [])):
			match String(c.get("check", "")):
				"var":
					_node(keys, "var", String(c.get("name", "")))
					links.append(["var:" + String(c.get("name", "")), "trigger:" + tid, "checks"])
				"zone_owner", "zone_locked":
					_node(keys, "zone", String(c.get("zone", "")))
					links.append(["zone:" + String(c.get("zone", "")), "trigger:" + tid, "checks"])
				"owns", "feature_at":
					_node(keys, "feature", String(c.get("feature", "")))
					links.append(["feature:" + String(c.get("feature", "")), "trigger:" + tid, "checks"])
				"fired":
					_node(keys, "trigger", String(c.get("trigger", "")))
					links.append(["trigger:" + String(c.get("trigger", "")), "trigger:" + tid, "fired"])
		for a: Dictionary in v.get("do", []):
			var verb := String(a.get("do", ""))
			match verb:
				"set_var", "add_var":
					_node(keys, "var", String(a.get("name", "")))
					links.append(["trigger:" + tid, "var:" + String(a.get("name", "")), verb])
				"unlock_zone", "lock_zone":
					_node(keys, "zone", String(a.get("zone", "")))
					links.append(["trigger:" + tid, "zone:" + String(a.get("zone", "")), verb])
				"add_feature", "remove_feature":
					_node(keys, "feature", String(a.get("feature", "")))
					links.append(["trigger:" + tid, "feature:" + String(a.get("feature", "")), verb])
	# Lay out: one column per kind group, rows by name.
	var rows := {}
	var sorted_keys: Array = keys.keys()
	sorted_keys.sort()
	for key: String in sorted_keys:
		var kind := key.get_slice(":", 0)
		var col := COLUMN_X[kind] as float
		var r: int = rows.get(col, 0)
		rows[col] = r + 1
		var nid: int = keys[key]
		out["nodes"][nid] = {"id": nid, "kind": kind, "name": key.substr(kind.length() + 1),
			"position": {"x": col, "y": r * ROW_H}}
	var seen := {}
	var lid := 0
	for l: Array in links:
		var k := "%s>%s>%s" % l
		if seen.has(k):
			continue
		seen[k] = true
		out["links"][lid] = {"id": lid, "start_node_id": keys[l[0]], "end_node_id": keys[l[1]], "label": l[2]}
		lid += 1
	return out


## The node ID for "kind:name" in a built graph, or -1.
static func node_id(graph: Dictionary, kind: String, name: String) -> int:
	for nid: int in graph["nodes"]:
		var n: Dictionary = graph["nodes"][nid]
		if n["kind"] == kind and n["name"] == name:
			return nid
	return -1


static func _node(keys: Dictionary, kind: String, name: String) -> void:
	var key := "%s:%s" % [kind, name]
	if not keys.has(key):
		keys[key] = keys.size()


## Checks with "any" groups flattened.
static func _checks(list: Array) -> Array:
	var out := []
	for c: Dictionary in list:
		if String(c.get("check", "")) == "any":
			out.append_array(_checks(c.get("of", [])))
		else:
			out.append(c)
	return out
