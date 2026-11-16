extends RefCounted
## Mock (sw-ll4.11): the results screen over the war room at the end of a
## skirmish. Render with
## `hx godot mock res://src/presentation/mocks/results_mock.gd`.

const FRAME := Vector2(1280, 720)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME
	var w := MainMenu.skirmish_room("profile_utility", "skirmish_mirror", 3)
	w.record_match = false
	root.add_child(w)
	w.ready.connect(func() -> void:
		ResultsScreen.open_over(w, "won", "Every enemy commander is defeated.", {"turns": 14, "battles": 3, "players": {
			1: {"squads_lost": 2, "commanders_lost": 0, "features_taken": 4},
			2: {"squads_lost": 6, "commanders_lost": 1, "features_taken": 1}}}, 1,
			{"replay": true, "menu": true, "note": "Match log: user://matches/20261117-skirmish_mirror-s3"}), CONNECT_DEFERRED)
	return root
