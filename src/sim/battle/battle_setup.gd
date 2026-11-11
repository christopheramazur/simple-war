class_name BattleSetup
extends RefCounted
## Builds a fresh BattleState from compiled rules: deploys each side's squads
## evenly down its deployment rectangle, in formation. GDD 02 §2.4.


static func create(context_id: int, rules: BattleRules, seed_value: int) -> BattleState:
	var state := BattleState.new(context_id, rules, seed_value)
	for side in rules.sides:
		_deploy_side(state, side)
	Centroids.update(state)
	return state


static func _deploy_side(state: BattleState, side: Dictionary) -> void:
	var r := state.rules
	var d: PackedInt64Array = side["deploy"]
	var list: PackedInt64Array = side["squads"]
	var n := list.size()
	for i in n:
		var st := list[i]
		var ax := d[0] + d[2] / 2
		var ay := d[1] + Fixed.round_div(d[3] * (2 * i + 1), 2 * n)
		spawn_squad(state, side["player"], st, ax, ay, side["facing"])


## Spawns one squad and its units; returns the squad ID.
static func spawn_squad(state: BattleState, player: int, st: int, ax: int, ay: int, facing: int) -> int:
	var r := state.rules
	var members := r.sq_members[st]
	var hp_total := 0
	for ui in members:
		hp_total += r.ut_hp[ui]
	var values := {
		"player": player, "tmpl": st, "order": BattleSquads.Order.HOLD,
		"tx": ax, "ty": ay, "facing": facing, "ax": ax, "ay": ay, "cx": ax, "cy": ay,
		"alive": members.size(), "hp_max": hp_total,
		"seen_by": BattleSquads.bit(player),
	}
	for p in 5:
		values[BattleSquads.POOLS[p]] = r.sq_pool_start[st * 5 + p]
		values[BattleSquads.CAPS[p]] = r.sq_pool_cap[st * 5 + p]
	var sid := state.squads.spawn(values)
	for slot in members.size():
		var ui := members[slot]
		var off := Formation.offset(r.sq_shape[st], slot, members.size(), r.sq_spacing[st], facing)
		var w := r.ut_weapon[ui]
		var uid := state.units.spawn({
			"squad": sid, "tmpl": ui, "slot": slot,
			"x": Fixed.clamp_fixed(ax + off[0], 0, Fixed.from_int(r.width) - 1),
			"y": Fixed.clamp_fixed(ay + off[1], 0, Fixed.from_int(r.height) - 1),
			"facing": facing, "hp": r.ut_hp[ui], "hp_max": r.ut_hp[ui],
			"ammo": r.wp_magazine[w] if w >= 0 else 0,
		})
		for b in r.ut_bundles[ui]:
			Effects.apply(state, b, sid, uid)
	for b in r.sq_bundles[st]:
		Effects.apply(state, b, sid)
	Abilities.spawn_for(state, sid, st)
	return sid
