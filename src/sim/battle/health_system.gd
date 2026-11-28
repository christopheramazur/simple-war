class_name HealthSystem
extends SimSystem
## Owns unit HP (E2Q2, E4Q1). Applies every hit queued this tick, after all
## fire, in canonical order (shooter unit ID, then queue order). A unit killed
## earlier in the drain takes no further hits; the hit that killed it gets the
## kill. Negative entries heal. Each depth-0 hit reports hit / damaged / kill
## / casualty to Effects; hits those hooks queue are drained in the same tick. Then: squad HP lost, Stamina sink for HP lost (R4Q5), Legend floats
## for archetypal damage (R5Q6), kills, Value score, and a `squad_damaged`
## event per (attacker, target) pair. That event also carries the fire
## accounting (U1 D1): `raw` (positive damage queued, before any defence),
## `wasted_hits` / `wasted_damage` (queued on a unit already dead), `overkill`
## (post-defence damage past the HP a killing hit needed) and `mitigation`
## (raw minus what got through the defence; evasion is all mitigation). For
## every live hit, raw = mitigation + damage + overkill.


func system_name() -> StringName:
	return &"health"


## Per-pair tally slots ("attacker|target" -> Array of these).
const T_DEALT := 0
const T_KILLS := 1
const T_RAW := 2
const T_WASTED_HITS := 3
const T_WASTED := 4
const T_OVERKILL := 5
const T_MITIGATION := 6
const T_SLOTS := 7


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	# "attacker|target" -> [T_* slots]; first-seen order kept for events.
	var tally := {}
	var pairs: Array[String] = []
	while not state.damage_queue.is_empty():
		var q := state.damage_queue
		state.damage_queue = PackedInt64Array()
		_drain(state, q, tally, pairs)
	for key in pairs:
		var ids := key.split("|")
		var t: Array = tally[key]
		state.events.push(&"squad_damaged", {"squad": int(ids[0]), "target": int(ids[1]),
			"damage": t[T_DEALT], "kills": t[T_KILLS], "raw": t[T_RAW],
			"wasted_hits": t[T_WASTED_HITS], "wasted_damage": t[T_WASTED],
			"overkill": t[T_OVERKILL], "mitigation": t[T_MITIGATION]}, state.tick)


func _drain(state: BattleState, q: PackedInt64Array, tally: Dictionary, pairs: Array[String]) -> void:
	var n := q.size() / Health.STRIDE
	var order: Array[int] = []
	order.resize(n)
	for i in n:
		order[i] = i
	order.sort_custom(func(a: int, b: int) -> bool:
		var ua := q[a * Health.STRIDE + Health.Q_BY_UNIT]
		var ub := q[b * Health.STRIDE + Health.Q_BY_UNIT]
		return ua < ub if ua != ub else a < b)
	var r := state.rules
	var sq := state.squads
	var u := state.units
	for i in order:
		var o := i * Health.STRIDE
		var victim := u.row_of(q[o + Health.Q_VICTIM])
		var by_squad := q[o + Health.Q_BY_SQUAD]
		var row := sq.row_of(by_squad)
		var trow := sq.row_of(q[o + Health.Q_VICTIM_SQUAD])
		# Only enemies earn credit (Legend, Value) for damage and kills.
		var enemy := row >= 0 and trow >= 0 and sq.player[row] != sq.player[trow]
		var raw: int = q[o + Health.Q_DAMAGE]
		if victim < 0 or trow < 0 or u.hp[victim] <= 0:
			# Queued on a unit already dead (or gone): wasted fire (U1 D1).
			if raw > 0 and row >= 0 and trow >= 0:
				var wt := _slots(tally, pairs, by_squad, q[o + Health.Q_VICTIM_SQUAD])
				wt[T_WASTED_HITS] += 1
				wt[T_WASTED] += raw
				wt[T_RAW] += raw
			continue
		var depth := q[o + Health.Q_DEPTH]
		if raw < 0:
			_heal(state, victim, -raw)
			continue
		var dtype := q[o + Health.Q_TYPE]
		var cover := r.f_cover_evasion[r.feature_at(u.x[victim], u.y[victim])]
		var res := DamagePipeline.apply(state, victim, raw, dtype, cover)
		var dealt: int = res["to_hp"] + res["to_temp"]
		var killed: bool = res["killed"]
		# Post-defence damage past what a killing hit needed (U1 D1 overkill).
		var through: int = res["through"]
		var overkill := maxi(through - dealt, 0) if killed else 0
		if dealt > 0:
			var lost: PackedInt64Array = sq.take_column(&"hp_lost")
			lost[trow] += res["to_hp"]
			sq.put_column(&"hp_lost", lost)
			var stam := Fixed.from_ratio(res["to_hp"] * 100 * r.sink("stamina_per_hp_lost_pct"), maxi(sq.hp_max[trow], 1))
			Pools.flow(state, trow, BattleSquads.STAMINA, -stam, &"hp_lost")
			if enemy:
				_legend_per_10(state, row, &"dmg_dealt", dealt, dtype)
			_legend_per_10(state, trow, &"dmg_taken", dealt, dtype)
		var vid := u.id_at(victim)
		var tid := sq.id_at(trow)
		var by_unit := q[o + Health.Q_BY_UNIT]
		if state.trace_shots and dealt > 0:
			state.hit_trace.append_array(PackedInt64Array([state.tick, vid, dealt, by_unit]))
		if killed:
			state.commands.despawn(&"unit", vid)
			if enemy:
				var killer := sq.player[row]
				state.value_score[killer] = int(state.value_score[killer]) + Fixed.round_div(r.sq_value[sq.tmpl[trow]], r.sq_members[sq.tmpl[trow]].size())
			state.events.push(&"unit_killed", {"unit": vid, "squad": tid, "by": by_squad}, state.tick)
			_count_loss(state, trow)
		if dealt > 0:
			Effects.on_event(state, "damaged", tid, vid, by_squad, by_unit, dealt, depth)
			Abilities.on_event(state, "damaged", tid, by_squad)
			if row >= 0:
				Effects.on_event(state, "hit", by_squad, by_unit, tid, vid, Fixed.ONE, depth)
		if killed:
			Effects.on_event(state, "casualty", tid, vid, by_squad, by_unit, Fixed.ONE, depth)
			Abilities.on_event(state, "casualty", tid, by_squad)
			if row >= 0:
				Effects.on_event(state, "kill", by_squad, by_unit, tid, vid, Fixed.ONE, depth)
		if row < 0:
			continue
		var t := _slots(tally, pairs, by_squad, tid)
		t[T_DEALT] += dealt
		t[T_KILLS] += 1 if killed else 0
		t[T_RAW] += raw
		t[T_OVERKILL] += overkill
		t[T_MITIGATION] += raw - through


## The tally slots for one (attacker, target) pair, created on first use.
func _slots(tally: Dictionary, pairs: Array[String], by_squad: int, tid: int) -> Array:
	var key := "%d|%d" % [by_squad, tid]
	if not tally.has(key):
		tally[key] = [0, 0, 0, 0, 0, 0, 0]
		pairs.append(key)
	return tally[key]


func _heal(state: BattleState, victim: int, amount: int) -> void:
	var u := state.units
	var hp: PackedInt64Array = u.take_column(&"hp")
	hp[victim] = mini(hp[victim] + amount, u.hp_max[victim])
	u.put_column(&"hp", hp)


func _count_loss(state: BattleState, trow: int) -> void:
	var sq := state.squads
	var alive: PackedInt64Array = sq.take_column(&"alive")
	alive[trow] -= 1
	var gone := alive[trow] <= 0
	sq.put_column(&"alive", alive)
	if gone:
		var d: PackedByteArray = sq.take_column(&"destroyed")
		d[trow] = 1
		sq.put_column(&"destroyed", d)
		state.events.push(&"squad_destroyed", {"squad": sq.id_at(trow), "player": sq.player[trow]}, state.tick)


## Legend for archetypal damage: dealers on damage dealt, sappers on explosive
## damage dealt, tanks on damage taken; one float per 10 points (R5Q6).
func _legend_per_10(state: BattleState, row: int, counter: StringName, amount: int, dtype: int) -> void:
	var r := state.rules
	var sq := state.squads
	var arche := BattleRules.ARCHETYPES[r.sq_archetype[sq.tmpl[row]]]
	var key := ""
	if counter == &"dmg_dealt" and arche == "damage":
		key = "legend_damage_per_10_dealt"
	elif counter == &"dmg_dealt" and arche == "sapper" and r.damage_types[dtype] == "explosive":
		key = "legend_sapper_per_10_dealt"
	elif counter == &"dmg_taken" and arche == "tank":
		key = "legend_tank_per_10_taken"
	if key.is_empty():
		return
	var col: PackedInt64Array = sq.take_column(counter)
	col[row] += amount
	var ten := 10 * Fixed.ONE  # damage is fixed-point (E3Q1)
	var tens := col[row] / ten
	col[row] -= tens * ten
	sq.put_column(counter, col)
	if tens > 0:
		Pools.flow(state, row, BattleSquads.LEGEND, Fixed.from_int(tens * r.flt(key)), StringName("legend_" + arche))
