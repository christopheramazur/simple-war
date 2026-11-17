extends RefCounted
## Mock: steering a garrison like a commander (sw-kys.8): selected, its reach
## lit, a two-leg route drawn. Render with
## `hx godot mock res://src/presentation/mocks/convoy_steer_mock.gd`.

const FRAME := Vector2(1100, 620)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var holder := Control.new()
	holder.size = FRAME
	holder.clip_contents = true
	root.add_child(holder)
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
	w.record_match = false
	holder.add_child(w)
	w.ready.connect(func() -> void:
		var me: Dictionary = {}
		for c: Dictionary in w.session.observe(1)["commanders"]:
			if c["player"] == 1:
				me = c
		var at: int = me["plot"]
		Detachments.drop(w.session.state, int(me["id"]), at)
		w._on_hex_clicked(at, MOUSE_BUTTON_LEFT)
		w._on_hex_clicked(at, MOUSE_BUTTON_LEFT)
		w._on_hex_clicked(Hex.plot(9, 4, w.session.rules.width), MOUSE_BUTTON_RIGHT)
		w._on_hex_clicked(Hex.plot(9, 7, w.session.rules.width), MOUSE_BUTTON_RIGHT, true))
	return root
