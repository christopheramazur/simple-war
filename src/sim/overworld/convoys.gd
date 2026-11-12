class_name Convoys
extends RefCounted
## Production, supply lines and convoys (GDD 02 §2.9, R5Q10, R6Q13, R8Q3).
##   - Production: a feature with `produces` options makes squads for its
##     owner: the selected option (the first by default) advances one turn
##     per overworld turn, and on reaching its `turns` the squad is made for
##     its `cost` in Value (waiting while the owner can't pay). Capturing the
##     feature resets its progress and output, and its supply line lapses.
##   - Without a supply line, produced squads join the owner's detachment
##     holding the feature's hex: a garrison commanders pick up from.
##   - Supply lines: the owner sends a feature's output to a plot or to one
##     of its commanders. Each produced squad leaves as a convoy on that line;
##     convoys on one hex along the same line merge.
##   - Rallies: a detachment sent to a plot or commander becomes a convoy.
##     The survivors of a commander that left its battle rally to it (R8Q3).
##   - Movement: a convoy is a detachment with a destination. Each turn it
##     walks the cheapest path it knows (avoiding hexes it knows are
##     guarded) for the map's `convoy_movement` points, on the commanders'
##     timeline (OverworldMovement). Like any detachment, it fights what it
##     meets: entering a hostile hex, or being entered, starts an engagement
##     (interception).
##   - Arrival: at a plot, it becomes a detachment holding it (joining the
##     player's one there). At its commander's hex, its squads join the army
##     up to the cap; the rest halt there. A convoy whose commander is gone
##     halts where it is.


static func is_convoy(s: OverworldState, row: int) -> bool:
	return s.detachments.dest_plot[row] >= 0 or s.detachments.dest_commander[row] >= 0


## Convoy IDs, ascending.
static func ids(s: OverworldState) -> PackedInt64Array:
	var out := PackedInt64Array()
	var d := s.detachments
	for row in d.count():
		if is_convoy(s, row):
			out.append(d.id_at(row))
	out.sort()
	return out


## The plot a convoy heads for now, or -1.
static func target(s: OverworldState, did: int) -> int:
	var d := s.detachments
	var row := d.row_of(did)
	if d.dest_plot[row] >= 0:
		return d.dest_plot[row]
	var cr := s.commanders.row_of(d.dest_commander[row])
	return s.commanders.plot[cr] if cr >= 0 else -1


# --- planning ----------------------------------------------------------------

## Selects which of an owned feature's production options it makes.
static func set_output(s: OverworldState, player: int, fid: int, option: int) -> String:
	var err := _own_producer(s, player, fid)
	if not err.is_empty():
		return err
	var row := s.features.row_of(fid)
	if option < 0 or option >= s.rules.production_count(s.features.tmpl[row]):
		return "no such output"
	if s.features.output[row] != option:
		s.features.set_value(fid, &"output", option)
		s.features.set_value(fid, &"progress", 0)
	return ""


## Sends an owned feature's output to a plot or one of the player's
## commanders (both -1 clears the line). Convoys already on the line turn
## to the new destination.
static func set_line(s: OverworldState, player: int, fid: int, plot: int, commander: int) -> String:
	var err := _own_producer(s, player, fid)
	if not err.is_empty():
		return err
	if plot < 0 and commander < 0:
		s.supply_lines.erase(fid)
		return ""
	err = _dest(s, player, plot, commander)
	if not err.is_empty():
		return err
	if commander >= 0:
		plot = -1
	s.supply_lines[fid] = {"player": player, "plot": plot, "commander": commander}
	var d := s.detachments
	for row in d.count():
		if d.line[row] == fid and d.player[row] == player:
			d.set_value(d.id_at(row), &"dest_plot", plot)
			d.set_value(d.id_at(row), &"dest_commander", commander)
	return ""


## Sends a detachment (or redirects a convoy) to a plot or one of the
## player's commanders; both -1 halts it where it is.
static func rally(s: OverworldState, player: int, did: int, plot: int, commander: int) -> String:
	var d := s.detachments
	var row := d.row_of(did)
	if row < 0:
		return "no such detachment"
	if d.player[row] != player:
		return "not your detachment"
	if d.engagement[row] >= 0:
		return "is in a battle"
	if plot >= 0 or commander >= 0:
		var err := _dest(s, player, plot, commander)
		if not err.is_empty():
			return err
	d.set_value(did, &"dest_plot", plot if commander < 0 else -1)
	d.set_value(did, &"dest_commander", commander)
	d.set_value(did, &"line", -1)
	return ""


static func _own_producer(s: OverworldState, player: int, fid: int) -> String:
	var row := s.features.row_of(fid)
	if row < 0:
		return "no such feature"
	if s.features.owner[row] != player:
		return "not your feature"
	if s.rules.production_count(s.features.tmpl[row]) == 0:
		return "this feature produces nothing"
	return ""


static func _dest(s: OverworldState, player: int, plot: int, commander: int) -> String:
	if commander >= 0:
		var cr := s.commanders.row_of(commander)
		if cr < 0:
			return "no such commander"
		if s.commanders.player[cr] != player:
			return "not your commander"
		return ""
	if plot >= s.rules.plot_count():
		return "that hex is off the map"
	if OverworldVision.known_costs(s, player)[plot] < 0:
		return "that hex is impassable"
	return ""


# --- production --------------------------------------------------------------

## Advances every owned producing feature; makes squads that are due.
static func produce(s: OverworldState) -> void:
	var f := s.features
	var fids := f.ids()
	fids.sort()
	for fid in fids:
		var row := f.row_of(fid)
		var owner := f.owner[row]
		var t := f.tmpl[row]
		var n := s.rules.production_count(t)
		if owner <= 0 or n == 0:
			continue
		var o := clampi(f.output[row], 0, n - 1) * 3
		var opts := s.rules.hf_produces[t]
		var sq := opts[o]
		var turns := opts[o + 1]
		var cost := opts[o + 2]
		var progress := mini(f.progress[row] + 1, turns)
		if progress >= turns and s.value_of(owner) >= cost:
			s.add_value(owner, -cost, &"production")
			_make(s, fid, owner, f.plot[row], sq)
			progress = 0
		f.set_value(fid, &"progress", progress)


## A produced squad joins the line's convoy leaving the hex, or the owner's
## detachment holding it.
static func _make(s: OverworldState, fid: int, owner: int, p: int, sq: int) -> void:
	var d := s.detachments
	var sl: Dictionary = s.supply_lines.get(fid, {})
	var did := -1
	for row in d.count():
		if d.plot[row] != p or d.player[row] != owner or d.engagement[row] >= 0:
			continue
		if (sl.is_empty() and not is_convoy(s, row)) or (not sl.is_empty() and d.line[row] == fid):
			did = d.id_at(row)
			break
	if did < 0:
		var v := {&"player": owner, &"plot": p}
		if not sl.is_empty():
			v[&"dest_plot"] = sl["plot"]
			v[&"dest_commander"] = sl["commander"]
			v[&"line"] = fid
		did = d.spawn(v)
	var size := s.rules.sq_size[sq]
	var id := s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": sq, &"alive": size, &"size": size})
	s.events.push(&"squad_produced", {"feature": fid, "player": owner, "plot": p, "squad": id,
		"tmpl": sq, "detachment": did}, s.tick)


## A captured feature starts over, and its supply line lapses.
static func on_captured(s: OverworldState, fid: int) -> void:
	s.features.set_value(fid, &"progress", 0)
	s.features.set_value(fid, &"output", 0)
	s.supply_lines.erase(fid)


# --- movement ----------------------------------------------------------------

## Plots the player knows hold a guard feature (convoys route around them).
static func guarded_mask(s: OverworldState, player: int) -> PackedByteArray:
	var n := s.rules.plot_count()
	var mask := PackedByteArray()
	mask.resize(n)
	var sight := OverworldVision.sight(s, player)
	for p in n:
		for t in OverworldVision.known_tmpls(s, player, p, sight):
			if not s.rules.hf_guard[t].is_empty():
				mask[p] = 1
	return mask


## The convoy's path this turn: [plots to enter, times] within its points.
static func plan(s: OverworldState, did: int, masks: Dictionary) -> Array:
	var d := s.detachments
	var row := d.row_of(did)
	var to := target(s, did)
	var player := d.player[row]
	if to < 0 or to == d.plot[row]:
		return [PackedInt64Array(), PackedInt64Array()]
	if not masks.has(player):
		masks[player] = guarded_mask(s, player)
	var path := OverworldPath.find(s, d.plot[row], to, player, masks[player])
	var plots := PackedInt64Array()
	var times := PackedInt64Array()
	var t := 0
	var at := d.plot[row]
	for p in path:
		var cost := s.move_cost(p)
		if cost < 0 or not Hex.adjacent(at, p, s.rules.width) or t + cost > s.rules.convoy_mp:
			break
		t += cost
		plots.append(p)
		times.append(t)
		at = p
	return [plots, times]


## A convoy on its commander's hex hands over its squads, up to the army
## cap; the rest halt there. Returns whether it reached its commander.
static func deliver(s: OverworldState, did: int) -> bool:
	var d := s.detachments
	var row := d.row_of(did)
	var cid := d.dest_commander[row]
	var cr := s.commanders.row_of(cid)
	if cr < 0 or s.commanders.plot[cr] != d.plot[row] or s.commanders.engagement[cr] >= 0 or d.engagement[row] >= 0:
		return false
	var room := OverworldArmies.cap(s, cid) - OverworldArmies.count(s, cid)
	var moved := PackedInt64Array()
	for id in Detachments.squads_of(s, did):
		if moved.size() >= room:
			break
		OverworldArmies.move(s, id, cid)
		moved.append(id)
	var player := d.player[row]
	s.events.push(&"convoy_delivered", {"detachment": did, "commander": cid, "player": player,
		"plot": d.plot[row], "squads": moved}, s.tick)
	if Detachments.squads_of(s, did).is_empty():
		d.despawn(did)
	else:
		_halt(s, did, "army_full")
	return true


## After movement: convoys arrive, reach their commanders, halt if their
## commander is gone, and those sharing a hex and a line merge.
static func settle(s: OverworldState) -> void:
	var d := s.detachments
	for did in ids(s):
		var row := d.row_of(did)
		if row < 0 or d.engagement[row] >= 0:
			continue
		if d.dest_commander[row] >= 0:
			if not s.commanders.is_alive(d.dest_commander[row]):
				_halt(s, did, "commander_lost")
			else:
				deliver(s, did)
		elif d.plot[row] == d.dest_plot[row]:
			_arrive(s, did)
	var convoys := ids(s)
	for i in convoys.size():
		var a := d.row_of(convoys[i])
		if a < 0 or d.line[a] < 0 or d.engagement[a] >= 0:
			continue
		for j in range(i + 1, convoys.size()):
			var b := d.row_of(convoys[j])
			if b < 0 or d.engagement[b] >= 0 or d.line[b] != d.line[a] or d.plot[b] != d.plot[a] or d.player[b] != d.player[a]:
				continue
			for id in Detachments.squads_of(s, convoys[j]):
				s.squads.set_value(id, &"detachment", convoys[i])
			s.events.push(&"convoys_merged", {"detachment": convoys[j], "into": convoys[i], "player": d.player[a],
				"plot": d.plot[a]}, s.tick)
			d.despawn(convoys[j])
			a = d.row_of(convoys[i])


## Arrived at its plot: it holds the hex, joining the player's detachment
## already holding it.
static func _arrive(s: OverworldState, did: int) -> void:
	var d := s.detachments
	var row := d.row_of(did)
	var p := d.plot[row]
	var player := d.player[row]
	s.events.push(&"convoy_arrived", {"detachment": did, "player": player, "plot": p}, s.tick)
	_stop(s, did)
	for other in Detachments.at(s, p):
		var orow := d.row_of(other)
		if other != did and d.player[orow] == player and not is_convoy(s, orow) and d.engagement[orow] < 0:
			for id in Detachments.squads_of(s, did):
				s.squads.set_value(id, &"detachment", other)
			d.despawn(did)
			return


static func _halt(s: OverworldState, did: int, reason: String) -> void:
	var d := s.detachments
	var row := d.row_of(did)
	s.events.push(&"convoy_halted", {"detachment": did, "player": d.player[row], "plot": d.plot[row], "reason": reason}, s.tick)
	_stop(s, did)


static func _stop(s: OverworldState, did: int) -> void:
	s.detachments.set_value(did, &"dest_plot", -1)
	s.detachments.set_value(did, &"dest_commander", -1)
	s.detachments.set_value(did, &"line", -1)


## Squads of commander cid that come out of a battle it left: they form a
## convoy at plot p rallied to it (R8Q3).
static func rally_survivors(s: OverworldState, cid: int, p: int, squads: PackedInt64Array) -> void:
	if squads.is_empty():
		return
	var player := s.commanders.get_value(cid, &"player")
	var did := s.detachments.spawn({&"player": player, &"plot": p, &"dest_commander": cid})
	for id in squads:
		s.squads.set_value(id, &"holder", -1)
		s.squads.set_value(id, &"detachment", did)
	s.events.push(&"convoy_rallied", {"detachment": did, "commander": cid, "player": player, "plot": p, "squads": squads}, s.tick)
