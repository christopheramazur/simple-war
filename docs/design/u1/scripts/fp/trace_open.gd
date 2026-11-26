extends SceneTree
## sw-txnj.5 scratch: trace a rifle squad attack-moving into range.

const ONE := Fixed.ONE

func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	var rules := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleState.new(1, rules, 1)
	var me := BattleSetup.spawn_squad(s, 1, rules.squad_index("rifle_squad"), 25 * ONE, 80 * ONE, 0)
	var foe := BattleSetup.spawn_squad(s, 2, rules.squad_index("rifle_squad"), 85 * ONE, 80 * ONE, Fixed.ANGLE_QUARTER)
	Centroids.update(s)
	for urow in Centroids.units_of(s, s.squads.row_of(foe)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
	var row := s.squads.row_of(me)
	BattleOrders.set_order(s, row, BattleSquads.Order.ATTACK_MOVE, 85 * ONE, 80 * ONE, -1, 0)
	var sim := BattleSim.new()
	for t in 90:
		sim.runner.step(s)
		var line := "t%d eng%d seen%d stop%d |" % [s.tick - 1, s.squads.engaged[row], s.squads.seen_by[s.squads.row_of(foe)], s.squads.fp_stop[row]]
		for urow in Centroids.units_of(s, row):
			var best := 1 << 62
			for t2 in Centroids.units_of(s, s.squads.row_of(foe)):
				best = mini(best, Fixed.distance(s.units.x[urow], s.units.y[urow], s.units.x[t2], s.units.y[t2]))
			line += " %.1f%s%d" % [float(best) / ONE, "*" if s.units.fired_tick[urow] == s.tick - 1 else "", s.units.fpos[urow]]
		if t >= 30:
			print(line)
	quit(0)
