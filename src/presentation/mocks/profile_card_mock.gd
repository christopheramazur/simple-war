extends RefCounted
## Mock (sw-kif): the skirmish profile card at 1280x800, the Aggressor selected.
## Render with `hx godot mock res://src/presentation/mocks/profile_card_mock.gd`.


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(1280, 800)
	var m: MainMenu = load("res://src/presentation/main_menu/main_menu.tscn").instantiate()
	root.add_child(m)
	m.ready.connect(func() -> void:
		var i := m.profiles.find("profile_aggressor")
		m._profile_pick.select(i)
		m._describe())
	return root
