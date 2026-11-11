class_name Inspection
extends RefCounted
## What the inspection window shows for one squad (GDD 02 §2.13, E2Q3,
## E2Q12, E3Q8). Read-only: it never changes the state. The UI only formats
## what this returns; every number here is the one the simulation uses.
##
## Returned Dictionary:
##   id, player, template, name
##   stats:   squad stats, each a stat entry (below). Pool capacities only
##            for the owner.
##   units:   [{id, template, name, hp, hp_max, stats: [stat entries]}]
##   effects: bundle instances the squad or its units hold:
##            {id, bundle, name, tags, unit (-1 = whole squad), source (squad
##            ID, -1), stacks, remaining_ticks (-1 = lasts the battle),
##            lines (rules text), accumulator ({} or {event, value, threshold,
##            next_in, text})}
##   abilities (owner only): Abilities.view entries plus lines and the
##            effective costs {pool: fixed}.
## A stat entry: {stat (registry ID), name, label (e.g. the fire mode), unit,
##   base, value, trace: [{step, value, terms: [{source, name, amount}]}]}.
## Values are raw fixed.
##
## Deception (E2Q12): for anyone but the owner, a bundle tagged "deception"
## that has a disguise is shown as the disguise: in the effects list, and in
## traces, where the disguise's own self-targeted modify effects stand in
## for the real ones.

const DECEPTION: String = "deception"
const POOL_CAP_STATS: Array[StringName] = EffectSystem.POOL_CAP_STATS


## `viewer` is the inspecting player; 0 sees everything as the owner does
## (tests, replays, the AI factory).
static func squad(state: BattleState, squad_id: int, viewer: int = 0) -> Dictionary:
	var r := state.rules
	var sq := state.squads
	var srow := sq.row_of(squad_id)
	if srow < 0:
		return {}
	var st := sq.tmpl[srow]
	var owner := viewer == 0 or viewer == sq.player[srow]
	var hidden := {} if owner else _hidden_bundles(state, squad_id)
	var stats := [
		_entry(state, srow, -1, &"squad.sight", r.sq_sight[st], hidden),
		_entry(state, srow, -1, &"squad.concealment_pct", r.sq_concealment[st], hidden),
		_entry(state, srow, -1, &"squad.detection_radius", r.sq_detection[st], hidden),
	]
	if owner:
		for p in 5:
			stats.append(_entry(state, srow, -1, POOL_CAP_STATS[p], r.sq_pool_cap[st * 5 + p], hidden))
	var units := []
	for urow in Centroids.units_of(state, srow):
		units.append(_unit(state, srow, urow, hidden))
	var out := {
		"id": squad_id, "player": sq.player[srow], "template": r.squad_ids[st], "name": r.sq_names[st],
		"stats": stats, "units": units, "effects": _effects(state, squad_id, hidden),
	}
	if owner:
		out["abilities"] = _abilities(state, srow)
	return out


static func _unit(state: BattleState, srow: int, urow: int, hidden: Dictionary) -> Dictionary:
	var r := state.rules
	var u := state.units
	var ut := u.tmpl[urow]
	var df := r.ut_defense[ut]
	var mv := r.ut_movement[ut]
	var stats := [
		_entry(state, srow, urow, &"unit.hp", r.ut_hp[ut], hidden),
		_entry(state, srow, urow, &"unit.proficiency_pct", Fixed.from_int(r.ut_proficiency[ut]), hidden),
		_entry(state, srow, urow, &"defense.evasion_pct", Fixed.from_int(r.df_evasion[df]), hidden),
		_entry(state, srow, urow, &"defense.flat", r.df_flat[df], hidden),
	]
	var nt := DataSchema.DAMAGE_TYPES.size()
	for d in nt:
		stats.append(_entry(state, srow, urow, DamagePipeline.RESIST_STATS[d], Fixed.from_int(r.df_resist[df * nt + d]), hidden))
	stats.append(_entry(state, srow, urow, &"movement.walk", r.mv_walk[mv], hidden))
	stats.append(_entry(state, srow, urow, &"movement.run", r.mv_run[mv], hidden))
	var w := r.ut_weapon[ut]
	if w >= 0:
		for m in range(r.wp_mode_start[w], r.wp_mode_start[w] + r.wp_mode_count[w]):
			stats.append(_entry(state, srow, urow, &"weapon.modes.*.accuracy", r.md_accuracy[m], hidden, r.md_name[m]))
			stats.append(_entry(state, srow, urow, &"weapon.modes.*.damage", r.md_damage[m], hidden, r.md_name[m]))
	return {"id": u.id_at(urow), "template": r.unit_ids[ut], "name": _unit_name(state, ut),
		"hp": u.hp[urow], "hp_max": u.hp_max[urow], "stats": stats}


static func _entry(state: BattleState, srow: int, urow: int, stat: StringName, base: int, hidden: Dictionary, label: String = "") -> Dictionary:
	var def := Stats.def_of(state, stat)
	var mods := Stats.unit_mods(state, urow, stat) if urow >= 0 else Stats.squad_mods(state, srow, stat)
	if not hidden.is_empty():
		mods = _disguised(state, srow, urow, stat, mods, hidden)
	var t := StatCalc.with_trace(def, base, mods)
	var trace := []
	for step: Dictionary in t["trace"]:
		var terms := []
		for term: Array in step["terms"]:
			var bid := String(term[0]).get_slice("#", 0)
			terms.append({"source": bid, "name": _bundle_name(state, bid), "amount": term[1]})
		trace.append({"step": step["step"], "value": step["value"], "terms": terms})
	return {"stat": String(stat), "name": RulesText.stat_name(def.id), "label": label, "unit": def.unit,
		"base": base, "value": t["value"], "trace": trace}


## Bundles on this squad (or its units) that a non-owner sees disguised:
## real bundle index -> disguise bundle index.
static func _hidden_bundles(state: BattleState, squad_id: int) -> Dictionary:
	var fx := state.effects
	var bundles := state.rules.fx.bundles
	var out := {}
	for row in fx.count():
		if fx.holder_squad[row] != squad_id:
			continue
		var bd: Dictionary = bundles[fx.bundle[row]]
		if bd["disguise"] >= 0 and (bd["tags"] as PackedStringArray).has(DECEPTION):
			out[fx.bundle[row]] = bd["disguise"]
	return out


## Drops modifiers from hidden bundles and adds what their disguises would
## give the holder (self-targeted modify effects, times the real stacks).
static func _disguised(state: BattleState, srow: int, urow: int, stat: StringName, mods: Array[StatModifier], hidden: Dictionary) -> Array[StatModifier]:
	var fx := state.effects
	var bundles := state.rules.fx.bundles
	var hidden_ids := {}
	for b: int in hidden:
		hidden_ids[bundles[b]["id"]] = true
	var out: Array[StatModifier] = []
	for m in mods:
		if not hidden_ids.has(m.source.get_slice("#", 0)):
			out.append(m)
	var sid := state.squads.id_at(srow)
	var uid := state.units.id_at(urow) if urow >= 0 else -1
	for row in fx.count():
		if fx.holder_squad[row] != sid or not hidden.has(fx.bundle[row]):
			continue
		if fx.holder_unit[row] >= 0 and fx.holder_unit[row] != uid:
			continue
		for e: Dictionary in bundles[hidden[fx.bundle[row]]]["effects"]:
			var self_target: bool = (e["target"] as Dictionary).get("select", "self") == "self"
			if e["when"] == "while" and e["stat"] == stat and self_target:
				out.append(StatModifier.make(String(stat), e["mod"], e["amount"] * fx.stacks[row], e["source"]))
	return out


static func _effects(state: BattleState, squad_id: int, hidden: Dictionary) -> Array:
	var r := state.rules
	var fx := state.effects
	var out := []
	var ids := fx.ids()
	ids.sort()
	for eid in ids:
		var row := fx.row_of(eid)
		if fx.holder_squad[row] != squad_id:
			continue
		var b: int = hidden.get(fx.bundle[row], fx.bundle[row])
		var bd: Dictionary = r.fx.bundles[b]
		var acc := {}
		if b == fx.bundle[row] and not (bd["acc"] as Dictionary).is_empty():
			acc = _accumulator(bd["acc"], fx.acc[row])
		out.append({
			"id": eid, "bundle": bd["id"], "name": bd["name"], "tags": bd["tags"],
			"unit": fx.holder_unit[row], "source": fx.source[row], "stacks": fx.stacks[row],
			"remaining_ticks": fx.expires[row] - state.tick if fx.expires[row] >= 0 else -1,
			"lines": RulesText.bundle_lines(r.fx, b, r.stats, r.tps), "accumulator": acc,
		})
	return out


## Accumulator progress (E2Q9): "next in" counts events, HP or seconds.
static func _accumulator(acc: Dictionary, value: int) -> Dictionary:
	var step: int = maxi(acc["step"], 1)
	var next_in := Fixed.div(maxi(acc["threshold"] - value, 0), step)
	if acc["event"] in ["attack", "hit", "casualty"]:
		next_in = (next_in + Fixed.ONE - 1) / Fixed.ONE * Fixed.ONE
	return {"event": acc["event"], "value": value, "threshold": acc["threshold"], "next_in": next_in,
		"text": RulesText.next_in(acc["event"], next_in)}


static func _abilities(state: BattleState, srow: int) -> Array:
	var r := state.rules
	var out := Abilities.view(state, state.squads.id_at(srow))
	for v: Dictionary in out:
		var ab := Abilities.index_of(state, v["id"])
		v["lines"] = RulesText.ability_lines(r, ab)
		var costs := {}
		for p in 5:
			var c := Abilities.cost(state, srow, ab, p)
			if c > 0:
				costs[DataSchema.SIMPL[p]] = c
		v["costs"] = costs
	return out


static func _bundle_name(state: BattleState, bundle_id: String) -> String:
	var b := state.rules.fx.index_of(bundle_id)
	return state.rules.fx.bundles[b]["name"] if b >= 0 else bundle_id


static func _unit_name(state: BattleState, ut: int) -> String:
	return state.rules.ut_names[ut]
