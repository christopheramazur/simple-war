class_name DialogueEdit
extends RefCounted
## Edits to a dialogue's node graph (sw-7wt): the changes the graph editor
## makes (a node added, a link drawn or removed, a node deleted), written
## into the dialogue's `values` (see Dialogue). They touch only node names
## and the links between nodes: a node's speaker, text, do and if stay as
## they are. Each op changes `values` in place and returns an error ("" = ok).
## A link from a node with choices adds a choice to it; from any other node
## it sets that node's `next`. PackageEditor validates the result before it
## is written, so these ops do not have to be perfect about the schema.


## A node name nothing uses yet ("node_N").
static func new_name(values: Dictionary) -> String:
	var nodes: Dictionary = values.get("nodes", {})
	var i := nodes.size() + 1
	while nodes.has("node_%d" % i):
		i += 1
	return "node_%d" % i


## Adds an empty node (it ends the dialogue until something links from it).
static func add_node(values: Dictionary, name: String) -> String:
	var nodes = values.get("nodes")
	if not nodes is Dictionary:
		return "has no nodes"
	if name.is_empty() or (nodes as Dictionary).has(name):
		return "'%s' is empty or already a node" % name
	(nodes as Dictionary)[name] = {}
	return ""


## Removes a node and every link to it.
static func remove_node(values: Dictionary, name: String) -> String:
	var nodes = values.get("nodes")
	if not nodes is Dictionary or not (nodes as Dictionary).has(name):
		return "'%s' is not a node" % name
	(nodes as Dictionary).erase(name)
	for other: String in (nodes as Dictionary).keys():
		unlink(values, other, name)
	return ""


## Draws a link: a choice to `to` (its text is the target's name) when `from`
## has choices, otherwise `from`'s next. A link that is already there is kept.
static func link(values: Dictionary, from: String, to: String) -> String:
	var nodes = values.get("nodes")
	if not nodes is Dictionary or not (nodes as Dictionary).has(from) or not (nodes as Dictionary).has(to):
		return "'%s' or '%s' is not a node" % [from, to]
	var node: Dictionary = nodes[from]
	if node.has("choices"):
		for c: Variant in node["choices"]:
			if c is Dictionary and String(c.get("next", "")) == to:
				return ""
		node["choices"].append({"text": to, "next": to})
	else:
		node["next"] = to
	return ""


## Removes the link from `from` to `to`: the choice that leads there (a node
## left with no choices becomes a node without them), or the next. A node
## that is gone has no links left, so this is then a no-op.
static func unlink(values: Dictionary, from: String, to: String) -> String:
	var nodes = values.get("nodes")
	if not nodes is Dictionary or not (nodes as Dictionary).has(from):
		return ""
	var node: Dictionary = nodes[from]
	if node.has("choices"):
		var kept := []
		for c: Variant in node["choices"]:
			if not (c is Dictionary and String(c.get("next", "")) == to):
				kept.append(c)
		node["choices"] = kept
		if kept.is_empty():
			node.erase("choices")
	elif String(node.get("next", "")) == to:
		node.erase("next")
	return ""


## Every link between two nodes, as [from, to] pairs, sorted.
static func pairs(values: Dictionary) -> Array:
	var out := []
	var nodes: Dictionary = values.get("nodes", {})
	var names := nodes.keys()
	names.sort()
	for name: String in names:
		if not nodes[name] is Dictionary:
			continue
		for nx: String in Dialogue.successors(nodes[name]):
			if nodes.has(nx) and not out.has([name, nx]):
				out.append([name, nx])
	return out
