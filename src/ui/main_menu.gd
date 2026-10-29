extends Control

## Start menu: New Game, Continue, Options, Quit.

@onready var new_game_btn: Button = %NewGameButton
@onready var continue_btn: Button = %ContinueButton
@onready var options_btn: Button = %OptionsButton
@onready var quit_btn: Button = %QuitButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	options_btn.pressed.connect(_on_options)
	quit_btn.pressed.connect(_on_quit)
	new_game_btn.grab_focus()


func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://src/ui/scenario_select.tscn")


func _on_continue() -> void:
	_status("No saved campaign found yet.")


func _on_options() -> void:
	_status("Options screen coming soon.")


func _on_quit() -> void:
	get_tree().quit()


func _status(msg: String) -> void:
	status_label.text = msg
