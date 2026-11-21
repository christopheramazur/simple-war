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
## The side's spawn facing (BattleRules.sides). At 180° the equal-distance
## tie-break reverses, so mirror seats pick mirrored targets (sw-0nl).
var facing: int = 0


func _init(player_id: int, params: Dictionary = {}) -> void:
	player = player_id
	fall_back_pct = int(params.get("fall_back_pct", 0))
	run = bool(params.get("run", false))


## Battle rules carry the side's facing; HeadlessDuel offers them before play.
func set_battle_rules(rules: BattleRules) -> void:
	for side: Dictionary in rules.sides:
		if int(side["player"]) == player:
			facing = int(side["facing"])
			return


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
			if d < best_d or (d == best_d and _tie_before(t, best)):
				best_d = d
				best = t
		out.append({"squad": s["id"], "type": "attack_move", "x": best[0], "y": best[1], "run": run})
	return out


## Equal-distance targets go to the lowest x then y in the side's frame; a
## 180° facing reverses both, mirroring the choice (sw-0nl). List order never
## decides.
func _tie_before(a: Array, b: Array) -> bool:
	var flip := facing == Fixed.ANGLE_HALF
	if a[0] != b[0]:
		return (a[0] > b[0]) if flip else (a[0] < b[0])
	return (a[1] > b[1]) if flip else (a[1] < b[1])


## Takes the first offered reaction, if the profile wants reactions at all.
func reactions(opportunities: Array) -> Array:
	return []
