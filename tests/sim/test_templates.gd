extends GutTest
## Archetype template table. GDD 03 §3.1, R6Q18. Task sw-qio.3.


func _defs() -> Array:
	return [
		{"id": "infantry", "kind": "squad", "abstract": true,
			"values": {"hp": 10.0, "cr": 10, "move": {"walk": "1.5", "run": 3}}},
		{"id": "rifles", "parent": "infantry", "values": {"move": {"run": 4}, "weapon": "rifle"}},
		{"id": "veteran_rifles", "parent": "rifles", "values": {"hp": 12, "cr": null}},
	]


func test_flatten_merges_chain() -> void:
	var t := TemplateTable.build(_defs())
	assert_true(t.is_valid(), str(t.errors))
	var v := t.values_of("veteran_rifles")
	assert_eq(v["hp"], 12)
	assert_false(v.has("cr"), "null removes")
	assert_eq(v["move"]["walk"], "1.5")
	assert_eq(v["move"]["run"], 4)
	assert_eq(v["weapon"], "rifle")
	assert_eq(t.kind_of("veteran_rifles"), "squad", "kind inherited")


func test_integral_floats_become_ints() -> void:
	var t := TemplateTable.build(_defs())
	assert_eq(typeof(t.values_of("rifles")["hp"]), TYPE_INT)


func test_provenance() -> void:
	var t := TemplateTable.build(_defs())
	assert_eq(t.provenance("veteran_rifles", "hp"), "veteran_rifles")
	assert_eq(t.provenance("veteran_rifles", "move/run"), "rifles")
	assert_eq(t.provenance("veteran_rifles", "move/walk"), "infantry")
	assert_eq(t.provenance("veteran_rifles", "cr"), "", "removed key has none")


func test_values_are_read_only_and_instances_are_copies() -> void:
	var t := TemplateTable.build(_defs())
	var v := t.values_of("rifles")
	assert_true(v.is_read_only())
	assert_true((v["move"] as Dictionary).is_read_only())
	var inst := t.instantiate("rifles")
	inst["hp"] = 1
	inst["move"]["run"] = 99
	assert_eq(t.values_of("rifles")["hp"], 10)
	assert_eq(t.values_of("rifles")["move"]["run"], 4)


func test_abstract_flag_not_inherited() -> void:
	var t := TemplateTable.build(_defs())
	assert_true(t.is_abstract("infantry"))
	assert_false(t.is_abstract("rifles"))


func _has_error(t: TemplateTable, fragment: String) -> bool:
	for e in t.errors:
		if e.contains(fragment):
			return true
	return false


func test_depth_limit() -> void:
	var defs := _defs()
	defs.append({"id": "elite", "parent": "veteran_rifles", "values": {}})
	var t := TemplateTable.build(defs)
	assert_false(t.is_valid())
	assert_true(_has_error(t, "deeper than 3"), str(t.errors))


func test_cycle_missing_parent_duplicate() -> void:
	var t := TemplateTable.build([
		{"id": "a", "parent": "b", "kind": "squad", "values": {}},
		{"id": "b", "parent": "a", "values": {}},
		{"id": "c", "parent": "nope", "kind": "squad", "values": {}},
		{"id": "c", "kind": "squad", "values": {}},
	])
	assert_true(_has_error(t, "cycle"), str(t.errors))
	assert_true(_has_error(t, "missing parent 'nope'"), str(t.errors))
	assert_true(_has_error(t, "duplicate id"), str(t.errors))
	assert_false(t.has("a"), "invalid table exposes nothing")


func test_kind_mismatch_and_fractional_float() -> void:
	var t := TemplateTable.build([
		{"id": "base", "kind": "squad", "values": {"speed": 1.5}},
		{"id": "child", "parent": "base", "kind": "unit", "values": {}},
	])
	assert_true(_has_error(t, "fractional"), str(t.errors))
	assert_true(_has_error(t, "differs from parent kind"), str(t.errors))
