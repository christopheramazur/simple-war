class_name OverworldActivities
extends RefCounted
## Activities (GDD 02 §2.9, R4Q12): refit, recruit, a commander-led battle,
## converting a resource node. Planned with OverworldOrders.set_activity and
## performed after movement, only by a commander that ended its route on the
## planned hex and is not in a battle. The Value cost is paid on performing.
##   convert: the feature becomes its converts_to feature, owned by the player.
##   battle:  an engagement starts on the hex (battles begin at turn start).
##   recruit: the squad named by the plan joins the army at full strength,
##            if the army has room; costs activity_cost + the option's cost.
##   refit:   every squad of the army returns to full strength; costs
##            activity_cost + refit_cost per unit restored.


## The row of the first feature (by template order) on plot p that offers
## the activity, or -1.
static func offering(s: OverworldState, p: int, activity: String) -> int:
	for fr in s.features_at(p):
		if s.rules.has_activity(s.features.tmpl[fr], activity):
			return fr
	return -1


static func resolve(s: OverworldState) -> void:
	var c := s.commanders
	var ids: Array = s.activities.keys()
	ids.sort()
	for cid: int in ids:
		var row := c.row_of(cid)
		if row < 0:
			continue
		var a: Dictionary = s.activities[cid]
		var activity: String = a["activity"]
		var p: int = a["plot"]
		var option: String = a.get("option", "")
		var why := ""
		var cost := 0
		var fr := offering(s, p, activity)
		if c.plot[row] != p:
			why = "did not reach the hex"
		elif c.engagement[row] >= 0:
			why = "is in a battle"
		elif fr < 0:
			why = "no longer offered here"
		else:
			var t := s.features.tmpl[fr]
			cost = s.rules.hf_activity_cost[t]
			match activity:
				"recruit":
					var sq := s.rules.squad_index(option)
					var price := s.rules.recruit_cost(t, sq) if sq >= 0 else -1
					if price < 0:
						why = "no longer offered here"
					elif OverworldArmies.count(s, cid) >= OverworldArmies.cap(s, cid):
						why = "the army is full"
					cost += maxi(price, 0)
				"refit":
					var lost := OverworldArmies.losses(s, cid)
					if lost == 0:
						why = "the army has no losses"
					cost += lost * s.rules.hf_refit_cost[t]
			if why.is_empty() and s.value_of(c.player[row]) < cost:
				why = "not enough Value"
		if not why.is_empty():
			s.events.push(&"activity_cancelled", {"commander": cid, "plot": p, "activity": activity, "reason": why}, s.tick)
			continue
		_perform(s, row, fr, activity, option, cost)


static func _perform(s: OverworldState, row: int, fr: int, activity: String, option: String, cost: int) -> void:
	var c := s.commanders
	var f := s.features
	var cid := c.id_at(row)
	var player := c.player[row]
	var p := f.plot[fr]
	var t := f.tmpl[fr]
	var fid := f.id_at(fr)
	s.add_value(player, -cost, &"activity")
	s.events.push(&"activity_performed", {"commander": cid, "plot": p, "activity": activity, "feature": fid}, s.tick)
	match activity:
		"convert":
			var into := s.rules.hf_converts_to[t]
			s.remove_feature(fid)
			var nid := s.add_feature(p, into, player if s.rules.hf_controllable[into] == 1 else 0)
			s.events.push(&"feature_converted", {"plot": p, "from": fid, "to": nid, "player": player}, s.tick)
		"recruit":
			var sid := OverworldArmies.add(s, cid, s.rules.squad_index(option))
			s.events.push(&"squad_recruited", {"commander": cid, "squad": sid, "tmpl": option, "plot": p}, s.tick)
		"refit":
			var n := OverworldArmies.refit(s, cid)
			s.events.push(&"army_refitted", {"commander": cid, "plot": p, "units": n}, s.tick)
		"battle":
			var eid := s.engagement_at(p)
			if eid < 0:
				eid = s.engagements.spawn({&"plot": p, &"kinds": OverworldEngagements.ACTIVITY, &"turn": s.turn})
				s.events.push(&"engagement_started", {"engagement": eid, "plot": p, "kinds": OverworldEngagements.ACTIVITY}, s.tick)
			for other in Commanders.at(s, p):
				c.set_value(other, &"engagement", eid)
				s.events.push(&"commander_engaged", {"commander": other, "engagement": eid, "plot": p}, s.tick)
