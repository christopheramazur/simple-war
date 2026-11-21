extends RefCounted
## Mock (sw-opt): the options dialog in the logical viewport of a 1280x800
## window at 200% UI scale — 640x400. The dialog body is ~600px tall at 100%,
## so before the fit fix it overflows this viewport and Close falls off-screen;
## after, the body scrolls vertically inside the viewport and Close is
## reachable at the bottom (XAG 101: 200% without lost content). Render with:
##   hx godot mock res://src/presentation/mocks/options_fit_mock.gd
## The frame is the logical viewport, so layout matches the real 200% case.

const FRAME := Vector2(640, 400)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	var o := OptionsScreen.open_over(screen)
	# Once the fit scroll exists, show the bottom of the dialog (Close). Before
	# the fix there is no scroll, so the centred dialog simply overflows.
	o.ready.connect(func() -> void:
		var s := o.find_child("Scroll", true, false) as ScrollContainer
		if s == null:
			return
		var v := s.get_v_scroll_bar()
		v.changed.connect(func() -> void:
			if v.value < v.max_value:
				s.scroll_vertical = int(v.max_value))
	, CONNECT_DEFERRED)
	return root
