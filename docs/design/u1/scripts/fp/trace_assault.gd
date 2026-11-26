extends SceneTree
## sw-txnj.16 scratch: assault squad ATTACK a disarmed rifle squad at 44 m
## (the dps_orders "ATTACK target 44m" case). Prints the anchor, fp_stop/fp_lack
## and every armed unit's weapon, position, firing position and hold reason
## every 5 ticks.
const ONE := Fixed.ONE
const LANE_Y := 80
const AX := 20
var rules: BattleRules

const HOLD_LETTERS := {
	BattleActivity.Hold.NONE: ".", BattleActivity.Hold.UNARMED: "u", BattleActivity.Hold.FALLING_BACK: "f",
	BattleActivity.Hold.RELOADING: "R", BattleActivity.Hold.COOLDOWN: "c", BattleActivity.Hold.NO_MOVING_FIRE: "m",
	BattleActivity.Hold.MIN_RANGE: "n", BattleActivity.Hold.OUT_OF_RANGE: "o", BattleActivity.Hold.NO_LOS: "l",
	BattleActivity.Hold.NOT_SPOTTED: "s", BattleActivity.Hold.NO_TARGET: "t", BattleActivity.Hold.MOVING_TO_FIRE: "w",
}

func _place(s: BattleState, p: int, n: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, p, rules.squad_index(n), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid

func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleState.new(1, rules, 1)
	s.trace_shots = true
	var me := _place(s, 1, "assault_squad", AX, LANE_Y, 0)
	var foe := _place(s, 2, "rifle_squad", AX + 44, LANE_Y, Fixed.ANGLE_HALF)
	for urow in Centroids.units_of(s, s.squads.row_of(foe)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
		s.units.set_value(s.units.id_at(urow), &"hp", 1000 * ONE)
		s.units.set_value(s.units.id_at(urow), &"hp_max", 1000 * ONE)
	var frow := s.squads.row_of(foe)
	BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK, s.squads.cx[frow], s.squads.cy[frow], foe, 0)
	var sim := BattleSim.new()
	var row := s.squads.row_of(me)
	var t_max := 200
	for t in t_max:
		sim.runner.step(s)
		if t % 5 != 0 and t > 40:
			continue
		var frw := s.squads.row_of(foe)
		var fcx := s.squads.cx[frw] / float(ONE)
		var fcy := s.squads.cy[frw] / float(ONE)
		print("t%d anchor (%.1f,%.1f) dist %.1f stop %d lack %d route %d order %d eng %d" % [
			t, s.squads.ax[row] / float(ONE), s.squads.ay[row] / float(ONE),
			Fixed.distance(s.squads.ax[row], s.squads.ay[row], s.squads.cx[frw], s.squads.cy[frw]) / float(ONE),
			s.squads.fp_stop[row], s.squads.fp_lack[row], s.squads.route[row], s.squads.order[row], s.squads.engaged[row]])
		for urow in Centroids.units_of(s, row):
			if s.units.hp[urow] <= 0 or s.units.weapon[urow] < 0:
				continue
			var w := s.units.weapon[urow]
			var h: String = HOLD_LETTERS[BattleActivity.hold(s, urow)]
			var fd := Fixed.distance(s.units.x[urow], s.units.y[urow], s.units.fx[urow], s.units.fy[urow]) / float(ONE)
			var ps := FiringPositions.point_shot(s, urow, frw, s.units.fx[urow], s.units.fy[urow])
			var us := FiringPositions.point_shot(s, urow, frw, s.units.x[urow], s.units.y[urow])
			print("      gap to fx %.4f point_shot@fx %s point_shot@unit %s" % [fd, ps, us])
			print("   u%d w%d rng %.0f pos (%.1f,%.1f) d_foe %.1f fpos %d fx (%.1f,%.1f) mv %d hold %s fired %d" % [
				urow, w, s.rules.wp_range[w] / float(ONE),
				s.units.x[urow] / float(ONE), s.units.y[urow] / float(ONE),
				Fixed.distance(s.units.x[urow], s.units.y[urow], s.squads.cx[frw], s.squads.cy[frw]) / float(ONE),
				s.units.fpos[urow], s.units.fx[urow] / float(ONE), s.units.fy[urow] / float(ONE),
				s.units.moving[urow], h, s.units.fired_tick[urow]])
	quit(0)
