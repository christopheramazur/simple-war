extends Control

## Placeholder scenario-select screen for the start-menu scaffold.
## The real data-driven picker arrives in a follow-up task.

@onready var back_btn: Button = %BackButton


func _ready() -> void:
	back_btn.pressed.connect(_on_back)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
