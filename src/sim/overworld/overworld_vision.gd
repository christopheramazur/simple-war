class_name OverworldVision
extends RefCounted
## Fog of war on the overworld (GDD 02 §2.9, R8Q4).
##   - Sight sources: commanders (cm_sight) and controlled features (hf_sight)
##     see every plot within their radius in hexes. Every source sees its own
##     plot. Convoys and detachments join with armies (sw-o1m.2). There is no
##     line of sight on the overworld yet: terrain does not block.
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
}
## Events everyone sees, reduced to these keys without sight (battle tiles).
const _PUBLIC := {
	&"engagement_started": ["engagement", "plot"],
	&"engagement_ended": ["engagement", "plot"],
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
##   commanders in sight: [{"id", "player", "tmpl", "plot", "engagement"}];
##   battles: every engagement {"engagement", "plot"}, plus "kinds" and
##     "since" (turn) when in sight;
##   own routes, activities and offers.
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
			cmds.append({"id": c.id_at(row), "player": c.player[row], "tmpl": c.tmpl[row],
				"plot": c.plot[row], "engagement": c.engagement[row]})
		if c.player[row] == player:
			own[c.id_at(row)] = true
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
	var acts := {}
	for cid: int in s.activities:
		if own.has(cid):
			acts[cid] = (s.activities[cid] as Dictionary).duplicate()
	var offers := []
	for o in s.offers:
		if o["player"] == player:
			offers.append(o.duplicate())
	return {"turn": s.turn, "player": player, "value": s.value_of(player), "plots": plots,
		"commanders": cmds, "battles": battles, "routes": routes, "activities": acts, "offers": offers}


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
		var shown := false
		for k: String in spec[0]:
			var row := s.commanders.row_of(int(ev.data.get(k, -1)))
			shown = shown or (row >= 0 and not s.hostile(player, s.commanders.player[row]))
		for k: String in spec[1]:
			var who := int(ev.data.get(k, 0))
			shown = shown or (who > 0 and not s.hostile(player, who))
		for k: String in spec[2]:
			var p := int(ev.data.get(k, -1))
			shown = shown or (mem.has(p) and (mem[p] as PackedInt64Array)[0] == turn)
		if shown:
			out.append(ev)
		elif _PUBLIC.has(ev.type):
			var data := {}
			for k: String in _PUBLIC[ev.type]:
				data[k] = ev.data[k]
			var redacted := SimEvent.new(ev.type, data)
			redacted.source = ev.source
			redacted.seq = ev.seq
			redacted.tick = ev.tick
			out.append(redacted)
	return out
