class_name UtilityBattle
extends RefCounted
## The utility decision process for battles (GDD 05 §5.4, A2Q6). Each
## active squad scores candidate orders by the criteria they would lead to
## (SimCriteria's battle forms, adjusted by a quick estimate, no lookahead),
## weighed through the profile's mask, discounted by distance:
##   - capture: attack-move to a zone we don't hold (objective control);
##   - attack: attack-move on a seen enemy squad; the exchange is estimated
##     with Lanchester's square law between the two squads (value
##     efficiency, force ratio);
##   - fall back: a hurt squad near stronger enemies keeps what it has
##     left instead of trading it away;
##   - hold: scores 0.
## Squad Value comes from the battle rules when the controller has them
## (set_rules), else from hit points. Leader squads (`leaders`: a
## commander's own squad, whose loss defeats the commander) stay back:
## they capture or attack only while their side outweighs every enemy in
## sight by leader_margin (or, alone, while no enemy is in sight), and fall
## back once enemies in sight are too strong, whatever their losses. A
## battle turn is long enough to cross the field, so distance is no
## shelter.
##
## Params: run (false), fall_back_pct (30, HP lost before falling back is
## considered), outcome_weight (1.0: winning zones outright; losing a
## leader costs the whole weight), leader_margin ("1.5": how much stronger
## a leader must be to attack).

var player: int
var mask: SimCriteria.Mask
var rules: BattleRules
var fuzz := 0.0
var rng: SimRng
var run := false
var fall_back_pct := 30
var outcome_weight := 1.0
var leader_margin := 1.5
## Battle squad IDs of leader squads (set by ProfileController).
var leaders: Dictionary = {}


func _init(player_id: int, mask_in: SimCriteria.Mask, params: Dictionary = {}, fuzz_in: float = 0.0, rng_in: SimRng = null) -> void:
	player = player_id
	mask = mask_in
	fuzz = fuzz_in
	rng = rng_in if rng_in != null else SimRng.new(player_id)
	run = bool(params.get("run", run))
	fall_back_pct = int(params.get("fall_back_pct", fall_back_pct))
	outcome_weight = float(params.get("outcome_weight", outcome_weight))
	leader_margin = float(params.get("leader_margin", leader_margin))


func _value(q: Dictionary) -> float:
	if rules != null:
		var v := SimCriteria.battle_value(rules, q)
		if v > 0.0:
			return v
	return maxf(float(q.get("hp_max", 0)) - float(q.get("hp_lost", 0)), 0.0)


func orders(obs: Dictionary) -> Array:
	var now := _values(obs)
	var cond := _conditions(obs, now)
	var w := mask.weights(cond)
	var base_u := SimCriteria.utility(now, w)
	var own := 0.0
	var enemy := 0.0
	var enemies := []
	var mine := []
	for q: Dictionary in obs["squads"]:
		if bool(q.get("destroyed", false)) or bool(q.get("withdrawn", false)):
			continue
		if int(q["player"]) == player:
			own += _value(q)
			mine.append(q)
		else:
			enemy += _value(q)
			enemies.append(q)
	var zones := []
	for z: Dictionary in obs["zones"]:
		if not bool(z.get("locked", false)) and not (int(z["owner"]) == player and int(z["amount"]) >= int(z["threshold"])):
			zones.append(z)
	var open := 0
	var held := 0
	for z: Dictionary in obs["zones"]:
		if not bool(z.get("locked", false)):
			open += 1
			held += 1 if int(z["owner"]) == player else 0
	var reach := 1.0
	for q: Dictionary in mine:
		for t: Dictionary in zones + enemies:
			reach = maxf(reach, float(Fixed.distance(q["x"], q["y"], t["x"], t["y"])))
	var out := []
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for q: Dictionary in mine:
		var v := _value(q)
		var leader := leaders.has(int(q["id"]))
		var safe := own >= enemy * leader_margin if not enemies.is_empty() else mine.size() == 1
		var scored := []
		for z: Dictionary in zones:
			if leader and not safe:
				continue
			var p := now.duplicate()
			p["objective_control"] = 0.0 if open <= 0 else float(held + (0 if int(z["owner"]) == player else 1)) / open
			var bonus := outcome_weight * 0.25 if held + 1 >= open else 0.0
			scored.append([_gain(p, w, base_u, bonus, q, z, reach), {"squad": q["id"], "type": "attack_move", "x": z["x"], "y": z["y"], "run": run}])
		for e: Dictionary in enemies:
			var ev := _value(e)
			if leader and not safe:
				continue
			var p := now.duplicate()
			var lost := 0.0
			var killed := 0.0
			if v > ev:
				killed = ev
				lost = v - sqrt(v * v - ev * ev)
			else:
				lost = v
				killed = ev - sqrt(maxf(ev * ev - v * v, 0.0))
			var o2 := own - lost
			var e2 := enemy - killed
			p["force_ratio"] = 0.5 if o2 + e2 <= 0.0 else o2 / (o2 + e2)
			p["value_efficiency"] = _efficiency(obs, killed, lost)
			scored.append([_gain(p, w, base_u, 0.0, q, e, reach), {"squad": q["id"], "type": "attack_move", "x": e["x"], "y": e["y"], "run": run}])
		var hurt := int(q.get("hp_max", 0)) > 0 and int(q.get("hp_lost", 0)) * 100 >= int(q["hp_max"]) * fall_back_pct
		if (hurt or (leader and not safe and not enemies.is_empty())) and String(q.get("order", "")) != "fall_back":
			var near := enemy if leader else 0.0
			if not leader:
				for e: Dictionary in enemies:
					if Fixed.distance(q["x"], q["y"], e["x"], e["y"]) * 4 <= int(reach):
						near += _value(e)
			if near > (0.0 if leader else v):
				# Staying risks the squad (chance near / (v + near)); falling back keeps it.
				var p := now.duplicate()
				p["force_ratio"] = 0.5 if own - v + enemy <= 0.0 else (own - v) / (own - v + enemy)
				var kept := (base_u - SimCriteria.utility(p, w) + (outcome_weight if leader else 0.0)) * near / (v + near)
				scored.append([kept, {"squad": q["id"], "type": "fall_back"}])
		_add_fuzz(scored)
		var best: Array = [0.0, {"squad": q["id"], "type": "hold"}]
		for s: Array in scored:
			if s[0] > best[0]:
				best = s
		out.append(best[1])
	return out


## Gain per distance: nearer targets count more.
func _gain(p: Dictionary, w: Dictionary, base_u: float, bonus: float, q: Dictionary, t: Dictionary, reach: float) -> float:
	var d := float(Fixed.distance(q["x"], q["y"], t["x"], t["y"]))
	return (SimCriteria.utility(p, w) - base_u + bonus) / (1.0 + 3.0 * d / reach)


func _efficiency(obs: Dictionary, killed: float, lost: float) -> float:
	var me := int(obs["player"])
	var scores: Dictionary = obs.get("scores", {})
	var destroyed := float((scores.get(me, {}) as Dictionary).get("value", 0)) + killed
	var own_lost := lost
	for q: Dictionary in obs["squads"]:
		if int(q["player"]) == me:
			own_lost += maxf(float(q.get("hp_lost", 0)), 0.0) if rules == null else 0.0
	var total := destroyed + own_lost
	return 0.5 if total <= 0.0 else destroyed / total


func _values(obs: Dictionary) -> Dictionary:
	if rules != null:
		return SimCriteria.battle(obs, rules)
	var me := int(obs["player"])
	var own := 0.0
	var enemy := 0.0
	for q: Dictionary in obs["squads"]:
		if bool(q.get("withdrawn", false)):
			continue
		if int(q["player"]) == me:
			own += _value(q)
		else:
			enemy += _value(q)
	var held := 0
	var open := 0
	for z: Dictionary in obs["zones"]:
		if not bool(z.get("locked", false)):
			open += 1
			held += 1 if int(z["owner"]) == me else 0
	return {"margin": 0.0, "value_efficiency": _efficiency(obs, 0.0, 0.0),
		"force_ratio": 0.5 if own + enemy <= 0.0 else own / (own + enemy),
		"objective_control": 0.0 if open <= 0 else float(held) / open}


func _conditions(obs: Dictionary, values: Dictionary) -> Dictionary:
	if rules != null:
		return SimCriteria.battle_conditions(obs, rules, mask.contact_turn)
	var turn := int(obs["turn"])
	var seen := false
	for q: Dictionary in obs["squads"]:
		seen = seen or (int(q["player"]) != player and not bool(q.get("destroyed", false)))
	var ct := mask.contact_turn
	if ct < 0 and seen:
		ct = turn
	return {"turn": float(turn), "contact": 1.0 if ct >= 0 else 0.0, "since_contact": -1.0 if ct < 0 else float(turn - ct),
		"fog_pct": 0.0, "force_ratio": values["force_ratio"], "threat": 0.0, "bank": 0.0, "ahead": values["margin"]}


func _add_fuzz(scored: Array) -> void:
	if fuzz <= 0.0 or scored.is_empty():
		return
	var top := 0.0
	for s: Array in scored:
		top = maxf(top, absf(s[0]))
	for s: Array in scored:
		s[0] += fuzz * top * (float(rng.next_below(2001)) / 1000.0 - 1.0)


## No reactions yet (the reaction window is a later gene).
func reactions(_opportunities: Array) -> Array:
	return []
