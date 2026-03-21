extends GutTest

const _SceneRoutes := preload("res://src/scene_routes.gd")


func test_scene_routes_paths_are_tscn() -> void:
	for p: String in _SceneRoutes.QUICKPLAY_SMOKE_FLOW:
		assert_true(p.ends_with(".tscn"), p)
	assert_eq(_SceneRoutes.QUICKPLAY_SMOKE_FLOW.size(), 7)
