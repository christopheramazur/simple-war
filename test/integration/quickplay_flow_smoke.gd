extends SceneTree

const _SceneRoutes := preload("res://src/scene_routes.gd")

func _initialize() -> void:
	for scene_path: String in _SceneRoutes.QUICKPLAY_SMOKE_FLOW:
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
