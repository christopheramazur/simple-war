extends GutTest
## Overworld tuning table (U1 E1, sw-63wt.1; draft 05 §5 B1). Pins the shipped
## numbers so a change to them is a deliberate edit of this table.

const CORE := "res://data/packages/core"


func _templates() -> TemplateTable:
	var l := PackageLoader.load_dirs(PackedStringArray([CORE]))
	assert_true(l.is_valid(), "\n".join(l.errors))
	return l.templates


func test_commander_movement_and_sight() -> void:
	var t := _templates()
	var table := {
		"field_commander": [50, 4],
		"outrider": [80, 5],
		"siege_captain": [40, 4],
		"jeff_commander": [45, 4],
	}
	for id: String in table:
		var v := t.values_of(id)
		assert_eq(v["movement_points"], table[id][0], "%s movement_points" % id)
		assert_eq(v["sight"], table[id][1], "%s sight" % id)


func test_feature_sight() -> void:
	var t := _templates()
	var table := {
		"hex_village": 3,
		"hex_frontier_town": 3,
		"hex_barracks": 2,
		"hex_depot": 2,
		"hex_mine": 1,
	}
	for id: String in table:
		assert_eq(t.values_of(id)["sight"], table[id], "%s sight" % id)


func test_convoy_movement() -> void:
	var t := _templates()
	assert_eq(t.values_of("test_vale")["convoy_movement"], 30, "test_vale convoy_movement")
	assert_eq(t.values_of("skirmish_mirror")["convoy_movement"], 30, "skirmish_mirror convoy_movement")
	assert_eq(OverworldRules.DEFAULT_CONVOY_MOVEMENT, 30, "code default convoy movement")
