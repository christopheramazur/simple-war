extends GutTest
## The vertical-slice squads (sw-kys.1) fight: an assault squad, an engineer
## team (dig in) and a mortar team against two rifle squads, on an empty
## duel_crossroads battle, for a few turns without errors.

const ONE := Fixed.ONE


func _rules() -> BattleRules:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	assert_true(r.is_valid(), "\n".join(r.errors))
	return r


func test_new_squads_fight() -> void:
	var r := _rules()
	var s := BattleSetup.create(1, r, 5)
	var mine := []
	for q: Array in [["assault_squad", 60, 40], ["engineer_team", 50, 55], ["mortar_team", 30, 50]]:
		mine.append(BattleSetup.spawn_squad(s, 1, r.squad_index(q[0]), int(q[1]) * ONE, int(q[2]) * ONE, 0))
	Centroids.update(s)
	var sim := BattleSim.new()
	var fired := {}
	var dbg := []
	for _t in 6:
		if s.is_over():
			break
		var orders := []
		for p in [1, 2]:
			orders = []
			for row in s.squads.count():
				if s.squads.player[row] == p and s.squads.is_active(row):
					orders.append({"squad": s.squads.id_at(row), "type": "attack_move", "x": 100 * ONE, "y": 50 * ONE})
			dbg.append(str(BattleOrders.apply(s, p, orders)))
		sim.execute_turn(s)
		var types := {}
		for e in s.turn_log:
			types[e.type] = types.get(e.type, 0) + 1
		dbg.append("t%d over=%s %s" % [_t, s.is_over(), types])
		for e in s.turn_log:
			if e.type == &"squad_fired":
				fired[int(e.data.get("squad", -1))] = true
	assert_true(fired.has(mine[0]) or fired.has(mine[2]), "the assault or mortar squad fired: %s" % str(dbg))


# --- range and vision (sw-kys.6) ---------------------------------------------

## A battle with only the given squads (the scenario's are withdrawn).
func _bare(r: BattleRules) -> BattleState:
	var s := BattleSetup.create(1, r, 5)
	var col: PackedByteArray = s.squads.take_column(&"withdrawn")
	for row in s.squads.count():
		col[row] = 1
	s.squads.put_column(&"withdrawn", col)
	return s


func _fired(s: BattleState, sid: int) -> int:
	var n := 0
	for e in s.turn_log:
		if e.type == &"squad_fired" and int(e.data["squad"]) == sid:
			n += 1
	return n


func test_a_spotted_mortar_on_an_attack_order_stands_and_fires() -> void:
	var r := _rules()
	var s := _bare(r)
	var m := BattleSetup.spawn_squad(s, 1, r.squad_index("mortar_team"), 70 * ONE, 50 * ONE, 0)
	BattleSetup.spawn_squad(s, 1, r.squad_index("scout_team"), 100 * ONE, 50 * ONE, 0)
	var e := BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), 150 * ONE, 50 * ONE, 32768)
	Centroids.update(s)
	var sim := BattleSim.new()
	var fired := 0
	for _t in 3:
		BattleOrders.apply(s, 1, [{"squad": m, "type": "attack", "target": e}])
		BattleOrders.apply(s, 2, [{"squad": e, "type": "hold"}])
		sim.execute_turn(s)
		fired += _fired(s, m)
	assert_gt(fired, 0, "fires at 80 m on the scout's vision (its own sight is 40 m)")
	var x := float(s.squads.cx[s.squads.row_of(m)]) / ONE
	assert_lt(x, 75.0, "stays put between shots instead of walking in (x=%.0f)" % x)


## [mortar post, target, spotter post]: terrain blocks every line between
## the first two; the spotter has a clear view of the target.
func _blocked_posts(r: BattleRules) -> Array:
	var found := []
	for y in range(5, r.height - 5, 3):
		for ax in range(10, r.width - 90, 5):
			var a := [ax * ONE, y * ONE]
			var b := [(ax + 75) * ONE, y * ONE]
			if not _blocked(r, a, b) or _solid(r, a) or _solid(r, b):
				continue
			for dx in [20, 25, 30]:
				var sp := [b[0] - dx * ONE, b[1]]
				if not _solid(r, sp) and _clear(r, sp, b):
					found = [a, b, sp]
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	return found


func test_indirect_fire_needs_no_line_of_sight() -> void:
	var r := _rules()
	var found := _blocked_posts(r)
	assert_false(found.is_empty(), "the map has a blocked line with a clear spotter post")
	if found.is_empty():
		return
	var out := {}
	for indirect in [1, 0]:
		var s := _bare(r)
		var mode := -1
		for i in r.md_indirect.size():
			if r.md_indirect[i] == 1:
				mode = i
		r.md_indirect[mode] = indirect
		var m := BattleSetup.spawn_squad(s, 1, r.squad_index("mortar_team"), found[0][0], found[0][1], 0)
		BattleSetup.spawn_squad(s, 1, r.squad_index("scout_team"), found[2][0], found[2][1], 0)
		var e := BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), found[1][0], found[1][1], 32768)
		Centroids.update(s)
		var sim := BattleSim.new()
		var fired := 0
		for _t in 2:
			BattleOrders.apply(s, 1, [{"squad": m, "type": "hold"}])
			BattleOrders.apply(s, 2, [{"squad": e, "type": "hold"}])
			sim.execute_turn(s)
			fired += _fired(s, m)
		out[indirect] = fired
		r.md_indirect[mode] = 1
	assert_gt(out[1], 0, "indirect: fires over the blocker on the spotter's vision")
	assert_eq(out[0], 0, "the same mortar firing direct has no line of fire")


func _solid(r: BattleRules, p: Array) -> bool:
	return r.f_impassable[r.feature_at(p[0], p[1])] == 1 or r.f_blocks_los[r.feature_at(p[0], p[1])] == 1


## Every pair of points within a few metres of a and b is blocked (squads
## spread their units around the centroid).
func _blocked(r: BattleRules, a: Array, b: Array) -> bool:
	for da in range(-5, 6, 1):
		for db in range(-5, 6, 1):
			if r.los(a[0] + da * ONE, a[1] + da * ONE, b[0], b[1] + db * ONE):
				return false
	return true


func _clear(r: BattleRules, a: Array, b: Array) -> bool:
	for d in range(-4, 5, 2):
		if not r.los(a[0], a[1] + d * ONE, b[0], b[1] + d * ONE):
			return false
	return true


func _own(obs: Dictionary, sid: int) -> Dictionary:
	for q: Dictionary in obs["squads"]:
		if q["id"] == sid:
			return q
	return {}


func test_observation_says_shot_blocked_and_spotted() -> void:
	var r := _rules()
	var s := _bare(r)
	var m := BattleSetup.spawn_squad(s, 1, r.squad_index("mortar_team"), 70 * ONE, 50 * ONE, 0)
	var sc := BattleSetup.spawn_squad(s, 1, r.squad_index("scout_team"), 100 * ONE, 50 * ONE, 0)
	var e := BattleSetup.spawn_squad(s, 2, r.squad_index("rifle_squad"), 150 * ONE, 50 * ONE, 32768)
	Centroids.update(s)
	VisionSystem.new().run(s)
	var obs := BattleSession.observe_state(s, 1)
	assert_eq(_own(obs, m)["fire"].get(e, ""), "shot", "the mortar reaches 80 m")
	assert_false((_own(obs, m)["sees"] as Array).has(e), "only the scout sees it")
	assert_true((_own(obs, sc)["sees"] as Array).has(e))
	assert_false(_own(obs, sc)["fire"].has(e), "50 m is beyond the scout's carbines")
	assert_false(_own(obs, e).has("fire"), "enemy squads carry no fire report")
	# A rifle squad behind cover from a spotted enemy has it in reach but no line.
	var posts := _blocked_posts(r)
	if posts.is_empty():
		return
	var b := _bare(r)
	var near: Array = posts[1].duplicate()
	near[0] -= 38 * ONE
	if not _blocked(r, near, posts[1]):
		return  # no blocker within rifle range on this map row
	var rf := BattleSetup.spawn_squad(b, 1, r.squad_index("rifle_squad"), near[0], near[1], 0)
	BattleSetup.spawn_squad(b, 1, r.squad_index("scout_team"), posts[2][0], posts[2][1], 0)
	var en := BattleSetup.spawn_squad(b, 2, r.squad_index("rifle_squad"), posts[1][0], posts[1][1], 32768)
	Centroids.update(b)
	VisionSystem.new().run(b)
	assert_eq(_own(BattleSession.observe_state(b, 1), rf)["fire"].get(en, ""), "blocked")
