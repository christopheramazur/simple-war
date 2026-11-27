class_name BattleDeploy
extends RefCounted
## The deployment step (GDD 02 §2.4 Deployment, U1Q9, U1Q30): in turn-1
## Planning of a battle whose scenario deployment is open, each side places
## its squads (anchor and facing) anywhere inside its deployment area,
## hidden and simultaneous. Placements apply first at Reveal, in canonical
## order (players ascending, then squad ID), then vision runs; then
## reinforcements and orders apply as usual.
##
## A placement is {"squad": int, "x": int, "y": int (fixed), "facing": int
## (binary angle)}. Squads without one keep their automatic places, which are
## exactly BattleSetup.deploy_side's, so a battle with no placement input
## runs as one with no deployment step.
##
## While `state.deploying`, a player sees no squad that isn't their own or an
## ally's, even one that would be in sight (`hides`): the build-time vision
## result is never exposed.


## The player's deployment area [x, y, w, h] (fixed), or empty if the
## player has no side in this battle.
static func area(state: BattleState, player: int) -> PackedInt64Array:
	for side: Dictionary in state.rules.sides:
		if int(side["player"]) == player:
			return (side["deploy"] as PackedInt64Array).duplicate()
	return PackedInt64Array()


## Whether squad row `row` is hidden from `player` because the battle is
## deploying. `allies`: players allied to `player` (none in a skirmish).
static func hides(state: BattleState, player: int, row: int, allies: PackedInt64Array = PackedInt64Array()) -> bool:
	if not state.deploying or player <= 0:
		return false
	var owner := state.squads.player[row]
	return owner != player and not allies.has(owner)


## Error text for one placement, "" if valid. `taken`: squad IDs already
## placed in the same list (a squad is placed at most once).
static func validate(state: BattleState, player: int, p: Variant, taken: Dictionary = {}) -> String:
	if not state.deploying:
		return "the battle is not deploying"
	if typeof(p) != TYPE_DICTIONARY:
		return "placement must be a dictionary"
	var d: Dictionary = p
	for k in ["squad", "x", "y", "facing"]:
		if typeof(d.get(k)) != TYPE_INT:
			return "%s must be an int" % k
	var sid: int = d["squad"]
	var row := state.squads.row_of(sid)
	if row < 0:
		return "unknown squad"
	if state.squads.player[row] != player:
		return "not your squad"
	if state.pinned.has(sid):
		return "locked: the scenario places this squad"
	if taken.has(sid):
		return "squad placed twice"
	var rect := area(state, player)
	if rect.is_empty():
		return "no deployment area"
	var x: int = d["x"]
	var y: int = d["y"]
	if x < rect[0] or y < rect[1] or x > rect[0] + rect[2] or y > rect[1] + rect[3]:
		return "outside the deployment area"
	if open_point_in(state.rules, state.squads.tmpl[row], x, y, rect).is_empty():
		return "no cell the squad can enter in the deployment area"
	return ""


## Validates a player's placements: {"kept": valid placements (copies),
## "errors": PackedStringArray}. Later duplicates of a squad are refused.
static func check(state: BattleState, player: int, placements: Array) -> Dictionary:
	var kept := []
	var errors := PackedStringArray()
	var taken := {}
	for i in placements.size():
		var err := validate(state, player, placements[i], taken)
		if err.is_empty():
			var d: Dictionary = (placements[i] as Dictionary).duplicate(true)
			taken[d["squad"]] = true
			kept.append(d)
		else:
			errors.append("placement %d: %s" % [i, err])
	return {"kept": kept, "errors": errors}


## Applies one player's placements (invalid ones are skipped). Returns how
## many were applied.
static func apply(state: BattleState, player: int, placements: Array) -> int:
	var kept: Array = check(state, player, placements)["kept"]
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["squad"]) < int(b["squad"]))
	var rect := area(state, player)
	for d: Dictionary in kept:
		_place(state, int(d["squad"]), int(d["x"]), int(d["y"]), int(d["facing"]) & Fixed.ANGLE_MASK, rect)
	return kept.size()


## Reveal's deployment step: applies every player's placements (`by_player`:
## player -> Array) in canonical order, then, if anything moved, refreshes
## centroids and vision (its events join the turn log). Clears `deploying`.
## Does nothing for a battle that isn't deploying.
static func reveal(state: BattleState, by_player: Dictionary) -> void:
	if not state.deploying:
		return
	var moved := 0
	for p in state.players:
		moved += apply(state, p, by_player.get(p, []))
	state.deploying = false
	if moved > 0:
		Centroids.update(state)
		VisionSystem.new().run(state)
		state.turn_log.append_array(state.events.drain())


static func _place(state: BattleState, sid: int, x: int, y: int, facing: int, rect: PackedInt64Array) -> void:
	var r := state.rules
	var sq := state.squads
	var row := sq.row_of(sid)
	var st := sq.tmpl[row]
	var at := open_point_in(r, st, x, y, rect)
	var ax := at[0]
	var ay := at[1]
	for c: StringName in [&"tx", &"ax", &"cx"]:
		sq.set_value(sid, c, ax)
	for c: StringName in [&"ty", &"ay", &"cy"]:
		sq.set_value(sid, c, ay)
	sq.set_value(sid, &"facing", facing)
	var u := state.units
	var count := sq.form_size[row]
	for urow in u.count():
		if u.squad[urow] != sid:
			continue
		var uid := u.id_at(urow)
		var off := Formation.offset(r.sq_shape[st], u.slot[urow], count, r.sq_spacing[st], facing)
		var p := BattleSetup.open_point(r, st, Fixed.clamp_fixed(ax + off[0], 0, Fixed.from_int(r.width) - 1),
			Fixed.clamp_fixed(ay + off[1], 0, Fixed.from_int(r.height) - 1))
		u.set_value(uid, &"x", p[0])
		u.set_value(uid, &"y", p[1])
		u.set_value(uid, &"facing", facing)


## Like BattleSetup.open_point, but the snapped point stays inside `rect`
## ([x, y, w, h], fixed): the point itself if the squad can stand on its
## cell, else the centre of the nearest enterable cell whose centre lies in
## the rect (ties by cell index). Empty if there is none.
static func open_point_in(r: BattleRules, st: int, x: int, y: int, rect: PackedInt64Array) -> PackedInt64Array:
	if r.terrain.size() < r.width * r.height or st < 0 or st >= r.sq_route_class.size():
		return PackedInt64Array([x, y])
	var costs: PackedInt32Array = r.rt_cost[r.sq_route_class[st]]
	var cx := clampi(Fixed.to_int_floor(x), 0, r.width - 1)
	var cy := clampi(Fixed.to_int_floor(y), 0, r.height - 1)
	if costs[r.terrain[cy * r.width + cx]] > 0:
		return PackedInt64Array([x, y])
	var half := Fixed.ONE / 2
	var best := -1
	var best_d := 0
	var x0 := clampi(Fixed.to_int_floor(rect[0]), 0, r.width - 1)
	var y0 := clampi(Fixed.to_int_floor(rect[1]), 0, r.height - 1)
	var x1 := clampi(Fixed.to_int_floor(rect[0] + rect[2]), 0, r.width - 1)
	var y1 := clampi(Fixed.to_int_floor(rect[1] + rect[3]), 0, r.height - 1)
	for qy in range(y0, y1 + 1):
		var my := Fixed.from_int(qy) + half
		if my < rect[1] or my > rect[1] + rect[3]:
			continue
		for qx in range(x0, x1 + 1):
			var mx := Fixed.from_int(qx) + half
			if mx < rect[0] or mx > rect[0] + rect[2] or costs[r.terrain[qy * r.width + qx]] <= 0:
				continue
			var d := (qx - cx) * (qx - cx) + (qy - cy) * (qy - cy)
			var cell := qy * r.width + qx
			if best < 0 or d < best_d or (d == best_d and cell < best):
				best = cell
				best_d = d
	if best < 0:
		return PackedInt64Array()
	@warning_ignore("integer_division")
	return PackedInt64Array([Fixed.from_int(best % r.width) + half, Fixed.from_int(best / r.width) + half])
