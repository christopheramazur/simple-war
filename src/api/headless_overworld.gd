class_name HeadlessOverworld
extends RefCounted
## Plays overworld turns through the Game API with one controller per player,
## at full speed and without presentation (R6Q24, R7Q14). A controller is any
## object with `plan(observation, session) -> Array` of {"commander",
## "route" (PackedInt64Array), "activity" (String, optional)}; it may call
## only player-scoped queries (session.observe / session.path).


## Plays until `turns` overworld turns have resolved. Returns the session.
static func play(session: OverworldSession, controllers: Dictionary, turns: int) -> OverworldSession:
	var guard := 0
	while session.turns_resolved() < turns and guard < turns * 4:
		guard += 1
		match session.clock.phase:
			PulseClock.Phase.PLANNING:
				for p in session.players():
					for o: Dictionary in controllers[p].plan(session.observe(p), session):
						session.set_route(p, o["commander"], o["route"])
						if not String(o.get("activity", "")).is_empty():
							session.set_activity(p, o["commander"], o["activity"])
				for p in session.players():
					session.ready(p)
			PulseClock.Phase.INTERMISSION:
				for p in session.players():
					session.ready(p)
			_:
				break
	return session
