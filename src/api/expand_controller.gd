class_name ExpandController
extends RefCounted
## A rule-based overworld controller profile (R7Q15). It reads only its
## player's observation, the public rules, and session.path:
##   - each free commander heads for the nearest known, unguarded hex with a
##     feature to take (controllable, not ours), a cache, or one it can
##     convert with the Value it has (and plans the convert);
##   - with nothing known to take, it explores toward the nearest
##     unexplored hex;
##   - commanders never share a target. Ties go to the lower plot index.

var player: int


func _init(player_id: int) -> void:
	player = player_id


func plan(obs: Dictionary, session: OverworldSession) -> Array:
	var r := session.rules
	var w: int = obs["width"]
	var n: int = w * int(obs["height"])
	var plots: Dictionary = obs["plots"]
	var value: int = obs["value"]
	var wanted := {}   # plot -> activity ("" = just go there)
	for p: int in plots:
		var guarded := false
		var want := ""
		var take := false
		for f: Dictionary in plots[p]["features"]:
			var t: int = f["tmpl"]
			guarded = guarded or not r.hf_guard[t].is_empty()
			if r.hf_controllable[t] == 1 and f["owner"] != player:
				take = true
			if r.hf_cache_value[t] > 0:
				take = true
			if r.has_activity(t, "convert") and value >= r.hf_activity_cost[t]:
				want = "convert"
				take = true
		if take and not guarded:
			wanted[p] = want
	var busy := {}
	var out := []
	for c: Dictionary in obs["commanders"]:
		if c["player"] != player or c["engagement"] >= 0:
			continue
		var at: int = c["plot"]
		var best := -1
		var best_d := 1 << 30
		for p: int in wanted:
			var d := Hex.plot_distance(at, p, w)
			if not busy.has(p) and (d < best_d or (d == best_d and p < best)):
				best = p
				best_d = d
		if best < 0:
			for p in n:
				if plots.has(p) or busy.has(p):
					continue
				var d := Hex.plot_distance(at, p, w)
				if d < best_d:
					best = p
					best_d = d
		if best < 0 or best == at:
			continue
		busy[best] = true
		var route := session.path(player, c["id"], best)
		if route.is_empty():
			continue
		var o := {"commander": c["id"], "route": route}
		if route[route.size() - 1] == best and not String(wanted.get(best, "")).is_empty():
			o["activity"] = wanted[best]
		out.append(o)
	return out
