extends Control

## Main Menu: Quick Play and Quit Game buttons.

@onready var quick_play_btn: Button = %QuickPlayButton
@onready var quit_btn: Button = %QuitButton


func _ready() -> void:
	quick_play_btn.pressed.connect(_on_quick_play)
	quit_btn.pressed.connect(_on_quit)
	quick_play_btn.grab_focus()


func _on_quick_play() -> void:
	get_tree().change_scene_to_file("res://src/ui/scenario_select.tscn")


func _on_quit() -> void:
	get_tree().quit()
