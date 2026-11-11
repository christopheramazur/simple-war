class_name OverworldState
extends SimContext
## The overworld: one hex map, its features and (later) commanders, convoys
## and fog. GDD 02 §2.9, 04 §4.2.

var rules: OverworldRules
var features: OverworldFeatures
## Turns resolved so far.
var turn: int = 0
## Derived cache, plot -> feature rows (ascending template index). Rebuilt
## by reindex(); never hashed or saved.
var plot_features: Dictionary = {}


func _init(context_id: int, overworld_rules: OverworldRules, seed_value: int = 0) -> void:
	super(context_id, &"overworld", seed_value)
	rules = overworld_rules
	features = OverworldFeatures.new()
	add_table(features)


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
	snap["overworld"] = {"turn": turn}


func _restore_extra(snap: Dictionary) -> void:
	turn = snap["overworld"]["turn"]
	reindex()


func state_hash() -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(super.state_hash())
	h.update(PackedInt64Array([turn]).to_byte_array())
	return h.finish()
