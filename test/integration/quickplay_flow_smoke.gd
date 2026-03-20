extends SceneTree

const FLOW_SCENES := [
	"res://src/ui/main_menu.tscn",
	"res://src/ui/campaign_planning.tscn",
	"res://src/ui/sector_map.tscn",
	"res://src/ui/armybuilding.tscn",
	"res://src/ui/sector_map.tscn",
	"res://src/ui/battle_planning.tscn",
	"res://src/ui/battlefield.tscn"
]

func _initialize() -> void:
	for scene_path in FLOW_SCENES:
		var packed: PackedScene = load(scene_path)
		if packed == null:
			push_error("Failed to load scene: %s" % scene_path)
			quit(1)
			return
		var instance := packed.instantiate()
		if instance == null:
			push_error("Failed to instantiate scene: %s" % scene_path)
			quit(1)
			return
		instance.free()

	print("Quickplay smoke flow passed scene load/instantiate checks.")
	quit(0)
