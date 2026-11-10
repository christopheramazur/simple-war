class_name Reactions
extends SimSystem
## The reaction window: forecast and triggered reactions. GDD 02 §2.2,
## R2Q4, R3Q4, R4Q3, R6Q1.
##
## After Reveal, `forecast()` runs the coming turn on a scratch copy of the
## battle with everyone's orders and reports the first contact between each
## pair of opposing squads. Each contact is a reaction opportunity for both
## squads. A chosen reaction is a restricted order queued on the squad; it
## fires when the real contact happens (this system, every tick), costs the
## squad Instinct, and floats Prowess for the squad that provoked it.
## One reaction timing, no counter-reactions.

const HALT: int = 0
const FALL_BACK: int = 1
const RETARGET: int = 2
const GO_PRONE: int = 3


func system_name() -> StringName:
	return &"reactions"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	var sq := state.squads
	for row in sq.count():
		var re := sq.reaction[row]
		if re < 0 or not sq.is_active(row):
			continue
		var trow := sq.row_of(sq.reaction_trigger[row])
		if trow < 0 or not sq.is_active(trow):
			continue
		if not in_contact(state, row, trow):
			continue
		_trigger(state, row, trow, re)


static func in_contact(state: BattleState, a: int, b: int) -> bool:
	var sq := state.squads
	if sq.engaged[a] == sq.id_at(b) or sq.engaged[b] == sq.id_at(a):
		return true
	var reach := maxi(state.rules.squad_range(sq.tmpl[a]), state.rules.squad_range(sq.tmpl[b]))
	return Fixed.distance(sq.cx[a], sq.cy[a], sq.cx[b], sq.cy[b]) <= reach \
		and (sq.seen_by[a] & BattleSquads.bit(sq.player[b]) != 0 or sq.seen_by[b] & BattleSquads.bit(sq.player[a]) != 0)


func _trigger(state: BattleState, row: int, trow: int, re: int) -> void:
	var r := state.rules
	var sq := state.squads
	match re:
		HALT, GO_PRONE:
			BattleOrders.set_order(state, row, BattleSquads.Order.HOLD, sq.cx[row], sq.cy[row], -1, 0)
		FALL_BACK:
			var p := BattleOrders.fall_back_point(state, row)
			BattleOrders.set_order(state, row, BattleSquads.Order.FALL_BACK, p[0], p[1], -1, 1)
		RETARGET:
			BattleOrders.set_order(state, row, BattleSquads.Order.ATTACK, sq.cx[trow], sq.cy[trow], sq.id_at(trow), 0)
	var cost := r.sq_reaction_cost[sq.tmpl[row]][re]
	Pools.flow(state, row, BattleSquads.INSTINCT, -maxi(cost, 0), &"reaction")
	Pools.flow(state, trow, BattleSquads.PROWESS, Fixed.from_int(r.flt("prowess_reacted_to")), &"reacted_to")
	var col: PackedInt64Array = sq.take_column(&"reaction")
	col[row] = -1
	sq.put_column(&"reaction", col)
	state.events.push(&"reaction_triggered", {"squad": sq.id_at(row), "trigger": sq.id_at(trow),
		"reaction": BattleRules.REACTIONS[re]}, state.tick)


## Queues a reaction. Returns "" or an error. Validation is the API's job;
## this only checks the squad can perform it.
static func queue(state: BattleState, squad_id: int, reaction: String, trigger_id: int) -> String:
	var sq := state.squads
	var row := sq.row_of(squad_id)
	var re := BattleRules.REACTIONS.find(reaction)
	if row < 0 or re < 0:
		return "unknown squad or reaction"
	if state.rules.sq_reaction_cost[sq.tmpl[row]][re] < 0:
		return "squad cannot %s" % reaction
	if sq.row_of(trigger_id) < 0:
		return "unknown trigger squad"
	for pair: Array in [[&"reaction", re], [&"reaction_trigger", trigger_id]]:
		var col: PackedInt64Array = sq.take_column(pair[0])
		col[row] = pair[1]
		sq.put_column(pair[0], col)
	return ""


static func clear_all(state: BattleState) -> void:
	var sq := state.squads
	var col: PackedInt64Array = sq.take_column(&"reaction")
	col.fill(-1)
	sq.put_column(&"reaction", col)


## Runs the coming turn on a scratch copy and returns opportunities:
## [{"squad", "player", "trigger", "tick", "reactions": [names]}] in
## canonical order (tick, squad ID, trigger ID).
static func forecast(state: BattleState, sim: BattleSim) -> Array:
	var scratch := BattleState.new(state.id, state.rules)
	scratch.restore(state.snapshot())
	Centroids.update(scratch)
	var seen := {}
	var out := []
	scratch.begin_turn()
	for _t in state.rules.ticks_per_turn:
		sim.runner.step(scratch)
		var sq := scratch.squads
		for e in scratch.turn_log:
			if e.type != &"engagement" or seen.has("%d,%d" % [e.data["squad"], e.data["target"]]):
				continue
			var a: int = e.data["squad"]
			var b: int = e.data["target"]
			seen["%d,%d" % [a, b]] = true
			seen["%d,%d" % [b, a]] = true
			for pair in [[a, b], [b, a]]:
				var row := sq.row_of(pair[0])
				if row < 0:
					continue
				var names := []
				for re in BattleRules.REACTIONS.size():
					if state.rules.sq_reaction_cost[sq.tmpl[row]][re] >= 0:
						names.append(BattleRules.REACTIONS[re])
				if names.is_empty():
					continue
				out.append({"squad": pair[0], "player": sq.player[row], "trigger": pair[1], "tick": e.tick, "reactions": names})
		scratch.turn_log = []
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["tick"] != y["tick"]:
			return x["tick"] < y["tick"]
		if x["squad"] != y["squad"]:
			return x["squad"] < y["squad"]
		return x["trigger"] < y["trigger"])
	return out
