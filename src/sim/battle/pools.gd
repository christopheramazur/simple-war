class_name Pools
extends RefCounted
## The one implementation shared by every SIMPL pressure pool (R4Q4, R5Q1).
## Every change goes through `flow`, which clamps, records the source-tagged
## ledger entry (R6Q3) and emits Surge / Break events on band crossings (R6Q2).

const SURGING: int = 4
const BROKEN: int = 0


static func value(state: BattleState, row: int, pool: int) -> int:
	return state.squads.get(BattleSquads.POOLS[pool])[row]


static func capacity(state: BattleState, row: int, pool: int) -> int:
	return state.squads.get(BattleSquads.CAPS[pool])[row]


## Neutral scales with the squad's current capacity.
static func neutral(state: BattleState, row: int, pool: int) -> int:
	var i := state.squads.tmpl[row] * 5 + pool
	return _scaled(state, row, pool, state.rules.sq_pool_neutral[i], state.rules.sq_pool_cap[i])


## Drift per tick, scaled with the squad's current capacity.
static func drift(state: BattleState, row: int, pool: int) -> int:
	var i := state.squads.tmpl[row] * 5 + pool
	return _scaled(state, row, pool, state.rules.sq_pool_drift[i], state.rules.sq_pool_cap[i])


static func _scaled(state: BattleState, row: int, pool: int, v: int, template_cap: int) -> int:
	var cap := capacity(state, row, pool)
	if cap == template_cap or template_cap <= 0:
		return v
	return Fixed.mul_ratio(v, cap, template_cap)


## Sets a pool's capacity. The value keeps its ratio to capacity unless
## `restores` (E3Q2). The change is a flow (ledger source `source`), so bands
## and Surge/Break events stay correct.
static func set_capacity(state: BattleState, row: int, pool: int, new_cap: int, restores: bool, source: StringName) -> void:
	var old_cap := capacity(state, row, pool)
	if new_cap == old_cap:
		return
	var before := value(state, row, pool)
	var after := MaxChange.rescale(before, old_cap, new_cap, restores)
	var cn := BattleSquads.CAPS[pool]
	var caps: PackedInt64Array = state.squads.take_column(cn)
	caps[row] = new_cap
	state.squads.put_column(cn, caps)
	# The clamp in flow uses the new capacity.
	flow(state, row, pool, after - before, source)


static func band(state: BattleState, row: int, pool: int) -> int:
	return state.rules.band_of(value(state, row, pool), capacity(state, row, pool))


## value / neutral, clamped to [lo, hi] (fixed). The "efficacy" a pool
## grants relative to Neutral, used where the Rules Spec names one (R4Q5, R4Q6).
static func efficacy(state: BattleState, row: int, pool: int, lo: int = 0, hi: int = Fixed.ONE) -> int:
	var n := neutral(state, row, pool)
	if n <= 0:
		return hi
	return Fixed.clamp_fixed(Fixed.div(value(state, row, pool), n), lo, hi)


## Adds `amount` (fixed, negative = sink) to a pool. Returns what applied.
static func flow(state: BattleState, row: int, pool: int, amount: int, source: StringName) -> int:
	if amount == 0:
		return 0
	var col_name := BattleSquads.POOLS[pool]
	var cap := capacity(state, row, pool)
	var col: PackedInt64Array = state.squads.take_column(col_name)
	var before := col[row]
	var after := Fixed.clamp_fixed(before + amount, 0, cap)
	col[row] = after
	state.squads.put_column(col_name, col)
	var applied := after - before
	if applied == 0:
		return 0
	var sid := state.squads.id_at(row)
	state.record_flow(sid, pool, source, applied)
	var b0 := state.rules.band_of(before, cap)
	var b1 := state.rules.band_of(after, cap)
	if b0 != b1:
		var pool_name: String = DataSchema.SIMPL[pool]
		if b1 == SURGING:
			state.events.push(&"pool_surge", {"squad": sid, "pool": pool_name}, state.tick)
		elif b1 == BROKEN:
			state.events.push(&"pool_break", {"squad": sid, "pool": pool_name}, state.tick)
		state.events.push(&"pool_band", {"squad": sid, "pool": pool_name, "from": b0, "to": b1}, state.tick)
	return applied
