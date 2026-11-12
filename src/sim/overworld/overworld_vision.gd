class_name OverworldVision
extends RefCounted
## Fog of war on the overworld (GDD 02 §2.9, R8Q4).
##   - Sight sources: commanders (cm_sight), controlled features (hf_sight)
##     and detachments, convoys included (the map's detachment_sight), see
##     every plot within their radius in hexes. Every source sees its own
##     plot. There is no line of sight on the overworld yet: terrain does
##     not block.
##   - Allies: a player sees what every non-hostile player's sources see.
##   - Memory: each player remembers, per explored plot, the features last
##     seen there and the turn it was seen (OverworldState.memory). Plots are
##     recorded at the start and end of every turn and around every hex a
##     commander enters mid-turn. Commanders are not remembered.
##   - Battles: where a battle is is public (every route needs to know that a
##     battle tile ends movement); what is in it (kinds, commanders) is seen
##     only with sight.
## Orders and pathfinding use what the player knows: an unexplored plot costs
## the map's base cost and is passable until seen otherwise; movement itself
## always uses the truth.

## Per event type: [commander fields, player fields, plot fields]. A player
## sees an event that concerns an allied commander or player, or happened on
## a plot it saw during the turn.
const _EVENT_FIELDS := {
	&"commander_moved": [["commander"], [], ["from", "to"]],
	&"commander_engaged": [["commander"], [], ["plot"]],
	&"engagement_started": [[], [], ["plot"]],
	&"engagement_ended": [[], [], ["plot"]],
	&"feature_captured": [[], ["player", "from"], ["plot"]],
	&"cache_picked": [["commander"], ["player"], ["plot"]],
	&"value_changed": [[], ["player"], []],
	&"activity_cancelled": [["commander"], [], []],
	&"activity_performed": [["commander"], [], ["plot"]],
	&"feature_converted": [[], ["player"], ["plot"]],
	&"interaction_offered": [[], ["player"], []],
	&"squad_recruited": [["commander"], [], []],
	&"army_refitted": [["commander"], [], []],
	&"squad_transferred": [[], ["player"], []],
	&"battleforce_deployed": [["commander"], ["player"], []],
	&"battle_started": [[], [], ["plot"]],
	&"battle_resolved": [[], ["winner"], ["plot"]],
	&"guard_cleared": [[], ["player"], ["plot"]],
	&"squad_reinforced": [[], ["player"], []],
	&"commander_defeated": [[], ["player"], ["plot"]],
	&"commander_left_battle": [["commander"], ["player"], ["plot"]],
	&"battleforce_dropped": [["commander"], ["player"], ["plot"]],
	&"squad_picked_up": [["commander"], ["player"], ["plot"]],
	&"detachment_disbanded": [[], ["player"], ["plot"]],
	&"squad_produced": [[], ["player"], ["plot"]],
	&"convoy_moved": [[], ["player"], ["from", "to"]],
	&"convoy_delivered": [["commander"], ["player"], ["plot"]],
	&"convoy_arrived": [[], ["player"], ["plot"]],
	&"convoy_halted": [[], ["player"], ["plot"]],
	&"convoys_merged": [[], ["player"], ["plot"]],
	&"convoy_rallied": [["commander"], ["player"], ["plot"]],
	&"item_produced": [[], ["player"], ["plot"]],
	&"items_picked": [["commander"], ["player"], ["plot"]],
	&"item_equipped": [["commander"], ["player"], []],
	&"item_unequipped": [["commander"], ["player"], []],
	&"item_given": [["from", "to"], ["player"], []],
	&"items_taken": [["commander"], ["player"], ["plot"]],
	&"items_seized": [["commander"], ["player", "by"], ["plot"]],
}
## Events a hostile player sees only through sight of the plot, reduced to
## these keys: what forces hold is never shown to enemies (R5Q9).
const _HOSTILE := {
	&"battleforce_dropped": ["detachment", "player", "plot"],
	&"squad_picked_up": ["detachment", "player", "plot"],
	&"squad_produced": ["feature", "player", "plot", "detachment"],
	&"convoy_delivered": ["detachment", "player", "plot"],
	&"convoy_rallied": ["detachment", "player", "plot"],
	&"item_produced": ["feature", "player", "plot", "detachment"],
	&"items_picked": ["commander", "player", "plot", "feature"],
	&"items_taken": ["commander", "detachment", "player", "plot"],
	&"items_seized": ["detachment", "player", "plot", "by", "commander"],
}
## Events everyone sees, reduced to these keys without sight (battle tiles).
const _PUBLIC := {
	&"engagement_started": ["engagement", "plot"],
	&"engagement_ended": ["engagement", "plot"],
	&"battle_started": ["engagement", "plot"],
	&"battle_resolved": ["engagement", "plot"],
}


## Plots in sight of `player` and its allies: 1 per plot in sight.
static func sight(s: OverworldState, player: int) -> PackedByteArray:
	var r := s.rules
	var out := PackedByteArray()
	out.resize(r.plot_count())
	var c := s.commanders
	for row in c.count():
		if not s.hostile(player, c.player[row]):
			_mark(s, out, c.plot[row], r.cm_sight[c.tmpl[row]])
	var f := s.features
	for row in f.count():
		var owner := f.owner[row]
		if owner > 0 and not s.hostile(player, owner):
			_mark(s, out, f.plot[row], r.hf_sight[f.tmpl[row]])
	var d := s.detachments
	for row in d.count():
		if not s.hostile(player, d.player[row]):
			_mark(s, out, d.plot[row], r.detachment_sight)
	return out


static func _mark(s: OverworldState, mask: PackedByteArray, p: int, radius: int) -> void:
	for q in Hex.within(p, maxi(radius, 0), s.rules.width, s.rules.height):
		mask[q] = 1


## Players with a sight source, ascending.
static func players(s: OverworldState) -> Array:
	var seen := {}
	var c := s.commanders
	for row in c.count():
		seen[c.player[row]] = true
	var f := s.features
	for row in f.count():
		if f.owner[row] > 0:
			seen[f.owner[row]] = true
	for row in s.detachments.count():
		seen[s.detachments.player[row]] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## Records what every player sees now into its memory, stamped with s.turn.
static func update(s: OverworldState) -> void:
	for player: int in players(s):
		_record(s, player, sight(s, player))


## A commander of `mover` entered plot p mid-turn: it and its allies see
## the plots around it as they are at that moment.
static func glimpse(s: OverworldState, mover: int, p: int, radius: int) -> void:
	var cells := Hex.within(p, maxi(radius, 0), s.rules.width, s.rules.height)
	for player: int in players(s):
		if s.hostile(player, mover):
			continue
		var mem: Dictionary = s.memory.get(player, {})
		for q in cells:
			mem[q] = _entry(s, q)
		s.memory[player] = mem


static func _record(s: OverworldState, player: int, mask: PackedByteArray) -> void:
	var mem: Dictionary = s.memory.get(player, {})
	for p in mask.size():
		if mask[p] == 1:
			mem[p] = _entry(s, p)
	s.memory[player] = mem


## [turn, then (feature ID, template, owner) per feature on the plot].
static func _entry(s: OverworldState, p: int) -> PackedInt64Array:
	var e := PackedInt64Array([s.turn])
	var f := s.features
	for row in s.features_at(p):
		e.append_array([f.id_at(row), f.tmpl[row], f.owner[row]])
	return e


## Whether the player has ever seen plot p (sight now or memory).
static func explored(s: OverworldState, player: int, p: int) -> bool:
	return (s.memory.get(player, {}) as Dictionary).has(p) or sight(s, player)[p] == 1


## The turn plot p was last recorded for the player, or -1 if never.
static func last_seen(s: OverworldState, player: int, p: int) -> int:
	var e: Variant = (s.memory.get(player, {}) as Dictionary).get(p)
	return -1 if e == null else (e as PackedInt64Array)[0]


## Feature templates the player believes are on plot p: the truth if in
## sight, else the remembered ones (none if unexplored).
static func known_tmpls(s: OverworldState, player: int, p: int, mask: PackedByteArray) -> PackedInt64Array:
	var out := PackedInt64Array()
	if mask[p] == 1:
		for row in s.features_at(p):
			out.append(s.features.tmpl[row])
		return out
	var e: Variant = (s.memory.get(player, {}) as Dictionary).get(p)
	if e != null:
		var entry: PackedInt64Array = e
		for i in range(2, entry.size(), 3):
			out.append(entry[i])
	return out


## Movement cost of every plot as the player knows it (-1 = impassable).
## Player 0 knows the truth.
static func known_costs(s: OverworldState, player: int) -> PackedInt64Array:
	var n := s.rules.plot_count()
	var out := PackedInt64Array()
	out.resize(n)
	if player <= 0:
		for p in n:
			out[p] = s.move_cost(p)
		return out
	var mask := sight(s, player)
	for p in n:
		out[p] = s.cost_of(known_tmpls(s, player, p, mask))
	return out


## The template of the first known feature on plot p offering the activity,
## or -1.
static func known_offering(s: OverworldState, player: int, p: int, activity: String) -> int:
	for t in known_tmpls(s, player, p, sight(s, player)):
		if s.rules.has_activity(t, activity):
			return t
	return -1


## The overworld as `player` may see it (GDD 04 §4.4 observations):
##   turn, player, value (own);
##   plots: explored plot -> {"visible", "turn" (now if visible, else when
##     last seen), "features": [{"id", "tmpl", "owner"}]};
##   commanders in sight: [{"id", "player", "tmpl", "plot", "engagement"}],
##     with "army" (OverworldArmies.view, equipped items included) and
##     "chest" (WarChest.chest_view) for own and allied commanders,
##     plus "battleforce" (deployed squads, or those that would fight if
##     engaged now) and
##     "battleforce_plan" for own ones;
##     what a hostile army holds is never shown (R5Q9);
##   detachments in sight, convoys included: [{"id", "player", "plot",
##     "engagement", "convoy"}], with "squads" (OverworldArmies.view),
##     "items" (its War Chest, WarChest.view) and "dest_plot",
##     "dest_commander", "line" for own and allied ones only;
##   production of own producing features: feature ID -> {"output",
##     "progress"}; own supply lines (feature ID -> {"player", "plot",
##     "commander"});
##   battles: every engagement {"engagement", "plot"}, plus "kinds" and
##     "since" (turn) when in sight;
##   own routes, drop-offs, activities and offers.
static func observe(s: OverworldState, player: int) -> Dictionary:
	var mask := sight(s, player)
	var mem: Dictionary = s.memory.get(player, {})
	var plots := {}
	for p in mask.size():
		var entry: PackedInt64Array
		if mask[p] == 1:
			entry = _entry(s, p)
			entry[0] = s.turn
		elif mem.has(p):
			entry = mem[p]
		else:
			continue
		var feats := []
		for i in range(1, entry.size(), 3):
			feats.append({"id": entry[i], "tmpl": entry[i + 1], "owner": entry[i + 2]})
		plots[p] = {"visible": mask[p] == 1, "turn": entry[0], "features": feats}
	var c := s.commanders
	var cmds := []
	var own := {}
	for row in c.count():
		if mask[c.plot[row]] == 1:
			var d := {"id": c.id_at(row), "player": c.player[row], "tmpl": c.tmpl[row],
				"plot": c.plot[row], "engagement": c.engagement[row]}
			if not s.hostile(player, c.player[row]):
				d["army"] = OverworldArmies.view(s, c.id_at(row))
				d["chest"] = WarChest.chest_view(s, c.id_at(row))
			if c.player[row] == player:
				d["battleforce"] = OverworldBattleforce.of(s, c.id_at(row))
				d["battleforce_plan"] = OverworldBattleforce.plan_of(s, c.id_at(row)).duplicate(true)
			cmds.append(d)
		if c.player[row] == player:
			own[c.id_at(row)] = true
	var d := s.detachments
	var dets := []
	for row in d.count():
		if mask[d.plot[row]] == 1:
			var x := {"id": d.id_at(row), "player": d.player[row], "plot": d.plot[row], "engagement": d.engagement[row],
				"convoy": Convoys.is_convoy(s, row)}
			if not s.hostile(player, d.player[row]):
				x["squads"] = Detachments.view(s, d.id_at(row))
				x["items"] = WarChest.view(s, WarChest.of_detachment(s, d.id_at(row)))
				x["dest_plot"] = d.dest_plot[row]
				x["dest_commander"] = d.dest_commander[row]
				x["line"] = d.line[row]
			dets.append(x)
	var e := s.engagements
	var battles := []
	for row in e.count():
		var b := {"engagement": e.id_at(row), "plot": e.plot[row]}
		if mask[e.plot[row]] == 1:
			b["kinds"] = e.kinds[row]
			b["since"] = e.turn[row]
		battles.append(b)
	var routes := {}
	for cid: int in s.routes:
		if own.has(cid):
			routes[cid] = (s.routes[cid] as PackedInt64Array).duplicate()
	var production := {}
	var f := s.features
	for row in f.count():
		if f.owner[row] == player and s.rules.production_count(f.tmpl[row]) > 0:
			production[f.id_at(row)] = {"output": f.output[row], "progress": f.progress[row]}
	var lines := {}
	for fid: int in s.supply_lines:
		if s.supply_lines[fid]["player"] == player:
			lines[fid] = (s.supply_lines[fid] as Dictionary).duplicate()
	var drops := {}
	for cid: int in s.drops:
		if own.has(cid):
			drops[cid] = (s.drops[cid] as Dictionary).duplicate()
	var acts := {}
	for cid: int in s.activities:
		if own.has(cid):
			acts[cid] = (s.activities[cid] as Dictionary).duplicate()
	var offers := []
	for o in s.offers:
		if o["player"] == player:
			offers.append(o.duplicate())
	return {"turn": s.turn, "player": player, "value": s.value_of(player), "plots": plots,
		"commanders": cmds, "detachments": dets, "battles": battles, "routes": routes, "drops": drops,
		"activities": acts, "offers": offers, "production": production, "supply_lines": lines,
		"presets": (s.presets.get(player, {}) as Dictionary).duplicate(true)}


## The events of a resolved turn that `player` may see: those concerning an
## allied commander or player, or on a plot it saw at some point during
## turn `turn` (default: the turn just resolved). Battle tiles starting and
## ending are public, reduced to where they are.
static func filter_events(s: OverworldState, player: int, events: Array[SimEvent], turn: int = -1) -> Array[SimEvent]:
	if turn < 0:
		turn = s.turn - 1
	var mem: Dictionary = s.memory.get(player, {})
	var out: Array[SimEvent] = []
	for ev in events:
		var spec: Array = _EVENT_FIELDS.get(ev.type, [[], [], []])
		var allied := false
		for k: String in spec[0]:
			var row := s.commanders.row_of(int(ev.data.get(k, -1)))
			allied = allied or (row >= 0 and not s.hostile(player, s.commanders.player[row]))
		for k: String in spec[1]:
			var who := int(ev.data.get(k, 0))
			allied = allied or (who > 0 and not s.hostile(player, who))
		var seen := false
		for k: String in spec[2]:
			var p := int(ev.data.get(k, -1))
			seen = seen or (mem.has(p) and (mem[p] as PackedInt64Array)[0] == turn)
		if allied or (seen and not _HOSTILE.has(ev.type)):
			out.append(ev)
		elif seen:
			out.append(_redact(ev, _HOSTILE[ev.type]))
		elif _PUBLIC.has(ev.type):
			out.append(_redact(ev, _PUBLIC[ev.type]))
	return out


static func _redact(ev: SimEvent, keys: Array) -> SimEvent:
	var data := {}
	for k: String in keys:
		data[k] = ev.data[k]
	var redacted := SimEvent.new(ev.type, data)
	redacted.source = ev.source
	redacted.seq = ev.seq
	redacted.tick = ev.tick
	return redacted
