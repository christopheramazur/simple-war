@tool
class_name WarDataPanel
extends VBoxContainer
## The data editor (GDD 04 §4.9, R8Q7): a content package's templates by
## kind; for the selected one, its flattened values with the template that
## set each, and its definition to edit, validated against the whole
## package before it is written (PackageEditor). The Triggers tab draws a
## map's or scenario's triggers with custom_graph_editor (TriggerGraph), the
## Dialogues tab a dialogue's nodes (DialogueGraph; edited in the graph and
## saved as DialogueEdit changes);
## selecting a trigger node opens its template. The Maps tab paints battle
## maps (MapPainter), the World maps tab overworld maps (OverworldPainter).
## Problems lists everything
## the package would fail to load with. Runs in the editor's main screen
## (plugin.gd) and standalone (F6).

const GRAPH_SCENE := "res://addons/custom_graph_editor/graph_editor.tscn"
const NODE_UI_SCENE := "res://addons/simple_war_tools/war_graph_node_ui.tscn"

@export var package_dir: String = "res://data/packages/core"

var model: PackageEditor
var selected_id: String = ""

var _path: LineEdit
var _status: Label
var _tree: Tree
var _tabs: TabContainer
var _info: Label
var _values: Tree
var _source: TextEdit
var _new_file: OptionButton
var _result: Label
var _owners: OptionButton
var _graph_holder: Control
var _graph: Control
var _graph_data: Dictionary = {}
var _graph_owner: String = ""
var _tresult: Label
var _dialogues: OptionButton
var _dgraph_holder: Control
var _dgraph: Control
var _dgraph_data: Dictionary = {}
var _dgraph_id: String = ""
var _dresult: Label
var _dinspect: GridContainer
var _dinspect_node: String = ""
var _dname: LineEdit
var _dspeaker: LineEdit
var _dtext: LineEdit
var _problems: ItemList
var _maps: MapPainter
var _world: OverworldPainter


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	open(package_dir)


## Loads (or reloads) a package.
func open(dir: String) -> void:
	package_dir = dir
	_path.text = dir
	model = PackageEditor.open(dir)
	_fill_tree()
	_fill_owners()
	_fill_dialogues()
	_fill_problems()
	_maps.set_model(model)
	_world.set_model(model)
	if not selected_id.is_empty() and model.file_of(selected_id) != "":
		select(selected_id)


## The Maps tab.
func painter() -> MapPainter:
	return _maps


## The World maps tab (overworld maps).
func world_painter() -> OverworldPainter:
	return _world


## Opens the Maps tab (the map painter).
func show_maps() -> void:
	_tabs.current_tab = _maps.get_index()


## Shows one template.
func select(id: String) -> void:
	selected_id = id
	_info.text = "%s  ·  %s  ·  %s" % [id, model.templates.kind_of(id), model.file_of(id)]
	_values.clear()
	var root := _values.create_item()
	for row: Dictionary in model.flattened(id):
		var it := _values.create_item(root)
		it.set_text(0, row["field"])
		it.set_text(1, JSON.stringify(row["value"]))
		it.set_text(2, row["from"])
	_source.text = model.definition_text(id)
	_result.text = ""
	_tabs.current_tab = 0
	_open_in_maps(id)


## A battle map selected on the left is opened in the Maps tab too, and a
## scenario with the map it is played on, unless that would drop unsaved
## paint. The tab is not switched.
func _open_in_maps(id: String) -> void:
	var kind := model.templates.kind_of(id) if model.templates != null else ""
	if kind == "overworld_map" and not model.templates.is_abstract(id):
		if _world.canvas == null or not _world.canvas.dirty:
			_world.open_map(id)
		return
	var was := _maps._result.text
	if kind == "battle_map":
		_maps.open_map(id)
	elif kind == "scenario" and not model.templates.is_abstract(id):
		var map := str(model.templates.values_of(id).get("map", ""))
		if not map.is_empty() and _maps.open_map(map):
			_maps.open_scenario(id)
	else:
		return
	if _maps.canvas != null and _maps.canvas.dirty:
		_maps._result.text = was  # a refusal belongs on the Maps tab only when it is used


## Validates the edited definition without writing. Returns the errors.
func validate_edit() -> PackedStringArray:
	var errs := model.preview(selected_id, _source.text)
	_show(errs, "Valid: the package loads with this change.")
	return errs


## Writes the edited definition if the package stays valid.
func apply_edit() -> PackedStringArray:
	var errs := model.replace(selected_id, _source.text)
	_show(errs, "Saved to %s." % model.file_of(selected_id))
	if errs.is_empty():
		open(package_dir)
		_result.text = "Saved to %s." % model.file_of(selected_id)
	return errs


## Adds the edited text as a new template in the chosen data file.
func add_new() -> PackedStringArray:
	var file := _new_file.get_item_text(_new_file.selected) if _new_file.item_count > 0 else ""
	var errs := model.add(_source.text, file)
	_show(errs, "Added to %s." % file)
	if errs.is_empty():
		var def: Dictionary = JSON.parse_string(_source.text)
		selected_id = str(def["id"])
		open(package_dir)
	return errs


## Draws the triggers of a map or scenario. The graph is a view (GDD 04
## §4.9): an edit drawn in it is not saved, and the graph is drawn again from
## the definition with a note saying so.
func show_triggers(owner: String) -> void:
	_graph_owner = owner
	_tresult.text = ""
	_draw_triggers()


func _draw_triggers() -> void:
	_graph_data = TriggerGraph.build(model.templates, _graph_owner)
	_graph = _load_graph(_graph_holder, _graph, _graph_data)
	var g: CGEGraph = _graph.get("graph")
	g.node_created.connect(_on_trigger_graph_edited.unbind(1))
	g.node_deleted.connect(_on_trigger_graph_edited.unbind(1))
	g.link_created.connect(_on_trigger_graph_edited.unbind(3))
	g.link_deleted.connect(_on_trigger_graph_edited.unbind(1))


## The editor changed the trigger graph. Applied after the editor's command is done.
func _on_trigger_graph_edited() -> void:
	_refuse_trigger_edit.call_deferred()


func _refuse_trigger_edit() -> void:
	_draw_triggers()
	_tresult.text = "Not saved: the trigger graph only shows the triggers. Edit them in the definition text (Template tab)."


## Draws one dialogue (DialogueGraph) on the Dialogues tab. Its graph is
## editable: changes made in the editor are written to the dialogue
## (sync_dialogue) and the graph is drawn again from the definition.
func show_dialogue(id: String) -> void:
	_dgraph_id = id
	_dgraph_data = DialogueGraph.build(model.templates, id)
	_dgraph = _load_graph(_dgraph_holder, _dgraph, _dgraph_data)
	var g: CGEGraph = _dgraph.get("graph")
	g.node_created.connect(_on_dialogue_graph_edited.unbind(1))
	g.node_deleted.connect(_on_dialogue_graph_edited.unbind(1))
	g.link_created.connect(_on_dialogue_graph_edited.unbind(3))
	g.link_deleted.connect(_on_dialogue_graph_edited.unbind(1))
	_dinspect.visible = false


## The editor changed its graph. Applied after the editor's command is done.
func _on_dialogue_graph_edited() -> void:
	sync_dialogue.call_deferred()


## Shows the inspector for a dialogue node selected in the graph: its name,
## speaker and text, ready to edit.
func _inspect_dialogue_node(name: String) -> void:
	var nodes: Dictionary = model.templates.values_of(_dgraph_id).get("nodes", {})
	if not nodes.get(name) is Dictionary:
		_dinspect.visible = false
		return
	var node: Dictionary = nodes[name]
	_dinspect_node = name
	_dname.text = name
	_dspeaker.text = String(node.get("speaker", ""))
	_dtext.text = String(node.get("text", ""))
	_dinspect.visible = true


## The inspector's Apply: renames the node `old` to `new_name` and sets its
## speaker and text. The change is validated and saved like a graph edit
## (DialogueEdit); a refused one is shown and undone on screen. Returns the errors.
func edit_dialogue_node(old: String, new_name: String, speaker: String, text: String) -> PackedStringArray:
	var def: Variant = _editable_dialogue()
	if def == null:
		_dresult.text = "Not saved: the nodes of '%s' come from another template; edit them in the Template tab." % _dgraph_id
		return PackedStringArray(["the nodes are not in this template"])
	var original := (def as Dictionary).duplicate(true)
	var values: Dictionary = def["values"]
	var name := new_name.strip_edges()
	var err := DialogueEdit.rename(values, old, name)
	if err.is_empty():
		err = DialogueEdit.set_line(values, name, speaker, text)
	if not err.is_empty():
		_dresult.text = "Not saved:\n" + err
		return PackedStringArray([err])
	return _save_dialogue(def, original)


## The shown dialogue's definition, parsed, when its nodes are in this
## template; otherwise null.
func _editable_dialogue() -> Variant:
	if _dgraph == null or _dgraph_id.is_empty() or model == null or model.file_of(_dgraph_id).is_empty():
		return null
	var def: Variant = JSON.parse_string(model.definition_text(_dgraph_id))
	if not def is Dictionary or not (def as Dictionary).get("values") is Dictionary or not ((def as Dictionary)["values"] as Dictionary).has("nodes"):
		return null
	return def


## Writes a changed definition and draws the dialogue again from it.
func _save_dialogue(def: Dictionary, original: Dictionary) -> PackedStringArray:
	if def == original:
		return PackedStringArray()
	var errs := model.replace(_dgraph_id, JSON.stringify(def, "\t"))
	_dresult.text = ("Saved to %s." % model.file_of(_dgraph_id)) if errs.is_empty() else "Not saved:\n" + "\n".join(errs)
	_fill_problems()
	if selected_id == _dgraph_id:
		select(selected_id)
	show_dialogue(_dgraph_id)
	return errs


## Writes the graph editor's changes to the shown dialogue: new nodes get a
## name, links the editor drew or lost become links or unlinks, and nodes
## the editor deleted are removed. The definition is validated and written
## like any edit; then the graph is drawn again from the definition, so a
## refused change is undone on screen too. Returns the errors.
func sync_dialogue() -> PackedStringArray:
	if _dgraph == null or _dgraph_id.is_empty() or model == null or model.file_of(_dgraph_id).is_empty():
		return PackedStringArray()
	var g: CGEGraph = _dgraph.get("graph")
	var def: Variant = _editable_dialogue()
	if def == null:
		_dresult.text = "Not saved: the nodes of '%s' come from another template; edit them in the Template tab." % _dgraph_id
		show_dialogue(_dgraph_id)
		return PackedStringArray(["the nodes are not in this template"])
	var original := (def as Dictionary).duplicate(true)
	var values: Dictionary = def["values"]
	var before := DialogueEdit.pairs(values)
	# Editor node ID -> dialogue node name. Variable nodes are not dialogue nodes.
	var names := {}
	var fresh := []
	for nid: int in g.get_all_node_ids():
		var n := g.get_node(nid) as WarGraphNode
		if n == null or n.kind == "var":
			continue
		if n.node_name.is_empty():
			fresh.append(nid)
		else:
			names[nid] = n.node_name
	for nid: int in fresh:
		names[nid] = DialogueEdit.new_name(values)
		DialogueEdit.add_node(values, names[nid])
	var now := []
	for nid: int in names:
		for l in g.get_links_from(nid):
			if names.has(l.end_node_id) and not now.has([names[nid], names[l.end_node_id]]):
				now.append([names[nid], names[l.end_node_id]])
	var alive := {}
	for nid: int in names:
		alive[names[nid]] = true
	# Lost links go first (a deleted node's links are among them), then new
	# links, then the nodes the editor deleted.
	for p: Array in before:
		if not now.has(p):
			DialogueEdit.unlink(values, p[0], p[1])
	for p: Array in now:
		if not before.has(p):
			DialogueEdit.link(values, p[0], p[1])
	for name: String in (values["nodes"] as Dictionary).keys():
		if not alive.has(name):
			DialogueEdit.remove_node(values, name)
	return _save_dialogue(def, original)


## Replaces the graph editor in `holder` with one showing `data`.
func _load_graph(holder: Control, old: Control, data: Dictionary) -> Control:
	if old != null:
		holder.remove_child(old)
		old.queue_free()
	var g := (load(GRAPH_SCENE) as PackedScene).instantiate() as Control
	g.set("graph_node_ui_scene", load(NODE_UI_SCENE))
	g.set("node_class", WarGraphNode)
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(g)
	g.call("deserialize", {"nodes": data["nodes"], "links": data["links"]})
	g.connect("graph_element_selected", _on_graph_selected)
	return g


func graph_node_count() -> int:
	return (_graph_data.get("nodes", {}) as Dictionary).size()


func dialogue_node_count() -> int:
	return (_dgraph_data.get("nodes", {}) as Dictionary).size()


# --- building ------------------------------------------------------------------

func _build() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.text_submitted.connect(func(t: String) -> void: open(t))
	bar.add_child(_path)
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(func() -> void: open(_path.text))
	bar.add_child(reload)
	_status = Label.new()
	bar.add_child(_status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 260
	add_child(split)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(240, 0)
	_tree.item_selected.connect(_on_tree_selected)
	split.add_child(_tree)
	_tabs = TabContainer.new()
	split.add_child(_tabs)
	var page := VBoxContainer.new()
	page.name = "Template"
	_tabs.add_child(page)
	_info = Label.new()
	page.add_child(_info)
	_values = Tree.new()
	_values.columns = 3
	_values.hide_root = true
	_values.column_titles_visible = true
	_values.set_column_title(0, "Field")
	_values.set_column_title(1, "Value (flattened)")
	_values.set_column_title(2, "Set by")
	_values.custom_minimum_size = Vector2(0, 180)
	page.add_child(_values)
	_source = TextEdit.new()
	_source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_source.custom_minimum_size = Vector2(0, 200)
	page.add_child(_source)
	var actions := HBoxContainer.new()
	page.add_child(actions)
	for b: Array in [["Validate", validate_edit], ["Apply", apply_edit], ["Add as new template to", add_new]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		actions.add_child(btn)
	_new_file = OptionButton.new()
	actions.add_child(_new_file)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_result)
	var trig := VBoxContainer.new()
	trig.name = "Triggers"
	_tabs.add_child(trig)
	_owners = OptionButton.new()
	_owners.item_selected.connect(func(i: int) -> void: show_triggers(_owners.get_item_text(i)))
	trig.add_child(_owners)
	_graph_holder = Control.new()
	_graph_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_holder.clip_contents = true
	trig.add_child(_graph_holder)
	_tresult = Label.new()
	_tresult.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trig.add_child(_tresult)
	var dlg := VBoxContainer.new()
	dlg.name = "Dialogues"
	_tabs.add_child(dlg)
	_dialogues = OptionButton.new()
	_dialogues.item_selected.connect(func(i: int) -> void: show_dialogue(_dialogues.get_item_text(i)))
	dlg.add_child(_dialogues)
	var dhint := Label.new()
	dhint.text = "Drag from a node to another: a node with choices gets a choice to it, any other node its next. Delete a link or a node to remove it. Add Node makes node_N. Select a node to edit its name, speaker and text below the graph (do and if: Template tab). Each change is saved."
	dhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg.add_child(dhint)
	_dgraph_holder = Control.new()
	_dgraph_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dgraph_holder.clip_contents = true
	dlg.add_child(_dgraph_holder)
	_dinspect = GridContainer.new()
	_dinspect.columns = 2
	_dinspect.visible = false
	dlg.add_child(_dinspect)
	_dinspect.add_child(_inspect_label("Node name"))
	_dname = LineEdit.new()
	_dname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dinspect.add_child(_dname)
	_dinspect.add_child(_inspect_label("Speaker"))
	_dspeaker = LineEdit.new()
	_dspeaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dinspect.add_child(_dspeaker)
	_dinspect.add_child(_inspect_label("Text"))
	_dtext = LineEdit.new()
	_dtext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dinspect.add_child(_dtext)
	var apply := Button.new()
	apply.text = "Apply node"
	apply.pressed.connect(func() -> void: edit_dialogue_node(_dinspect_node, _dname.text, _dspeaker.text, _dtext.text))
	_dinspect.add_child(Control.new())
	_dinspect.add_child(apply)
	_dresult = Label.new()
	_dresult.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg.add_child(_dresult)
	_maps = MapPainter.new()
	_maps.saved.connect(_on_map_saved)
	_tabs.add_child(_maps)
	_world = OverworldPainter.new()
	_world.saved.connect(_on_map_saved)
	_tabs.add_child(_world)
	_problems = ItemList.new()
	_problems.name = "Problems"
	_tabs.add_child(_problems)


func _fill_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for kind in model.kinds():
		var k := _tree.create_item(root)
		k.set_text(0, "%s (%d)" % [kind, model.ids_of(kind).size()])
		k.set_selectable(0, false)
		k.collapsed = true
		for id in model.ids_of(kind):
			var it := k.create_child()
			it.set_text(0, id)
			it.set_metadata(0, id)
	_new_file.clear()
	for f in model.files:
		_new_file.add_item(f)


func _fill_owners() -> void:
	_owners.clear()
	for kind: String in ["overworld_map", "scenario"]:
		for id in model.ids_of(kind):
			if not (model.templates.values_of(id).get("triggers", []) as Array).is_empty():
				_owners.add_item(id)


func _fill_dialogues() -> void:
	_dialogues.clear()
	for id in model.ids_of("dialogue"):
		_dialogues.add_item(id)


func _inspect_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _fill_problems() -> void:
	_problems.clear()
	for e in model.errors:
		_problems.add_item(e)
	_status.text = "%d templates · %s" % [model.templates.ids().size() if model.templates != null else 0,
		"no problems" if model.errors.is_empty() else "%d problems" % model.errors.size()]


func _show(errs: PackedStringArray, ok_text: String) -> void:
	_result.text = ok_text if errs.is_empty() else "Not saved:\n" + "\n".join(errs)


## The painter wrote through `model`, which has reloaded itself.
func _on_map_saved(_id: String) -> void:
	_fill_tree()
	_fill_owners()
	_fill_dialogues()
	_fill_problems()


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it != null and it.get_metadata(0) != null:
		select(String(it.get_metadata(0)))


func _on_graph_selected(node: Variant) -> void:
	var el: Variant = node.get("graph_element") if node != null else null
	if el is WarGraphNode and (el as WarGraphNode).kind == "trigger" and model.file_of((el as WarGraphNode).node_name) != "":
		select((el as WarGraphNode).node_name)
	elif el is WarGraphNode and (el as WarGraphNode).kind in ["line", "choice", "end"]:
		_inspect_dialogue_node((el as WarGraphNode).node_name)
