extends Control

func _ready() -> void:
	var wrapper: MarginContainer = MarginContainer.new()
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_theme_constant_override("margin_left", 48)
	wrapper.add_theme_constant_override("margin_top", 48)
	wrapper.add_theme_constant_override("margin_right", 48)
	wrapper.add_theme_constant_override("margin_bottom", 48)
	add_child(wrapper)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 20)
	wrapper.add_child(layout)

	var title: Label = Label.new()
	title.text = "Campaign Planning"
	title.add_theme_font_size_override("font_size", 34)
	layout.add_child(title)

	var summary: Label = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = "A single Battle against a single opposing commander, with pre-built armies."
	layout.add_child(summary)

	layout.add_spacer(false)
	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 12)
	layout.add_child(button_row)

	var back_button: Button = Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(func() -> void: SceneRoutes.go_to_main_menu(get_tree()))
	button_row.add_child(back_button)

	var embark_button: Button = Button.new()
	embark_button.text = "Embark"
	embark_button.pressed.connect(func() -> void:
		CampaignRuntime.submit_intent("campaign.embark")
		SceneRoutes.go_to_sector_map(get_tree())
	)
	button_row.add_child(embark_button)
