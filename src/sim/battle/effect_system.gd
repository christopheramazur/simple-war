class_name EffectSystem
extends SimSystem
## Runs first every tick (GDD 02 §2.13):
## 1. ends instances whose holder is gone, and expires finished ones;
## 2. fires periodic ("every") effects and per-second accumulators, and
##    resets idle accumulators;
## 3. rebuilds the modifier lists Stats reads, from "while" effects whose
##    condition holds, including auras on selected squads;
## 4. pushes max-value changes (unit max HP, pool capacities) through the
##    ratio-keeping setters (E3Q2).

const POOL_CAP_STATS: Array[StringName] = [
	&"squad.pools.stamina.capacity", &"squad.pools.instinct.capacity", &"squad.pools.morale.capacity",
	&"squad.pools.prowess.capacity", &"squad.pools.legend.capacity",
]
const HP_STAT: StringName = &"unit.hp"


func system_name() -> StringName:
	return &"effects"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	var fx := state.effects
	if fx.count() == 0 and not state.fx_had_mods:
		return
	_end_and_expire(state)
	_time(state)
	_rebuild(state)
	var has_mods := not (state.squad_mods.is_empty() and state.unit_mods.is_empty())
	if has_mods or state.fx_had_mods:
		_push_maxima(state)
	state.fx_had_mods = has_mods


func _end_and_expire(state: BattleState) -> void:
	var fx := state.effects
	var gone := PackedInt64Array()
	var done := PackedInt64Array()
	for row in fx.count():
		var srow := state.squads.row_of(fx.holder_squad[row])
		var dead := srow < 0 or state.squads.destroyed[srow] == 1 \
			or (fx.holder_unit[row] >= 0 and state.units.row_of(fx.holder_unit[row]) < 0)
		if dead:
			gone.append(fx.id_at(row))
		elif fx.expires[row] >= 0 and state.tick >= fx.expires[row]:
			done.append(fx.id_at(row))
	for eid in gone:
		Effects.remove(state, eid, false)
	for eid in done:
		Effects.remove(state, eid, true)


func _time(state: BattleState) -> void:
	var fx := state.effects
	var bundles := state.rules.fx.bundles
	var ids := fx.ids()
	ids.sort()
	for eid in ids:
		var row := fx.row_of(eid)
		if row < 0:
			continue
		var bd: Dictionary = bundles[fx.bundle[row]]
		var age := state.tick - fx.applied[row]
		for e: Dictionary in bd["effects"]:
			if e["when"] == "every" and age > 0 and age % int(e["every"]) == 0:
				Effects.run_effect(state, eid, e)
		row = fx.row_of(eid)
		var acc: Dictionary = bd["acc"]
		if row < 0 or acc.is_empty():
			continue
		if acc["event"] == "second":
			Effects.count(state, eid, Fixed.round_div(acc["step"], state.rules.tps))
		elif acc["reset_after"] > 0 and fx.acc[row] != acc["start"] and state.tick - fx.acc_last[row] >= acc["reset_after"]:
			fx.set_value(eid, &"acc", acc["start"])


func _rebuild(state: BattleState) -> void:
	var fx := state.effects
	var bundles := state.rules.fx.bundles
	state.squad_mods = {}
	state.unit_mods = {}
	state.mod_restores = {}
	state.fx_listening = {}
	for row in fx.count():
		var bd: Dictionary = bundles[fx.bundle[row]]
		for ev: String in bd["listens"]:
			state.fx_listening[ev] = true
		var srow := state.squads.row_of(fx.holder_squad[row])
		for e: Dictionary in bd["effects"]:
			if e["when"] != "while" or not Effects.condition_holds(state, srow, e["cond"], fx.holder_unit[row]):
				continue
			var amount: int = e["amount"] * Effects.stacks_for(state, row, e)
			var m := StatModifier.make(String(e["stat"]), e["mod"], amount, e["source"])
			for tgt: Array in Effects.targets(state, row, e["target"]):
				_add(state, tgt[0], tgt[1], m, e["restores"])


func _add(state: BattleState, squad_id: int, unit_id: int, m: StatModifier, restores: bool) -> void:
	var store: Dictionary = state.unit_mods if unit_id >= 0 else state.squad_mods
	var key := unit_id if unit_id >= 0 else squad_id
	var by_stat: Dictionary = store.get(key, {})
	var stat := StringName(m.stat)
	var list: Array = by_stat.get(stat, [])
	list.append(m)
	by_stat[stat] = list
	store[key] = by_stat
	if restores:
		state.mod_restores["%s|%d|%d" % [stat, squad_id, unit_id]] = true


func _push_maxima(state: BattleState) -> void:
	var r := state.rules
	var u := state.units
	for urow in u.count():
		var want := Stats.unit(state, urow, HP_STAT, r.ut_hp[u.tmpl[urow]])
		if want != u.hp_max[urow]:
			Health.set_max(state, urow, want, Stats.restores(state, u.squad[urow], u.id_at(urow), HP_STAT))
	var sq := state.squads
	for srow in sq.count():
		if not sq.is_active(srow):
			continue
		for p in 5:
			var want := Stats.squad(state, srow, POOL_CAP_STATS[p], r.sq_pool_cap[sq.tmpl[srow] * 5 + p])
			if want != Pools.capacity(state, srow, p):
				Pools.set_capacity(state, srow, p, maxi(want, Fixed.ONE), Stats.restores(state, sq.id_at(srow), -1, POOL_CAP_STATS[p]), &"effect_capacity")
