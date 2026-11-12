class_name GuardController
extends RefCounted
## Battle behaviour for the neutral side of overworld battles: guards and
## Angels (GDD 02 §2.11, R6Q17). Runs on the server side each Reveal
## (OverworldSession), deterministically from the neutral player's own
## observation, so replays reproduce it.
##   - Every guard squad attacks the nearest enemy squad it can see, and
##     holds while it sees none.
##   - Squads with the "hunter" keyword (Angels) go for squads with the
##     "civilian" keyword first, whatever else is nearer (they hunt the
##     civilians, GDD 06 §6.9). Seeing nobody, a hunter doesn't wait: it
##     attack-moves to the nearest zone it doesn't hold, where the prey
##     must come.


static func orders(obs: Dictionary, rules: BattleRules, player: int) -> Array:
	var out := []
	var enemies := []
	for s: Dictionary in obs.get("squads", []):
		if s["player"] != player and not s["destroyed"] and not s["withdrawn"]:
			enemies.append(s)
	for s: Dictionary in obs.get("squads", []):
		if s["player"] != player or s["destroyed"] or s["withdrawn"]:
			continue
		var pool := enemies
		if _has(rules, s["template"], "hunter"):
			var prey := enemies.filter(func(e: Dictionary) -> bool: return _has(rules, e["template"], "civilian"))
			if not prey.is_empty():
				pool = prey
		var best := {}
		var best_d := 0
		for e: Dictionary in pool:
			var d := Fixed.distance(s["x"], s["y"], e["x"], e["y"])
			if best.is_empty() or d < best_d or (d == best_d and e["id"] < best["id"]):
				best = e
				best_d = d
		if best.is_empty():
			var zone := _nearest_zone(obs, s, player) if _has(rules, s["template"], "hunter") else {}
			if zone.is_empty():
				out.append({"squad": s["id"], "type": "hold"})
			else:
				out.append({"squad": s["id"], "type": "attack_move", "x": zone["x"], "y": zone["y"]})
		else:
			out.append({"squad": s["id"], "type": "attack", "target": best["id"]})
	return out


static func _nearest_zone(obs: Dictionary, s: Dictionary, player: int) -> Dictionary:
	var best := {}
	var best_d := 0
	for z: Dictionary in obs.get("zones", []):
		if z["owner"] == player:
			continue
		var d := Fixed.distance(s["x"], s["y"], z["x"], z["y"])
		if best.is_empty() or d < best_d:
			best = z
			best_d = d
	return best


static func _has(rules: BattleRules, template: String, keyword: String) -> bool:
	var i := rules.squad_index(template)
	return i >= 0 and rules.sq_keywords[i].has(keyword)
