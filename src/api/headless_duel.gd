class_name HeadlessDuel
extends RefCounted
## Plays a battle to the end through the Game API with one controller per
## player, at full speed and without presentation (R6Q24, R7Q14).
## A controller is any object with `orders(observation) -> Array` and
## `reactions(opportunities) -> Array` of {"squad","reaction","trigger"}.

## Plays until the battle ends or `max_turns` pass. Returns the session.
static func play(session: BattleSession, controllers: Dictionary, max_turns: int = 50) -> BattleSession:
	var guard := 0
	while not session.is_over() and guard < max_turns * 4:
		guard += 1
		match session.clock.phase:
			PulseClock.Phase.PLANNING:
				for p in session.players():
					session.submit_orders(p, controllers[p].orders(session.observe(p)))
				for p in session.players():
					session.ready(p)
			PulseClock.Phase.REACTION:
				for p in session.players():
					for re: Dictionary in controllers[p].reactions(session.reaction_opportunities(p)):
						session.submit_reaction(p, re["squad"], re["reaction"], re["trigger"])
				for p in session.players():
					session.ready(p)
			PulseClock.Phase.INTERMISSION:
				for p in session.players():
					session.ready(p)
			_:
				break
	return session
