class_name Reactions
extends SimSystem
## The reaction window: forecast and triggered reactions. GDD 02 §2.2,
## R2Q4, R3Q4, R4Q3, R6Q1.
##
## After Reveal, `forecast()` runs the coming turn on a scratch copy of the
## battle with everyone's orders and reports the first contact between each
## pair of opposing squads. Each contact is a reaction opportunity for each
## squad whose player already sees the other one (sw-tz1). Reactions are abilities with reaction timing (E3Q7): a chosen one
## is queued on the squad and fires when the real contact happens (this
## system, every tick). It pays its activation costs (Instinct by default)
## and floats Prowess for the squad that provoked it. Its bundle sees the
## trigger as "other" (e.g. an "attack" order at the trigger).
## One reaction timing, no counter-reactions.


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
	var reach := maxi(sq.reach[a], sq.reach[b])
	return Fixed.distance(sq.cx[a], sq.cy[a], sq.cx[b], sq.cy[b]) <= reach \
		and (sq.seen_by[a] & BattleSquads.bit(sq.player[b]) != 0 or sq.seen_by[b] & BattleSquads.bit(sq.player[a]) != 0)


func _trigger(state: BattleState, row: int, trow: int, ab: int) -> void:
	var sq := state.squads
	var aid := Abilities.find(state, sq.id_at(row), ab)
	if aid >= 0:
		Abilities.react(state, aid, sq.id_at(trow))
	Pools.flow(state, trow, BattleSquads.PROWESS, Fixed.from_int(state.rules.flt("prowess_reacted_to")), &"reacted_to")
	var col: PackedInt64Array = sq.take_column(&"reaction")
	col[row] = -1
	sq.put_column(&"reaction", col)
	state.events.push(&"reaction_triggered", {"squad": sq.id_at(row), "trigger": sq.id_at(trow),
		"reaction": state.rules.ab_ids[ab]}, state.tick)


## Queues a reaction (a reaction ability's ID). Returns "" or an error.
## Validation is the API's job; this only checks the squad can perform it.
static func queue(state: BattleState, squad_id: int, reaction: String, trigger_id: int) -> String:
	var sq := state.squads
	var row := sq.row_of(squad_id)
	var ab := Abilities.index_of(state, reaction)
	if row < 0 or ab < 0:
		return "unknown squad or reaction"
	var aid := Abilities.find(state, squad_id, ab)
	if aid < 0 or state.rules.ab_reaction[ab] == 0:
		return "squad cannot %s" % reaction
	var err := Abilities.can_use(state, aid)
	if not err.is_empty():
		return err
	if sq.row_of(trigger_id) < 0:
		return "unknown trigger squad"
	for pair: Array in [[&"reaction", ab], [&"reaction_trigger", trigger_id]]:
		var col: PackedInt64Array = sq.take_column(pair[0])
		col[row] = pair[1]
		sq.put_column(pair[0], col)
	return ""


## Reaction abilities the squad could use now.
static func available(state: BattleState, row: int) -> Array:
	var names := []
	var t := state.abilities
	for aid in Abilities.of_squad(state, state.squads.id_at(row)):
		var ab := t.ability[t.row_of(aid)]
		if state.rules.ab_reaction[ab] == 1 and Abilities.can_use(state, aid).is_empty():
			names.append(state.rules.ab_ids[ab])
	return names


static func clear_all(state: BattleState) -> void:
	var sq := state.squads
	var col: PackedInt64Array = sq.take_column(&"reaction")
	col.fill(-1)
	sq.put_column(&"reaction", col)


## Whether `player` sees squad `trigger` now (at Reveal, before the turn
## runs). A squad can react only to an enemy its player already sees: one
## still hidden when orders are given is no reaction opportunity.
static func sees_at_reveal(state: BattleState, player: int, trigger: int) -> bool:
	var row := state.squads.row_of(trigger)
	return row >= 0 and state.squads.seen_by[row] & BattleSquads.bit(player) != 0


## Whether any squad owns a reaction ability (else a forecast finds no
## opportunity, and only the telegraphs would need its run).
static func any_reactions(state: BattleState) -> bool:
	var t := state.abilities
	for row in t.count():
		if state.rules.ab_reaction[t.ability[row]] == 1:
			return true
	return false


## Runs the coming turn on a scratch copy and returns opportunities (only
## against triggers the reacting player sees at Reveal, sees_at_reveal):
## [{"squad", "player", "trigger", "tick", "reactions": [names]}] in
## canonical order (tick, squad ID, trigger ID).
static func forecast(state: BattleState, sim: BattleSim) -> Array:
	return forecast_all(state, sim)["opportunities"]


## The same scratch run, with the enemy attack telegraphs (sw-7o7) taken
## from it, so there is no second turn sim: {"opportunities": forecast(),
## "telegraphs": [{"attacker", "target", "player" (the target's), "damage"
## (fixed, summed over the turn from the sim's own squad_damaged events),
## "kills", "tick" (first damage)}]} in (tick, attacker, target) order. Only
## committed attacks on a squad whose attacker its player sees at Reveal
## (sees_at_reveal): hidden attackers and drafts never show. It assumes
## the orders stay as committed; a reaction changes the real result.
static func forecast_all(state: BattleState, sim: BattleSim, telegraphs_wanted: bool = true) -> Dictionary:
	if not telegraphs_wanted and not any_reactions(state):
		return {"opportunities": [], "telegraphs": []}  # nothing to react with: skip the scratch turn (sw-kd5)
	var scratch := BattleState.new(state.id, state.rules)
	scratch.restore(state.snapshot())
	Centroids.update(scratch)
	var seen := {}
	var out := []
	var hits := {}
	scratch.begin_turn()
	for _t in state.rules.ticks_per_turn:
		sim.runner.step(scratch)
		var sq := scratch.squads
		for e in scratch.turn_log:
			if e.type == &"squad_damaged":
				_tally(state, hits, e)
			if e.type != &"engagement" or seen.has("%d,%d" % [e.data["squad"], e.data["target"]]):
				continue
			var a: int = e.data["squad"]
			var b: int = e.data["target"]
			seen["%d,%d" % [a, b]] = true
			seen["%d,%d" % [b, a]] = true
			for pair in [[a, b], [b, a]]:
				var row := sq.row_of(pair[0])
				if row < 0 or not sees_at_reveal(state, sq.player[row], pair[1]):
					continue
				var names := available(state, row)
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
	var telegraphs := hits.values()
	telegraphs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["tick"] != y["tick"]:
			return x["tick"] < y["tick"]
		if x["attacker"] != y["attacker"]:
			return x["attacker"] < y["attacker"]
		return x["target"] < y["target"])
	return {"opportunities": out, "telegraphs": telegraphs}


static func _tally(state: BattleState, hits: Dictionary, e: Variant) -> void:
	var sq := state.squads
	var a: int = e.data["squad"]
	var b: int = e.data["target"]
	var arow := sq.row_of(a)
	var brow := sq.row_of(b)
	if arow < 0 or brow < 0 or sq.player[arow] == sq.player[brow]:
		return
	if not sees_at_reveal(state, sq.player[brow], a):
		return
	var key := "%d,%d" % [a, b]
	if not hits.has(key):
		hits[key] = {"attacker": a, "target": b, "player": sq.player[brow], "damage": 0, "kills": 0, "tick": e.tick}
	hits[key]["damage"] += int(e.data["damage"])
	hits[key]["kills"] += int(e.data["kills"])
