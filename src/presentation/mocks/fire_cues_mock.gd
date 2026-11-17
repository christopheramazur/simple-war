extends RefCounted
## Mock: fire cues (sw-kys.7). A mortar team selected; a scout spots an enemy
## rifle squad 80 m out ("in range", "spotted by allies"); a second enemy is
## out of reach. Render with
## `hx godot mock res://src/presentation/mocks/fire_cues_mock.gd`.

const ONE := Fixed.ONE


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleSetup.create(1, r, 5)
	var col: PackedByteArray = s.squads.take_column(&"withdrawn")
	for row in s.squads.count():
		col[row] = 1
	s.squads.put_column(&"withdrawn", col)
	var m := BattleSetup.spawn_squad(s, 1, r.squad_index("mortar_team"), 70 * ONE, 50 * ONE, 0)
	BattleSetup.spawn_squad(s, 1, r.squad_index("scout_team"), 125 * ONE, 66 * ONE, 0)
	BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), 150 * ONE, 50 * ONE, 32768)
	BattleSetup.spawn_squad(s, 2, r.squad_index("heavy_weapons_team"), 150 * ONE, 25 * ONE, 32768)
	Centroids.update(s)
	VisionSystem.new().run(s)
	var root := Control.new()
	root.custom_minimum_size = Vector2(900, 520)
	var v := ContextView.new()
	v.art = ArtSet.core()
	v.terrain_colors = ContextView.feature_colors(l.templates)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(v)
	v.show_battle(BattleSession.observe_state(s, 1), {"selected": [m], "terrain": r})
	return root
