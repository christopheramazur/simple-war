extends Control

@onready var army_button: Button = %ArmyButton
@onready var deploy_button: Button = %DeployButton


func _ready() -> void:
	var selected_army_name: String = CampaignRuntime.get_selected_army_name()
	army_button.text = "Use %s" % (selected_army_name if not selected_army_name.is_empty() else "Militia")
	army_button.pressed.connect(_on_army_toggled)
	deploy_button.pressed.connect(_on_deploy_pressed)
	_update_deploy_state(army_button.button_pressed)


func _on_army_toggled() -> void:
	_update_deploy_state(army_button.button_pressed)


func _update_deploy_state(selected: bool) -> void:
	deploy_button.disabled = not selected


func _on_deploy_pressed() -> void:
	var result: Dictionary = CampaignRuntime.submit_intent("battleplanning.start")
	if result.get("ok", false):
		get_tree().change_scene_to_file("res://src/ui/battlefield.tscn")
