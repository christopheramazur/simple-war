class_name OverworldTurn
extends RefCounted
## Resolves one overworld turn after planning (GDD 02 §2.2, §2.9):
##   1. movement, with captures and cache pickups on the way;
##   2. activities of commanders that ended on their planned hex;
##   3. production: controlled features pay their owners Value;
##   4. the turn advances, and uncertain-outcome features are offered to
##      players with a commander uncontested on their hex (R6Q14).
## Fog of war memory is recorded at the start and end of the turn and as
## commanders move (OverworldVision).


## Returns the turn's events in order.
static func resolve(s: OverworldState) -> Array[SimEvent]:
	s.begin_turn()
	OverworldVision.update(s)
	OverworldMovement.resolve(s)
	s.routes = {}
	s.drops = {}
	OverworldActivities.resolve(s)
	s.activities = {}
	produce(s)
	OverworldVision.update(s)
	s.turn += 1
	offer(s)
	s.end_tick()
	return s.turn_log


## Every controlled feature pays its owner its Value per turn (R5Q10).
static func produce(s: OverworldState) -> void:
	var totals := {}
	var f := s.features
	for row in f.count():
		var owner := f.owner[row]
		if owner > 0:
			totals[owner] = int(totals.get(owner, 0)) + s.rules.hf_value_per_turn[f.tmpl[row]]
	var players: Array = totals.keys()
	players.sort()
	for p: int in players:
		s.add_value(p, totals[p], &"production")


## Uncertain outcomes (negotiation, battle, interactive events) are presented
## at the start of a turn to the one player whose free commanders stand on
## the hex, uncontested. What answering does belongs to the trigger layer.
static func offer(s: OverworldState) -> void:
	s.offers = []
	var c := s.commanders
	var uncertain := OverworldRules.INTERACTIONS.find("uncertain")
	var plots: Array = s.plot_features.keys()
	plots.sort()
	for p: int in plots:
		var players := {}
		var engaged := false
		for cid in Commanders.at(s, p):
			var row := c.row_of(cid)
			players[c.player[row]] = true
			engaged = engaged or c.engagement[row] >= 0
		if players.size() != 1 or engaged:
			continue
		var player: int = players.keys()[0]
		for fr in s.features_at(p):
			if s.rules.hf_interaction[s.features.tmpl[fr]] == uncertain:
				var o := {"plot": p, "feature": s.features.id_at(fr), "player": player}
				s.offers.append(o)
				s.events.push(&"interaction_offered", o.duplicate(), s.tick)
