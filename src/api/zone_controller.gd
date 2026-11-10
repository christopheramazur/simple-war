class_name ZoneController
extends RefCounted
## A rule-based controller profile (R7Q15): reads only its player's
## observation and returns orders, like any client of the Game API.
##
## Each squad attack-moves to the nearest zone its player doesn't hold;
## when every zone is held, toward the nearest visible enemy; else holds.
## Squads below a break-off point of their HP fall back once. Parameters:
##   fall_back_pct: HP lost (percent) at which a squad falls back (0 = never)
##   run: whether squads run to their objective

var player: int
var fall_back_pct: int = 0
var run: bool = false


func _init(player_id: int, params: Dictionary = {}) -> void:
	player = player_id
	fall_back_pct = int(params.get("fall_back_pct", 0))
	run = bool(params.get("run", false))


func orders(obs: Dictionary) -> Array:
	var out := []
	var targets := []
	for z: Dictionary in obs["zones"]:
		if not (z["owner"] == player and z["amount"] >= z["threshold"]):
			targets.append([z["x"], z["y"]])
	if targets.is_empty():
		for s: Dictionary in obs["squads"]:
			if s["player"] != player:
				targets.append([s["x"], s["y"]])
	for s: Dictionary in obs["squads"]:
		if s["player"] != player or s["destroyed"] or s["withdrawn"]:
			continue
		if fall_back_pct > 0 and s["hp_lost"] * 100 >= s["hp_max"] * fall_back_pct and s["order"] != "fall_back":
			out.append({"squad": s["id"], "type": "fall_back"})
			continue
		if targets.is_empty():
			out.append({"squad": s["id"], "type": "hold"})
			continue
		var best: Array = targets[0]
		var best_d := Fixed.distance(s["x"], s["y"], best[0], best[1])
		for t: Array in targets:
			var d := Fixed.distance(s["x"], s["y"], t[0], t[1])
			if d < best_d:
				best_d = d
				best = t
		out.append({"squad": s["id"], "type": "attack_move", "x": best[0], "y": best[1], "run": run})
	return out


## Takes the first offered reaction, if the profile wants reactions at all.
func reactions(opportunities: Array) -> Array:
	return []
