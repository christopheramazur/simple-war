extends Control

const MENU_OVERLAY_SCRIPT := preload("res://src/ui/menu_overlay.gd")
const SectorMapData := preload("res://src/campaign/sector_map_data.gd")

var _map_data: Dictionary = {}

var note_label: Label
var commander_marker: ColorRect
var army_marker: ColorRect
var begin_button: Button
var move_button: Button
var start_battle_button: Button

func _ready() -> void:
	_map_data = SectorMapData.load_map_by_id(SectorMapData.POC_MAP_ID)
	_create_canvas()
	add_child(MENU_OVERLAY_SCRIPT.new())
	_refresh_ui()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05), true)
	var nodes: Dictionary = _map_data.get("nodes", {})
	for plot_id: Variant in nodes.keys():
		var pos: Vector2 = nodes[plot_id]
		var meta: Dictionary = _map_data.get("node_meta", {}).get(plot_id, {})
		var act: String = str(meta.get("activity_type", ""))
		var fill: Color = Color(0.2, 0.4, 0.8, 0.3) if act == "armybuilding" else Color(0.8, 0.2, 0.2, 0.3)
		draw_circle(pos, 40.0, fill)
	for conn: Variant in _map_data.get("connections", []):
		if typeof(conn) != TYPE_DICTIONARY:
			continue
		var from_id: String = str(conn.get("from", ""))
		var to_id: String = str(conn.get("to", ""))
		var p1: Vector2 = nodes.get(from_id, Vector2.ZERO)
		var p2: Vector2 = nodes.get(to_id, Vector2.ZERO)
		draw_line(p1, p2, Color(0.7, 0.7, 0.8), 2.0, true)

func _create_canvas() -> void:
	var map_title: String = str(_map_data.get("display_name", "Sector Map"))
	var title: Label = Label.new()
	title.text = map_title
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 32)
	add_child(title)

	var nodes: Dictionary = _map_data.get("nodes", {})
	var meta: Dictionary = _map_data.get("node_meta", {})
	for plot_id: Variant in nodes.keys():
		var pos: Vector2 = nodes[plot_id]
		var plot_label: Label = Label.new()
		var nm: Dictionary = meta.get(plot_id, {})
		plot_label.text = str(nm.get("title", str(plot_id)))
		plot_label.position = pos + Vector2(-60, 50)
		add_child(plot_label)

	commander_marker = ColorRect.new()
	commander_marker.color = Color(1.0, 0.85, 0.35)
	commander_marker.size = Vector2(16, 16)
	add_child(commander_marker)

	army_marker = ColorRect.new()
	army_marker.color = Color(0.4, 0.9, 0.5)
	army_marker.size = Vector2(12, 12)
	add_child(army_marker)

	note_label = Label.new()
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.position = Vector2(24, 560)
	note_label.size = Vector2(700, 120)
	add_child(note_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.position = Vector2(840, 650)
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)

	begin_button = Button.new()
	begin_button.text = "Begin Activity"
	begin_button.pressed.connect(_on_begin_activity_pressed)
	buttons.add_child(begin_button)

	move_button = Button.new()
	move_button.text = "Move Here"
	move_button.pressed.connect(_on_move_pressed)
	buttons.add_child(move_button)

	start_battle_button = Button.new()
	start_battle_button.text = "Start Battle"
	start_battle_button.pressed.connect(_on_start_battle_pressed)
	buttons.add_child(start_battle_button)

func _refresh_ui() -> void:
	var projection: Dictionary = CampaignRuntime.get_sector_projection()
	var army_selected: bool = projection.get("army_selected", false)
	var plot_id: String = str(projection.get("current_plot_id", "armybuilding"))
	var nodes: Dictionary = _map_data.get("nodes", {})
	var commander_position: Vector2 = nodes.get(plot_id, Vector2.ZERO)
	commander_marker.position = commander_position - (commander_marker.size * 0.5)
	army_marker.visible = army_selected
	army_marker.position = commander_position + Vector2(14, -4)
	note_label.text = str(projection.get("note_text", "Plan your next action."))
	begin_button.visible = projection.get("can_begin_activity", false)
	move_button.visible = projection.get("can_move", false)
	start_battle_button.visible = projection.get("can_start_battle", false)
	queue_redraw()

func _on_begin_activity_pressed() -> void:
	var projection: Dictionary = CampaignRuntime.get_sector_projection()
	get_tree().change_scene_to_file(str(projection.get("route_target", "res://src/ui/armybuilding.tscn")))

func _on_move_pressed() -> void:
	var result: Dictionary = CampaignRuntime.submit_intent("sector.move_to_battle")
	if result.get("ok", false):
		_refresh_ui()

func _on_start_battle_pressed() -> void:
	get_tree().change_scene_to_file("res://src/ui/battle_planning.tscn")
