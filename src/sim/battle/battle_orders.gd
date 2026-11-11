class_name BattleOrders
extends RefCounted
## Validates and applies one player's orders at the start of Execute.
## The Game API is the only caller; nothing here trusts the client (R3Q11).
##
## Order dict (all positions are raw fixed ints):
##   {"squad": id, "type": "hold"|"move"|"attack_move"|"attack"|"fall_back"|"withdraw",
##    "x": fx, "y": fy, "target": squad_id, "run": bool,
##    "abilities": [{"id": ability, "on": bool} | {"id": ability, "target": squad_id}]}
## Abilities are planning orders validated against their activation
## (E3Q7); toggles such as Detection and Concealment switch at execute
## start (R8Q2). See Abilities.validate_use.

const TYPES: Dictionary = {
	"hold": BattleSquads.Order.HOLD,
	"move": BattleSquads.Order.MOVE,
	"attack_move": BattleSquads.Order.ATTACK_MOVE,
	"attack": BattleSquads.Order.ATTACK,
	"fall_back": BattleSquads.Order.FALL_BACK,
	"withdraw": BattleSquads.Order.WITHDRAW,
}
## Fall back retreats this far from the nearest visible enemy.
const FALL_BACK_DISTANCE: int = 20 * Fixed.ONE


## Returns the errors; valid orders in the list are still applied.
static func apply(state: BattleState, player: int, orders: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for i in orders.size():
		var o: Variant = orders[i]
		var err := validate(state, player, o)
		if not err.is_empty():
			errors.append("order %d: %s" % [i, err])
			continue
		_apply_one(state, o)
	return errors


static func validate(state: BattleState, player: int, o: Variant) -> String:
	if typeof(o) != TYPE_DICTIONARY:
		return "not an object"
	var sid: Variant = o.get("squad")
	if typeof(sid) != TYPE_INT or not state.squads.is_alive(sid):
		return "unknown squad"
	var row := state.squads.row_of(sid)
	if state.squads.player[row] != player:
		return "not your squad"
	if not state.squads.is_active(row):
		return "squad is out of action"
	var t: Variant = o.get("type", "hold")
	if typeof(t) != TYPE_STRING or not TYPES.has(t):
		return "unknown order type"
	if t in ["move", "attack_move"]:
		for k in ["x", "y"]:
			if typeof(o.get(k)) != TYPE_INT:
				return "missing %s" % k
		var w := Fixed.from_int(state.rules.width)
		var h := Fixed.from_int(state.rules.height)
		if o["x"] < 0 or o["x"] > w or o["y"] < 0 or o["y"] > h:
			return "target point off the battlefield"
	if t == "attack":
		var tid: Variant = o.get("target")
		if typeof(tid) != TYPE_INT or not state.squads.is_alive(tid):
			return "unknown target"
		var trow := state.squads.row_of(tid)
		if state.squads.player[trow] == player or not state.squads.is_active(trow):
			return "invalid target"
		if state.squads.seen_by[trow] & BattleSquads.bit(player) == 0:
			return "target not visible"
	if o.has("run") and typeof(o["run"]) != TYPE_BOOL:
		return "run must be true or false"
	var abl: Variant = o.get("abilities", [])
	if typeof(abl) != TYPE_ARRAY:
		return "abilities must be a list"
	for a: Variant in abl:
		var err := Abilities.validate_use(state, row, a)
		if not err.is_empty():
			return err
	return ""


static func _apply_one(state: BattleState, o: Dictionary) -> void:
	var sq := state.squads
	var row := sq.row_of(o["squad"])
	var t: int = TYPES[o.get("type", "hold")]
	var tx := sq.cx[row]
	var ty := sq.cy[row]
	var target := -1
	var run := 1 if o.get("run", false) else 0
	match t:
		BattleSquads.Order.MOVE, BattleSquads.Order.ATTACK_MOVE:
			tx = o["x"]
			ty = o["y"]
		BattleSquads.Order.ATTACK:
			target = o["target"]
		BattleSquads.Order.FALL_BACK:
			var away := fall_back_point(state, row)
			tx = away[0]
			ty = away[1]
			run = 1
		BattleSquads.Order.WITHDRAW:
			tx = 0 if _own_edge_is_west(state, sq.player[row]) else Fixed.from_int(state.rules.width)
			ty = sq.cy[row]
	set_order(state, row, t, tx, ty, target, run)
	for a: Dictionary in o.get("abilities", []):
		# Re-checked: an earlier entry may have spent the cost or charge.
		if Abilities.validate_use(state, row, a).is_empty():
			Abilities.apply_use(state, row, a)


static func set_order(state: BattleState, row: int, t: int, tx: int, ty: int, target: int, run: int) -> void:
	var sq := state.squads
	for pair: Array in [[&"order", t], [&"tx", tx], [&"ty", ty], [&"target", target]]:
		var col: PackedInt64Array = sq.take_column(pair[0])
		col[row] = pair[1]
		sq.put_column(pair[0], col)
	_set_byte(sq, &"run", row, run)


## A point FALL_BACK_DISTANCE directly away from the nearest enemy the
## squad's player can see (or straight back toward its own edge if none).
static func fall_back_point(state: BattleState, row: int) -> PackedInt64Array:
	var sq := state.squads
	var me := sq.player[row]
	var best := -1
	var best_d := 1 << 62
	for r in sq.count():
		if sq.player[r] == me or not sq.is_active(r) or sq.seen_by[r] & BattleSquads.bit(me) == 0:
			continue
		var d := Fixed.distance(sq.cx[row], sq.cy[row], sq.cx[r], sq.cy[r])
		if d < best_d:
			best_d = d
			best = r
	var dir_x := -Fixed.ONE if _own_edge_is_west(state, me) else Fixed.ONE
	var dir_y := 0
	if best >= 0 and best_d > 0:
		dir_x = Fixed.div(sq.cx[row] - sq.cx[best], best_d)
		dir_y = Fixed.div(sq.cy[row] - sq.cy[best], best_d)
	var w := Fixed.from_int(state.rules.width)
	var h := Fixed.from_int(state.rules.height)
	return PackedInt64Array([
		Fixed.clamp_fixed(sq.cx[row] + Fixed.mul(dir_x, FALL_BACK_DISTANCE), 0, w),
		Fixed.clamp_fixed(sq.cy[row] + Fixed.mul(dir_y, FALL_BACK_DISTANCE), 0, h),
	])


static func _own_edge_is_west(state: BattleState, player: int) -> bool:
	for side in state.rules.sides:
		if side["player"] == player:
			var d: PackedInt64Array = side["deploy"]
			return d[0] + d[2] / 2 < Fixed.from_int(state.rules.width) / 2
	return true


static func _set_byte(t: SoaTable, column: StringName, row: int, v: int) -> void:
	var col: PackedByteArray = t.take_column(column)
	col[row] = v
	t.put_column(column, col)
