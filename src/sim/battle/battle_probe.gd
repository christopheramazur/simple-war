class_name BattleProbe
extends RefCounted
## One read-only truth snapshot of a battle (sw-tho3.2, U1 B2). Visual
## grading, the behaviour workshop and overlays read the same facts from here
## instead of stitching them together from BattleActivity, LineOfFire,
## Inspection and the event log. Nothing is written: the state hash is the
## same before and after a snapshot.
##
## viewer 0 is all-seeing (replays, tests, the workshop): every active squad
## in full, as BattleActivity and LineOfFire report it. viewer > 0 is
## fog-safe, with the same rules as BattleSession.observe_state: own squads in
## full; enemy squads only while the viewer's side sees them (seen_by), and
## then behaviour only (no order, no pools, no casualties, no hold reason, no
## victim). Anything that involves an unseen squad (fire pairs, shots, hits,
## casualties) is left out entirely.
##
## Returned Dictionary:
##   viewer, tick, turn, recent_ticks (how far back the event lists reach)
##   squads: [{id, player, label, template, x, y (centroid, fixed), alive,
##            start, destroyed, withdrawn, range, sight, facing, activity
##            (BattleActivity.Squad), target (-1 none; enemies only while
##            firing at a seen squad)}]; full view also: order, hp_lost,
##            hp_max, pools {pool: band name}
##   units:   [{id, squad, x, y, hp, hp_max}]; full view also: hold
##            (BattleActivity.Hold), victim (-1 none), victim_dist (fixed)
##   fire:    [{from, to, los}]: LineOfFire.check codes for each full-view
##            squad against each visible enemy it engages or can reach
##   shots:   [{tick, squad, target, shots, hits}]   (squad_fired)
##   hits:    [{tick, squad, target, damage, kills}] (squad_damaged)
##   casualties: [{tick, unit, squad, by}]            (unit_killed)
## Values are raw fixed where a field says fixed.

## How many recent ticks the shot, hit and casualty lists cover.
const RECENT_TICKS: int = 3


static func snapshot(state: BattleState, viewer: int = 0) -> Dictionary:
	var sq := state.squads
	var u := state.units
	var rules := state.rules
	var all_seeing := viewer <= 0
	var me := 0 if all_seeing else BattleSquads.bit(viewer)
	var ranges := _ranges(state)
	var squads: Array = []
	var visible := {}
	var full := {}
	var live: Array[int] = []
	for row in sq.count():
		var sid := sq.id_at(row)
		var own := not all_seeing and sq.player[row] == viewer
		if not own and (not sq.is_active(row) or (not all_seeing and (sq.seen_by[row] & me) == 0)):
			continue
		visible[sid] = true
		var is_full := own or all_seeing
		if is_full:
			full[sid] = true
		var tmpl := sq.tmpl[row]
		var d := {
			"id": sid, "player": sq.player[row], "label": rules.sq_names[tmpl],
			"template": rules.squad_ids[tmpl], "x": sq.cx[row], "y": sq.cy[row],
			"alive": sq.alive[row], "start": rules.sq_members[tmpl].size(),
			"destroyed": sq.destroyed[row] == 1, "withdrawn": sq.withdrawn[row] == 1,
			"range": ranges.get(sid, 0), "sight": rules.sq_sight[tmpl], "facing": sq.facing[row],
		}
		if is_full:
			d["activity"] = BattleActivity.squad(state, row)
			d["target"] = sq.engaged[row]
			d["order"] = BattleOrders.TYPES.find_key(sq.order[row])
			d["hp_lost"] = sq.hp_lost[row]
			d["hp_max"] = sq.hp_max[row]
			var pools := {}
			for p in 5:
				pools[DataSchema.SIMPL[p]] = DataSchema.BANDS[Pools.band(state, row, p)]
			d["pools"] = pools
		else:
			d["activity"] = BattleActivity.squad_seen(state, row)
			var trow := sq.row_of(sq.engaged[row])
			if d["activity"] == BattleActivity.Squad.ENGAGED and trow >= 0 and sq.is_active(trow) \
					and (sq.seen_by[trow] & me) != 0:
				d["target"] = sq.engaged[row]
		squads.append(d)
		if sq.alive[row] > 0 and sq.is_active(row):
			live.append(row)

	var units: Array = []
	for row in u.count():
		var sid := u.squad[row]
		if not visible.has(sid):
			continue
		var ud := {"id": u.id_at(row), "squad": sid, "x": u.x[row], "y": u.y[row],
			"hp": u.hp[row], "hp_max": u.hp_max[row]}
		if full.has(sid):
			var v := BattleActivity.victim(state, row)
			ud["hold"] = BattleActivity.hold(state, row)
			ud["victim"] = u.id_at(v) if v >= 0 else -1
			ud["victim_dist"] = Fixed.distance(u.x[row], u.y[row], u.x[v], u.y[v]) if v >= 0 else 0
		units.append(ud)

	var out := {
		"viewer": viewer, "tick": state.tick, "turn": state.turn, "recent_ticks": RECENT_TICKS,
		"squads": squads, "units": units, "fire": _fire(state, live, full),
	}
	out.merge(_recent(state, visible, all_seeing))
	return out


## Fire pairs for the full-view squads: each against every visible enemy it
## engages or can reach (centre distance within its reach). Bounded by the
## live squads that are near each other, not all pairs.
static func _fire(state: BattleState, live: Array[int], full: Dictionary) -> Array:
	var sq := state.squads
	var out: Array = []
	for a in live:
		var aid := sq.id_at(a)
		if not full.has(aid):
			continue
		for b in live:
			if sq.player[b] == sq.player[a]:
				continue
			var bid := sq.id_at(b)
			var d := Fixed.distance(sq.cx[a], sq.cy[a], sq.cx[b], sq.cy[b])
			if sq.engaged[a] != bid and d > sq.reach[a]:
				continue
			out.append({"from": aid, "to": bid, "los": LineOfFire.check(state, a, b)})
	return out


## Shots, hits and casualties of the last RECENT_TICKS ticks from the turn
## log. An event is left out when any squad it names is unseen (viewer > 0).
static func _recent(state: BattleState, visible: Dictionary, all_seeing: bool) -> Dictionary:
	var shots: Array = []
	var hits: Array = []
	var casualties: Array = []
	var since := state.tick - RECENT_TICKS
	for e in state.turn_log:
		if e.tick < since:
			continue
		var d := e.data
		match e.type:
			&"squad_fired":
				if _shows(visible, all_seeing, [d["squad"], d["target"]]):
					shots.append({"tick": e.tick, "squad": d["squad"], "target": d["target"],
						"shots": d["shots"], "hits": d["hits"]})
			&"squad_damaged":
				if _shows(visible, all_seeing, [d["squad"], d["target"]]):
					hits.append({"tick": e.tick, "squad": d["squad"], "target": d["target"],
						"damage": d["damage"], "kills": d["kills"]})
			&"unit_killed":
				if _shows(visible, all_seeing, [d["squad"], d["by"]]):
					casualties.append({"tick": e.tick, "unit": d["unit"], "squad": d["squad"], "by": d["by"]})
	return {"shots": shots, "hits": hits, "casualties": casualties}


static func _shows(visible: Dictionary, all_seeing: bool, ids: Array) -> bool:
	if all_seeing:
		return true
	for id in ids:
		if int(id) >= 0 and not visible.has(id):
			return false
	return true


## Longest weapon range among each squad's living units (squad ID -> fixed).
static func _ranges(state: BattleState) -> Dictionary:
	var u := state.units
	var out := {}
	for row in u.count():
		var w := u.weapon[row]
		if w < 0:
			continue
		var sid := u.squad[row]
		var r := state.rules.wp_range[w]
		if r > int(out.get(sid, 0)):
			out[sid] = r
	return out
