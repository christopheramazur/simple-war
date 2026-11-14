class_name HeadlessOverworld
extends RefCounted
## Plays overworld turns through the Game API with one controller per player,
## at full speed and without presentation (R6Q24, R7Q14). A controller is any
## object with `plan(observation, session) -> Array` of {"commander",
## "route" (PackedInt64Array), "activity" and "option" (Strings,
## optional)}; it may call
## only player-scoped queries (session.observe / session.path). A
## controller with `battle_orders(battle_observation) -> Array` also fights
## the battles its player is in, and one with `reactions(opportunities)
## -> Array` of {"engagement", "squad", "reaction", "trigger"} reacts in the
## reaction window. One with `set_battle_rules(rules)` is given each
## battle's (public) rules before its battle orders.


## Plays until `turns` overworld turns have resolved. Returns the session.
static func play(session: OverworldSession, controllers: Dictionary, turns: int) -> OverworldSession:
	var guard := 0
	while session.turns_resolved() < turns and guard < turns * 5:
		guard += 1
		match session.clock.phase:
			PulseClock.Phase.PLANNING:
				for p in session.players():
					plan_for(session, p, controllers[p])
				for p in session.players():
					session.ready(p)
			PulseClock.Phase.REACTION:
				for p in session.players():
					react_for(session, p, controllers[p])
				for p in session.players():
					session.ready(p)
			PulseClock.Phase.INTERMISSION:
				for p in session.players():
					session.ready(p)
			_:
				break
	return session


## One player's planning: overworld orders, then battle orders for every
## battle the player is in. The war room calls it for AI opponents.
static func plan_for(session: OverworldSession, p: int, controller: Object) -> void:
	for o: Dictionary in controller.plan(session.observe(p), session):
		session.set_route(p, o["commander"], o["route"])
		if not String(o.get("activity", "")).is_empty():
			session.set_activity(p, o["commander"], o["activity"], o.get("option", ""))
	if controller.has_method("battle_orders"):
		var eids: Array = session.battles.keys()
		eids.sort()
		for eid: int in eids:
			var bo := session.observe_battle(p, eid)
			if not bo.is_empty():
				if controller.has_method("set_battle_rules"):
					controller.set_battle_rules((session.battles[eid] as OverworldBattle).state.rules)
				session.submit_battle_orders(p, eid, controller.battle_orders(bo))


## One player's reactions in the reaction window.
static func react_for(session: OverworldSession, p: int, controller: Object) -> void:
	if controller.has_method("reactions"):
		for re: Dictionary in controller.reactions(session.reaction_opportunities(p)):
			session.submit_reaction(p, re["engagement"], re["squad"], re["reaction"], re["trigger"])
