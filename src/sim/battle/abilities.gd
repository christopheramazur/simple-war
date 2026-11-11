class_name Abilities
extends RefCounted
## Abilities at runtime: a bundle plus an activation (GDD 02 §2.13, E2Q10,
## E3Q6, E3Q7). Owns the abilities table.
##
## - Planning orders use abilities ("abilities" in the order; BattleOrders
##   validates through validate_use). Toggles switch on or off at execute
##   start (R8Q2); others pay their costs, start their cooldown and spend a
##   charge.
## - A toggle that sinks nothing starts on (R7Q4). One that sinks a pool
##   pays upkeep each tick and switches off when a pool it sinks falls to its
##   auto-off band (default Broken, R8Q2).
## - Reactions are queued in the reaction window (Reactions) and fire on
##   contact; their bundle sees the trigger as "other".
## - Readying (R7Q3, E3Q6): with a ready time, the ability readies first,
##   sinking the squad's Prowess (Vacuum), and its bundle — the readied
##   state — applies when readying ends. lose_on events cancel readying or
##   end the readied state; interrupting a readying squad floats the
##   interrupter's Prowess.
## Activation numbers are read through the ability.activation.* stats, so
## effects can change them for the whole squad.

const COST_STATS: Array[StringName] = [
	&"ability.activation.costs.stamina", &"ability.activation.costs.instinct", &"ability.activation.costs.morale",
	&"ability.activation.costs.prowess", &"ability.activation.costs.legend",
]
const UPKEEP_STATS: Array[StringName] = [
	&"ability.activation.upkeep_per_s.stamina", &"ability.activation.upkeep_per_s.instinct",
	&"ability.activation.upkeep_per_s.morale", &"ability.activation.upkeep_per_s.prowess",
	&"ability.activation.upkeep_per_s.legend",
]
const COOLDOWN_STAT: StringName = &"ability.activation.cooldown_s"
const READY_STAT: StringName = &"ability.activation.ready_s"
const READY_PROWESS_STAT: StringName = &"ability.activation.readying_prowess_per_s"
const RANGE_STAT: StringName = &"ability.activation.range"


## Creates the squad's ability rows; toggles that sink nothing start on.
static func spawn_for(state: BattleState, squad_id: int, st: int) -> void:
	var r := state.rules
	for ab in r.sq_abilities[st]:
		var aid := state.abilities.spawn({"squad": squad_id, "ability": ab, "charges": r.ab_charges[ab]})
		if r.ab_default_on[ab] == 1:
			set_toggle(state, aid, true)


## Ability row ID for (squad, ability index), or -1.
static func find(state: BattleState, squad_id: int, ab: int) -> int:
	var t := state.abilities
	for row in t.count():
		if t.squad[row] == squad_id and t.ability[row] == ab:
			return t.id_at(row)
	return -1


## Ability index by template ID, or -1.
static func index_of(state: BattleState, ability_id: String) -> int:
	return Array(state.rules.ab_ids).find(ability_id)


## Ability row IDs of a squad, in template order.
static func of_squad(state: BattleState, squad_id: int) -> PackedInt64Array:
	var t := state.abilities
	var out := PackedInt64Array()
	for row in t.count():
		if t.squad[row] == squad_id:
			out.append(t.id_at(row))
	return out


static func cost(state: BattleState, srow: int, ab: int, pool: int) -> int:
	return Stats.squad(state, srow, COST_STATS[pool], state.rules.ab_costs[ab][pool])


## "" if the ability can be used now (cooldown, charges, costs), else why.
static func can_use(state: BattleState, aid: int) -> String:
	var t := state.abilities
	var row := t.row_of(aid)
	var ab := t.ability[row]
	var name: String = state.rules.ab_ids[ab]
	if t.cooldown_until[row] > state.tick:
		return "'%s' is cooling down" % name
	if t.charges[row] == 0:
		return "'%s' has no charges left" % name
	var srow := state.squads.row_of(t.squad[row])
	for p in 5:
		var c := cost(state, srow, ab, p)
		if c > 0 and Pools.value(state, srow, p) < c:
			return "not enough %s for '%s'" % [DataSchema.SIMPL[p], name]
	return ""


## Validates one entry of an order's "abilities" list for squad row `srow`:
## {"id": ability, "on": bool} for toggles, {"id": ability, "target": squad}
## for others ("target" only when the ability targets a squad).
static func validate_use(state: BattleState, srow: int, a: Variant) -> String:
	if typeof(a) != TYPE_DICTIONARY or typeof((a as Dictionary).get("id")) != TYPE_STRING:
		return "ability entry needs an id"
	var r := state.rules
	var sq := state.squads
	var ab := index_of(state, a["id"])
	var aid := find(state, sq.id_at(srow), ab) if ab >= 0 else -1
	if aid < 0:
		return "squad has no ability '%s'" % a["id"]
	if r.ab_reaction[ab] == 1:
		return "'%s' is a reaction: queue it in the reaction window" % a["id"]
	var t := state.abilities
	if r.ab_toggle[ab] == 1:
		if typeof(a.get("on")) != TYPE_BOOL:
			return "'%s' needs on: true or false" % a["id"]
		if a["on"] and t.on[t.row_of(aid)] == 0:
			return can_use(state, aid)
		return ""
	var err := can_use(state, aid)
	if not err.is_empty():
		return err
	match BattleRules.TARGETING[r.ab_targeting[ab]]:
		"squad":
			var tid: Variant = a.get("target")
			if typeof(tid) != TYPE_INT or not sq.is_alive(tid):
				return "'%s' needs a target squad" % a["id"]
			var trow := sq.row_of(tid)
			if not sq.is_active(trow):
				return "invalid target"
			if sq.player[trow] != sq.player[srow] and sq.seen_by[trow] & BattleSquads.bit(sq.player[srow]) == 0:
				return "target not visible"
			var reach := Stats.squad(state, srow, RANGE_STAT, r.ab_range[ab]) if r.ab_range[ab] >= 0 else -1
			if reach >= 0 and Fixed.distance(sq.cx[srow], sq.cy[srow], sq.cx[trow], sq.cy[trow]) > reach:
				return "target out of range"
		"point":
			return "'%s': point targeting is not supported yet" % a["id"]
	return ""


## Applies a validated order entry.
static func apply_use(state: BattleState, srow: int, a: Dictionary) -> void:
	var aid := find(state, state.squads.id_at(srow), index_of(state, a["id"]))
	if state.rules.ab_toggle[state.abilities.ability[state.abilities.row_of(aid)]] == 1:
		set_toggle(state, aid, a["on"])
	else:
		use(state, aid, int(a.get("target", -1)))


## Switches a toggle on (paying its costs, readying if it has a ready time)
## or off.
static func set_toggle(state: BattleState, aid: int, turn_on: bool) -> void:
	var t := state.abilities
	var row := t.row_of(aid)
	if (t.on[row] == 1) == turn_on:
		return
	if not turn_on:
		_end(state, aid, "off")
		return
	_pay(state, aid, StringName("ability_" + state.rules.ab_ids[t.ability[row]]))
	_begin(state, aid, -1)


## Uses a non-toggle ability on `target_id` (-1 = its own squad).
static func use(state: BattleState, aid: int, target_id: int) -> void:
	_pay(state, aid, StringName("ability_" + state.rules.ab_ids[state.abilities.ability[state.abilities.row_of(aid)]]))
	_begin(state, aid, target_id)


## Fires a queued reaction against its trigger squad (Reactions).
static func react(state: BattleState, aid: int, trigger_id: int) -> void:
	_pay(state, aid, &"reaction")
	var t := state.abilities
	var row := t.row_of(aid)
	_put(t, aid, &"since", state.tick)
	var eid := Effects.apply(state, state.rules.ab_bundle[t.ability[row]], t.squad[row], -1, -1, 0, trigger_id)
	_hold(state, aid, eid)


## Reports a damaged / casualty event on `squad_id` caused by `by_squad`
## (HealthSystem), for lose_on.
static func on_event(state: BattleState, event: String, squad_id: int, by_squad: int) -> void:
	if not state.rules.ab_lost_on_hits:
		return
	var t := state.abilities
	for row in t.count():
		if t.squad[row] == squad_id and t.on[row] == 1 and state.rules.ab_lose_on[t.ability[row]].has(event):
			lose(state, t.id_at(row), by_squad)


## A lose_on condition hit: readying is interrupted (floating the
## interrupter's Prowess if an enemy did it), or the readied state ends.
static func lose(state: BattleState, aid: int, by_squad: int) -> void:
	var t := state.abilities
	var row := t.row_of(aid)
	var sid := t.squad[row]
	var name: String = state.rules.ab_ids[t.ability[row]]
	var readying := t.ready_at[row] >= 0
	_end(state, aid, "interrupted" if readying else "lost")
	if not readying:
		return
	var sq := state.squads
	var brow := sq.row_of(by_squad)
	if brow >= 0 and sq.player[brow] != sq.player[sq.row_of(sid)]:
		Pools.flow(state, brow, BattleSquads.PROWESS, Fixed.from_int(state.rules.flt("prowess_interrupt")), &"interrupt")
	state.events.push(&"ability_interrupted", {"squad": sid, "ability": name, "by": by_squad}, state.tick)


## Per tick (AbilitySystem): lose_on move / attack, readying, expiry of the
## held state, upkeep and auto-off.
static func tick(state: BattleState) -> void:
	var r := state.rules
	var t := state.abilities
	var sq := state.squads
	for row in t.count():
		if t.on[row] == 0:
			continue
		var aid := t.id_at(row)
		var srow := sq.row_of(t.squad[row])
		if srow < 0 or not sq.is_active(srow):
			continue
		var ab := t.ability[row]
		var lose_on := r.ab_lose_on[ab]
		if state.tick > t.since[row] and ((lose_on.has("move") and sq.moving[srow] == 1) \
				or (lose_on.has("attack") and sq.fired_tick[srow] >= t.since[row])):
			lose(state, aid, -1)
			continue
		if t.ready_at[row] >= 0:
			var vac := Fixed.round_div(Stats.squad(state, srow, READY_PROWESS_STAT, r.ab_ready_prowess[ab]), r.tps)
			Pools.flow(state, srow, BattleSquads.PROWESS, -vac, &"readying")
			if state.tick >= t.ready_at[row]:
				_put(t, aid, &"ready_at", -1)
				_fire(state, aid)
				state.events.push(&"ability_ready", {"squad": t.squad[row], "ability": r.ab_ids[ab]}, state.tick)
				if t.on[row] == 0:
					continue
		elif t.effect[row] >= 0 and state.effects.row_of(t.effect[row]) < 0:
			_end(state, aid, "expired")
			continue
		if r.ab_toggle[ab] == 0:
			continue
		var off := false
		for p in 5:
			var up := Stats.squad(state, srow, UPKEEP_STATS[p], r.ab_upkeep[ab][p])
			if up <= 0:
				continue
			Pools.flow(state, srow, p, -Fixed.round_div(up, r.tps), StringName("ability_" + r.ab_ids[ab]))
			off = off or Pools.band(state, srow, p) <= r.ab_auto_off_band[ab]
		if off:
			_end(state, aid, "auto_off")
			state.events.push(&"ability_auto_off", {"squad": t.squad[row], "ability": r.ab_ids[ab]}, state.tick)


## What the Game API shows for a squad's abilities.
static func view(state: BattleState, squad_id: int) -> Array:
	var r := state.rules
	var t := state.abilities
	var out := []
	for aid in of_squad(state, squad_id):
		var row := t.row_of(aid)
		var ab := t.ability[row]
		out.append({
			"id": r.ab_ids[ab], "name": r.ab_names[ab], "toggle": r.ab_toggle[ab] == 1,
			"reaction": r.ab_reaction[ab] == 1, "on": t.on[row] == 1,
			"readying_ticks": maxi(t.ready_at[row] - state.tick, 0) if t.ready_at[row] >= 0 else 0,
			"cooldown_ticks": maxi(t.cooldown_until[row] - state.tick, 0), "charges": t.charges[row],
		})
	return out


static func _pay(state: BattleState, aid: int, source: StringName) -> void:
	var r := state.rules
	var t := state.abilities
	var row := t.row_of(aid)
	var ab := t.ability[row]
	var srow := state.squads.row_of(t.squad[row])
	for p in 5:
		var c := cost(state, srow, ab, p)
		if c > 0:
			Pools.flow(state, srow, p, -c, source)
	var cd := Stats.squad(state, srow, COOLDOWN_STAT, r.ab_cooldown_s[ab])
	_put(t, aid, &"cooldown_until", state.tick + Fixed.to_int_round(cd * r.tps))
	if t.charges[row] > 0:
		_put(t, aid, &"charges", t.charges[row] - 1)


static func _begin(state: BattleState, aid: int, target_id: int) -> void:
	var r := state.rules
	var t := state.abilities
	var row := t.row_of(aid)
	var ab := t.ability[row]
	_put(t, aid, &"on", 1)
	_put(t, aid, &"since", state.tick)
	_put(t, aid, &"target", target_id)
	var srow := state.squads.row_of(t.squad[row])
	var ready := Fixed.to_int_round(Stats.squad(state, srow, READY_STAT, r.ab_ready_s[ab]) * r.tps)
	if ready > 0:
		_put(t, aid, &"ready_at", state.tick + ready)
		state.events.push(&"ability_readying", {"squad": t.squad[row], "ability": r.ab_ids[ab], "ticks": ready}, state.tick)
		return
	_fire(state, aid)


## Applies the bundle: to the target squad (sourced from the user) or to
## the user itself.
static func _fire(state: BattleState, aid: int) -> void:
	var t := state.abilities
	var row := t.row_of(aid)
	var me := t.squad[row]
	var tgt := t.target[row]
	var b := state.rules.ab_bundle[t.ability[row]]
	var eid := Effects.apply(state, b, tgt, -1, me) if tgt >= 0 and tgt != me else Effects.apply(state, b, me)
	state.events.push(&"ability_used", {"squad": me, "ability": state.rules.ab_ids[t.ability[row]], "target": tgt}, state.tick)
	_hold(state, aid, eid)


## Keeps the bundle instance as the ability's held state, unless it is
## instant (it has acted and nothing is left to hold) or was refused.
static func _hold(state: BattleState, aid: int, eid: int) -> void:
	var t := state.abilities
	var held := eid >= 0 and state.effects.row_of(eid) >= 0
	if held and state.rules.fx.bundles[state.effects.bundle[state.effects.row_of(eid)]]["instant"]:
		Effects.remove(state, eid, false)
		held = false
	_put(t, aid, &"effect", eid if held else -1)
	_put(t, aid, &"on", 1 if held else 0)


static func _end(state: BattleState, aid: int, reason: String) -> void:
	var t := state.abilities
	var row := t.row_of(aid)
	if t.effect[row] >= 0:
		Effects.remove(state, t.effect[row], false)
	_put(t, aid, &"on", 0)
	_put(t, aid, &"effect", -1)
	_put(t, aid, &"ready_at", -1)
	state.events.push(&"ability_ended", {"squad": t.squad[row], "ability": state.rules.ab_ids[t.ability[row]], "reason": reason}, state.tick)


static func _put(t: BattleAbilities, aid: int, column: StringName, v: int) -> void:
	t.set_value(aid, column, v)
