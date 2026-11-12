extends RefCounted
## Mock (sw-cf6): the playable Angelfall slice on one sheet. Left: the
## frontier overworld with Jeff selected, set to no battleforce and routed
## to the Angel blockade, the commander panel and the messages. Right: the
## spaceport battle reached by playing real turns, with the evacuation
## drafted and its intent ghosts. Render with
## `hx godot mock res://src/presentation/mocks/angelfall_mock.gd`.

const FRAME := Vector2(920, 600)
const GAP := 16.0
const W := 12


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y + GAP * 2)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for i in 2:
		var holder := Control.new()
		holder.position = Vector2(GAP + i * (FRAME.x + GAP), GAP)
		holder.size = FRAME
		root.add_child(holder)
		var w: WarRoom = load("res://src/presentation/angelfall/angelfall.tscn").instantiate()
		w.ready.connect(_overworld.bind(w) if i == 0 else _battle.bind(w))
		holder.add_child(w)
	return root


static func _jeff(w: WarRoom) -> int:
	return w.session.state.commanders.ids()[0]


static func _overworld(w: WarRoom) -> void:
	w.contexts.select_commander(_jeff(w))
	w.set_battleforce(OverworldBattleforce.NONE, false)
	w.route_to(Hex.plot(7, 3, W))
	w.end_turn_requested.emit()
	w.contexts.select_commander(_jeff(w))
	w.route_to(Hex.plot(9, 3, W))


static func _battle(w: WarRoom) -> void:
	var j := _jeff(w)
	w.contexts.select_commander(j)
	w.set_battleforce(OverworldBattleforce.NONE, false)
	for i in 6:
		if not w.session.battles.is_empty():
			break
		var at: int = w.session.state.commanders.get_value(j, &"plot")
		if at == Hex.plot(7, 3, W) or at == Hex.plot(8, 3, W):
			w.set_battleforce("", true)
		var goal := Hex.plot(7, 3, W) if w.session.state.vars.get("angels_dispersed", 0) == 0 else Hex.plot(10, 3, W)
		w.contexts.select_commander(j)
		w.route_to(goal)
		w.end_turn_requested.emit()
	if w.contexts.tab_in():
		var pl := w.planner(w.contexts.focus)
		var ctl := EvacuationController.new(1)
		for o: Dictionary in ctl.orders(w.session.observe_battle(1, w.contexts.focus)):
			pl.select([o["squad"]])
			if o.has("x"):
				pl.move_to(Vector2(float(o["x"]) / Fixed.ONE, float(o["y"]) / Fixed.ONE), false, o["type"] == "attack_move")
		pl.select(pl.own_squads())
