class_name DialogueGraph
extends RefCounted
## One dialogue (Dialogue, GDD 04 §4.9) as the graph editor draws it: a node
## per dialogue node (kind "line", "choice" for a node with choices, or "end"
## for a leaf), plus "var" nodes for the variables (dispositions) its effects
## write and its choices read. Links: node -> node (label "next" or the
## choice's text), node -> var (the write verb), var -> node ("checks").
## `build` returns the editor's serialize() shape, laid out by depth.

const COLUMN_W: float = 260.0
const ROW_H: float = 80.0


static func build(t: TemplateTable, id: String) -> Dictionary:
	var errors := PackedStringArray()
	var out := {"nodes": {}, "links": {}, "errors": errors}
	if not t.has(id) or t.kind_of(id) != "dialogue":
		errors.append("'%s' is not a dialogue" % id)
		return out
	var v := t.values_of(id)
	errors.append_array(Dialogue.problems(v))
	var nodes: Dictionary = v.get("nodes", {})
	if not nodes.has(String(v.get("start", ""))):
		return out
	# Depth by breadth-first walk from the start; unreachable nodes go last.
	var depth := {String(v["start"]): 0}
	var queue: Array = [String(v["start"])]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for nx in Dialogue.successors(nodes[cur]):
			if nodes.has(nx) and not depth.has(nx):
				depth[nx] = depth[cur] + 1
				queue.append(nx)
	var names: Array = nodes.keys()
	names.sort()
	var ids := {}  # "kind:name" -> node id
	var rows := {}
	for n: String in names:
		var d: int = depth.get(n, int(depth.values().max()) + 1)
		var node: Dictionary = nodes[n]
		var kind := "choice" if node.has("choices") else ("end" if Dialogue.successors(node).is_empty() else "line")
		_add(out, ids, rows, kind, n, d)
	var vars_col: int = (int(depth.values().max()) + 2) if not depth.is_empty() else 1
	var seen := {}
	for n: String in names:
		var node: Dictionary = nodes[n]
		var from: int = ids["node:" + n]
		_writes(out, ids, rows, seen, from, node.get("do", []), vars_col)
		if node.has("choices"):
			for c: Dictionary in node["choices"]:
				var label := String(c.get("text", c.get("key", "choice")))
				if String(c.get("next", "")) != "":
					_link(out, seen, from, ids["node:" + String(c["next"])], label)
				_writes(out, ids, rows, seen, from, c.get("do", []), vars_col)
				for chk: Dictionary in c.get("if", []):
					if String(chk.get("check", "")) == "var":
						var vid := _add(out, ids, rows, "var", String(chk.get("name", "")), vars_col)
						_link(out, seen, vid, from, "checks")
		elif String(node.get("next", "")) != "":
			_link(out, seen, from, ids["node:" + String(node["next"])], "next")
	return out


## The node ID for a node of a built graph by kind and name, or -1.
static func node_id(graph: Dictionary, kind: String, name: String) -> int:
	for nid: int in graph["nodes"]:
		var n: Dictionary = graph["nodes"][nid]
		if n["kind"] == kind and n["name"] == name:
			return nid
	return -1


static func _writes(out: Dictionary, ids: Dictionary, rows: Dictionary, seen: Dictionary, from: int, actions: Array, col: int) -> void:
	for a: Dictionary in actions:
		var vid := _add(out, ids, rows, "var", String(a.get("name", "")), col)
		_link(out, seen, from, vid, String(a.get("do", "")))


static func _add(out: Dictionary, ids: Dictionary, rows: Dictionary, kind: String, name: String, col: int) -> int:
	var key := ("var:" if kind == "var" else "node:") + name
	if ids.has(key):
		return ids[key]
	var nid: int = (out["nodes"] as Dictionary).size()
	ids[key] = nid
	var r: int = rows.get(col, 0)
	rows[col] = r + 1
	out["nodes"][nid] = {"id": nid, "kind": kind, "name": name, "position": {"x": col * COLUMN_W, "y": r * ROW_H}}
	return nid


## One link per node pair (the editor refuses doubles); labels merge.
static func _link(out: Dictionary, seen: Dictionary, a: int, b: int, label: String) -> void:
	var k := "%d>%d" % [a, b]
	if seen.has(k):
		var l: Dictionary = out["links"][seen[k]]
		if not (", " + l["label"] + ", ").contains(", " + label + ", "):
			l["label"] = l["label"] + ", " + label
		return
	var lid: int = (out["links"] as Dictionary).size()
	seen[k] = lid
	out["links"][lid] = {"id": lid, "start_node_id": a, "end_node_id": b, "label": label}
