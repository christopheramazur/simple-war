class_name OverworldTurn
extends RefCounted
## Resolves one overworld turn after planning (GDD 02 §2.2, §2.9). Later
## steps add quick actions, activities, production and fog here.


## Moves every commander along its route, clears routes and advances the
## turn. Returns the turn's events in order.
static func resolve(s: OverworldState) -> Array[SimEvent]:
	s.begin_turn()
	OverworldMovement.resolve(s)
	s.routes = {}
	s.turn += 1
	s.end_tick()
	return s.turn_log
