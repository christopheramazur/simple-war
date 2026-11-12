extends GutTest
## Authoring tools (GDD 04 §4.9, R8Q7): the data editor's model
## (PackageEditor), the trigger graph (TriggerGraph) and the War Data panel.
## Task sw-cgl.3. Edits run on a copy of the core package in user://.

const CORE := "res://data/packages/core"
const COPY := "user://test_pkg_core"


func before_each() -> void:
	_copy(CORE, COPY)


func after_all() -> void:
	_remove(COPY)


func _copy(from: String, to: String) -> void:
	_remove(to)
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	for f in d.get_files():
		if not f.ends_with(".import"):
			DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for sub in d.get_directories():
		_copy(from.path_join(sub), to.path_join(sub))


func _remove(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove(path.path_join(sub))
	DirAccess.remove_absolute(path)


func test_browsing_the_core_package() -> void:
	var e := PackageEditor.open(CORE)
	assert_eq(e.errors, PackedStringArray(), "the core package is valid")
	assert_true(e.kinds().has("trigger") and e.kinds().has("term"))
	assert_eq(e.file_of("hex_barracks"), "defs/overworld.json")
	var def: Dictionary = JSON.parse_string(e.definition_text("hex_lake"))
	assert_eq(def["id"], "hex_lake")
	var rows := e.flattened("carbine")
	var name_row: Array = rows.filter(func(r: Dictionary) -> bool: return r["field"] == "name")
	assert_eq(name_row[0]["from"], "carbine")
	var range_row: Array = rows.filter(func(r: Dictionary) -> bool: return r["field"] == "magazine")
	assert_eq(range_row[0]["from"], "rifle", "provenance: inherited from the parent")


func test_edits_are_validated_against_the_package() -> void:
	var e := PackageEditor.open(COPY)
	var lake := e.definition_text("hex_lake")
	assert_eq(e.preview("hex_lake", lake), PackedStringArray(), "unchanged is fine")
	assert_gt(e.preview("hex_lake", "{nope").size(), 0)
	assert_eq(e.preview("hex_lake", lake.replace("hex_lake", "hex_pond"))[0], "the id must stay 'hex_lake' (add a new template instead)")
	assert_gt(e.preview("hex_lake", lake.replace("true", "\"yes\"")).size(), 0, "schema: impassable is a bool")
	var vale := e.definition_text("vale_angels_gather")
	var broken := vale.replace("\"add_feature\"", "\"unlock_zone\"")
	var errs := e.preview("vale_angels_gather", broken)
	assert_gt(errs.size(), 0, "the map's triggers would no longer compile")
	assert_eq(e.replace("vale_angels_gather", broken), errs, "and nothing is written")
	assert_eq(e.definition_text("vale_angels_gather"), vale)


func test_replace_changes_only_that_template() -> void:
	var e := PackageEditor.open(COPY)
	var before := FileAccess.get_file_as_string(COPY.path_join("defs/overworld.json"))
	var forest := e.definition_text("hex_forest")
	var edited := forest.replace("\"move_cost\": 5", "\"move_cost\": 7")
	assert_eq(e.replace("hex_forest", edited), PackedStringArray())
	var after := FileAccess.get_file_as_string(COPY.path_join("defs/overworld.json"))
	assert_eq(after, before.replace(forest, edited), "the rest of the file is untouched")
	assert_eq(e.templates.values_of("hex_forest")["move_cost"], 7, "reloaded")


func test_adding_a_template() -> void:
	var e := PackageEditor.open(COPY)
	var swamp := "{\"id\": \"hex_swamp\", \"kind\": \"hex_feature\", \"values\": {\"name\": \"Swamp\", \"move_cost\": 15}}"
	assert_eq(e.add(swamp, "defs/nope.json"), PackedStringArray(["unknown data file 'defs/nope.json'"]))
	assert_eq(e.add(swamp, "defs/overworld.json"), PackedStringArray())
	assert_eq(e.file_of("hex_swamp"), "defs/overworld.json")
	assert_eq(e.errors, PackedStringArray(), "still a valid package")
	assert_eq(e.add(swamp, "defs/overworld.json"), PackedStringArray(["'hex_swamp' already exists"]))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(COPY.path_join("defs/overworld.json")))
	assert_eq(typeof(data), TYPE_DICTIONARY, "the file is still JSON")


func test_trigger_graphs() -> void:
	var t := PackageEditor.open(CORE).templates
	var g := TriggerGraph.build(t, "trigger_vale")
	assert_eq(g["errors"], PackedStringArray())
	for pair: Array in [["event", "turn_resolved"], ["event", "offer_answered"], ["event", "feature_captured"],
			["trigger", "vale_angels_gather"], ["var", "angels"], ["var", "village_taken"], ["feature", "hex_angel_host"]]:
		assert_ne(TriggerGraph.node_id(g, pair[0], pair[1]), -1, "%s %s" % pair)
	var links: Array = (g["links"] as Dictionary).values()
	var gather := TriggerGraph.node_id(g, "trigger", "vale_angels_gather")
	var host := TriggerGraph.node_id(g, "feature", "hex_angel_host")
	assert_true(links.any(func(l: Dictionary) -> bool: return l["start_node_id"] == gather and l["end_node_id"] == host and l["label"] == "add_feature"))
	var h := TriggerGraph.build(t, "hangar_drill")
	var zone := TriggerGraph.node_id(h, "zone", "hangar")
	var held := TriggerGraph.node_id(h, "trigger", "drill_hangar_held")
	var hl: Array = (h["links"] as Dictionary).values()
	assert_true(hl.any(func(l: Dictionary) -> bool: return l["start_node_id"] == zone and l["end_node_id"] == held and l["label"] == "checks"))
	assert_eq(TriggerGraph.build(t, "hex_lake")["errors"].size(), 1)


func test_the_panel_runs_standalone() -> void:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	p.select("hex_forest")
	assert_string_contains(p._source.text, "hex_forest")
	p._source.text = p._source.text.replace("\"move_cost\": 5", "\"move_cost\": \"lots\"")
	assert_gt(p.validate_edit().size(), 0)
	p._source.text = p._source.text.replace("\"move_cost\": \"lots\"", "\"move_cost\": 6")
	assert_eq(p.apply_edit(), PackedStringArray())
	assert_eq(p.model.templates.values_of("hex_forest")["move_cost"], 6)
	p.show_triggers("trigger_vale")
	await get_tree().process_frame
	assert_eq(p.graph_node_count(), (TriggerGraph.build(p.model.templates, "trigger_vale")["nodes"] as Dictionary).size())
	assert_not_null(p._graph.call("get_graph_node", 0), "the graph editor holds the nodes")
