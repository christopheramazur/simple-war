extends RefCounted
## Mock: the behaviour workshop (sw-tho3.8, U1 B8) on dps_orders' attack-move
## variant, paused in turn 1 with the rifles' card open: the debug overlay
## over the playback, the probe list and the squad card from the cursor.
## Render with `hx godot mock res://src/presentation/mocks/behaviour_workshop_mock.gd`.


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(1500, 860)
	var w := BehaviourWorkshop.new()
	w.scenario_path = "res://data/sim/workshop/dps_orders.json"
	w.variant = "attack_move"
	w.ready.connect(func() -> void:
		w.seek_frame(w.run.frame_at(1, 60))
		w.inspect(int(w.run.sids["rifles"])))
	root.add_child(w)
	w.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root
