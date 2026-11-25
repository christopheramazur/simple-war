extends SceneTree
## sw-txnj.5 scratch: trace the leash and min-range cases.
const ONE := Fixed.ONE
var rules: BattleRules

func _place(s: BattleState, p: int, n: String, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, p, rules.squad_index(n), x * ONE, y * ONE, 0 if p == 1 else Fixed.ANGLE_HALF)
	Centroids.update(s)
	return sid

func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	for case in ["leash", "mortar"]:
		var s := BattleState.new(1, rules, 1)
		var me: int
		var foe: int
		if case == "leash":
			me = _place(s, 1, "assault_squad", 20, 80)
			foe = _place(s, 2, "rifle_squad", 85, 80)
			var sp := _place(s, 1, "rifle_squad", 75, 92)
			BattleOrders.set_order(s, s.squads.row_of(sp), BattleSquads.Order.HOLD, 75 * ONE, 92 * ONE, -1, 0)
			BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK_MOVE, 45 * ONE, 80 * ONE, -1, 0)
		else:
			me = _place(s, 1, "mortar_team", 20, 80)
			foe = _place(s, 2, "rifle_squad", 34, 80)
			BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK, 20 * ONE, 80 * ONE, foe, 0)
		for urow in Centroids.units_of(s, s.squads.row_of(foe)):
			s.units.set_value(s.units.id_at(urow), &"weapon", -1)
			s.units.set_value(s.units.id_at(urow), &"hp", 1000 * ONE)
		var sim := BattleSim.new()
		var row := s.squads.row_of(me)
		for t in 200:
			sim.runner.step(s)
			if t % 10 == 0 or t < 6:
				var f := ""
				for urow in Centroids.units_of(s, row):
					f += str(s.units.fpos[urow])
				print("%s t%d ax %.1f ay %.1f eng %d seen %d stop %d route %d w %.1f fpos %s order %d tgt %d" % [case, t, s.squads.ax[row] / float(ONE), s.squads.ay[row] / float(ONE), s.squads.engaged[row], s.squads.seen_by[s.squads.row_of(foe)], s.squads.fp_stop[row], s.squads.route[row], s.squads.wx[row] / float(ONE), f, s.squads.order[row], s.squads.target[row]])
	quit(0)
