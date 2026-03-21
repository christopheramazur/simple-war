extends Object
class_name SceneRoutes
## Central scene paths and [method go] helpers. See Scene_Routing_Spike.md.

const MAIN_MENU := "res://src/ui/main_menu.tscn"
const CAMPAIGN_PLANNING := "res://src/ui/campaign_planning.tscn"
const SECTOR_MAP := "res://src/ui/sector_map.tscn"
const ARMYBUILDING := "res://src/ui/armybuilding.tscn"
const BATTLE_PLANNING := "res://src/ui/battle_planning.tscn"
const BATTLEFIELD := "res://src/ui/battlefield.tscn"

## Order matches quick-play UI flow; used by [code]test/integration/quickplay_flow_smoke.gd[/code].
const QUICKPLAY_SMOKE_FLOW: Array[String] = [
	MAIN_MENU,
	CAMPAIGN_PLANNING,
	SECTOR_MAP,
	ARMYBUILDING,
	SECTOR_MAP,
	BATTLE_PLANNING,
	BATTLEFIELD,
]


static func go(tree: SceneTree, path: String) -> void:
	tree.change_scene_to_file(path)


static func go_to_main_menu(tree: SceneTree) -> void:
	go(tree, MAIN_MENU)


static func go_to_campaign_planning(tree: SceneTree) -> void:
	go(tree, CAMPAIGN_PLANNING)


static func go_to_sector_map(tree: SceneTree) -> void:
	go(tree, SECTOR_MAP)


static func go_to_armybuilding(tree: SceneTree) -> void:
	go(tree, ARMYBUILDING)


static func go_to_battle_planning(tree: SceneTree) -> void:
	go(tree, BATTLE_PLANNING)


static func go_to_battlefield(tree: SceneTree) -> void:
	go(tree, BATTLEFIELD)
