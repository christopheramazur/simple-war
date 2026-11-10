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
## Returns {evaded, blocked, resisted, flat, percent, floored, to_temp, to_hp,
##          absorbed, killed, terms: Array[[step, value]]}.
static func apply(state: BattleState, row: int, damage: int, dtype: int, cover_pct: int) -> Dictionary:
	var r := state.rules
	var u := state.units
	var prof := r.ut_defense[u.tmpl[row]]
	var nt := BattleRules.DAMAGE_TYPES.size()
	var out := {"evaded": false, "blocked": 0, "resisted": 0, "flat": 0, "percent": 0,
		"floored": 0, "to_temp": 0, "to_hp": 0, "absorbed": 0, "killed": false, "terms": []}
	var terms: Array = out["terms"]
	terms.append(["incoming", damage])

	var evasion := mini(r.df_evasion[prof] + cover_pct, 95)
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

	var res := r.df_resist[prof * nt + dtype]
	if res != 0:
		var rv := Fixed.round_div(d * res, 100)
		d -= rv
		out["resisted"] = rv
		terms.append(["resistance", -rv])

	var flat := mini(r.df_flat[prof], d)
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
	d = maxi(d, 0)

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
		heal = mini(heal, r.ut_hp[u.tmpl[row]] - hp[row])
		if heal > 0:
			hp[row] += heal
			out["absorbed"] = heal
			terms.append(["absorption", heal])
	u.put_column(&"hp", hp)
	return out
