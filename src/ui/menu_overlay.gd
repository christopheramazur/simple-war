extends CanvasLayer

func _ready() -> void:
	layer = 100
	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.position = Vector2(1160, 16)
	menu_button.pressed.connect(_show_menu.bind(menu_button))
	add_child(menu_button)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_show_menu(self)

func _show_menu(anchor_node: Node) -> void:
	var popup := PopupMenu.new()
	popup.add_item("Main Menu", 1)
	popup.add_item("Settings (Placeholder)", 2)
	popup.add_separator()
	popup.add_item("Exit Game", 3)
	popup.id_pressed.connect(_on_menu_item_pressed)
	add_child(popup)

	if anchor_node is Control:
		var control := anchor_node as Control
		var pos := control.global_position + Vector2(0, control.size.y + 4)
		popup.position = Vector2i(pos)
	else:
		popup.position = Vector2i(1060, 56)
	popup.popup()

func _on_menu_item_pressed(id: int) -> void:
	match id:
		1:
			SceneRoutes.go_to_main_menu(get_tree())
		2:
			push_warning("Settings are not implemented in PoC yet.")
		3:
			get_tree().quit()
