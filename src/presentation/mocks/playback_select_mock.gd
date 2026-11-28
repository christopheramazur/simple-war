extends RefCounted
## Mock (sw-bafi.2): battle playback with a squad selected. Two own rifle
## squads and one enemy, a turn played back halfway, the first own squad
## selected while it watches: its selection ring and range / sight rings show
## as in Planning, and no orders are drawn.
## Render with `hx godot mock res://src/presentation/mocks/playback_select_mock.gd`.

const ONE := Fixed.ONE


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleSetup.create(1, r, 5)
	var col: PackedByteArray = s.squads.take_column(&"withdrawn")
	for row in s.squads.count():
		col[row] = 1
	s.squads.put_column(&"withdrawn", col)
	var own := BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), 70 * ONE, 48 * ONE, 0)
	BattleSetup.spawn_squad(s, 1, r.squad_index("rifle_squad"), 70 * ONE, 74 * ONE, 0)
	BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), 84 * ONE, 56 * ONE, 32768)
	Centroids.update(s)
	VisionSystem.new().run(s)
	var session := OverworldSession.new()
	var b := OverworldBattle.new()
	b.rules = r
	b.state = s
	b.engagement = 1
	session._record_turn(1, b)
	var rec: Dictionary = session.playback(1)[1]
	var root := Control.new()
	root.custom_minimum_size = Vector2(1280, 800)
	var v := ContextView.new()
	v.art = ArtSet.core()
	v.terrain_colors = ContextView.feature_colors(l.templates)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.title = "Turn 1 playing out (45%): squad selected, orders open in Planning"
	root.add_child(v)
	v.show_playback(rec, 0.45, BattleSession.observe_state(s, 1), -1, [own])
	return root
