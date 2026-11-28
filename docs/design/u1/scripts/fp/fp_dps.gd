extends SceneTree
## sw-0jm5 sign-off: firing-position budgets (EVAL_CAP, SEARCH_CAP) only bite
## with many squads, which dps_orders.gd (one squad) never has. Runs the
## fp_cost fixture (n squads, both sides attack-moving at each other on
## Crossroads, the real BattleSim) for TICKS ticks and prints damage dealt
## and shots per side, units lost, and the share of armed unit-ticks under
## attack orders that held a firing position. Compare two builds of
## firing_positions.gd by running this on each.
## Run: harness/bin/hx godot run docs/design/u1/scripts/fp/fp_dps.gd -- [ticks]

const MC := preload("res://docs/design/u1/scripts/movement_cost/movement_cost.gd")


func _initialize() -> void:
	Fixed.warm()
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[0]) if args.size() > 0 else 600
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	for n in [12, 24, 40]:
		var mc = MC.new()
		mc.rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
		Stats.warm(mc.rules)
		mc.rules.routes.warm(mc.rules)
		mc.mix = PackedStringArray(["rifle_squad", "rifle_squad", "heavy_weapons_team", "marksman_team", "scout_team"])
		var s: BattleState = mc._make_state(n)
		var hp0 := _hp(s)
		var units0 := _alive(s)
		var shots := [0, 0, 0]
		var has := 0
		var armed := 0
		var sim := BattleSim.new()
		s.begin_turn()
		var t0 := Time.get_ticks_usec()
		for t in ticks:
			if t > 0 and t % mc.rules.ticks_per_turn == 0:
				s.begin_turn()
			sim.runner.step(s)
			var u := s.units
			for urow in u.count():
				if u.hp[urow] <= 0:
					continue
				if u.fired_tick[urow] == s.tick - 1:
					shots[_player(s, urow)] += 1
				if u.weapon[urow] >= 0 and u.fpos[urow] != FiringPositions.NONE:
					armed += 1
					if u.fpos[urow] == FiringPositions.HAS:
						has += 1
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / ticks
		var hp1 := _hp(s)
		var units1 := _alive(s)
		# Damage dealt by a side = HP its enemy lost.
		print("n=%d ticks=%d  dmg p1 %.0f p2 %.0f  shots p1 %d p2 %d  lost p1 %d p2 %d  HAS %.1f%%  sim %.2f ms/t  hash %s" % [
			n, ticks, (hp0[2] - hp1[2]) / float(Fixed.ONE), (hp0[1] - hp1[1]) / float(Fixed.ONE),
			shots[1], shots[2], units0[1] - units1[1], units0[2] - units1[2],
			100.0 * has / maxi(armed, 1), ms, s.state_hash().hex_encode().substr(0, 12)])
	quit(0)


func _player(s: BattleState, urow: int) -> int:
	return s.squads.player[s.squads.row_of(s.units.squad[urow])]


## Living HP (temp HP not counted) per player [0, p1, p2].
func _hp(s: BattleState) -> Array:
	var out := [0, 0, 0]
	for urow in s.units.count():
		if s.units.hp[urow] > 0 and s.squads.row_of(s.units.squad[urow]) >= 0:
			out[_player(s, urow)] += s.units.hp[urow]
	return out


func _alive(s: BattleState) -> Array:
	var out := [0, 0, 0]
	for urow in s.units.count():
		if s.units.hp[urow] > 0 and s.squads.row_of(s.units.squad[urow]) >= 0:
			out[_player(s, urow)] += 1
	return out
