class_name OverworldActivities
extends RefCounted
## Activities (GDD 02 §2.9, R4Q12): refit, recruit, a commander-led battle,
## converting a resource node. Planned with OverworldOrders.set_activity and
## performed after movement, only by a commander that ended its route on the
## planned hex and is not in a battle. The Value cost is paid on performing.
##   convert: the feature becomes its converts_to feature, owned by the player.
##   battle:  an engagement starts on the hex (battles begin at turn start).
##   recruit, refit: emit activity_performed; armies (sw-o1m.2) act on it.


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
		var why := ""
		var fr := offering(s, p, activity)
		if c.plot[row] != p:
			why = "did not reach the hex"
		elif c.engagement[row] >= 0:
			why = "is in a battle"
		elif fr < 0:
			why = "no longer offered here"
		elif s.value_of(c.player[row]) < s.rules.hf_activity_cost[s.features.tmpl[fr]]:
			why = "not enough Value"
		if not why.is_empty():
			s.events.push(&"activity_cancelled", {"commander": cid, "plot": p, "activity": activity, "reason": why}, s.tick)
			continue
		_perform(s, row, fr, activity)


static func _perform(s: OverworldState, row: int, fr: int, activity: String) -> void:
	var c := s.commanders
	var f := s.features
	var cid := c.id_at(row)
	var player := c.player[row]
	var p := f.plot[fr]
	var t := f.tmpl[fr]
	var fid := f.id_at(fr)
	s.add_value(player, -s.rules.hf_activity_cost[t], &"activity")
	s.events.push(&"activity_performed", {"commander": cid, "plot": p, "activity": activity, "feature": fid}, s.tick)
	match activity:
		"convert":
			var into := s.rules.hf_converts_to[t]
			s.remove_feature(fid)
			var nid := s.add_feature(p, into, player if s.rules.hf_controllable[into] == 1 else 0)
			s.events.push(&"feature_converted", {"plot": p, "from": fid, "to": nid, "player": player}, s.tick)
		"battle":
			var eid := s.engagement_at(p)
			if eid < 0:
				eid = s.engagements.spawn({&"plot": p, &"kinds": OverworldEngagements.ACTIVITY, &"turn": s.turn})
				s.events.push(&"engagement_started", {"engagement": eid, "plot": p, "kinds": OverworldEngagements.ACTIVITY}, s.tick)
			for other in Commanders.at(s, p):
				c.set_value(other, &"engagement", eid)
				s.events.push(&"commander_engaged", {"commander": other, "engagement": eid, "plot": p}, s.tick)
