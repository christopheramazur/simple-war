class_name OverworldOrders
extends RefCounted
## Planning-phase orders on the overworld (GDD 02 §2.2, §2.9). The UI and AI
## submit routes here; nothing moves until the turn resolves.


## Sets a commander's route: the plots to enter, in order. Returns "" or why
## the route was refused (and leaves the old route in place).
static func set_route(s: OverworldState, player: int, commander_id: int, plots: PackedInt64Array) -> String:
	var err := validate_route(s, player, commander_id, plots)
	if err.is_empty():
		if plots.is_empty():
			s.routes.erase(commander_id)
		else:
			s.routes[commander_id] = plots.duplicate()
	return err


static func clear_route(s: OverworldState, player: int, commander_id: int) -> String:
	return set_route(s, player, commander_id, PackedInt64Array())


## Plans an activity (R4Q12): refit, recruit, battle or convert. It needs
## the route to end on a hex with a feature offering it (or, with no route,
## the commander's own hex). Recruit names the squad in `option`. Returns ""
## or why it was refused.
static func set_activity(s: OverworldState, player: int, commander_id: int, activity: String, option: String = "") -> String:
	var c := s.commanders
	var row := c.row_of(commander_id)
	if row < 0:
		return "no such commander"
	if c.player[row] != player:
		return "not your commander"
	if activity.is_empty():
		s.activities.erase(commander_id)
		return ""
	if not OverworldRules.ACTIVITIES.has(activity):
		return "unknown activity '%s'" % activity
	if c.engagement[row] >= 0:
		return "is in a battle"
	var route: PackedInt64Array = s.routes.get(commander_id, PackedInt64Array())
	var dest := c.plot[row] if route.is_empty() else route[route.size() - 1]
	# What the player knows of the hex (fog of war); resolving uses the truth.
	var t := OverworldVision.known_offering(s, player, dest, activity)
	if t < 0:
		return "the route must end on a hex offering %s" % activity
	var cost := s.rules.hf_activity_cost[t]
	match activity:
		"recruit":
			var sq := s.rules.squad_index(option)
			var price := s.rules.recruit_cost(t, sq) if sq >= 0 else -1
			if price < 0:
				return "this hex does not recruit '%s'" % option
			if OverworldArmies.count(s, commander_id) >= OverworldArmies.cap(s, commander_id):
				return "the army is full (%d squads)" % OverworldArmies.cap(s, commander_id)
			cost += price
		"refit":
			var lost := OverworldArmies.losses(s, commander_id)
			if lost == 0:
				return "the army has no losses to refit"
			cost += lost * s.rules.hf_refit_cost[t]
	if s.value_of(player) < cost:
		return "%s costs %d Value, you have %d" % [activity, cost, s.value_of(player)]
	s.activities[commander_id] = {"activity": activity, "plot": dest, "option": option}
	return ""


## Friendly commanders sharing a hex trade squads freely during planning
## (R7Q9). Takes effect at once. Returns "" or why it was refused.
static func transfer_squad(s: OverworldState, player: int, squad_id: int, to_commander: int) -> String:
	var q := s.squads
	var row := q.row_of(squad_id)
	if row < 0:
		return "no such squad"
	var c := s.commanders
	var from := q.holder[row]
	var fr := c.row_of(from)
	var tr := c.row_of(to_commander)
	if fr < 0 or c.player[fr] != player:
		return "not your squad"
	if tr < 0:
		return "no such commander"
	if c.player[tr] != player:
		return "not your commander"
	if from == to_commander:
		return "already in that army"
	if q.own[row] == 1:
		return "a commander's own squad stays with it"
	if c.plot[fr] != c.plot[tr]:
		return "the commanders must share a hex"
	if c.engagement[fr] >= 0 or c.engagement[tr] >= 0:
		return "a commander in a battle cannot trade"
	if OverworldArmies.count(s, to_commander) >= OverworldArmies.cap(s, to_commander):
		return "the receiving army is full (%d squads)" % OverworldArmies.cap(s, to_commander)
	OverworldArmies.move(s, squad_id, to_commander)
	s.events.push(&"squad_transferred", {"squad": squad_id, "from": from, "to": to_commander, "player": player}, s.tick)
	return ""


static func validate_route(s: OverworldState, player: int, commander_id: int, plots: PackedInt64Array) -> String:
	var c := s.commanders
	var row := c.row_of(commander_id)
	if row < 0:
		return "no such commander"
	if c.player[row] != player:
		return "not your commander"
	if plots.is_empty():
		return ""
	if c.engagement[row] >= 0:
		return "is in a battle: it cannot move until the battle ends"
	var at := c.plot[row]
	var spent := 0
	# Costs as the player knows them: an unexplored hex looks like open ground.
	var costs := OverworldVision.known_costs(s, player)
	for i in plots.size():
		var p := plots[i]
		if p < 0 or p >= s.rules.plot_count():
			return "step %d is off the map" % (i + 1)
		if not Hex.adjacent(at, p, s.rules.width):
			return "step %d is not next to the previous hex" % (i + 1)
		var cost := costs[p]
		if cost < 0:
			return "step %d is impassable" % (i + 1)
		if s.engagement_at(p) >= 0 and i < plots.size() - 1:
			return "step %d is a battle: a route onto a battle ends there" % (i + 1)
		spent += cost
		at = p
	var budget := Commanders.budget(s, row)
	if spent > budget:
		return "needs %d movement points, has %d" % [spent, budget]
	return ""
