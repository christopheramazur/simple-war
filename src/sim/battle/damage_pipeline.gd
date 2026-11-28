class_name DamagePipeline
extends RefCounted
## One hit through a Defensive Profile, in the order fixed by R7Q1:
##   Evasion -> Block -> Resistance -> Flat -> Percentage -> Floor
##   -> Temporary HP -> Hit Points -> Absorption.
## Chance-based layers (evasion, block) are deterministic accumulators: a 25%
## evasion evades exactly every 4th hit (R2Q6). Every step is reported in the
## result so tooltips show the real calculation (R1Q3, R3Q10).

## Applies one hit of `damage` of `dtype` to unit row `row`. `cover_pct` is
## the terrain cover evasion at the target's position.
## Returns {evaded, blocked, resisted, flat, percent, floored, through, to_temp,
##          to_hp, absorbed, killed, terms: Array[[step, value]]}. `through` is
## the damage left after every defence (0 when evaded), before temporary HP.


static func apply(state: BattleState, row: int, damage: int, dtype: int, cover_pct: int) -> Dictionary:
	var r := state.rules
	var u := state.units
	var prof := u.defense[row]
	var nt := r.damage_types.size()
	var out := {"evaded": false, "blocked": 0, "resisted": 0, "flat": 0, "percent": 0,
		"floored": 0, "through": 0, "to_temp": 0, "to_hp": 0, "absorbed": 0, "killed": false, "terms": []}
	var terms: Array = out["terms"]
	terms.append(["incoming", damage])

	var evasion := mini(Fixed.to_int_round(Stats.unit(state, row, &"defense.evasion_pct", Fixed.from_int(r.df_evasion[prof]))) + cover_pct, 95)
	if evasion > 0:
		var acc: PackedInt64Array = u.take_column(&"acc_evade")
		acc[row] += evasion
		var evaded := acc[row] >= 100
		if evaded:
			acc[row] -= 100
		u.put_column(&"acc_evade", acc)
		if evaded:
			out["evaded"] = true
			terms.append(["evasion", evasion])
			return out

	var d := damage
	var block_chance := r.df_block_chance[prof]
	if block_chance > 0:
		var acc: PackedInt64Array = u.take_column(&"acc_block")
		acc[row] += block_chance
		var blocked := acc[row] >= 100
		if blocked:
			acc[row] -= 100
		u.put_column(&"acc_block", acc)
		if blocked:
			var b := Fixed.round_div(d * r.df_block_amount[prof], 100)
			d -= b
			out["blocked"] = b
			terms.append(["block", -b])

	d = _mitigate(state, row, d, dtype, out, terms)
	out["through"] = d

	var tmp: PackedInt64Array = u.take_column(&"temp_hp")
	var soak := mini(tmp[row], d)
	tmp[row] -= soak
	u.put_column(&"temp_hp", tmp)
	d -= soak
	if soak > 0:
		out["to_temp"] = soak
		terms.append(["temporary_hp", -soak])

	var hp: PackedInt64Array = u.take_column(&"hp")
	var to_hp := mini(hp[row], d)
	hp[row] -= to_hp
	out["to_hp"] = to_hp
	terms.append(["hit_points", to_hp])
	if hp[row] <= 0:
		out["killed"] = true
	elif to_hp > 0:
		var heal := r.df_absorb_flat[prof * nt + dtype] + Fixed.round_div(to_hp * r.df_absorb_pct[prof * nt + dtype], 100)
		heal = mini(heal, u.hp_max[row] - hp[row])
		if heal > 0:
			hp[row] += heal
			out["absorbed"] = heal
			terms.append(["absorption", heal])
	u.put_column(&"hp", hp)
	return out


## Expected effective damage of one hit, through every defence except the
## chance-based ones (evasion, block; R2Q6): the `through` that apply would
## report with both at zero. Pure: reads state, writes nothing. Fire
## distribution sums these per victim (GDD 02 §2.6 Remaining HP), so a
## shooter stops on a unit only once its expected damage covers it.
## Temporary HP and absorption are not counted (they are not part of "through").
static func preview(state: BattleState, row: int, damage: int, dtype: int) -> int:
	return _mitigate(state, row, damage, dtype, {}, [])


## Resistance, flat, percentage and floor (R7Q1 steps 3-6), in that order.
## Returns the damage left, never below 0. Writes each step into `out` and
## appends its [step, value] term to `terms` (preview discards both).
static func _mitigate(state: BattleState, row: int, damage: int, dtype: int, out: Dictionary, terms: Array) -> int:
	var r := state.rules
	var prof := state.units.defense[row]
	var nt := r.damage_types.size()
	var d := damage

	var res := Fixed.to_int_round(Stats.unit(state, row, r.resist_stats[dtype], Fixed.from_int(r.df_resist[prof * nt + dtype])))
	if res != 0:
		var rv := Fixed.round_div(d * res, 100)
		d -= rv
		out["resisted"] = rv
		terms.append(["resistance", -rv])

	var flat := mini(Stats.unit(state, row, &"defense.flat", r.df_flat[prof]), d)
	if flat > 0:
		d -= flat
		out["flat"] = flat
		terms.append(["flat", -flat])

	var pct := r.df_percent[prof]
	if pct > 0:
		var pv := Fixed.round_div(d * pct, 100)
		d -= pv
		out["percent"] = pv
		terms.append(["percentage", -pv])

	var floor_v := r.df_floor[prof * nt + dtype]
	if d < floor_v:
		out["floored"] = floor_v - d
		terms.append(["floor", floor_v - d])
		d = floor_v
	return maxi(d, 0)
