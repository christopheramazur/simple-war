extends RefCounted
## Mock: readable combat playback (sw-aba). Two rifle squads trade fire at
## 18 m: two moments of the recorded turn up close (projectiles in flight
## with recoil, hits flashing with damage numbers, misses flying past), then
## the second at the whole field's scale.
## Render with `hx godot mock res://src/presentation/mocks/combat_fx_mock.gd`.

const ONE := Fixed.ONE


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleSetup.create(1, r, 5)
	var col: PackedByteArray = s.squads.take_column(&"withdrawn")
	for row in s.squads.count():
		col[row] = 1
	s.squads.put_column(&"withdrawn", col)
	BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), 82 * ONE, 50 * ONE, 0)
	BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), 100 * ONE, 51 * ONE, 32768)
	Centroids.update(s)
	VisionSystem.new().run(s)
	var session := OverworldSession.new()
	var b := OverworldBattle.new()
	b.rules = r
	b.state = s
	b.engagement = 1
	session._record_turn(1, b)
	var rec: Dictionary = session.playback(1)[1]
	# A zoomed-in rec: the fight's corner of the field only.
	var root := HBoxContainer.new()
	root.custom_minimum_size = Vector2(1500, 560)
	var n := float((rec["frames"] as Array).size() - 1)
	var fx := BattleFx.from_playback(rec)
	# Mid-flight before the first volley that hits lands, then just after.
	var picks: Array[float] = [n * 0.25, n * 0.25 + 4.0]
	for f in range(6, int(n)):
		if fx.flashes(f).size() >= 1 and fx.dying(f).is_empty():
			picks = [float(f) - 2.0, float(f) + 0.5]
			break
	for f in picks:
		var v := ContextView.new()
		v.art = ArtSet.core()
		v.terrain_colors = ContextView.feature_colors(l.templates)
		v.custom_minimum_size = Vector2(500, 560)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.title = "frame %d" % int(f)
		root.add_child(v)
		v.show_playback(_crop(rec.duplicate(), Rect2(72, 34, 40, 32)), f / n, BattleSession.observe_state(s, 1))
	var whole := ContextView.new()
	whole.art = ArtSet.core()
	whole.custom_minimum_size = Vector2(500, 560)
	whole.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	whole.title = "frame %d, whole field" % int(picks[1])
	root.add_child(whole)
	whole.show_playback(rec, picks[1] / n, BattleSession.observe_state(s, 1))
	return root


## The rec moved and cut to `box` (metres) so the mock shows the fight up close.
static func _crop(rec: Dictionary, box: Rect2) -> Dictionary:
	var frames := []
	for fr: Dictionary in rec["frames"]:
		var out := {}
		for id: int in fr:
			var d: Dictionary = (fr[id] as Dictionary).duplicate()
			var pts := []
			for p: Vector2 in d["units"]:
				pts.append(p - box.position)
			d["units"] = pts
			out[id] = d
		frames.append(out)
	rec["frames"] = frames
	rec["width"] = int(box.size.x)
	rec["height"] = int(box.size.y)
	rec["rules"] = null
	return rec
