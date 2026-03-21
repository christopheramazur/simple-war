extends Control

const MENU_OVERLAY_SCRIPT := preload("res://src/ui/menu_overlay.gd")

@onready var militia_button: Button = %MilitiaButton
@onready var back_button: Button = %BackButton

func _ready() -> void:
	add_child(MENU_OVERLAY_SCRIPT.new())
	militia_button.pressed.connect(_on_militia_selected)
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://src/ui/sector_map.tscn")

func _on_militia_selected() -> void:
	CampaignRuntime.submit_intent("armybuilding.select", {"army_name": "Militia"})
	get_tree().change_scene_to_file("res://src/ui/sector_map.tscn")
