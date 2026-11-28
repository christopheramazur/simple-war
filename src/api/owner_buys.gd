class_name OwnerBuys
extends RefCounted
## The remote buys an AI controller makes at its owned features (sw-63wt.11,
## U1 E10, U1Q24): the same buy a human makes from anywhere
## (OverworldSession.set_owner_action), planned from the player's observation
## and the public rules only.
##
## A candidate is one recruits squad that an owned feature with the buy
## action sells. Its weight is the squad's Value, times (1 + the garrison
## threat at the feature), times the share of the Value held that is left
## after paying. A buy is only a candidate while it costs at most KEEP_SHARE
## of the Value held, so a single buy never empties the bank. Without that
## reserve the AI spent its Value on squads every turn and drew battles it
## used to win (sw-63wt.11 sim runs: 8 battles and 34 buys against 1 battle
## and no buys on skirmish_mirror, utility variant). The reserve is per buy,
## not cumulative: a cumulative reserve cost the cautious variant its win.
## Garrison threat is the hostile Value within THREAT_RANGE of the feature
## as a share of that and the player's own Value there. Items (sells) are not
## bought: SimCriteria values no items.
##
## Candidates are taken best first while the Value held covers them and the
## feature is under its purchases-per-turn limit (the plan itself may spend up
## to all the Value held; the resolver then pays in order). Skipped: a feature whose hex
## has an engagement or a hostile commander or detachment on it (the resolver
## would cancel the buy). Ties go to the lower feature ID, then the option ID.

## The share of the Value held a buy must leave (0.5: a buy costs at most half).
const KEEP_SHARE := 0.5

## Planned buys, best first: [{"feature": fid, "option": squad ID, "score"}].
## Plans against the observation's Value; the session still checks each buy
## when it is planned, so a plan that no longer fits is refused, not spent.
static func plan(obs: Dictionary, rules: OverworldRules) -> Array:
	var me := int(obs["player"])
	var value := int(obs.get("value", 0))
	if value <= 0:
		return []
	var orders: Dictionary = obs.get("owner_orders", {})
	var plots: Dictionary = obs["plots"]
	var foes: Array = SimCriteria.forces(obs, rules)[2]
	var busy := {}
	for c: Dictionary in obs["commanders"]:
		if int(c.get("engagement", -1)) >= 0:
			busy[int(c["plot"])] = true
	for f: Array in foes:
		busy[int(f[0])] = true
	var cands := []
	for p: int in plots:
		if busy.has(p):
			continue
		var threat := _threat(obs, rules, p, foes)
		for ft: Dictionary in plots[p]["features"]:
			var t := int(ft["tmpl"])
			var fid := int(ft["id"])
			if int(ft["owner"]) != me or not rules.has_owner_action(t, "buy"):
				continue
			for i in range(0, rules.hf_recruits[t].size(), 2):
				var sq: int = rules.hf_recruits[t][i]
				var option := rules.squad_ids[sq]
				var buy := rules.buy_option(t, option)
				if buy.is_empty() or float(buy[3]) > KEEP_SHARE * float(value):
					continue
				var left := float(value - buy[3]) / float(value)
				cands.append({"feature": fid, "tmpl": t, "option": option, "price": buy[3],
					"score": float(rules.sq_value[sq]) * (1.0 + threat) * left})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		if a["feature"] != b["feature"]:
			return a["feature"] < b["feature"]
		return String(a["option"]) < String(b["option"]))
	# Greedy, best first: the Value held and each feature's limit are spent as planned.
	var out := []
	var spent := 0
	var counts := {}
	for c: Dictionary in cands:
		var fid: int = c["feature"]
		var order: Dictionary = orders.get(fid, {})
		var used: int = (order.get("buys", PackedStringArray()) as PackedStringArray).size() + int(counts.get(fid, 0))
		if float(c["score"]) <= 0.0 or spent + int(c["price"]) > value or used >= rules.hf_buys[c["tmpl"]]:
			continue
		spent += int(c["price"])
		counts[fid] = int(counts.get(fid, 0)) + 1
		out.append({"feature": fid, "option": c["option"], "score": c["score"]})
	return out


## Hostile Value within THREAT_RANGE of plot p as a share of the hostile and
## the player's own Value there; 0 with no hostile near.
static func _threat(obs: Dictionary, rules: OverworldRules, p: int, foes: Array) -> float:
	var me := int(obs["player"])
	var hostile := 0.0
	for f: Array in foes:
		if Hex.plot_distance(p, int(f[0]), rules.width) <= SimCriteria.THREAT_RANGE:
			hostile += float(f[1])
	if hostile <= 0.0:
		return 0.0
	var own := 0.0
	for c: Dictionary in obs["commanders"]:
		if int(c["player"]) == me and Hex.plot_distance(p, int(c["plot"]), rules.width) <= SimCriteria.THREAT_RANGE:
			own += SimCriteria.squads_value(rules, c.get("army", []))
	for d: Dictionary in obs["detachments"]:
		if int(d["player"]) == me and Hex.plot_distance(p, int(d["plot"]), rules.width) <= SimCriteria.THREAT_RANGE:
			own += SimCriteria.squads_value(rules, d.get("squads", []))
	return hostile / (hostile + own)
