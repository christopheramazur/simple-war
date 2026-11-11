class_name Stats
extends RefCounted
## Effective stat values (GDD 02 §2.13, E1Q3). Systems pass the base value
## they already have and get back the value with every active modifier
## applied. Modifiers on a squad apply to the squad's stats and to all of
## its units; modifiers on a unit apply to that unit only. EffectSystem
## rebuilds the modifier lists at the start of every tick.

static var _defs: Dictionary = {}  # StringName -> StatDef


static func def_of(state: BattleState, stat: StringName) -> StatDef:
	var d: StatDef = _defs.get(stat)
	if d == null:
		d = state.rules.stats.find(String(stat))
		assert(d != null, "Stats: unregistered stat %s" % stat)
		_defs[stat] = d
	return d


static func squad(state: BattleState, srow: int, stat: StringName, base: int) -> int:
	if state.squad_mods.is_empty():
		return base
	var mods := _squad_mods(state, srow, stat)
	return base if mods.is_empty() else StatCalc.value(def_of(state, stat), base, mods)


static func unit(state: BattleState, urow: int, stat: StringName, base: int) -> int:
	if state.squad_mods.is_empty() and state.unit_mods.is_empty():
		return base
	var mods := _unit_mods(state, urow, stat)
	return base if mods.is_empty() else StatCalc.value(def_of(state, stat), base, mods)


## Whether any active modifier touches this squad stat.
static func squad_has_mods(state: BattleState, srow: int, stat: StringName) -> bool:
	var by_stat: Dictionary = state.squad_mods.get(state.squads.id_at(srow), {})
	return by_stat.has(stat)


## As `squad`, with the step trace for the inspection window.
static func squad_trace(state: BattleState, srow: int, stat: StringName, base: int) -> Dictionary:
	return StatCalc.with_trace(def_of(state, stat), base, _squad_mods(state, srow, stat))


static func unit_trace(state: BattleState, urow: int, stat: StringName, base: int) -> Dictionary:
	return StatCalc.with_trace(def_of(state, stat), base, _unit_mods(state, urow, stat))


## Whether a "restores" effect is changing this stat on this holder (E3Q2).
static func restores(state: BattleState, squad_id: int, unit_id: int, stat: StringName) -> bool:
	return state.mod_restores.has("%s|%d|-1" % [stat, squad_id]) or state.mod_restores.has("%s|%d|%d" % [stat, squad_id, unit_id])


## The modifiers on a squad stat, or on a unit stat (squad's plus the
## unit's own), for the inspection call.
static func squad_mods(state: BattleState, srow: int, stat: StringName) -> Array[StatModifier]:
	return _squad_mods(state, srow, stat)


static func unit_mods(state: BattleState, urow: int, stat: StringName) -> Array[StatModifier]:
	return _unit_mods(state, urow, stat)


static func _squad_mods(state: BattleState, srow: int, stat: StringName) -> Array[StatModifier]:
	var by_stat: Dictionary = state.squad_mods.get(state.squads.id_at(srow), {})
	var out: Array[StatModifier] = []
	out.assign(by_stat.get(stat, []))
	return out


static func _unit_mods(state: BattleState, urow: int, stat: StringName) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var s: Dictionary = state.squad_mods.get(state.units.squad[urow], {})
	out.append_array(s.get(stat, []))
	var u: Dictionary = state.unit_mods.get(state.units.id_at(urow), {})
	out.append_array(u.get(stat, []))
	return out
