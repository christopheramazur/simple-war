class_name Health
extends RefCounted
## Unit hit points (GDD 02 §2.13, E3Q1, E3Q2). HP and max HP are fixed-point;
## a unit is dead at HP <= 0.


## Sets a unit's max HP, keeping the HP/max ratio unless `restores`.
## A living unit never dies from a max change (its HP stays above 0).
static func set_max(state: BattleState, row: int, new_max: int, restores: bool = false) -> void:
	var u := state.units
	var maxes: PackedInt64Array = u.take_column(&"hp_max")
	var old_max := maxes[row]
	if new_max == old_max:
		u.put_column(&"hp_max", maxes)
		return
	maxes[row] = new_max
	u.put_column(&"hp_max", maxes)
	var hp: PackedInt64Array = u.take_column(&"hp")
	if hp[row] > 0:
		hp[row] = maxi(MaxChange.rescale(hp[row], old_max, new_max, restores), 1)
	u.put_column(&"hp", hp)
