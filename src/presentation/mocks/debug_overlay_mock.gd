extends RefCounted
## Mock: the workshop debug overlay (sw-tho3.6, U1 B6). A workshop scenario
## on the core duel_crossroads map, one turn in: a rifle squad trades fire
## with an enemy squad (lines of fire, victims, holds), a second squad
## walks across the field on a route, a far enemy is out of reach (grey
## line). Left: the default layers; right: zoomed in with large labels.
## Render with `hx godot mock res://src/presentation/mocks/debug_overlay_mock.gd`.

const SCENARIO: Dictionary = {
	"id": "debug_overlay_mock",
	"component": "overlay",
	"doc": "Mock scene for the debug overlay.",
	"status": "pending",
	"package": "core",
	"map": "duel_crossroads",
	"seed": 3,
	"turns": 1,
	"squads": [
		{"key": "gunners", "player": 1, "squad": "rifle_squad", "at": [78, 50], "facing": 0},
		{"key": "walkers", "player": 1, "squad": "rifle_squad", "at": [30, 20], "facing": 0},
		{"key": "enemy", "player": 2, "squad": "rifle_squad", "at": [98, 52], "facing": 180},
		{"key": "far", "player": 2, "squad": "heavy_weapons_team", "at": [112, 30], "facing": 180},
	],
	"script": {
		"1": [
			{"squad": "gunners", "type": "attack_move", "x": 100, "y": 52},
			{"squad": "walkers", "type": "move", "x": 140, "y": 80},
		],
	},
	"probes": [],
}


static func build() -> Control:
	var sc := WorkshopScenario.from_dict(SCENARIO, "debug_overlay_mock")
	var run := WorkshopRun.execute(sc, WorkshopScenario.BASE, true, true)
	var root := HBoxContainer.new()
	root.custom_minimum_size = Vector2(1500, 640)
	if not run.is_ok():
		var err := Label.new()
		err.text = "\n".join(run.errors)
		root.add_child(err)
		return root
	var last := run.frame_turn.size() - 1
	var obs := BattleSession.observe_state(run.state, 0)
	var layouts: Array = [
		{"title": "default layers, frame %d" % last, "zoom": 1.0, "labels": false},
		{"title": "zoomed, large labels", "zoom": 2.4, "labels": true},
	]
	for lay: Dictionary in layouts:
		var v := ContextView.new()
		v.art = ArtSet.core()
		v.terrain_colors = ContextView.feature_colors(WorkshopRun.loader_for("core").templates)
		v.custom_minimum_size = Vector2(740, 640)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.title = lay["title"]
		root.add_child(v)
		v.show_battle(obs, {"terrain": run.rules})
		if lay["zoom"] > 1.0:
			v.set_camera(lay["zoom"], Vector2(90, 46))
		var o := DebugOverlay.new()
		o.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.add_child(o)
		o.attach(v)
		o.set_layer("labels", lay["labels"])
		o.show_frame(run.debug_frames[last])
	return root
