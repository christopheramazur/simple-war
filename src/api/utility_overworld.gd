class_name UtilityOverworld
extends RefCounted
## The utility decision process for the overworld (GDD 05 §5.4, A2Q6). For
## each free commander it lists candidate orders, estimates the criteria
## each would lead to (SimCriteria's decision-time forms, adjusted by a quick
## model of the order's effect, no simulated lookahead), weighs them
## through the profile's mask, and takes the best gain per turn of travel.
## Staying put scores 0. Commanders never share a target.
##
## Candidates and their estimated effects:
##   - take: a known feature to capture (controllable, not ours) or a cache;
##     guarded ones need a battle against the guard (see fights below);
##   - convert: a known convertible hex we can pay for (it becomes ours);
##   - recruit: an own hex offering recruits, with the strongest squad we
##     can afford and the army has room for (spending Value, A2Q4);
##   - attack: a seen hostile commander or detachment, at its guessed
##     strength (enemy armies are never shown, R5Q9);
##   - explore: the nearest unexplored hexes (more fog revealed);
##   - every destination also changes the commander's safety.
## Fights are estimated with Lanchester's square law between the
## commander's battleforce (what would fight) and the foe: the stronger side
## wins keeping sqrt(a² - b²); a lost fight defeats the commander and
## scatters its whole army. Winning against a commander adds half the
## outcome weight; losing our last commander subtracts the whole weight.
##
## Params: outcome_weight (1.0), risk (1.0, multiplies guessed enemy
## strength), explore (6, unexplored hexes considered per commander),
## cache_scale (10, Value at which a cache counts half of the economy
## gain). Reads only its player's observation, the public rules and
## session.path.

var player: int
var mask: SimCriteria.Mask
var fuzz := 0.0
var rng: SimRng
var outcome_weight := 1.0
var risk := 1.0
var explore := 6
var cache_scale := 10.0


func _init(player_id: int, mask_in: SimCriteria.Mask, params: Dictionary = {}, fuzz_in: float = 0.0, rng_in: SimRng = null) -> void:
	player = player_id
	mask = mask_in
	fuzz = fuzz_in
	rng = rng_in if rng_in != null else SimRng.new(player_id)
	outcome_weight = float(params.get("outcome_weight", outcome_weight))
	risk = float(params.get("risk", risk))
	explore = int(params.get("explore", explore))
	cache_scale = float(params.get("cache_scale", cache_scale))


func plan(obs: Dictionary, session: OverworldSession) -> Array:
	var r := session.rules
	var now := SimCriteria.overworld(obs, r)
	var w := mask.weights(SimCriteria.overworld_conditions(obs, r, mask.contact_turn))
	var base_u := SimCriteria.utility(now, w)
	var ctx := _context(obs, r)
	var out := []
	var busy := {}
	var mine := []
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) == player and int(c["engagement"]) < 0:
			mine.append(c)
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for c: Dictionary in mine:
		var scored := []
		for cand: Dictionary in _candidates(c, obs, r, ctx):
			if busy.has(cand["plot"]):
				continue
			var v := _predict(now, ctx, c, cand, r)
			var gain := SimCriteria.utility(v, w) - base_u + outcome_weight * float(cand.get("outcome", 0.0))
			scored.append([gain / _turns(c, int(cand["plot"]), r), cand])
		_add_fuzz(scored)
		scored.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] > b[0] or (a[0] == b[0] and int(a[1]["plot"]) < int(b[1]["plot"])))
		for s: Array in scored:
			if s[0] <= 0.0:
				break
			var cand: Dictionary = s[1]
			var o := _order(c, cand, session)
			if not o.is_empty():
				busy[cand["plot"]] = true
				out.append(o)
				break
	return out


## Fuzz (A1Q4): deterministic noise, `fuzz` times the largest score.
func _add_fuzz(scored: Array) -> void:
	if fuzz <= 0.0 or scored.is_empty():
		return
	var top := 0.0
	for s: Array in scored:
		top = maxf(top, absf(s[0]))
	for s: Array in scored:
		s[0] += fuzz * top * (float(rng.next_below(2001)) / 1000.0 - 1.0)


func _order(c: Dictionary, cand: Dictionary, session: OverworldSession) -> Dictionary:
	var to: int = cand["plot"]
	var route := PackedInt64Array()
	if to != int(c["plot"]):
		route = session.path(player, int(c["id"]), to)
		if route.is_empty() or route[route.size() - 1] != to:
			return {}
	var o := {"commander": c["id"], "route": route}
	if cand.has("activity"):
		o["activity"] = cand["activity"]
		o["option"] = cand.get("option", "")
	elif route.is_empty():
		return {}
	return o


## Turns of travel to plot, at least 1.
static func _turns(c: Dictionary, plot: int, r: OverworldRules) -> float:
	var d := Hex.plot_distance(int(c["plot"]), plot, r.width)
	var per := maxf(float(r.cm_mp[int(c["tmpl"])]) / maxf(float(r.base_cost), 1.0), 1.0)
	return maxf(ceilf(d / per), 1.0)


## What the estimates need from the observation.
func _context(obs: Dictionary, r: OverworldRules) -> Dictionary:
	var f := SimCriteria.forces(obs, r)
	var owned := 0
	var known := 0
	var producing := 0
	var known_producing := 0
	for p: int in obs["plots"]:
		for ft: Dictionary in obs["plots"][p]["features"]:
			known += 1
			var makes := SimCriteria.makes_value(r, int(ft["tmpl"]))
			known_producing += 1 if makes else 0
			if int(ft["owner"]) == player:
				owned += 1
				producing += 1 if makes else 0
	var own_cmds := 0
	var safety_of := {}
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) != player:
			continue
		own_cmds += 1
		var a := SimCriteria.squads_value(r, c.get("army", []))
		var e := 0.0
		for foe: Array in f[2]:
			if Hex.plot_distance(int(c["plot"]), foe[0], r.width) <= SimCriteria.THREAT_RANGE:
				e += float(foe[1]) * risk
		safety_of[int(c["id"])] = 1.0 if a + e <= 0.0 else a / (a + e)
	return {"own": f[0], "enemy": f[1], "foes": f[2], "owned": owned, "known": known, "producing": producing,
		"known_producing": known_producing, "seen": (obs["plots"] as Dictionary).size(), "plots_seen": obs["plots"],
		"own_cmds": own_cmds, "safety_of": safety_of, "value": int(obs.get("value", 0))}


func _guard_value(r: OverworldRules, t: int) -> float:
	var v := 0.0
	for id in r.hf_guard[t]:
		var sq := r.squad_index(id)
		if sq >= 0:
			v += r.sq_value[sq]
	return v


func _candidates(c: Dictionary, obs: Dictionary, r: OverworldRules, ctx: Dictionary) -> Array:
	var out := []
	var plots: Dictionary = obs["plots"]
	var army := SimCriteria.squads_value(r, c.get("army", []))
	var room := r.cm_army_cap[int(c["tmpl"])] - ((c.get("army", []) as Array).size() - (1 if r.cm_own_squad[int(c["tmpl"])] >= 0 else 0))
	for p: int in plots:
		var guard := 0.0
		var cand := {}
		for ft: Dictionary in plots[p]["features"]:
			var t := int(ft["tmpl"])
			guard += _guard_value(r, t)
			if r.hf_controllable[t] == 1 and int(ft["owner"]) != player:
				cand["take"] = t
			if r.hf_cache_value[t] > 0:
				cand["cache"] = r.hf_cache_value[t]
			if r.has_activity(t, "convert") and ctx["value"] >= r.hf_activity_cost[t] and r.hf_converts_to[t] >= 0:
				cand["convert"] = r.hf_converts_to[t]
				cand["activity"] = "convert"
			if int(ft["owner"]) == player and r.has_activity(t, "recruit") and room > 0:
				var best := -1
				for i in range(0, r.hf_recruits[t].size(), 2):
					var sq: int = r.hf_recruits[t][i]
					var cost: int = r.hf_recruits[t][i + 1] + r.hf_activity_cost[t]
					if cost <= ctx["value"] and (best < 0 or r.sq_value[sq] > r.sq_value[best]):
						best = sq
				if best >= 0:
					cand["recruit"] = float(r.sq_value[best])
					cand["activity"] = "recruit"
					cand["option"] = r.squad_ids[best]
		if cand.is_empty():
			continue
		cand["plot"] = p
		if guard > 0.0:
			cand["fight"] = guard * risk
		out.append(cand)
	for foe: Array in ctx["foes"]:
		out.append({"plot": foe[0], "fight": float(foe[1]) * risk, "foe": true})
	var at := int(c["plot"])
	var frontier := []
	var n: int = int(obs["width"]) * int(obs["height"])
	for p in n:
		if not plots.has(p):
			frontier.append([Hex.plot_distance(at, p, r.width), p])
	frontier.sort()
	for i in mini(explore, frontier.size()):
		out.append({"plot": frontier[i][1], "explore": true})
	var bf_ids: Variant = c.get("battleforce", [])
	var bf := 0.0
	for q: Dictionary in c.get("army", []):
		if (bf_ids as Array).has(int(q["id"])) if bf_ids is Array else (bf_ids as PackedInt64Array).has(int(q["id"])):
			bf += SimCriteria.squads_value(r, [q])
	for cand: Dictionary in out:
		cand["army"] = army
		cand["bf"] = bf if bf > 0.0 else army
	return out


## The criteria an order would lead to (a quick estimate, no lookahead).
func _predict(now: Dictionary, ctx: Dictionary, c: Dictionary, cand: Dictionary, r: OverworldRules) -> Dictionary:
	var v := now.duplicate()
	var own: float = ctx["own"]
	var enemy: float = ctx["enemy"]
	var army: float = cand["army"]
	var alive := true
	if cand.has("fight"):
		var e: float = cand["fight"]
		var bf: float = cand["bf"]
		if bf > e:
			var lost := bf - sqrt(bf * bf - e * e)
			own -= lost
			army -= lost
			if cand.get("foe", false):
				enemy = maxf(enemy - e / risk, 0.0)
				cand["outcome"] = 0.5
		else:
			own -= army
			alive = false
			if cand.get("foe", false):
				enemy = maxf(enemy - (e - sqrt(maxf(e * e - bf * bf, 0.0))) / risk, 0.0)
			if ctx["own_cmds"] <= 1:
				cand["outcome"] = -1.0
	if alive and cand.has("recruit"):
		own += float(cand["recruit"])
		army += float(cand["recruit"])
	var ratio := 0.5 if own + enemy <= 0.0 else own / (own + enemy)
	v["force_ratio"] = ratio
	v["margin"] = ratio * 2.0 - 1.0
	if alive:
		var owned: int = ctx["owned"]
		var producing: int = ctx["producing"]
		if cand.has("take"):
			owned += 1
			producing += 1 if SimCriteria.makes_value(r, int(cand["take"])) else 0
		if cand.has("convert") and r.hf_controllable[int(cand["convert"])] == 1:
			owned += 1
			producing += 1 if SimCriteria.makes_value(r, int(cand["convert"])) else 0
		v["objective_control"] = 0.0 if ctx["known"] <= 0 else float(owned) / ctx["known"]
		var econ: float = 0.5 if ctx["known_producing"] <= 0 else float(producing) / ctx["known_producing"]
		if cand.has("cache"):
			econ += (1.0 - econ) * 0.5 * float(cand["cache"]) / (float(cand["cache"]) + cache_scale)
		v["economy"] = econ
		var seen: int = ctx["seen"] + _new_sight(cand, c, r, ctx)
		var target := float((SimCriteria.library().get("criteria", {}) as Dictionary).get("exploration", {}).get("params", {}).get("target_pct", 60))
		v["exploration"] = clampf(100.0 * seen / maxi(r.plot_count(), 1) / maxf(target, SimCriteria.EPS), 0.0, 1.0)
	v["commander_safety"] = _safety(cand, c, army, alive, ctx, r)
	return v


## Unexplored hexes the commander would see from its destination.
func _new_sight(cand: Dictionary, c: Dictionary, r: OverworldRules, ctx: Dictionary) -> int:
	if not cand.has("unseen"):
		var n := 0
		for p in Hex.within(int(cand["plot"]), r.cm_sight[int(c["tmpl"])], r.width, r.height):
			if not (ctx["plots_seen"] as Dictionary).has(p):
				n += 1
		cand["unseen"] = n
	return cand["unseen"]


## The weakest own commander's safety after the move.
func _safety(cand: Dictionary, c: Dictionary, army: float, alive: bool, ctx: Dictionary, r: OverworldRules) -> float:
	if not alive and ctx["own_cmds"] <= 1:
		return 0.0
	var safety := 1.0  # a fallen commander is no longer at risk
	if alive:
		var e := 0.0
		for f: Array in ctx["foes"]:
			if cand.get("foe", false) and int(f[0]) == int(cand["plot"]):
				continue  # beaten
			if Hex.plot_distance(int(cand["plot"]), f[0], r.width) <= SimCriteria.THREAT_RANGE:
				e += float(f[1]) * risk
		safety = 1.0 if army + e <= 0.0 else army / (army + e)
	var others: Dictionary = ctx["safety_of"]
	for cid: int in others:
		if cid != int(c["id"]):
			safety = minf(safety, float(others[cid]))
	return safety
