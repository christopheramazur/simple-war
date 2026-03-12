class_name UnitFactory
extends RefCounted

## Builds runtime UnitData instances from JSON definitions.
## Requires an ItemFactory to resolve item references on models.

var _unit_defs: Dictionary = {}   # id -> raw dict
var _model_defs: Dictionary = {}  # id -> raw dict
var _item_factory: ItemFactory = null


func load_all(item_factory: ItemFactory) -> void:
	_item_factory = item_factory

	var raw_units := DataLoader.load_units()
	if raw_units.has("units"):
		for entry: Dictionary in raw_units["units"]:
			_unit_defs[entry["id"]] = entry

	var raw_models := DataLoader.load_models()
	if raw_models.has("models"):
		for entry: Dictionary in raw_models["models"]:
			_model_defs[entry["id"]] = entry


func create_unit(unit_id: String) -> UnitData:
	if not _unit_defs.has(unit_id):
		push_error("UnitFactory: unknown unit '%s'" % unit_id)
		return null

	var def: Dictionary = _unit_defs[unit_id]
	var unit := UnitData.new()
	unit.id = def.get("id", "")
	unit.display_name = def.get("display_name", "")

	var fk: Array = def.get("faction_keywords", [])
	unit.faction_keywords.assign(fk)
	var uk: Array = def.get("unit_keywords", [])
	unit.unit_keywords.assign(uk)

	unit.endurance = int(def.get("endurance", 0))
	unit.durability = int(def.get("durability", 0))
	unit.morale = int(def.get("morale", 0))
	unit.speed = int(def.get("speed", 0))
	unit.reflex = int(def.get("reflex", 0))
	unit.value = int(def.get("value", 0))

	var ws: Dictionary = def.get("weapon_skill", {})
	unit.weapon_skill = {}
	for key in ws.keys():
		unit.weapon_skill[key] = int(ws[key])

	var composition: Array = def.get("composition", [])
	for comp: Dictionary in composition:
		var model_id: String = comp.get("model_id", "")
		var count: int = int(comp.get("count", 0))
		for i in range(count):
			var model := _create_model(model_id, unit)
			if model != null:
				unit.models.append(model)

	return unit


func get_unit_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_unit_defs.keys())
	return ids


func _create_model(model_id: String, parent_unit: UnitData) -> ModelData:
	if not _model_defs.has(model_id):
		push_error("UnitFactory: unknown model '%s'" % model_id)
		return null

	var def: Dictionary = _model_defs[model_id]
	var model := ModelData.new()
	model.id = def.get("id", "")
	model.display_name = def.get("display_name", "")

	model.endurance = parent_unit.endurance
	model.durability = parent_unit.durability
	model.morale = parent_unit.morale
	model.speed = parent_unit.speed
	model.reflex = parent_unit.reflex
	# Copy unit-level weapon skills; can be specialized per-model later if needed.
	model.weapon_skill = parent_unit.weapon_skill.duplicate(true)

	var items_raw: Array = def.get("items", [])
	for item_entry: Dictionary in items_raw:
		var item_id: String = item_entry.get("id", "")
		var item := _item_factory.get_item(item_id)
		if item != null:
			var count: int = int(item_entry.get("count", 1))
			for _i in range(count):
				model.items.append(item)

	return model
