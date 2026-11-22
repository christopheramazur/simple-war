extends RefCounted
## Mock (sw-7o7): the reaction window at 1280x800 with enemy attack
## telegraphs (arrow + "▶ damage" box on each own squad under committed
## fire). Real data: a seeded duel played to its first telegraph. Render with
## `hx godot mock res://src/presentation/mocks/telegraph_mock.gd`.


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	var s := BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	var c := {1: ZoneController.new(1), 2: ZoneController.new(2, {"fall_back_pct": 60})}
	var player := 1
	for _t in 8:
		for p in s.players():
			s.submit_orders(p, c[p].orders(s.observe(p)))
		for p in s.players():
			s.ready(p)
		var found := false
		for p in s.players():
			if not s.telegraphs(p).is_empty():
				player = p
				found = true
		if found:
			break
		s.ready(1)
		s.ready(2)
		s.ready(1)
		s.ready(2)
	var root := Control.new()
	root.custom_minimum_size = Vector2(1280, 800)
	var v := ContextView.new()
	v.art = ArtSet.core()
	v.terrain_colors = ContextView.feature_colors(l.templates)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(v)
	v.show_battle(s.observe(player), {"telegraphs": s.telegraphs(player), "terrain": s.state.rules})
	return root
