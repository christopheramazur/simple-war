extends Control

const MENU_OVERLAY_SCRIPT := preload("res://src/ui/menu_overlay.gd")
const _SectorMapData := preload("res://src/campaign/sector_map_data.gd")

var _map_data: Dictionary = {}

@onready var plot_labels_layer: Control = %PlotLabelsLayer
@onready var map_title: Label = %MapTitle
@onready var note_label: Label = %NoteLabel
@onready var commander_marker: ColorRect = %CommanderMarker
@onready var army_marker: ColorRect = %ArmyMarker
@onready var begin_button: Button = %BeginButton
@onready var move_button: Button = %MoveButton
@onready var start_battle_button: Button = %StartBattleButton

func _ready() -> void:
	_map_data = _SectorMapData.load_map_by_id(_SectorMapData.POC_MAP_ID)
	map_title.text = str(_map_data.get("display_name", "Sector Map"))
	_populate_plot_labels()
	add_child(MENU_OVERLAY_SCRIPT.new())
	begin_button.pressed.connect(_on_begin_activity_pressed)
	move_button.pressed.connect(_on_move_pressed)
	start_battle_button.pressed.connect(_on_start_battle_pressed)
	_refresh_ui()

func _populate_plot_labels() -> void:
	for c: Node in plot_labels_layer.get_children():
		c.queue_free()
	var nodes: Dictionary = _map_data.get("nodes", {})
	var meta: Dictionary = _map_data.get("node_meta", {})
	for plot_id: Variant in nodes.keys():
		var pos: Vector2 = nodes[plot_id]
		var plot_label: Label = Label.new()
		var nm: Dictionary = meta.get(plot_id, {})
		plot_label.text = str(nm.get("title", str(plot_id)))
		plot_label.position = pos + Vector2(-60, 50)
		plot_labels_layer.add_child(plot_label)

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
	SceneRoutes.go(get_tree(), str(projection.get("route_target", SceneRoutes.ARMYBUILDING)))

func _on_move_pressed() -> void:
	var result: Dictionary = CampaignRuntime.submit_intent("sector.move_to_battle")
	if result.get("ok", false):
		_refresh_ui()

func _on_start_battle_pressed() -> void:
	SceneRoutes.go_to_battle_planning(get_tree())
