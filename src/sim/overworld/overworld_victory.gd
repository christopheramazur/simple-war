class_name OverworldVictory
extends RefCounted
## Built-in overworld win conditions (GDD 05 §5.4, A2Q2). Story missions end
## through their triggers' end_mission instead.
##   - Elimination (the map's `elimination`, duel-style skirmish): once every
##     commander of all teams but one is defeated, that team wins. If the
##     last commanders of every team fall together, the game is a draw.
## The outcome reads from player 1's view (won / lost / drew, like a
## mission), and "winner" names the winning player (0 = draw).


## Checks after commanders may have fallen (a battle ended).
static func check(s: OverworldState) -> void:
	if not s.outcome.is_empty() or not s.rules.elimination:
		return
	var teams := {}
	for row in s.commanders.count():
		teams[s.team_of(s.commanders.player[row])] = true
	if teams.size() > 1:
		return
	var winner := 0
	if teams.size() == 1:
		var team: int = teams.keys()[0]
		for p in s.rules.players():
			if s.team_of(p) == team:
				winner = p
				break
	var o := "drew"
	if winner > 0:
		o = "won" if s.team_of(winner) == s.team_of(1) else "lost"
	s.outcome = {"outcome": o, "winner": winner, "key": "elimination",
		"text": "A side has no commanders left.", "turn": s.turn}
	s.events.push(&"mission_ended", s.outcome.duplicate(), s.tick)
