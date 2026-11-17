extends GutTest
## The vertical-slice squads (sw-kys.1) fight: an assault squad, an engineer
## team (dig in) and a mortar team against two rifle squads, on an empty
## duel_crossroads battle, for a few turns without errors.

const ONE := Fixed.ONE


func _rules() -> BattleRules:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
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
