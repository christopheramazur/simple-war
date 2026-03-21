extends RefCounted
class_name SectorMapData

const DEFAULT_PATH: String = "res://data/Sector_Maps.json"
const POC_MAP_ID: String = "poc_sector_map"

## Parsed graph: { "nodes": Dictionary[String, Vector2], "connections": Array, "display_name": String }
static func load_map_by_id(map_id: String, data_path: String = DEFAULT_PATH) -> Dictionary:
	var file := FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		push_error("SectorMapData: could not open %s" % data_path)
		return _fallback_poc()
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SectorMapData: JSON parse failed")
		return _fallback_poc()
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return _fallback_poc()
	for m: Variant in root.get("maps", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == map_id:
			return _parse_map_entry(m)
	push_warning("SectorMapData: map id %s not found, using fallback" % map_id)
	return _fallback_poc()


static func _parse_map_entry(map_entry: Dictionary) -> Dictionary:
	var graph: Dictionary = map_entry.get("graph", {})
	var nodes_raw: Array = graph.get("nodes", [])
	var nodes: Dictionary = {}
	var node_meta: Dictionary = {}
	for n: Variant in nodes_raw:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var id: String = str(n.get("id", ""))
		var pos: Dictionary = n.get("position", {})
		nodes[id] = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
		node_meta[id] = {
			"title": str(n.get("title", id)),
			"activity_type": str(n.get("activity_type", ""))
		}
	return {
		"nodes": nodes,
		"node_meta": node_meta,
		"connections": graph.get("connections", []),
		"display_name": str(map_entry.get("display_name", ""))
	}


static func _fallback_poc() -> Dictionary:
	return {
		"nodes": {
			"armybuilding": Vector2(320.0, 360.0),
			"battle": Vector2(900.0, 220.0)
		},
		"node_meta": {
			"armybuilding": {"title": "Armybuilding", "activity_type": "armybuilding"},
			"battle": {"title": "Battle", "activity_type": "battle"}
		},
		"connections": [
			{"from": "armybuilding", "to": "battle", "direction": "one_way"}
		],
		"display_name": "Campaign PoC Sector (fallback)"
	}
