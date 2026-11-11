class_name OverworldState
extends SimContext
## The overworld: one hex map, its features and (later) commanders, convoys
## and fog. GDD 02 §2.9, 04 §4.2.

var rules: OverworldRules
var features: OverworldFeatures
var commanders: OverworldCommanders
var engagements: OverworldEngagements
## Turns resolved so far.
var turn: int = 0
## Planned routes: commander ID -> plots to enter, in order (start excluded).
## Set during planning by OverworldOrders; cleared when the turn resolves.
var routes: Dictionary = {}
## Planned activities: commander ID -> {"activity": String, "plot": int}.
## Set during planning; performed if the commander ends the turn there.
var activities: Dictionary = {}
## Value per player, the sole resource (R5Q11).
var value: Dictionary = {}
## Uncertain-outcome interactions presented this turn (R6Q14): [{"plot",
## "feature" (ID), "player"}], rebuilt as each turn resolves.
var offers: Array[Dictionary] = []
## Derived cache, plot -> feature rows (ascending template index). Rebuilt
## by reindex(); never hashed or saved.
var plot_features: Dictionary = {}


func _init(context_id: int, overworld_rules: OverworldRules, seed_value: int = 0) -> void:
	super(context_id, &"overworld", seed_value)
	rules = overworld_rules
	features = OverworldFeatures.new()
	commanders = OverworldCommanders.new()
	engagements = OverworldEngagements.new()
	add_table(features)
	add_table(commanders)
	add_table(engagements)


## A new overworld with its map generated from the seed.
static func create(context_id: int, overworld_rules: OverworldRules, seed_value: int) -> OverworldState:
	var s := OverworldState.new(context_id, overworld_rules, seed_value)
	MapGen.generate(s)
	return s


## Feature rows on a plot, by ascending template index.
func features_at(p: int) -> PackedInt64Array:
	return plot_features.get(p, PackedInt64Array())


## The row of feature template f on plot p, or -1.
func feature_row(p: int, f: int) -> int:
	for row in features_at(p):
		if features.tmpl[row] == f:
			return row
	return -1


func value_of(player: int) -> int:
	return int(value.get(player, 0))


func add_value(player: int, amount: int, source: StringName) -> void:
	if amount == 0:
		return
	value[player] = value_of(player) + amount
	events.push(&"value_changed", {"player": player, "amount": amount, "source": source}, tick)


## Whether two players are enemies. Alliances arrive with campaigns; until
## then every other player is hostile.
func hostile(a: int, b: int) -> bool:
	return a != b


## Guard squads on a plot (neutral guards, R4Q14): the union of its
## features' guard lists. Empty = unguarded.
func guard_at(p: int) -> PackedStringArray:
	var out := PackedStringArray()
	for row in features_at(p):
		out.append_array(rules.hf_guard[features.tmpl[row]])
	return out


## The engagement on a plot (a battle tile), or -1.
func engagement_at(p: int) -> int:
	for row in engagements.count():
		if engagements.plot[row] == p:
			return engagements.id_at(row)
	return -1


## Movement points to enter a plot: the map's base cost plus its features'
## costs, at least 1. -1 = impassable.
func move_cost(p: int) -> int:
	var cost := rules.base_cost
	for row in features_at(p):
		var f := features.tmpl[row]
		if rules.hf_impassable[f] == 1:
			return -1
		cost += rules.hf_move_cost[f]
	return maxi(cost, 1)


## Adds feature f to plot p (no-op if it is already there). Returns its ID.
func add_feature(p: int, f: int, owner: int = 0) -> int:
	var row := feature_row(p, f)
	if row >= 0:
		return features.id_at(row)
	var id := features.spawn({&"plot": p, &"tmpl": f, &"owner": owner})
	# Spawning appends a row and moves none, so the cache updates in place.
	var list := features_at(p)
	var at := 0
	while at < list.size() and features.tmpl[list[at]] < f:
		at += 1
	list.insert(at, features.row_of(id))
	plot_features[p] = list
	return id


## Despawning swap-removes rows, so the whole cache is rebuilt.
func remove_feature(id: int) -> void:
	if features.despawn(id):
		reindex()


## Rebuilds plot_features from the table (after spawns, despawns, restore).
func reindex() -> void:
	plot_features = {}
	var order := []
	for row in features.count():
		order.append(row)
	order.sort_custom(func(a: int, b: int) -> bool:
		return features.tmpl[a] < features.tmpl[b] if features.plot[a] == features.plot[b] else features.plot[a] < features.plot[b])
	for row: int in order:
		var p := features.plot[row]
		var list: PackedInt64Array = plot_features.get(p, PackedInt64Array())
		list.append(row)
		plot_features[p] = list


func _snapshot_extra(snap: Dictionary) -> void:
	var r := {}
	for cid: int in routes:
		r[cid] = (routes[cid] as PackedInt64Array).duplicate()
	snap["overworld"] = {"turn": turn, "routes": r, "activities": activities.duplicate(true),
		"value": value.duplicate(), "offers": offers.duplicate(true)}


func _restore_extra(snap: Dictionary) -> void:
	turn = snap["overworld"]["turn"]
	routes = {}
	var r: Dictionary = snap["overworld"].get("routes", {})
	for cid: int in r:
		routes[cid] = (r[cid] as PackedInt64Array).duplicate()
	activities = (snap["overworld"].get("activities", {}) as Dictionary).duplicate(true)
	value = (snap["overworld"].get("value", {}) as Dictionary).duplicate()
	offers.assign((snap["overworld"].get("offers", []) as Array).duplicate(true))
	reindex()


func state_hash() -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(super.state_hash())
	h.update(PackedInt64Array([turn]).to_byte_array())
	var ids: Array = routes.keys()
	ids.sort()
	for cid: int in ids:
		h.update(PackedInt64Array([cid, (routes[cid] as PackedInt64Array).size()]).to_byte_array())
		h.update((routes[cid] as PackedInt64Array).to_byte_array())
	var text := ""
	ids = activities.keys()
	ids.sort()
	for cid: int in ids:
		text += "A%d:%s@%d;" % [cid, activities[cid]["activity"], activities[cid]["plot"]]
	var players: Array = value.keys()
	players.sort()
	for p: int in players:
		text += "V%d:%d;" % [p, value[p]]
	for o in offers:
		text += "O%d:%d:%d;" % [o["plot"], o["feature"], o["player"]]
	if not text.is_empty():
		h.update(text.to_utf8_buffer())
	return h.finish()
