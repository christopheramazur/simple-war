extends SceneTree
## Separation cost per tick as shipped (sw-txnj.12), measured on the sw-txnj.3
## fixture: n squads on Crossroads (core data), half per side in two blocks
## 60 m apart, all on attack-move at their mirror, 300 ticks.
## Each tick, before the real step, the shipped Separation pass is timed on
## the tick's start positions and its writes are undone; the step itself
## then runs MovementSystem (with its own separation pass) as the game does.
##
## Run: harness/bin/hx godot run docs/design/u1/scripts/separation_cost/separation_cost.gd --timeout 600

const ONE := Fixed.ONE
const TICKS := 300

var rules: BattleRules
var mix := PackedStringArray(["rifle_squad", "rifle_squad", "heavy_weapons_team", "marksman_team", "scout_team"])


func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	Stats.warm(rules)
	rules.routes.warm(rules)
	for n in [4, 20, 40]:
		_measure(n)
	quit(0)


func _make_state(n: int) -> BattleState:
	var s := BattleState.new(1, rules, 1)
	var per_side := n / 2
	var cols := 2 if per_side <= 4 else 4
	for i in per_side:
		var c := i % cols
		var rr := i / cols
		var rows := ceili(float(per_side) / cols)
		var y := 50 - (rows - 1) * 7 + rr * 14
		y = clampi(y, 8, rules.height - 8)
		var sq_name := mix[i % mix.size()]
		var a := BattleSetup.spawn_squad(s, 1, rules.squad_index(sq_name), (70 - c * 7) * ONE, y * ONE, 0)
		var b := BattleSetup.spawn_squad(s, 2, rules.squad_index(sq_name), (130 + c * 7) * ONE, y * ONE, Fixed.ANGLE_HALF)
		Centroids.update(s)
		var ra := s.squads.row_of(a)
		var rb := s.squads.row_of(b)
		BattleOrders.set_order(s, ra, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[rb], s.squads.cy[rb], -1, 0)
		BattleOrders.set_order(s, rb, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[ra], s.squads.cy[ra], -1, 0)
	Centroids.update(s)
	return s


func _measure(n: int) -> void:
	var s := _make_state(n)
	var sim := BattleSim.new()
	var sep := Separation.new()
	var units0 := s.units.count()
	var us := 0
	var worst := 0
	var pushes := 0
	s.begin_turn()
	for t in TICKS:
		if t > 0 and t % rules.ticks_per_turn == 0:
			s.begin_turn()
		var u := s.units
		var x := u.x.duplicate()
		var y := u.y.duplicate()
		var cr := u.crowded.duplicate()
		var t0 := Time.get_ticks_usec()
		sep.run(s)
		var dt := Time.get_ticks_usec() - t0
		us += dt
		worst = maxi(worst, dt)
		pushes += sep.pushes
		u.put_column(&"x", x)
		u.put_column(&"y", y)
		u.put_column(&"crowded", cr)
		sim.runner.step(s)
	print("squads %d units %d: separation %.3f ms/tick (worst %.2f), pushes/tick %.1f" % [
		n, units0, us / 1000.0 / TICKS, worst / 1000.0, pushes / float(TICKS)])
