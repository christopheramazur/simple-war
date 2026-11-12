class_name OverworldTurn
extends RefCounted
## Resolves one overworld turn after planning (GDD 02 §2.2, §2.9):
##   1. movement, with captures and cache pickups on the way;
##   2. activities of commanders that ended on their planned hex;
##   3. production: controlled features pay their owners Value;
##   4. the turn advances, and uncertain-outcome features are offered to
##      players with a commander uncontested on their hex (R6Q14);
##   5. the map's triggers run over the turn's events (Triggers).
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
	if s.rules.triggers != null:
		s.rules.triggers.run(s, s.events.all())
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
	Convoys.produce(s)


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
				var ev := o.duplicate()
				ev["template"] = s.rules.feature_ids[s.features.tmpl[fr]]
				s.events.push(&"interaction_offered", ev, s.tick)


## Answers an offer made to the player this turn with one of the feature's
## `choices`; what that does is up to the map's triggers ("offer_answered").
## Each offer is answered once. "" or why not.
static func answer(s: OverworldState, player: int, fid: int, choice: String) -> String:
	var at := -1
	for i in s.offers.size():
		if s.offers[i]["feature"] == fid and s.offers[i]["player"] == player:
			at = i
	if at < 0:
		return "no such offer"
	var row := s.features.row_of(fid)
	var t := s.features.tmpl[row]
	if not s.rules.hf_choices[t].has(choice):
		return "no such choice"
	var o: Dictionary = s.offers[at]
	s.offers.remove_at(at)
	s.events.push(&"offer_answered", {"player": player, "feature": fid, "plot": o["plot"],
		"template": s.rules.feature_ids[t], "choice": choice}, s.tick)
	return ""
