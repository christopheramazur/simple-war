class_name ItemFactory
extends RefCounted

## Builds runtime Item archetype Entity instances from Items.json.
## Items are indexed by id for O(1) lookup when populating
## EquippedItemsComponent on Model Entities.
##
## Weapon entries are resolved through AttackFactory (base attack +
## per-item overrides) into AttackProfileComponent instances.
## Armour entries become ArmourComponent instances.

var _items: Dictionary = {}  # id -> ItemData
var _attack_factory: AttackFactory = null


func load_all(attack_factory: AttackFactory) -> void:
	_attack_factory = attack_factory

	var raw := DataLoader.load_items()
	if not raw.has("items"):
		push_error("ItemFactory: Items.json missing 'items' key")
		return
	for entry: Dictionary in raw["items"]:
		var item := _parse_item(entry)
		_items[item.id] = item


func get_item(id: String) -> ItemData:
	if not _items.has(id):
		push_error("ItemFactory: unknown item '%s'" % id)
		return null
	return _items[id]


func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_items.keys())
	return ids


func _parse_item(entry: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = entry.get("id", "")
	item.display_name = entry.get("display_name", "")
	item.description = entry.get("description", "")

	# ItemTypeComponent classifications
	var item_types: Array = entry.get("item_types", [])
	for it: Dictionary in item_types:
		if it.has("weapon"):
			var weapon_data: Dictionary = it["weapon"]
			var attacks_raw: Array = weapon_data.get("attacks", [])
			for atk_entry: Dictionary in attacks_raw:
				var profile := _attack_factory.resolve(atk_entry)
				if profile != null:
					item.attack_profiles.append(profile)

		if it.has("armour"):
			var armour_raw: Dictionary = it["armour"]
			item.armour = _parse_armour(armour_raw)

		if it.has("consumable"):
			item.consumable = it["consumable"]

	return item


func _parse_armour(raw: Dictionary) -> ArmourData:
	var armour := ArmourData.new()
	armour.value = raw.get("value", 0)
	armour.type = raw.get("type", "none")
	var res_raw: Dictionary = raw.get("resistances", {})
	armour.resistances = {}
	for key: String in res_raw:
		armour.resistances[key] = int(res_raw[key])
	var mods_raw: Dictionary = raw.get("hit_modifiers", {})
	armour.hit_modifiers = {}
	for key in mods_raw.keys():
		armour.hit_modifiers[key] = float(mods_raw[key])
	return armour
