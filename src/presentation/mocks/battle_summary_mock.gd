extends RefCounted
## Mock (sw-1jy.5): the overworld glance — every battle tab and tile shows
## the worst SIMPL band across the player's own squads as word + icon (never
## colour alone) with the backward-looking trend. The camp battle has one
## own squad's morale broken; the meeting battle has every own pool filled
## (surging). Render with
## `hx godot mock res://src/presentation/mocks/battle_summary_mock.gd`.

const FRAME := Vector2(1230, 680)


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = FRAME + Vector2(32, 32)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var holder := Control.new()
	holder.position = Vector2(16, 16)
	holder.size = FRAME
	root.add_child(holder)
	var w: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	w.record_match = false
	w.ready.connect(func() -> void: _prepare(w))
	holder.add_child(w)
	return root


## Two different worst bands and trends against the last recorded turn.
static func _prepare(w: WarRoom) -> void:
	var eids := w.contexts.battles()
	var morale := DataSchema.SIMPL.find("morale")
	for i in eids.size():
		var b: OverworldBattle = w.session.battles[eids[i]]
		for row in b.state.squads.count():
			if b.state.squads.player[row] != 1 or not b.state.squads.is_active(row):
				continue
			if i == 0:
				Pools.flow(b.state, row, morale, -Pools.value(b.state, row, morale), &"mock")
				break
			for p in DataSchema.SIMPL.size():
				Pools.flow(b.state, row, p, Pools.capacity(b.state, row, p) - Pools.value(b.state, row, p), &"mock")
	w._queue_refresh()
