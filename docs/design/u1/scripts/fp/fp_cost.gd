extends SceneTree
## sw-txnj.5 scratch: cost of FiringPositions.update at 40 squads (the
## sw-txnj.3 fixture), split from the rest of MovementSystem.
## Run: harness/bin/hx godot run docs/design/u1/scripts/fp/fp_cost.gd -- [n]

const MC := preload("res://docs/design/u1/scripts/movement_cost/movement_cost.gd")
const ONE := Fixed.ONE

class Timed extends SimSystem:
	var us := 0
	var inner: SimSystem
	func _init(s: SimSystem) -> void:
		inner = s
	func system_name() -> StringName:
		return inner.system_name()
	func run(ctx: SimContext) -> void:
		var t0 := Time.get_ticks_usec()
		inner.run(ctx)
		us += Time.get_ticks_usec() - t0

class MS extends MovementSystem:
	var t := [0, 0, 0, 0]
	var plans := {}
	var lack := {}
	func run(ctx: SimContext) -> void:
		var state := ctx as BattleState
		var a := Time.get_ticks_usec()
		FiringPositions.update(state)
		var b := Time.get_ticks_usec()
		var sq := state.squads
		var wx0 := sq.wx.duplicate()
		var wy0 := sq.wy.duplicate()
		var rx0 := sq.rx.duplicate()
		var ry0 := sq.ry.duplicate()
		_plan_routes(state)
		for row in sq.count():
			if wx0[row] != sq.wx[row] or wy0[row] != sq.wy[row] or rx0[row] != sq.rx[row] or ry0[row] != sq.ry[row]:
				var k := "o%d e%d stop%d route%d drift%.1f" % [sq.order[row], 1 if sq.engaged[row] >= 0 else 0, sq.fp_stop[row], sq.route[row], Fixed.distance(rx0[row], ry0[row], sq.rx[row], sq.ry[row]) / float(Fixed.ONE)]
				k = k.substr(0, k.find("drift")) + ("big" if Fixed.distance(rx0[row], ry0[row], sq.rx[row], sq.ry[row]) > Fixed.ONE else "small")
				plans[k] = int(plans.get(k, 0)) + 1
		var c := Time.get_ticks_usec()
		_move_anchors(state)
		var d := Time.get_ticks_usec()
		_move_units(state)
		var e := Time.get_ticks_usec()
		t[0] += b - a
		t[1] += c - b
		t[2] += d - c
		t[3] += e - d
		var u := state.units
		for row in sq.count():
			if sq.fp_stop[row] == 1 or FiringPositions.engaging(state, row) < 0:
				continue
			for urow in Centroids.units_of(state, row):
				if u.hp[urow] > 0 and u.weapon[urow] >= 0 and u.fpos[urow] != FiringPositions.HAS and u.fpos[urow] != FiringPositions.UNACHIEVABLE:
					var trow := FiringPositions.engaging(state, row)
					var k := "%s fpos%d far%s" % [state.rules.unit_index.find_key(u.tmpl[urow]) if "unit_index" in state.rules else str(u.tmpl[urow]), u.fpos[urow], FiringPositions._too_far(state, urow, row, trow)]
					lack[k] = int(lack.get(k, 0)) + 1


class TR extends BattleRoute:
	var calls := 0
	var us := 0
	var far := 0
	func next_waypoint(r: BattleRules, route_class: int, from_x: int, from_y: int, to_x: int, to_y: int, frame: int = 0) -> PackedInt64Array:
		var t0 := Time.get_ticks_usec()
		var out := super(r, route_class, from_x, from_y, to_x, to_y, frame)
		us += Time.get_ticks_usec() - t0
		calls += 1
		if Fixed.distance(from_x, from_y, to_x, to_y) > 16 * Fixed.ONE:
			far += 1
		return out


class FP extends SimSystem:
	var us := 0
	func system_name() -> StringName:
		return &"fp"
	func run(ctx: SimContext) -> void:
		var t0 := Time.get_ticks_usec()
		FiringPositions.update(ctx as BattleState)
		us += Time.get_ticks_usec() - t0


func _initialize() -> void:
	Fixed.warm()
	var mc = MC.new()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	mc.rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	Stats.warm(mc.rules)
	mc.rules.routes.warm(mc.rules)
	mc.mix = PackedStringArray(["rifle_squad", "rifle_squad", "heavy_weapons_team", "marksman_team", "scout_team"])
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 40
	var tr := TR.new()
	mc.rules.routes = tr
	tr.warm(mc.rules)
	var s: BattleState = mc._make_state(n)
	var fp := FP.new()
	var ms := MS.new()
	var mv := Timed.new(ms)
	var cb := Timed.new(CombatSystem.new())
	var sim := BattleSim.new()
	var runner := SystemRunner.new()
	runner.add_phase(&"effects", [AbilitySystem.new(), EffectSystem.new()] as Array[SimSystem])
	runner.add_phase(&"move", [Centroids.new(), mv] as Array[SimSystem])
	runner.add_phase(&"sense", [Centroids.new(), VisionSystem.new(), Reactions.new()] as Array[SimSystem])
	runner.add_phase(&"fight", [cb, HealthSystem.new()] as Array[SimSystem])
	runner.add_phase(&"pressure", [Centroids.new(), PoolsSystem.new()] as Array[SimSystem])
	sim.runner = runner
	s.begin_turn()
	for t in 300:
		if t > 0 and t % mc.rules.ticks_per_turn == 0:
			s.begin_turn()
		sim.runner.step(s)
	print("n=%d fp(extra call) %.3f ms/t  movement(incl. its own fp call) %.3f  combat %.3f" % [n, fp.us / 300000.0, mv.us / 300000.0, cb.us / 300000.0])
	print("next_waypoint calls %d (far %d) %.3f ms/t" % [tr.calls, tr.far, tr.us / 300000.0])
	print(ms.plans)
	print(ms.lack)
	print("  movement split ms/t: fp %.3f routes %.3f anchors %.3f units %.3f" % [ms.t[0] / 300000.0, ms.t[1] / 300000.0, ms.t[2] / 300000.0, ms.t[3] / 300000.0])
	quit(0)
