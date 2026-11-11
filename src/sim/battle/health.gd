class_name Health
extends RefCounted
## Unit hit points (GDD 02 §2.13, E3Q1, E3Q2). HP and max HP are fixed-point;
## a unit is dead at HP <= 0. Damage is never applied directly: callers queue
## it, and HealthSystem applies the whole tick's queue at once (E2Q2), so all
## fire in a tick is simultaneous.

## Queue entry layout.
const STRIDE: int = 7
const Q_BY_UNIT: int = 0
const Q_BY_SQUAD: int = 1
const Q_VICTIM: int = 2
const Q_VICTIM_SQUAD: int = 3
const Q_DAMAGE: int = 4
const Q_TYPE: int = 5
## Chain depth of the action that caused it; hooks fire only at 0 (E2Q5).
const Q_DEPTH: int = 6


## Queues one hit of `damage` (fixed) of damage type `dtype` on unit
## `victim_id`, from unit `by_unit` of squad `by_squad` (-1 for effects with
## no shooter / no source). Negative damage heals, up to max HP. IDs, not rows.
static func queue(state: BattleState, by_unit: int, by_squad: int, victim_id: int, victim_squad: int, damage: int, dtype: int, depth: int = 0) -> void:
	state.damage_queue.append_array(PackedInt64Array([by_unit, by_squad, victim_id, victim_squad, damage, dtype, depth]))


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
