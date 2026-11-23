extends GutTest
## Editing dialogue graphs (sw-7wt): DialogueEdit on dialogue values, and the
## Dialogues tab of the War Data panel saving what the graph editor changed.
## Edits run on a copy of the core package in user://.

const CORE := "res://data/packages/core"
const COPY := "user://test_pkg_dialogue_edit"


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
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _values() -> Dictionary:
	return {"start": "a", "nodes": {
		"a": {"speaker": "x", "text": "hi", "choices": [{"text": "to b", "next": "b"}]},
		"b": {"text": "bye", "next": "c"},
		"c": {"text": "end"},
	}}


func test_link_from_a_line_sets_its_next() -> void:
	var v := _values()
	assert_eq(DialogueEdit.link(v, "b", "a"), "")
	assert_eq(v["nodes"]["b"]["next"], "a")
	assert_eq(DialogueEdit.link(v, "c", "b"), "")
	assert_eq(v["nodes"]["c"]["next"], "b")
	assert_eq(Dialogue.problems(v), PackedStringArray())


func test_link_from_a_choice_node_adds_a_choice_once() -> void:
	var v := _values()
	assert_eq(DialogueEdit.link(v, "a", "c"), "")
	var choices: Array = v["nodes"]["a"]["choices"]
	assert_eq(choices.size(), 2)
	assert_eq(choices[1], {"text": "c", "next": "c"})
	DialogueEdit.link(v, "a", "c")
	assert_eq(choices.size(), 2, "the same link is not doubled")


func test_link_to_or_from_a_missing_node_is_refused() -> void:
	var v := _values()
	assert_ne(DialogueEdit.link(v, "a", "zz"), "")
	assert_ne(DialogueEdit.link(v, "zz", "a"), "")
	assert_eq(v["nodes"]["a"]["choices"].size(), 1)


func test_unlink_removes_the_choice_or_the_next() -> void:
	var v := _values()
	DialogueEdit.unlink(v, "a", "b")
	assert_false(v["nodes"]["a"].has("choices"), "the last choice goes and so does the list")
	DialogueEdit.unlink(v, "b", "c")
	assert_false(v["nodes"]["b"].has("next"))
	assert_eq(DialogueEdit.unlink(v, "zz", "a"), "", "a node that is gone has no links left")


func test_unlink_keeps_other_choices_and_their_effects() -> void:
	var v := _values()
	v["nodes"]["a"]["choices"].append({"text": "keep", "next": "c", "do": [{"do": "add_var", "name": "disp.x", "value": 1}]})
	v["nodes"]["a"]["choices"].append({"text": "ends"})
	DialogueEdit.unlink(v, "a", "c")
	var choices: Array = v["nodes"]["a"]["choices"]
	assert_eq(choices.size(), 2)
	assert_eq(choices[0]["text"], "to b")
	assert_eq(choices[1], {"text": "ends"})


func test_remove_node_takes_its_links_with_it() -> void:
	var v := _values()
	assert_eq(DialogueEdit.remove_node(v, "b"), "")
	assert_false(v["nodes"].has("b"))
	assert_false(v["nodes"]["a"].has("choices"), "a's only choice went to b")
	assert_ne(DialogueEdit.remove_node(v, "b"), "", "removing twice is refused")


func test_add_node_and_new_name() -> void:
	var v := _values()
	var name := DialogueEdit.new_name(v)
	assert_false(v["nodes"].has(name))
	assert_eq(DialogueEdit.add_node(v, name), "")
	assert_eq(v["nodes"][name], {})
	assert_ne(DialogueEdit.add_node(v, name), "", "a taken name is refused")
	assert_ne(DialogueEdit.add_node(v, ""), "")


func test_pairs_lists_each_link_once() -> void:
	var v := _values()
	v["nodes"]["a"]["choices"].append({"text": "again", "next": "b"})
	assert_eq(DialogueEdit.pairs(v), [["a", "b"], ["b", "c"]])


func _find(graph: Dictionary, name: String) -> int:
	for nid: int in graph["nodes"]:
		if graph["nodes"][nid]["name"] == name and graph["nodes"][nid]["kind"] != "var":
			return nid
	return -1


func test_the_panel_saves_graph_edits() -> void:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	p.show_dialogue("af_jeff_briefing")
	await get_tree().process_frame

	# A node added in the editor is named and saved.
	var g: CGEGraph = p._dgraph.get("graph")
	g.create_node()
	await get_tree().process_frame
	assert_true(_nodes(p).has("node_5"), "the new node is named")
	assert_eq(p._dresult.text, "Saved to %s." % p.model.file_of("af_jeff_briefing"))

	# A link drawn from it to the end: a node without choices gets next.
	g = p._dgraph.get("graph")
	g.create_link(_find(p._dgraph_data, "node_5"), _find(p._dgraph_data, "end"))
	await get_tree().process_frame
	assert_eq(_nodes(p)["node_5"]["next"], "end")

	# A link drawn from the choice node adds a choice.
	g = p._dgraph.get("graph")
	g.create_link(_find(p._dgraph_data, "greet"), _find(p._dgraph_data, "node_5"))
	await get_tree().process_frame
	var choices: Array = _nodes(p)["greet"]["choices"]
	assert_eq(choices.size(), 4)
	assert_eq(choices[3], {"text": "node_5", "next": "node_5"})

	# Deleting a node in the editor removes it and the choices that led to it.
	g = p._dgraph.get("graph")
	g.remove_node(_find(p._dgraph_data, "careful"))
	await get_tree().process_frame
	assert_false(_nodes(p).has("careful"))
	assert_eq(_nodes(p)["greet"]["choices"].size(), 3, "the choice to careful went with it")
	assert_eq(Dialogue.problems(p.model.templates.values_of("af_jeff_briefing")), PackedStringArray())
	assert_eq(DialogueGraph.build(p.model.templates, "af_jeff_briefing")["errors"], PackedStringArray())


func _nodes(p: WarDataPanel) -> Dictionary:
	return p.model.templates.values_of("af_jeff_briefing")["nodes"]


func test_a_refused_graph_edit_is_undone_on_screen() -> void:
	var p := WarDataPanel.new()
	p.package_dir = COPY
	add_child_autofree(p)
	p.show_dialogue("af_jeff_briefing")
	await get_tree().process_frame
	var g: CGEGraph = p._dgraph.get("graph")
	# Removing the start node leaves the dialogue without one: refused.
	g.remove_node(_find(p._dgraph_data, "greet"))
	await get_tree().process_frame
	assert_string_starts_with(p._dresult.text, "Not saved:")
	var values := p.model.templates.values_of("af_jeff_briefing")
	assert_eq(values["start"], "greet")
	assert_true((values["nodes"] as Dictionary).has("greet"))
	assert_eq(p.dialogue_node_count(), (DialogueGraph.build(p.model.templates, "af_jeff_briefing")["nodes"] as Dictionary).size(), "the graph is drawn again from the definition")
