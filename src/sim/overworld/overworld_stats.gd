class_name OverworldStats
extends RefCounted
## Effective overworld stats (GDD 04 §4.2, U1Q26, U1Q27): the one reader of
## a commander's, band's or feature's `sight` and `movement` points.
## Vision, convoy planning and glimpses call it, never the raw columns.
##   - What it adds up: the template base (for a band, its kind's, with the
##     map's overrides applied by OverworldRules), then payload contributions
##     in ID order, capped (sw-63wt.3).
##   - What it returns: {"value": int, "terms": [{"source", "name",
##     "amount"}]}, the terms for tooltips. Integer only, deterministic.
##   - Band kinds: a detachment's `band` column, or, when -1 (older saves,
##     rows spawned without one), derived: a caravan if it has a
##     destination or a supply line, else a garrison.

const COMMANDER: StringName = &"commander"
const BAND: StringName = &"band"
const FEATURE: StringName = &"feature"


## The band kind (OverworldRules band index) of detachment row `row`.
static func band_of(s: OverworldState, row: int) -> int:
	var d := s.detachments
	if d.band[row] >= 0:
		return d.band[row]
	if d.dest_plot[row] >= 0 or d.dest_commander[row] >= 0 or d.line[row] >= 0:
		return s.rules.band_caravan
	return s.rules.band_garrison


static func is_garrison(s: OverworldState, row: int) -> bool:
	return band_of(s, row) == s.rules.band_garrison


static func is_caravan(s: OverworldState, row: int) -> bool:
	return band_of(s, row) == s.rules.band_caravan


## Sight radius in hexes of a commander, band (detachment ID) or feature
## (feature ID). A feature's counts only while it is owned; the caller
## checks that. {} for an unknown kind or a gone entity.
static func sight(s: OverworldState, kind: StringName, id: int) -> Dictionary:
	var r := s.rules
	match kind:
		COMMANDER:
			var row := s.commanders.row_of(id)
			if row < 0:
				return {}
			var t := s.commanders.tmpl[row]
			return _base(r.commander_ids[t], r.cm_names[t], r.cm_sight[t])
		BAND:
			var row := s.detachments.row_of(id)
			if row < 0:
				return {}
			var b := band_of(s, row)
			return _base(r.band_ids[b], r.bd_names[b], r.bd_sight[b])
		FEATURE:
			var row := s.features.row_of(id)
			if row < 0:
				return {}
			var t := s.features.tmpl[row]
			return _base(r.feature_ids[t], r.hf_names[t], r.hf_sight[t])
	return {}


## Movement points per turn of a commander (its template's, before any
## banked points) or band. `as_band` >= 0 asks what a detachment would have
## as that kind (a garrison being sent off moves as a caravan).
static func movement(s: OverworldState, kind: StringName, id: int, as_band: int = -1) -> Dictionary:
	var r := s.rules
	match kind:
		COMMANDER:
			var row := s.commanders.row_of(id)
			if row < 0:
				return {}
			var t := s.commanders.tmpl[row]
			return _base(r.commander_ids[t], r.cm_names[t], r.cm_mp[t])
		BAND:
			var row := s.detachments.row_of(id)
			if row < 0:
				return {}
			var b := as_band if as_band >= 0 else band_of(s, row)
			return _base(r.band_ids[b], r.bd_names[b], r.bd_mp[b])
	return {}


## The value alone (0 for an unknown kind or a gone entity).
static func sight_of(s: OverworldState, kind: StringName, id: int) -> int:
	return int(sight(s, kind, id).get("value", 0))


static func movement_of(s: OverworldState, kind: StringName, id: int, as_band: int = -1) -> int:
	return int(movement(s, kind, id, as_band).get("value", 0))


static func _base(source: String, name: String, amount: int) -> Dictionary:
	return {"value": amount, "terms": [{"source": source, "name": name, "amount": amount}]}
