class_name MainMenu
extends Control
## The game's start screen (sw-ip8.6): Story (the Angelfall slice) or a
## Skirmish against an AI controller profile on a skirmish map (the AI
## factory's maps, GDD 05 §5.4). Presentation only: it reads the core
## package to list profiles and maps, then hands a configured WarRoom the
## choice. Runs standalone (F6).

const STORY_SCENE := "res://src/presentation/angelfall/angelfall.tscn"
const WAR_ROOM_SCENE := "res://src/presentation/war_room/war_room.tscn"
## The map the factory plays by default (hx.factory DEFAULTS["scenario"]).
const FACTORY_MAP := "skirmish_seeded"
const PANEL: Color = Color("1d2128")
const DIM: Color = Color("8a93a3")

## Profile and map template IDs offered, in menu order.
var profiles: PackedStringArray = PackedStringArray()
var maps: PackedStringArray = PackedStringArray()

var _templates: TemplateTable
var _profile_pick: OptionButton
var _profile_text: Label
var _map_pick: OptionButton
var _seed: SpinBox
var _error: Label


func _ready() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	if l.is_valid():
		_templates = l.templates
		_collect()
	_build_ui()
	if _templates == null:
		_error.text = "Content failed to load: " + "; ".join(l.errors)


## Controller profiles, and mirror maps (the skirmish maps) with the factory's
## map first.
func _collect() -> void:
	var ids := _templates.ids()
	ids.sort()
	for id in ids:
		if _templates.is_abstract(id):
			continue
		match _templates.kind_of(id):
			"controller_profile":
				profiles.append(id)
			"overworld_map":
				if _templates.values_of(id).get("mirror", false):
					maps.append(id)
	if maps.has(FACTORY_MAP):
		maps.remove_at(maps.find(FACTORY_MAP))
		maps.insert(0, FACTORY_MAP)
	if profiles.has("profile_utility"):
		profiles.remove_at(profiles.find("profile_utility"))
		profiles.insert(0, "profile_utility")


func _name(id: String) -> String:
	return String(_templates.values_of(id).get("name", id)) if _templates != null else id


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("12151a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_content_margin_all(24)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Simple War"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(HSeparator.new())
	var story := Button.new()
	story.text = "Story: Angelfall"
	story.custom_minimum_size = Vector2(0, 40)
	story.pressed.connect(start_story)
	col.add_child(story)
	col.add_child(HSeparator.new())
	col.add_child(_heading("Skirmish"))
	col.add_child(_dim("Opponent"))
	_profile_pick = OptionButton.new()
	for id in profiles:
		_profile_pick.add_item(_name(id))
	_profile_pick.item_selected.connect(func(_i: int) -> void: _describe())
	col.add_child(_profile_pick)
	_profile_text = _dim("")
	_profile_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_text.custom_minimum_size = Vector2(372, 0)
	col.add_child(_profile_text)
	col.add_child(_dim("Map"))
	_map_pick = OptionButton.new()
	for id in maps:
		_map_pick.add_item(_name(id) + (" (AI factory map)" if id == FACTORY_MAP else ""))
	col.add_child(_map_pick)
	var seed_row := HBoxContainer.new()
	seed_row.add_child(_dim("Seed"))
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 999999
	_seed.value = 1
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed)
	var roll := Button.new()
	roll.text = "Random"
	roll.pressed.connect(func() -> void: _seed.value = randi_range(1, 999999))
	seed_row.add_child(roll)
	col.add_child(seed_row)
	var go := Button.new()
	go.text = "Start skirmish"
	go.custom_minimum_size = Vector2(0, 40)
	go.disabled = profiles.is_empty() or maps.is_empty()
	go.pressed.connect(func() -> void: start_skirmish(_selected(profiles, _profile_pick),
		_selected(maps, _map_pick), int(_seed.value)))
	col.add_child(go)
	col.add_child(HSeparator.new())
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(quit)
	_error = _dim("")
	_error.add_theme_color_override("font_color", Color("e8735f"))
	col.add_child(_error)
	_describe()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	return l


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	return l


func _selected(ids: PackedStringArray, pick: OptionButton) -> String:
	return ids[pick.selected] if pick.selected >= 0 and pick.selected < ids.size() else ""


func _describe() -> void:
	var id := _selected(profiles, _profile_pick)
	_profile_text.text = String(_templates.values_of(id).get("text", "")) if not id.is_empty() else ""


func start_story() -> void:
	get_tree().change_scene_to_file.call_deferred(STORY_SCENE)


## A war room for a skirmish: player 1 against `profile` on `map`.
static func skirmish_room(profile: String, map: String, seed_value: int) -> WarRoom:
	var w: WarRoom = load(WAR_ROOM_SCENE).instantiate()
	w.map_id = map
	w.map_seed = seed_value
	w.ai_profile = profile
	return w


func start_skirmish(profile: String, map: String, seed_value: int) -> void:
	_swap_to.call_deferred(skirmish_room(profile, map, seed_value))


func _swap_to(scene: Node) -> void:
	var tree := get_tree()
	tree.root.add_child(scene)
	tree.current_scene = scene
	queue_free()
