extends GutTest

const SectorMapData := preload("res://src/campaign/sector_map_data.gd")

func test_load_poc_map_has_expected_plots() -> void:
	var m: Dictionary = SectorMapData.load_map_by_id(SectorMapData.POC_MAP_ID)
	var nodes: Dictionary = m.get("nodes", {})
	assert_true(nodes.has("armybuilding"))
	assert_true(nodes.has("battle"))
	assert_eq(nodes["armybuilding"], Vector2(320.0, 360.0))
	assert_eq(nodes["battle"], Vector2(900.0, 220.0))
	var meta: Dictionary = m.get("node_meta", {})
	assert_eq(str(meta["battle"].get("title", "")), "Battle")
