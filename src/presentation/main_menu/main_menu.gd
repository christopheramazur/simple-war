class_name MainMenu
extends Control
## The game's start screen (sw-ip8.6): Story (the Angelfall slice) or a
## Skirmish against an AI controller profile on a skirmish map (the AI
## factory's maps, GDD 05 §5.4). Presentation only: it reads the core
## package to list profiles and maps, then hands a configured WarRoom the
## choice. Map editor opens the War Data screen on its Maps tab (the same
## panel the Godot editor plugin shows). Runs standalone (F6).

const STORY_SCENE := "res://src/presentation/angelfall/angelfall.tscn"
const WAR_ROOM_SCENE := "res://src/presentation/war_room/war_room.tscn"
const MENU_SCENE := "res://src/presentation/main_menu/main_menu.tscn"
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
	if GameSettings.saved():
		GameSettings.apply(get_window())
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
	var editor := Button.new()
	editor.text = "Map editor"
	editor.custom_minimum_size = Vector2(0, 40)
	editor.pressed.connect(start_editor)
	col.add_child(editor)
	var load_game := Button.new()
	load_game.name = "Load"
	load_game.text = "Load game"
	load_game.custom_minimum_size = Vector2(0, 40)
	load_game.pressed.connect(open_saves)
	col.add_child(load_game)
	var replays := Button.new()
	replays.name = "Replays"
	replays.text = "Replays"
	replays.custom_minimum_size = Vector2(0, 40)
	replays.pressed.connect(open_replays)
	col.add_child(replays)
	var options := Button.new()
	options.name = "Options"
	options.text = "Options"
	options.custom_minimum_size = Vector2(0, 40)
	options.pressed.connect(func() -> void: OptionsScreen.open_over(self))
	col.add_child(options)
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


## A war room on a saved game (MatchDriver.load_game), or null with the
## reason in MatchDriver.last_error.
static func load_room(path: String) -> WarRoom:
	var driver := MatchDriver.load_game(path)
	if driver == null:
		return null
	var w: WarRoom = load(WAR_ROOM_SCENE).instantiate()
	w.driver = driver
	w.ai_profile = String(driver.meta.get("profile", ""))
	w.map_seed = int(driver.meta.get("seed", 1))
	return w


## A war room watching a recorded match (MatchReplay.open), or null with
## the reason in MatchReplay.last_error.
static func replay_room(dir: String) -> WarRoom:
	var r := MatchReplay.open(dir)
	if r == null:
		return null
	var w: WarRoom = load(WAR_ROOM_SCENE).instantiate()
	w.replay = r
	w.player = int(r.info.get("human", 1))
	w.record_match = false
	return w


## The recorded matches, newest first, over the menu. Picking one opens it
## as a replay.
func open_replays() -> Control:
	var parts := _list_overlay("Replays", "Replays")
	var list: VBoxContainer = parts["list"]
	var said: Label = parts["said"]
	var found := MatchReplay.list()
	if found.is_empty():
		list.add_child(_dim("No recorded matches yet. Every skirmish started from this menu is recorded."))
	for m: Dictionary in found:
		var b := Button.new()
		var map := String(m["map"])
		var versus := String(m["opponent"])
		b.text = "%s  ·  seed %d%s  ·  %s" % [_name(map) if _templates != null and _templates.has(map) else map, int(m["seed"]),
			"" if versus.is_empty() else " vs " + (_name(versus) if _templates != null and _templates.has(versus) else versus), String(m["started"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			var w := replay_room(String(m["dir"]))
			if w == null:
				said.text = "This match can not be replayed: " + MatchReplay.last_error
				return
			w.use_settings = true
			_swap_to.call_deferred(w))
		list.add_child(b)
	return parts["over"]


## A list over the menu with a heading, a scrolling list, a line for a
## refusal and a Back button: {"over", "list", "said"}.
func _list_overlay(node_name: String, title: String) -> Dictionary:
	var over := Control.new()
	over.name = node_name
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.05, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_content_margin_all(24)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(_heading(title))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var said := _dim("")
	said.add_theme_color_override("font_color", Color("e8735f"))
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(said)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(over.queue_free)
	col.add_child(close)
	add_child(over)
	return {"over": over, "list": list, "said": said}


## The list of saved games, newest first, over the menu. Picking one loads
## it.
func open_saves() -> Control:
	var parts := _list_overlay("Saves", "Load game")
	var list: VBoxContainer = parts["list"]
	var said: Label = parts["said"]
	var found := MatchDriver.saves()
	if found.is_empty():
		list.add_child(_dim("No saved games yet. A skirmish saves itself every turn, and the war room has a Save button."))
	for sv: Dictionary in found:
		var b := Button.new()
		var map := String(sv["map"])
		var versus := String(sv["profile"])
		b.text = "%s  ·  %s, turn %d%s  ·  %s" % ["Autosave" if sv["slot"] == MatchDriver.AUTOSAVE else "Save",
			_name(map) if _templates != null and _templates.has(map) else map, int(sv["turn"]),
			"" if versus.is_empty() else " vs " + (_name(versus) if _templates != null and _templates.has(versus) else versus), String(sv["saved"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			var w := load_room(String(sv["path"]))
			if w == null:
				said.text = "This save can not be loaded: " + MatchDriver.last_error
				return
			w.use_settings = true
			w.autosave = true
			_swap_to.call_deferred(w))
		list.add_child(b)
	return parts["over"]


## The map editor as a screen: the War Data panel on its Maps tab, with a
## way back to this menu and "Play this map" (MapPlaytest) against a chosen
## controller profile.
static func editor_screen() -> Control:
	var root := Control.new()
	root.name = "MapEditor"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("12151a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(col)
	var bar := HBoxContainer.new()
	col.add_child(bar)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(func() -> void: root.get_tree().change_scene_to_file.call_deferred(MENU_SCENE))
	bar.add_child(back)
	var title := Label.new()
	title.text = "Map editor"
	bar.add_child(title)
	var panel := WarDataPanel.new()
	panel.name = "WarData"
	var opponent := OptionButton.new()
	opponent.name = "Opponent"
	opponent.tooltip_text = "The AI that plays player 2 in a playtest"
	var play := Button.new()
	play.name = "Play"
	play.text = "Play this map"
	play.tooltip_text = "Fight a battle on the open map as it is painted now, saved or not"
	var said := Label.new()
	said.name = "Said"
	said.add_theme_color_override("font_color", Color("e8735f"))
	bar.add_child(VSeparator.new())
	bar.add_child(opponent)
	bar.add_child(play)
	bar.add_child(said)
	panel.ready.connect(func() -> void:
		panel.show_maps()
		if panel.model.templates != null:
			for id in panel.model.ids_of("controller_profile"):
				opponent.add_item(id)
				if id == "profile_utility":
					opponent.select(opponent.item_count - 1))
	play.pressed.connect(func() -> void:
		var profile := opponent.get_item_text(opponent.selected) if opponent.selected >= 0 else ""
		said.text = play_map(root, panel, profile))
	col.add_child(panel)
	return root


## Opens a playtest of the editor's open map over the editor screen `root`.
## Returns why not, or "".
static func play_map(root: Control, panel: WarDataPanel, profile: String) -> String:
	var canvas := panel.painter().canvas
	if canvas == null:
		return "Open a map first."
	var made := MapPlaytest.start(panel.model, canvas, 1, panel.painter().scenario)
	if made["session"] == null:
		return "Can't play this map: " + "; ".join(made["errors"] as PackedStringArray)
	var editor := root.get_child(1) as Control
	var over := VBoxContainer.new()
	over.name = "Playtest"
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bar := HBoxContainer.new()
	over.add_child(bar)
	var back := Button.new()
	back.text = "Back to the editor"
	back.pressed.connect(func() -> void:
		editor.visible = true
		over.queue_free())
	bar.add_child(back)
	var title := Label.new()
	var sc := panel.painter().scenario
	title.text = "Playtest: %s%s%s" % [canvas.name, "" if sc == null else "  ·  scenario " + sc.id,
		"  (unsaved changes)" if canvas.dirty or (sc != null and sc.dirty) else ""]
	bar.add_child(title)
	var w: WarRoom = load(WAR_ROOM_SCENE).instantiate()
	w.session = made["session"]
	w.drives_turns = true
	w.use_settings = true
	w.ai_profile = profile
	w.menu_scene = ""
	w.record_match = false
	w.size_flags_vertical = Control.SIZE_EXPAND_FILL
	w.ready.connect(func() -> void: w.contexts.tab_in())
	over.add_child(w)
	editor.visible = false
	root.add_child(over)
	return ""


func start_editor() -> void:
	_swap_to.call_deferred(editor_screen())


func start_skirmish(profile: String, map: String, seed_value: int) -> void:
	var w := skirmish_room(profile, map, seed_value)
	w.use_settings = true  # turns play out over the player's chosen time
	w.autosave = true
	_swap_to.call_deferred(w)


func _swap_to(scene: Node) -> void:
	var tree := get_tree()
	tree.root.add_child(scene)
	tree.current_scene = scene
	queue_free()
