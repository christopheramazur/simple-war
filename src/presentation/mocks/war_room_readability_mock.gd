extends RefCounted
## Mock (sw-ip8.7): the war room's readability aids. Left: a skirmish
## overworld with a commander selected (its army in the panel), a garrison
## on its hex, army counts on commanders and the event feed. Right: a battle
## in a reaction window with terrain, the phase banner and a move drawn
## during the window (queued for Planning). Render with
## `hx godot mock res://src/presentation/mocks/war_room_readability_mock.gd`.

const FRAME := Vector2(1000, 620)
const GAP := 16.0


static func build() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(FRAME.x * 2 + GAP * 3, FRAME.y + GAP * 2)
	var bg := ColorRect.new()
	bg.color = Color("0b0d10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var left := _holder(root, Vector2(GAP, GAP))
	var w := MainMenu.skirmish_room("profile_turtle", MainMenu.FACTORY_MAP, 5)
	w.record_match = false
	w.ready.connect(func() -> void:
		var s := w.session
		var cid: int = Array(s.state.commanders.ids()).filter(func(c: int) -> bool: return s.state.commanders.get_value(c, &"player") == 1)[0]
		var at: int = s.state.commanders.get_value(cid, &"plot")
		var did := s.state.detachments.spawn({&"player": 1, &"plot": at})
		var sq := s.rules.squad_ids.find("rifle_squad")
		s.state.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": sq, &"alive": s.rules.sq_size[sq], &"size": s.rules.sq_size[sq]})
		for i in 4:
			w.end_turn_requested.emit()
		w.contexts.select_commander(cid))
	left.add_child(w)
	var right := _holder(root, Vector2(GAP * 2 + FRAME.x, GAP))
	var b: WarRoom = load("res://src/presentation/war_room/war_room.tscn").instantiate()
	b.demo_view = "battle"
	b.ready.connect(func() -> void: _reaction(b))
	right.add_child(b)
	return root


static func _holder(root: Control, at: Vector2) -> Control:
	var h := Control.new()
	h.position = at
	h.size = FRAME
	h.clip_contents = true
	root.add_child(h)
	return h


## Brings the demo battle to a reaction window and draws a move in it.
static func _reaction(w: WarRoom) -> void:
	var eid := w.contexts.focus
	var st: BattleState = (w.session.battles[eid] as OverworldBattle).state
	var sq := st.squads
	var g := -1
	for row in sq.count():
		if sq.player[row] != 1:
			g = row
	for row in sq.count():
		if sq.player[row] != 1:
			continue
		var dist := maxi(Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[g], sq.cy[g]), 1)
		var mx := sq.cx[g] + (sq.cx[row] - sq.cx[g]) * Fixed.from_int(20) / dist - sq.cx[row]
		var my := sq.cy[g] + (sq.cy[row] - sq.cy[g]) * Fixed.from_int(20) / dist - sq.cy[row]
		for urow in st.units.count():
			if st.units.squad[urow] == sq.id_at(row):
				st.units.set_value(st.units.id_at(urow), &"x", st.units.x[urow] + mx)
				st.units.set_value(st.units.id_at(urow), &"y", st.units.y[urow] + my)
	Centroids.update(st)
	w.end_turn_requested.emit()
	var pl := w.planner(eid)
	pl.select(pl.own_squads())
	pl.move_to(pl.selection_centre() + Vector2(-30, 10), false)
