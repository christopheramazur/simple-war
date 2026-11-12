@tool
class_name WarGraphNode
extends CGEGraphNode
## A trigger-graph node (TriggerGraph): what it stands for.

## "event", "trigger", "var", "zone" or "feature".
var kind: String = ""
var node_name: String = ""


func serialize() -> Dictionary:
	var d := super()
	d["kind"] = kind
	d["name"] = node_name
	return d


func deserialize(data: Dictionary) -> void:
	super(data)
	kind = String(data.get("kind", kind))
	node_name = String(data.get("name", node_name))
