extends GutTest

const UnitRuntime := preload("res://src/battle/runtime/unit_runtime.gd")


func test_unit_runtime_stores_formation_layout() -> void:
	var u: UnitRuntime = UnitRuntime.new(
		"id",
		"Name",
		"Faction",
		10.0,
		5,
		8,
		Vector2.ZERO,
		1.25,
		3,
		2
	)
	assert_eq(u.model_diameter_world, 1.25)
	assert_eq(u.formation_files, 3)
	assert_eq(u.formation_ranks, 2)
