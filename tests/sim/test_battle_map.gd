extends GutTest
## Battle maps as shape lists (GDD 03 section 3.5, O1Q11, sw-ll4.2): fills,
## facing, stamps with rotation, and how a scenario uses a map.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


## The core package plus `maps` (id -> battle_map values) and a scenario
## "t" made from duel_crossroads with `scenario` laid over it.
func _table(maps: Dictionary, scenario: Dictionary) -> TemplateTable:
	var defs := _l().defs.duplicate()
	for id: String in maps:
		defs.append({"id": id, "kind": "battle_map", "values": maps[id]})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	for f: String in ["map", "width", "height", "terrain_default", "terrain"]:
		sc.erase(f)
	sc.merge(scenario, true)
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	return TemplateTable.build(defs)


func _compile(maps: Dictionary, scenario: Dictionary) -> BattleRules:
	return BattleRules.compile(_table(maps, scenario), "t")


func _name(r: BattleRules, x: int, y: int) -> String:
	return r.feature_ids[r.feature_at(x * ONE, y * ONE)]


func _facing(r: BattleRules, x: int, y: int) -> String:
	var f := r.facing_at(x * ONE, y * ONE)
	return "" if f == 0 else DataSchema.FACINGS[f - 1]


## An L of two cells with facings, on a 3 wide, 2 tall stamp:
##   W . .      W = ruins facing n at (0,0); R = road facing e at (2,1)
##   . . R
const L_STAMP := {"width": 3, "height": 2, "base": "forest", "cells": [
	{"feature": "ruins", "x": 0, "y": 0, "facing": "n"},
	{"feature": "road", "x": 2, "y": 1, "facing": "e"}]}


func test_an_empty_map_is_valid() -> void:
	var t := _table({"m": {"width": 6, "height": 4, "base": "forest"}}, {"map": "m"})
	assert_eq(DataSchema.validate(t), PackedStringArray())
	var r := BattleRules.compile(t, "t")
	assert_eq(r.errors, PackedStringArray())
	assert_eq([r.width, r.height], [6, 4])
	assert_eq(_name(r, 0, 0), "forest")
	assert_eq(_name(r, 5, 3), "forest")


func test_later_entries_overwrite_and_clip() -> void:
	var r := _compile({"m": {"width": 6, "height": 4, "base": "open", "cells": [
		{"feature": "forest", "x": 1, "y": 1, "w": 3, "h": 2},
		{"feature": "road", "x": 2, "y": 0, "h": 4, "facing": "s"},
		{"feature": "ruins", "x": 4, "y": 3, "w": 50, "h": 50}]}}, {"map": "m"})
	assert_eq(r.errors, PackedStringArray())
	assert_eq(_name(r, 1, 1), "forest")
	assert_eq(_name(r, 2, 1), "road", "the later road overwrites the forest")
	assert_eq(_facing(r, 2, 3), "s")
	assert_eq(_facing(r, 1, 1), "", "no facing unless given")
	assert_eq(_name(r, 0, 0), "open", "w and h default to one cell")
	assert_eq(_name(r, 5, 3), "ruins", "a shape past the edge is clipped")


func test_a_stamp_copies_only_painted_cells() -> void:
	var r := _compile({"l": L_STAMP, "m": {"width": 8, "height": 6, "base": "open", "cells": [
		{"stamp": "l", "x": 4, "y": 2}]}}, {"map": "m"})
	assert_eq(r.errors, PackedStringArray())
	assert_eq(_name(r, 4, 2), "ruins")
	assert_eq(_name(r, 6, 3), "road")
	assert_eq(_name(r, 5, 2), "open", "the stamp's base is not copied")


func test_a_stamp_turns_clockwise_with_its_facings() -> void:
	# Turned 90 degrees the stamp is 2 wide and 3 tall: (x, y) -> (1 - y, x).
	var r := _compile({"l": L_STAMP, "m": {"width": 8, "height": 6, "base": "open", "cells": [
		{"stamp": "l", "x": 0, "y": 0, "rotate": 90},
		{"stamp": "l", "x": 4, "y": 0, "rotate": 180},
		{"stamp": "l", "x": 0, "y": 3, "rotate": 270}]}}, {"map": "m"})
	assert_eq(r.errors, PackedStringArray())
	assert_eq([_name(r, 1, 0), _facing(r, 1, 0)], ["ruins", "e"])
	assert_eq([_name(r, 0, 2), _facing(r, 0, 2)], ["road", "s"])
	# 180: (x, y) -> (2 - x, 1 - y), placed at 4,0.
	assert_eq([_name(r, 6, 1), _facing(r, 6, 1)], ["ruins", "s"])
	assert_eq([_name(r, 4, 0), _facing(r, 4, 0)], ["road", "w"])
	# 270: (x, y) -> (y, 2 - x), placed at 0,3.
	assert_eq([_name(r, 0, 5), _facing(r, 0, 5)], ["ruins", "w"])
	assert_eq([_name(r, 1, 3), _facing(r, 1, 3)], ["road", "n"])


func test_stamps_nest_but_not_into_themselves() -> void:
	var nested := _compile({"l": L_STAMP,
		"row": {"width": 6, "height": 2, "base": "open", "cells": [{"stamp": "l", "x": 0, "y": 0}, {"stamp": "l", "x": 3, "y": 0}]},
		"m": {"width": 8, "height": 6, "base": "open", "cells": [{"stamp": "row", "x": 1, "y": 1}]}}, {"map": "m"})
	assert_eq(nested.errors, PackedStringArray())
	assert_eq(_name(nested, 1, 1), "ruins")
	assert_eq(_name(nested, 4, 1), "ruins")
	var loop := _compile({
		"a": {"width": 4, "height": 4, "base": "open", "cells": [{"stamp": "b", "x": 0, "y": 0}]},
		"b": {"width": 4, "height": 4, "base": "open", "cells": [{"stamp": "a", "x": 0, "y": 0}]}}, {"map": "a"})
	assert_eq(loop.errors.size(), 1, "; ".join(loop.errors))
	assert_string_contains(loop.errors[0], "stamps itself")


func test_bad_entries_are_reported() -> void:
	var r := _compile({"l": L_STAMP, "m": {"width": 8, "height": 6, "base": "open", "cells": [
		{"x": 0, "y": 0},
		{"feature": "road", "stamp": "l", "x": 0, "y": 0},
		{"stamp": "l", "x": 0, "y": 0, "rotate": 45}]}}, {"map": "m"})
	assert_eq(r.errors.size(), 3, "; ".join(r.errors))
	var t := _table({"m": {"width": 4, "height": 4, "base": "open", "cells": [
		{"feature": "lava", "x": 0, "y": 0, "facing": "up"}]}}, {"map": "m"})
	assert_eq(DataSchema.validate(t).size(), 2, "an unknown feature and an unknown facing")


func test_scenario_rectangles_apply_after_the_map() -> void:
	var r := _compile({"m": {"width": 6, "height": 4, "base": "open", "cells": [
		{"feature": "forest", "x": 0, "y": 0, "w": 6, "h": 4, "facing": "n"}]}},
		{"map": "m", "terrain": [{"feature": "road", "x": 0, "y": 1, "w": 6, "h": 1}]})
	assert_eq(r.errors, PackedStringArray())
	assert_eq(_name(r, 3, 0), "forest")
	assert_eq([_name(r, 3, 1), _facing(r, 3, 1)], ["road", ""])


func test_a_scenario_needs_a_map_or_its_own_size() -> void:
	var neither := _compile({}, {})
	assert_eq(neither.errors.size(), 3, "; ".join(neither.errors))
	var both := _compile({"m": {"width": 6, "height": 4, "base": "open"}}, {"map": "m", "width": 6, "height": 4})
	assert_eq(both.errors.size(), 2, "; ".join(both.errors))
	var own := _compile({}, {"width": 30, "height": 20, "terrain_default": "open"})
	assert_eq(own.errors, PackedStringArray())
	assert_eq([own.width, own.height], [30, 20])


func test_core_maps_keep_their_terrain() -> void:
	var r := BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	assert_eq(r.errors, PackedStringArray())
	assert_eq([r.width, r.height], [200, 100])
	assert_eq(_name(r, 10, 49), "road")
	assert_eq(_facing(r, 10, 49), "e")
	assert_eq(_name(r, 50, 20), "forest")
	for at: Array in [[92, 40], [107, 47], [92, 52], [107, 59]]:
		assert_eq(_name(r, at[0], at[1]), "ruins", "ruin block corner %s" % [at])
	assert_eq(_name(r, 100, 49), "road", "the road runs between the two ruin blocks")
	assert_eq(_name(r, 91, 40), "open")
