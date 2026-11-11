class_name Effects
extends RefCounted
## The effect language at runtime (GDD 02 §2.13). Owns the effects table:
## applying and removing bundle instances, running instant effects, firing
## hooks and accumulators. EffectSystem drives time; HealthSystem and combat
## report events here.
##
## Chain depth (E2Q5): an action's depth is its instance's depth, plus 1 when
## a hook or accumulator caused it, plus 1 for apply_bundle. Hooks only fire
## on depth-0 actions, and apply_bundle stops beyond depth 2, so chains end.
## Instances are spawned and removed directly (not through the command
## buffer): only Effects and EffectSystem touch this table, and they never
## hold rows across a structural change.

const MAX_DEPTH: int = 2


## Applies bundle `b` to a squad (or one of its units). Returns the instance
## ID, or -1 if refused. Stacking per the bundle (E2Q6): refresh / stack /
## strongest update the existing instance; independent always adds one.
## "apply" effects run only when a new instance is created.
static func apply(state: BattleState, b: int, squad_id: int, unit_id: int = -1, source_id: int = -1, depth: int = 0) -> int:
	if b < 0 or depth > MAX_DEPTH or state.squads.row_of(squad_id) < 0:
		return -1
	var bd: Dictionary = state.rules.fx.bundles[b]
	var fx := state.effects
	var expires := _expiry(state, bd)
	if bd["policy"] != "independent":
		for row in fx.count():
			if fx.bundle[row] != b or fx.holder_squad[row] != squad_id or fx.holder_unit[row] != unit_id:
				continue
			if bd["per_source"] and fx.source[row] != source_id:
				continue
			var eid := fx.id_at(row)
			match bd["policy"]:
				"refresh":
					fx.set_value(eid, &"applied", state.tick)
					fx.set_value(eid, &"expires", expires)
				"stack":
					fx.set_value(eid, &"stacks", mini(fx.stacks[row] + 1, int(bd["max_stacks"])))
					fx.set_value(eid, &"applied", state.tick)
					fx.set_value(eid, &"expires", expires)
				"strongest":
					if fx.expires[row] >= 0 and (expires < 0 or expires > fx.expires[row]):
						fx.set_value(eid, &"expires", expires)
			return eid
	var acc: Dictionary = bd["acc"]
	var eid := fx.spawn({
		"bundle": b, "holder_squad": squad_id, "holder_unit": unit_id, "source": source_id,
		"stacks": 1, "applied": state.tick, "expires": expires, "depth": depth,
		"acc": acc.get("start", 0), "acc_last": state.tick, "hook_ready": 0,
	})
	for ev: String in bd["listens"]:
		state.fx_listening[ev] = true
	state.events.push(&"effect_applied", {"effect": eid, "bundle": bd["id"], "squad": squad_id, "unit": unit_id, "source": source_id}, state.tick)
	for e: Dictionary in bd["effects"]:
		if e["when"] == "apply":
			run_effect(state, eid, e)
	return eid


## Ends an instance: runs its "expire" effects if it ran its course.
static func remove(state: BattleState, eid: int, expired: bool) -> void:
	var row := state.effects.row_of(eid)
	if row < 0:
		return
	var bd: Dictionary = state.rules.fx.bundles[state.effects.bundle[row]]
	if expired:
		for e: Dictionary in bd["effects"]:
			if e["when"] == "expire":
				run_effect(state, eid, e)
	state.events.push(&"effect_ended", {"effect": eid, "bundle": bd["id"], "squad": state.effects.holder_squad[row], "expired": expired}, state.tick)
	state.effects.despawn(eid)


## Runs one instant effect of instance `eid` (damage, heal, pool_flow,
## apply_bundle). `other_*` is the other party of a hook event.
static func run_effect(state: BattleState, eid: int, e: Dictionary, other_squad: int = -1, other_unit: int = -1) -> void:
	var fx := state.effects
	var row := fx.row_of(eid)
	if row < 0:
		return
	var srow := state.squads.row_of(fx.holder_squad[row])
	if srow < 0 or not condition_holds(state, srow, e["cond"], fx.holder_unit[row]):
		return
	var depth := fx.depth[row]
	if e["when"] in DataSchema.HOOK_EVENTS or e["when"] == "accumulator":
		depth += 1
	var amount: int = e["amount"] * stacks_for(state, row, e)
	# Damage is credited to whoever applied the bundle, else its holder.
	var by: int = fx.source[row] if fx.source[row] >= 0 else fx.holder_squad[row]
	for tgt in targets(state, row, e["target"], other_squad, other_unit):
		var ts: int = tgt[0]
		var tu: int = tgt[1]
		match e["op"]:
			"damage", "heal":
				var signed := amount if e["op"] == "damage" else -amount
				var dtype: int = maxi(e["dtype"], 0)
				for uid in _units_of(state, ts, tu):
					Health.queue(state, -1, by, uid, ts, signed, dtype, depth)
			"pool_flow":
				var trow := state.squads.row_of(ts)
				if trow >= 0:
					Pools.flow(state, trow, e["pool"], amount, StringName("effect:" + str(e["source"])))
			"apply_bundle":
				apply(state, e["bundle"], ts, tu, fx.holder_squad[row], depth + 1)


## Reports an event to listening instances on (squad_id, unit_id): hooks with
## that `when`, and accumulators counting it (E2Q5, E2Q9). Only depth-0
## actions fire hooks. `amount` is fixed (1.0 per shot/hit/kill, HP lost for
## "damaged").
static func on_event(state: BattleState, event: String, squad_id: int, unit_id: int, other_squad: int, other_unit: int, amount: int, depth: int = 0) -> void:
	if depth > 0 or not state.fx_listening.has(event):
		return
	var fx := state.effects
	# IDs first: hooks may add or remove instances.
	var ids := PackedInt64Array()
	for row in fx.count():
		if fx.holder_squad[row] == squad_id and (fx.holder_unit[row] < 0 or fx.holder_unit[row] == unit_id):
			ids.append(fx.id_at(row))
	for eid in ids:
		var row := fx.row_of(eid)
		if row < 0:
			continue
		var bd: Dictionary = state.rules.fx.bundles[fx.bundle[row]]
		if not (bd["listens"] as PackedStringArray).has(event):
			continue
		var acc: Dictionary = bd["acc"]
		if not acc.is_empty():
			if acc["event"] == event:
				var step: int = acc["step"]
				count(state, eid, Fixed.mul(amount, step) if event == "damaged" else step)
			elif acc["reset_on"] == event:
				fx.set_value(eid, &"acc", acc["start"])
				fx.set_value(eid, &"acc_last", state.tick)
		row = fx.row_of(eid)
		if row < 0 or fx.hook_ready[row] > state.tick:
			continue
		var fired := false
		var cooldown := 0
		for e: Dictionary in bd["effects"]:
			if e["when"] == event:
				run_effect(state, eid, e, other_squad, other_unit)
				fired = true
				cooldown = maxi(cooldown, e["cooldown"])
		if fired and cooldown > 0 and fx.row_of(eid) >= 0:
			fx.set_value(eid, &"hook_ready", state.tick + cooldown)


## Adds `step` to an instance's accumulator; at the threshold its
## "accumulator" effects fire and the counter returns to start.
static func count(state: BattleState, eid: int, step: int) -> void:
	var fx := state.effects
	var row := fx.row_of(eid)
	if row < 0:
		return
	var bd: Dictionary = state.rules.fx.bundles[fx.bundle[row]]
	var acc: Dictionary = bd["acc"]
	var v := fx.acc[row] + step
	fx.set_value(eid, &"acc_last", state.tick)
	if v < acc["threshold"]:
		fx.set_value(eid, &"acc", v)
		return
	fx.set_value(eid, &"acc", acc["start"])
	state.events.push(&"accumulator_fired", {"effect": eid, "bundle": bd["id"], "squad": fx.holder_squad[row]}, state.tick)
	for e: Dictionary in bd["effects"]:
		if e["when"] == "accumulator":
			run_effect(state, eid, e)


## [squad_id, unit_id] pairs an effect acts on, in canonical order (distance
## from the holder, then ID; E2Q4). Empty selector = the holder itself.
static func targets(state: BattleState, row: int, sel: Dictionary, other_squad: int = -1, other_unit: int = -1) -> Array:
	var fx := state.effects
	var me: int = fx.holder_squad[row]
	var mine_unit: int = fx.holder_unit[row]
	var kind: String = sel.get("select", "self")
	match kind:
		"self":
			return [[me, mine_unit]]
		"source":
			return [[fx.source[row], -1]] if state.squads.row_of(fx.source[row]) >= 0 else []
		"other":
			return [[other_squad, other_unit]] if state.squads.row_of(other_squad) >= 0 else []
	var out := []
	for sid in select_squads(state, state.squads.row_of(me), sel):
		out.append([sid, -1])
	return out


## Squad IDs matched by an allies / enemies / squads selector around squad
## row `srow`, nearest first (then by ID), never the squad itself.
static func select_squads(state: BattleState, srow: int, sel: Dictionary) -> PackedInt64Array:
	var sq := state.squads
	var found := []
	if srow < 0:
		return PackedInt64Array()
	var kind: String = sel.get("select", "squads")
	var within: int = sel.get("within", -1)
	var tags: PackedStringArray = sel.get("tags", PackedStringArray())
	for t in sq.count():
		if t == srow or not sq.is_active(t) or sq.alive[t] <= 0:
			continue
		var ally := sq.player[t] == sq.player[srow]
		if (kind == "allies" and not ally) or (kind == "enemies" and ally):
			continue
		var d := Fixed.distance(sq.cx[srow], sq.cy[srow], sq.cx[t], sq.cy[t])
		if within >= 0 and d > within:
			continue
		if not tags.is_empty():
			var kw: PackedStringArray = state.rules.sq_keywords[sq.tmpl[t]]
			var ok := true
			for tag in tags:
				if not kw.has(tag):
					ok = false
					break
			if not ok:
				continue
		found.append([d, sq.id_at(t)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var cap: int = sel.get("max", 0)
	var out := PackedInt64Array()
	for f: Array in found:
		if cap > 0 and out.size() >= cap:
			break
		out.append(f[1])
	return out


## Stack multiplier for effect `e` of the instance at `row`: its stacks,
## times the effect's stack source if it has one (E4Q2).
static func stacks_for(state: BattleState, row: int, e: Dictionary) -> int:
	var fx := state.effects
	var n := fx.stacks[row]
	var per: Dictionary = e["per"]
	if per.is_empty():
		return n
	var srow := state.squads.row_of(fx.holder_squad[row])
	match per["source"]:
		"selector":
			return n * select_squads(state, srow, per["selector"]).size()
		"pool":
			return n * (Pools.value(state, srow, per["pool"]) / int(per["each"])) if srow >= 0 else 0
		"accumulator":
			return n * (fx.acc[row] / int(per["each"]))
	return n


## Data-defined conditions, all of which must hold (GDD 02 §2.13).
static func condition_holds(state: BattleState, srow: int, c: Dictionary, unit_id: int = -1) -> bool:
	if c.is_empty():
		return true
	var sq := state.squads
	if c.has("pool"):
		var band := Pools.band(state, srow, DataSchema.SIMPL.find(c["pool"]))
		if c.has("band_at_least") and band < DataSchema.BANDS.find(c["band_at_least"]):
			return false
		if c.has("band_at_most") and band > DataSchema.BANDS.find(c["band_at_most"]):
			return false
	if c.has("moving") and (sq.moving[srow] == 1) != bool(c["moving"]):
		return false
	if c.has("firing"):
		var ft := sq.fired_tick[srow]
		var firing := ft >= 0 and state.tick - ft <= state.rules.tps
		if firing != bool(c["firing"]):
			return false
	if c.has("hp_below_pct"):
		var pct := int(c["hp_below_pct"])
		var urow := state.units.row_of(unit_id) if unit_id >= 0 else -1
		if urow >= 0:
			if state.units.hp[urow] * 100 >= state.units.hp_max[urow] * pct:
				return false
		elif (sq.hp_max[srow] - sq.hp_lost[srow]) * 100 >= sq.hp_max[srow] * pct:
			return false
	if c.has("has_keyword") and not state.rules.sq_keywords[sq.tmpl[srow]].has(c["has_keyword"]):
		return false
	return true


static func _expiry(state: BattleState, bd: Dictionary) -> int:
	if bd["seconds_ticks"] > 0:
		return state.tick + int(bd["seconds_ticks"])
	if bd["turns"] > 0:
		return state.tick + int(bd["turns"]) * state.rules.ticks_per_turn
	return -1


## Unit IDs an instant effect hits: the one unit, or every living unit of
## the squad.
static func _units_of(state: BattleState, squad_id: int, unit_id: int) -> PackedInt64Array:
	if unit_id >= 0:
		return PackedInt64Array([unit_id]) if state.units.row_of(unit_id) >= 0 else PackedInt64Array()
	var out := PackedInt64Array()
	var srow := state.squads.row_of(squad_id)
	if srow < 0:
		return out
	for urow in Centroids.units_of(state, srow):
		if state.units.hp[urow] > 0:
			out.append(state.units.id_at(urow))
	return out
