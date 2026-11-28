class_name BattleSetup
extends RefCounted
## Builds a fresh BattleState from compiled rules: deploys each side's squads
## evenly down its deployment rectangle, in formation. GDD 02 §2.4.
## Nothing deploys on a cell it can't enter (§2.14): a squad's anchor, and
## each unit, moves to the nearest cell the squad's slowest member can.


## `jitter` (whole cells, default 0 = the even GDD 02 §2.4 deployment) offsets
## each squad's anchor within its deploy rectangle, seeded from the state's
## seed, so harness seeds vary a battle. Games leave it 0.
static func create(context_id: int, rules: BattleRules, seed_value: int, jitter: int = 0) -> BattleState:
	var state := BattleState.new(context_id, rules, seed_value)
	for side in rules.sides:
		deploy_side(state, side, jitter, seed_value)
	Centroids.update(state)
	return state


## Deploys a side's squads; returns their IDs in order. A side may carry
## "alive" (units per squad, e.g. overworld losses; default full strength),
## "gear" (per squad, as spawn_squad takes it) and "placed" (the scenario's
## entries, sw-tdz). A placed squad stands at its point (the nearest enterable
## cell of the area); the others deal evenly over the rest of the area.
## Locked placed squads go in state.pinned.
static func deploy_side(state: BattleState, side: Dictionary, jitter: int = 0, jitter_seed: int = 0) -> PackedInt64Array:
	var d: PackedInt64Array = side["deploy"]
	var list: PackedInt64Array = side["squads"]
	var alive: PackedInt64Array = side.get("alive", PackedInt64Array())
	var gear: Array = side.get("gear", [])
	var n := list.size()
	var placed := {}
	for p: Dictionary in side.get("placed", []):
		placed[p["squad"]] = p
	# The first squad of a placed template in the list is the placed one.
	var at := {}
	var rest := 0
	for i in n:
		var st := list[i]
		if placed.has(st):
			at[i] = placed[st]
			placed.erase(st)
		else:
			rest += 1
	var ids := PackedInt64Array()
	var rng: SimRng = null
	if jitter > 0:
		rng = SimRng.new(jitter_seed * 1000003 + int(side["player"]) * 7919 + 12345)
	var k := 0
	for i in n:
		var ax := d[0] + d[2] / 2
		var ay := 0
		var facing: int = side["facing"]
		var fixed_at: Dictionary = at.get(i, {})
		if not fixed_at.is_empty():
			var pt := BattleDeploy.open_point_in(state.rules, list[i], fixed_at["x"], fixed_at["y"], d)
			ax = pt[0] if not pt.is_empty() else fixed_at["x"]
			ay = pt[1] if not pt.is_empty() else fixed_at["y"]
			facing = fixed_at["facing"]
		else:
			ay = d[1] + Fixed.round_div(d[3] * (2 * k + 1), 2 * rest)
			k += 1
			if rng != null:
				var jx := mini(jitter * Fixed.ONE, d[2] / 2)
				var jy := mini(jitter * Fixed.ONE, d[3] / 2)
				ax = clampi(ax + rng.next_range(-jx, jx), d[0], d[0] + d[2])
				ay = clampi(ay + rng.next_range(-jy, jy), d[1], d[1] + d[3])
		var sid := spawn_squad(state, side["player"], list[i], ax, ay, facing, alive[i] if i < alive.size() else -1,
			gear[i] if i < gear.size() else [])
		if not fixed_at.is_empty() and fixed_at["locked"]:
			state.pinned[sid] = true
		ids.append(sid)
	return ids


## Spawns one squad and its units; returns the squad ID. `units` < 0 = all
## members; otherwise only the first `units` members (losses come off the
## end of the member list). `gear` (WarChest.gear), per member: {"weapon",
## "defense" (template IDs, "" = the unit's own), "bundles"}.
static func spawn_squad(state: BattleState, player: int, st: int, ax: int, ay: int, facing: int, units: int = -1, gear: Array = []) -> int:
	var r := state.rules
	var anchor := open_point(r, st, ax, ay)
	ax = anchor[0]
	ay = anchor[1]
	var members := r.sq_members[st]
	if units >= 0 and units < members.size():
		members = members.slice(0, units)
	var hp_total := 0
	for ui in members:
		hp_total += r.ut_hp[ui]
	var values := {
		"player": player, "tmpl": st, "order": BattleSquads.Order.HOLD,
		"tx": ax, "ty": ay, "facing": facing, "ax": ax, "ay": ay, "cx": ax, "cy": ay,
		"alive": members.size(), "form_size": members.size(), "hp_max": hp_total,
		"seen_by": BattleSquads.bit(player),
	}
	for p in 5:
		values[BattleSquads.POOLS[p]] = r.sq_pool_start[st * 5 + p]
		values[BattleSquads.CAPS[p]] = r.sq_pool_cap[st * 5 + p]
	var weapons := PackedInt64Array()
	var defenses := PackedInt64Array()
	var reach := 0
	for slot in members.size():
		var g: Dictionary = gear[slot] if slot < gear.size() else {}
		var w := r.ut_weapon[members[slot]]
		if String(g.get("weapon", "")) != "":
			w = r.weapon_index[g["weapon"]]
		var df := r.ut_defense[members[slot]]
		if String(g.get("defense", "")) != "":
			df = r.defense_index[g["defense"]]
		weapons.append(w)
		defenses.append(df)
		if w >= 0:
			reach = maxi(reach, r.wp_range[w])
	values["reach"] = reach
	var sid := state.squads.spawn(values)
	for slot in members.size():
		var ui := members[slot]
		var off := Formation.offset(r.sq_shape[st], slot, members.size(), r.sq_spacing[st], facing)
		var w := weapons[slot]
		var at := open_point(r, st, Fixed.clamp_fixed(ax + off[0], 0, Fixed.from_int(r.width) - 1),
			Fixed.clamp_fixed(ay + off[1], 0, Fixed.from_int(r.height) - 1))
		var uid := state.units.spawn({
			"squad": sid, "tmpl": ui, "weapon": w, "defense": defenses[slot], "slot": slot,
			"x": at[0], "y": at[1],
			"facing": facing, "hp": r.ut_hp[ui], "hp_max": r.ut_hp[ui],
			"ammo": r.wp_magazine[w] if w >= 0 else 0,
		})
		for b in r.ut_bundles[ui]:
			Effects.apply(state, b, sid, uid)
		if slot < gear.size():
			for b: String in (gear[slot] as Dictionary).get("bundles", PackedStringArray()):
				Effects.apply(state, r.fx.index_of(b), sid, uid)
	for b in r.sq_bundles[st]:
		Effects.apply(state, b, sid)
	Abilities.spawn_for(state, sid, st)
	return sid


## The point [x, y] (fixed) itself if squad template `st` can stand on its
## cell, else the centre of the nearest cell it can (ties by cell index).
## Unchanged if the battlefield has no terrain or no cell is passable.
static func open_point(r: BattleRules, st: int, x: int, y: int) -> PackedInt64Array:
	var here := PackedInt64Array([x, y])
	if r.terrain.size() < r.width * r.height or st < 0 or st >= r.sq_route_class.size():
		return here
	var costs: PackedInt32Array = r.rt_cost[r.sq_route_class[st]]
	var cx := clampi(Fixed.to_int_floor(x), 0, r.width - 1)
	var cy := clampi(Fixed.to_int_floor(y), 0, r.height - 1)
	if costs[r.terrain[cy * r.width + cx]] > 0:
		return here
	var best := -1
	var best_d := 0
	var limit := maxi(r.width, r.height)
	var ring := 1
	while ring <= limit:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var qx := cx + dx
				var qy := cy + dy
				if qx < 0 or qy < 0 or qx >= r.width or qy >= r.height or costs[r.terrain[qy * r.width + qx]] <= 0:
					continue
				var d := dx * dx + dy * dy
				var cell := qy * r.width + qx
				if best < 0 or d < best_d or (d == best_d and cell < best):
					best = cell
					best_d = d
		# A cell on this square ring can be nearer than one on the ring that
		# first found something only while ring * ring < best_d.
		if best >= 0 and (ring + 1) * (ring + 1) > best_d:
			break
		ring += 1
	if best < 0:
		return here
	@warning_ignore("integer_division")
	return PackedInt64Array([Fixed.from_int(best % r.width) + Fixed.ONE / 2, Fixed.from_int(best / r.width) + Fixed.ONE / 2])
