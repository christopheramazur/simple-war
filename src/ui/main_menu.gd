extends Control

func _ready() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -180
	root.offset_top = -120
	root.offset_right = 180
	root.offset_bottom = 120
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var title: Label = Label.new()
	title.text = "Simple War"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	root.add_child(title)

	var quick_play: Button = Button.new()
	quick_play.text = "Quick Play"
	quick_play.pressed.connect(_on_quick_play_pressed)
	root.add_child(quick_play)

	var quit_game: Button = Button.new()
	quit_game.text = "Quit Game"
	quit_game.pressed.connect(_on_quit_pressed)
	root.add_child(quit_game)

func _on_quick_play_pressed() -> void:
	CampaignRuntime.start_quickplay()
	get_tree().change_scene_to_file("res://src/ui/campaign_planning.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
