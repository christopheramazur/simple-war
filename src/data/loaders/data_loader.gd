class_name DataLoader
extends RefCounted

## Loads JSON data files from res://src/data/ and returns parsed Dictionaries.

const DATA_PATH := "res://src/data/"


static func load_json(filename: String) -> Dictionary:
	var path := DATA_PATH + filename
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("DataLoader: JSON parse error in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data


static func load_attacks() -> Dictionary:
	return load_json("Attacks.json")


static func load_items() -> Dictionary:
	return load_json("Items.json")


static func load_models() -> Dictionary:
	return load_json("Models.json")


static func load_units() -> Dictionary:
	return load_json("Units.json")


static func load_scenarios() -> Dictionary:
	return load_json("Scenarios.json")
