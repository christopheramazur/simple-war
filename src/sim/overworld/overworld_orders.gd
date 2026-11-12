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
		# A planned drop-off the new route no longer allows is dropped.
		if s.drops.has(commander_id):
			var d: Dictionary = s.drops[commander_id]
			if not validate_drop_off(s, player, commander_id, d["step"], d["plot"]).is_empty():
				s.drops.erase(commander_id)
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
## (R7Q9), and a commander picks up squads from the player's detachment on
## its hex (taking its War Chest with the last one). Takes effect at once.
## Returns "" or why it was refused.
static func transfer_squad(s: OverworldState, player: int, squad_id: int, to_commander: int) -> String:
	var q := s.squads
	var row := q.row_of(squad_id)
	if row < 0:
		return "no such squad"
	var c := s.commanders
	var d := s.detachments
	var from := q.holder[row]
	var did := q.detachment[row]
	var fr := c.row_of(from)
	var dr := d.row_of(did) if did >= 0 else -1
	var tr := c.row_of(to_commander)
	if (fr < 0 or c.player[fr] != player) and (dr < 0 or d.player[dr] != player):
		return "not your squad"
	if tr < 0:
		return "no such commander"
	if c.player[tr] != player:
		return "not your commander"
	if from == to_commander:
		return "already in that army"
	if q.own[row] == 1:
		return "a commander's own squad stays with it"
	var from_plot := d.plot[dr] if dr >= 0 else c.plot[fr]
	if from_plot != c.plot[tr]:
		return "the commanders must share a hex" if dr < 0 else "the commander must be on the detachment's hex"
	var from_engaged := d.engagement[dr] >= 0 if dr >= 0 else c.engagement[fr] >= 0
	if from_engaged or c.engagement[tr] >= 0:
		return "a commander in a battle cannot trade" if dr < 0 else "a detachment in a battle cannot be picked up"
	if OverworldArmies.count(s, to_commander) >= OverworldArmies.cap(s, to_commander):
		return "the receiving army is full (%d squads)" % OverworldArmies.cap(s, to_commander)
	OverworldArmies.move(s, squad_id, to_commander)
	if dr >= 0:
		s.events.push(&"squad_picked_up", {"squad": squad_id, "detachment": did, "commander": to_commander,
			"player": player, "plot": from_plot}, s.tick)
		if Detachments.squads_of(s, did).is_empty():
			WarChest.hand_over(s, did, to_commander)
			Detachments.disband(s, did, "picked_up")
	else:
		s.events.push(&"squad_transferred", {"squad": squad_id, "from": from, "to": to_commander, "player": player}, s.tick)
	return ""


## Plans a drop-off (R4Q13, R5Q9): after entering route step `step` (-1 =
## before moving), the commander drops its battleforce, planned with its
## own squad kept out, on that hex or on one next to it. A hex off the route
## costs its movement cost, so the route's later steps must still fit the
## budget. `plot` -1 clears it. Returns "" or why it was refused.
static func set_drop_off(s: OverworldState, player: int, commander_id: int, step: int, plot: int) -> String:
	if plot < 0:
		var row := s.commanders.row_of(commander_id)
		if row < 0:
			return "no such commander"
		if s.commanders.player[row] != player:
			return "not your commander"
		s.drops.erase(commander_id)
		return ""
	var err := validate_drop_off(s, player, commander_id, step, plot)
	if err.is_empty():
		s.drops[commander_id] = {"step": step, "plot": plot}
	return err


static func validate_drop_off(s: OverworldState, player: int, commander_id: int, step: int, plot: int) -> String:
	var c := s.commanders
	var row := c.row_of(commander_id)
	if row < 0:
		return "no such commander"
	if c.player[row] != player:
		return "not your commander"
	if c.engagement[row] >= 0:
		return "is in a battle"
	var route: PackedInt64Array = s.routes.get(commander_id, PackedInt64Array())
	if step < -1 or step >= route.size():
		return "step %d is not on the route" % (step + 1)
	var at := c.plot[row] if step < 0 else route[step]
	var costs := OverworldVision.known_costs(s, player)
	var extra := 0
	if plot != at:
		if plot >= s.rules.plot_count() or not Hex.adjacent(at, plot, s.rules.width):
			return "a battleforce is dropped on the route or 1 hex off it"
		extra = costs[plot]
		if extra < 0:
			return "that hex is impassable"
	if s.engagement_at(plot) >= 0:
		return "a battleforce cannot be dropped onto a battle"
	if OverworldBattleforce.pick(s, commander_id, true).is_empty():
		return "the battleforce has no squads to drop off (the commander's own squad stays)"
	var spent := extra
	for p in route:
		spent += costs[p]
	var budget := Commanders.budget(s, row)
	if spent > budget:
		return "needs %d movement points, has %d" % [spent, budget]
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


## A commander staying in its battle (its own squad deployed there) sends a
## squad from the rest of its army in as a reinforcement (R3Q3). It joins
## the battle before the next battle turn. `in_field` is how many of the
## commander's squads are still fighting there; the battleforce squad cap
## applies to them. Returns "" or why it was refused.
static func reinforce(s: OverworldState, player: int, commander_id: int, squad_id: int, in_field: int) -> String:
	var c := s.commanders
	var row := c.row_of(commander_id)
	if row < 0:
		return "no such commander"
	if c.player[row] != player:
		return "not your commander"
	var eid := c.engagement[row]
	if eid < 0:
		return "is not in a battle"
	var q := s.squads
	var staying := false
	for id in OverworldArmies.of(s, commander_id):
		var r := q.row_of(id)
		staying = staying or (q.own[r] == 1 and q.deployed[r] == eid)
	if not staying:
		return "only a commander staying in the battle brings reinforcements"
	var sr := q.row_of(squad_id)
	if sr < 0 or q.holder[sr] != commander_id:
		return "that squad is not in this army"
	if q.deployed[sr] >= 0:
		return "that squad is already in a battle"
	if q.alive[sr] <= 0:
		return "that squad has no units left"
	if in_field >= s.rules.bf_cap_squads:
		return "the battleforce cap is %d squads" % s.rules.bf_cap_squads
	q.set_value(squad_id, &"deployed", eid)
	return ""


## A commander whose own squad is not deployed leaves its battle (R2Q1): it
## can move again; the squads it deployed fight on. Returns "" or why not.
static func leave_battle(s: OverworldState, player: int, commander_id: int) -> String:
	var c := s.commanders
	var row := c.row_of(commander_id)
	if row < 0:
		return "no such commander"
	if c.player[row] != player:
		return "not your commander"
	var eid := c.engagement[row]
	if eid < 0:
		return "is not in a battle"
	var q := s.squads
	for id in OverworldArmies.of(s, commander_id):
		var r := q.row_of(id)
		if q.own[r] == 1 and q.deployed[r] == eid:
			return "its own squad is fighting: it cannot leave"
	c.set_value(commander_id, &"engagement", -1)
	s.events.push(&"commander_left_battle", {"commander": commander_id, "engagement": eid,
		"player": player, "plot": c.plot[row]}, s.tick)
	return ""
