extends Control

var deploy_button: Button

func _ready() -> void:
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 48
	layout.offset_top = 48
	layout.offset_right = -48
	layout.offset_bottom = -48
	layout.add_theme_constant_override("separation", 14)
	add_child(layout)

	var title: Label = Label.new()
	title.text = "Battle Planning"
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var label: Label = Label.new()
	label.text = "Select Army from Battleforces"
	layout.add_child(label)

	var army_button: Button = Button.new()
	var selected_army_name: String = CampaignRuntime.get_selected_army_name()
	army_button.text = "Use %s" % (selected_army_name if not selected_army_name.is_empty() else "Militia")
	army_button.toggle_mode = true
	army_button.button_pressed = true
	army_button.pressed.connect(_on_army_toggled.bind(army_button))
	layout.add_child(army_button)

	deploy_button = Button.new()
	deploy_button.text = "Deploy"
	deploy_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://src/ui/battlefield.tscn"))
	layout.add_child(deploy_button)
	_update_deploy_state(army_button.button_pressed)

func _on_army_toggled(button: Button) -> void:
	_update_deploy_state(button.button_pressed)

func _update_deploy_state(selected: bool) -> void:
	deploy_button.disabled = not selected
