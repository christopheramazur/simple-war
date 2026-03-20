extends Control
const MENU_OVERLAY_SCRIPT := preload("res://src/ui/menu_overlay.gd")

func _ready() -> void:
	add_child(MENU_OVERLAY_SCRIPT.new())
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 12)
	layout.offset_left = 48
	layout.offset_top = 48
	layout.offset_right = -48
	layout.offset_bottom = -48
	add_child(layout)

	var title: Label = Label.new()
	title.text = "Armybuilding"
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var prompt: Label = Label.new()
	prompt.text = "Select one army to complete this activity."
	layout.add_child(prompt)

	var militia_button: Button = Button.new()
	militia_button.text = "Militia (prebuilt)"
	militia_button.pressed.connect(_on_militia_selected)
	layout.add_child(militia_button)

	var back_button: Button = Button.new()
	back_button.text = "Back to Sector Map"
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://src/ui/sector_map.tscn"))
	layout.add_child(back_button)

func _on_militia_selected() -> void:
	CampaignRuntime.submit_intent("armybuilding.select", {"army_name": "Militia"})
	get_tree().change_scene_to_file("res://src/ui/sector_map.tscn")
