extends SceneTree
## U1 A6 movement spike (sw-txnj.3), throwaway. Scratch only: nothing here
## ships, the prototypes run as extra systems inside this script's runner.
##
## Measures per-tick cost of MovementSystem and CombatSystem and one
## IntentForecast at 4, 20 and 40 squads on Crossroads (duel_crossroads, real
## core data), then adds two prototypes:
##   - the U1Q29 per-unit firing-position search (rings around the slot toward
##     the target, inside coherency, enterable, first with a shot), every tick
##     and on a staggered N-tick re-evaluation;
##   - the draft 01 §3.3 separation pass (2 m spatial hash) and, for
##     comparison, a squad-circle broadphase doing the same pushes.
## Determinism: each variant is run twice from the same start and the state
## hash (plus the search results folded in) must match.
##
## Run: harness/bin/hx godot run docs/design/u1/scripts/movement_cost/movement_cost.gd --tail 200 --timeout 1200

const ONE := Fixed.ONE
const TICKS := 300  # three turns at 10 tps
const FiringSearch := preload("firing_search.gd")
const Separation := preload("separation.gd")

var rules: BattleRules
var mix := PackedStringArray()


func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	Stats.warm(rules)
	rules.routes.warm(rules)
	# duel_crossroads' per-side mix (data/packages/core/defs/scenarios.json).
	mix = PackedStringArray(["rifle_squad", "rifle_squad", "heavy_weapons_team", "marksman_team", "scout_team"])
	print("map %dx%d m, tps %d, ticks/turn %d, squad mix per side %s" % [rules.width, rules.height, rules.tps, rules.ticks_per_turn, mix])
	var args := OS.get_cmdline_user_args()
	var counts := [4, 20, 40]
	if args.has("--quick"):
		counts = [4]
	for n in counts:
		_scenario(n)
	if not args.has("--quick") and not args.has("--no-sweep"):
		_param_sweep(40)
	quit(0)


# --- scenario --------------------------------------------------------------

## n squads, half per side, in two blocks 60 m apart across the centre of
## Crossroads, every squad on attack-move toward its mirror, so they close,
## engage and fight through the terrain in the middle.
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


## A BattleSim whose "move" phase also runs the given prototype systems after
## MovementSystem (the order draft 01 §3.3 puts separation in).
func _sim(extra: Array[SimSystem]) -> BattleSim:
	var sim := BattleSim.new()
	var runner := SystemRunner.new()
	runner.add_phase(&"effects", [AbilitySystem.new(), EffectSystem.new()] as Array[SimSystem])
	var mv: Array[SimSystem] = [Centroids.new(), MovementSystem.new()]
	mv.append_array(extra)
	runner.add_phase(&"move", mv)
	runner.add_phase(&"sense", [Centroids.new(), VisionSystem.new(), Reactions.new()] as Array[SimSystem])
	runner.add_phase(&"fight", [CombatSystem.new(), HealthSystem.new()] as Array[SimSystem])
	runner.add_phase(&"pressure", [Centroids.new(), PoolsSystem.new()] as Array[SimSystem])
	sim.runner = runner
	return sim


## Runs TICKS ticks; returns per-tick ms for each system, total, and hash.
func _measure(n: int, extra: Array[SimSystem]) -> Dictionary:
	var s := _make_state(n)
	var sim := _sim(extra)
	sim.runner.profiling = true
	sim.runner.profile = {}
	var t0 := Time.get_ticks_usec()
	s.begin_turn()
	for t in TICKS:
		if t > 0 and t % rules.ticks_per_turn == 0:
			s.begin_turn()
		sim.runner.step(s)
	var total := Time.get_ticks_usec() - t0
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.state_hash())
	var proto := 0
	for x in extra:
		proto += int(x.get("us"))
		if x.has_method("fold_hash"):
			x.fold_hash(h)
	var alive := 0
	for row in s.units.count():
		if s.units.hp[row] > 0:
			alive += 1
	return {"profile": sim.runner.profile, "total_us": total, "proto_us": proto, "hash": h.finish().hex_encode().substr(0, 16), "alive": alive}


## One IntentForecast for player 1 from the state after one real turn (the
## blocks have closed and see each other, so the forecast keeps the enemy).
## Best of `reps`.
func _forecast_ms(n: int, extra: Array[SimSystem], reps: int) -> float:
	var s := _make_state(n)
	var base := _sim([] as Array[SimSystem])
	s.begin_turn()
	for t in rules.ticks_per_turn:
		base.runner.step(s)
	var sim := _sim(extra)
	var best := 1 << 62
	for i in reps:
		var t0 := Time.get_ticks_usec()
		IntentForecast.run(s, sim, 1, [])
		best = mini(best, Time.get_ticks_usec() - t0)
	return best / 1000.0


func _ms(p: Dictionary, key: String) -> float:
	return int(p.get(key, 0)) / 1000.0 / TICKS


func _scenario(n: int) -> void:
	var s0 := _make_state(n)
	var units := s0.units.count()
	print("\n== %d squads, %d units, %d ticks ==" % [n, units, TICKS])
	var variants := [
		["today", func() -> Array[SimSystem]: return [] as Array[SimSystem]],
		["+search every tick (literal: all target units)", func() -> Array[SimSystem]: return [FiringSearch.new(1, 2, 3, 7, false, 0)] as Array[SimSystem]],
		["+search every 5 ticks (literal)", func() -> Array[SimSystem]: return [FiringSearch.new(5, 2, 3, 7, false, 0)] as Array[SimSystem]],
		["+search memo (1 t, nearest)", func() -> Array[SimSystem]: return [FiringSearch.new(1, 2, 3, 7, true, 0, true)] as Array[SimSystem]],
		["+search recommended (5 t, nearest, memo, cap 4)", func() -> Array[SimSystem]: return [FiringSearch.new(5, 2, 3, 7, true, 4, true)] as Array[SimSystem]],
		["+separation (2 m hash)", func() -> Array[SimSystem]: return [Separation.new(Separation.HASH)] as Array[SimSystem]],
		["+separation (squad broadphase)", func() -> Array[SimSystem]: return [Separation.new(Separation.SQUADS)] as Array[SimSystem]],
		["+search recommended +separation (hash)", func() -> Array[SimSystem]: return [FiringSearch.new(5, 2, 3, 7, true, 4, true), Separation.new(Separation.HASH)] as Array[SimSystem]],
	]
	print("variant | movement ms/t | combat ms/t | prototype ms/t | whole tick ms/t | forecast ms | alive end | determinism | stats")
	for v in variants:
		var mk: Callable = v[1]
		var a_extra: Array[SimSystem] = mk.call()
		var a := _measure(n, a_extra)
		var b := _measure(n, mk.call())
		var p: Dictionary = a["profile"]
		var fc := _forecast_ms(n, mk.call(), 2)
		var stats := ""
		for x in a_extra:
			if x is FiringSearch:
				stats += (x as FiringSearch).stats() + "; "
			if x is Separation:
				stats += (x as Separation).stats()
		print("%s | %.3f | %.3f | %.3f | %.3f | %.1f | %d | %s | %s" % [v[0], _ms(p, "MovementSystem"), _ms(p, "CombatSystem"), a["proto_us"] / 1000.0 / TICKS,
			a["total_us"] / 1000.0 / TICKS, fc, a["alive"],
			"same %s" % a["hash"] if a["hash"] == b["hash"] else "DIFF %s %s" % [a["hash"], b["hash"]], stats])
	var a2 := _measure(n, [] as Array[SimSystem])
	var keys: Array = a2["profile"].keys()
	keys.sort()
	var parts := PackedStringArray()
	for k: String in keys:
		parts.append("%s %.3f" % [k, _ms(a2["profile"], k)])
	print("today, every system ms/tick: " + ", ".join(parts))


func _param_sweep(n: int) -> void:
	print("\n== search parameter sweep at %d squads (ms/tick of the search alone) ==" % n)
	print("cadence | ring step m | rings | angles | LoS targets | cap/tick | memo | ms/tick | stats")
	for p in [[1, 2, 3, 7, false, 0], [1, 2, 3, 7, true, 0], [5, 2, 3, 7, true, 0], [5, 2, 2, 5, true, 0], [10, 2, 3, 7, true, 0],
			[5, 1, 4, 9, true, 0], [5, 2, 3, 7, true, 8], [5, 2, 3, 7, true, 4], [5, 2, 3, 7, true, 2], [10, 2, 2, 5, true, 2], [1, 2, 3, 7, true, 1],
			[1, 2, 3, 7, true, 0, true], [5, 2, 3, 7, true, 0, true], [5, 2, 3, 7, true, 4, true], [5, 2, 3, 7, true, 2, true], [10, 2, 3, 7, true, 2, true], [5, 2, 2, 5, true, 2, true]]:
		var mm: bool = p[6] if p.size() > 6 else false
		var fs := FiringSearch.new(p[0], p[1], p[2], p[3], p[4], p[5], mm)
		var a := _measure(n, [fs] as Array[SimSystem])
		print("%d | %d | %d | %d | %s | %s | %s | %.3f | %s" % [p[0], p[1], p[2], p[3], "nearest" if p[4] else "all", str(p[5]) if p[5] > 0 else "-", "memo" if mm else "-", a["proto_us"] / 1000.0 / TICKS, fs.stats()])
