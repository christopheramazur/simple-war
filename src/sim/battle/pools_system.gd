class_name PoolsSystem
extends SimSystem
## SIMPL homeostasis and the Morale governor. GDD 02 §2.8, R4Q4, R5Q1, R6Q3.
##
## Every tick each pool drifts toward its Neutral at its own rate.
## Every morale_interval ticks, Morale (the only channel between systems):
##   1. generates its base rate into its own pool;
##   2. leeches morale_leech_pct of the surplus from governed pools above
##      Neutral (from all governed pools, of their whole value, when Morale is
##      Broken);
##   3. pays governed pools below Neutral, weighted by capacity x deficit, as
##      far as Morale's own pool allows.
## Governed pools: Stamina, Instinct, Prowess. Legend is outside governance
## (R6Q3). Contagion and battle-event inputs are explicitly later (R5Q3).

const GOVERNED: Array[int] = [BattleSquads.STAMINA, BattleSquads.INSTINCT, BattleSquads.PROWESS]


func system_name() -> StringName:
	return &"pools"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	var sq := state.squads
	var r := state.rules
	var govern := state.tick % r.morale_interval == 0
	for row in sq.count():
		if not sq.is_active(row):
			continue
		for pool in 5:
			_drift(state, row, pool)
		if govern:
			_govern(state, row)


func _drift(state: BattleState, row: int, pool: int) -> void:
	var rate := Pools.drift(state, row, pool)
	if rate <= 0:
		return
	var diff := Pools.neutral(state, row, pool) - Pools.value(state, row, pool)
	if diff == 0:
		return
	var step := clampi(diff, -rate, rate)
	Pools.flow(state, row, pool, step, &"drift")


func _govern(state: BattleState, row: int) -> void:
	var r := state.rules
	Pools.flow(state, row, BattleSquads.MORALE, r.morale_gen, &"morale_base")
	var broken := Pools.band(state, row, BattleSquads.MORALE) == Pools.BROKEN
	for pool in GOVERNED:
		var v := Pools.value(state, row, pool)
		var surplus := v if broken else v - Pools.neutral(state, row, pool)
		if surplus <= 0:
			continue
		var take := Fixed.round_div(surplus * r.morale_leech_pct, 100)
		var got := -Pools.flow(state, row, pool, -take, &"morale_leech")
		Pools.flow(state, row, BattleSquads.MORALE, got, &"morale_leech")
	if broken:
		return
	var weights := PackedInt64Array()
	var deficits := PackedInt64Array()
	var total_w := 0
	var total_def := 0
	for pool in GOVERNED:
		var deficit := maxi(Pools.neutral(state, row, pool) - Pools.value(state, row, pool), 0)
		var w := Fixed.mul(Pools.capacity(state, row, pool), deficit)
		deficits.append(deficit)
		weights.append(w)
		total_w += w
		total_def += deficit
	if total_w <= 0:
		return
	var budget := mini(Pools.value(state, row, BattleSquads.MORALE), total_def)
	var paid := 0
	for i in GOVERNED.size():
		if weights[i] == 0:
			continue
		var share := mini(Fixed.mul_ratio(budget, weights[i], total_w), deficits[i])
		paid += Pools.flow(state, row, GOVERNED[i], share, &"morale_pay")
	Pools.flow(state, row, BattleSquads.MORALE, -paid, &"morale_pay")
