extends SceneTree
## sw-arse: how battle cost grows with squads (40, 80, 160) and with several
## battles stepped in one process (1, 2, 4), and how much of it is line of
## sight. Each battle compiles its own rules (as OverworldBattles does) on a
## Crossroads map tiled to keep the density of 40 squads per 200 x 100 m:
## 40 squads 1 x 1 tiles, 80 1 x 2, 160 2 x 2. Both sides attack-move at each
## other across the centre (the fp_cost fixture, scaled).
##
## Prints per config: wall ms per tick for all battles, ms per battle-tick,
## ms per battle-second (x tps), and per battle-tick the split: firing
## positions, the rest of movement, vision, combat, other. With --trace, it
## also records every los() query (caller, cells, awareness) on battle 0 and
## replays them through the walk, the memo and the new structure (exact
## answers checked), so the LoS share is measured on the real query mix.
##
## Run: harness/bin/hx godot run docs/design/u1/scripts/fp/los_scale.gd --timeout 1800 -- \
##   [--squads 40,80,160] [--battles 1,2,4] [--ticks 300] [--trace] [--reps 1]
##   [--fp-scale N] (scales the firing-position budgets: the sw-arse trial, which
##   needs that trial's code; ignored without it) [--quality] (shots, damage,
##   losses and the share of armed unit-ticks holding a firing position, on
##   battle 0; it costs time, so compare timings without it). --reps takes the
##   median wall time.

const ONE := Fixed.ONE
const MIX := ["rifle_squad", "rifle_squad", "heavy_weapons_team", "marksman_team", "scout_team"]

## Records every los() call (tag = the system running), for --trace.
class TraceRules extends BattleRules:
	var tag := 0
	var trace := PackedInt64Array()
	func los(ax: int, ay: int, bx: int, by: int) -> bool:
		var ex := bx - ax
		var ey := by - ay
		var aware := ex * ex + ey * ey <= AWARENESS_SQ_LIMIT
		var x0 := clampi(Fixed.to_int_floor(ax), 0, width - 1)
		var y0 := clampi(Fixed.to_int_floor(ay), 0, height - 1)
		var x1 := clampi(Fixed.to_int_floor(bx), 0, width - 1)
		var y1 := clampi(Fixed.to_int_floor(by), 0, height - 1)
		trace.append_array(PackedInt64Array([tag, x0, y0, x1, y1, 1 if aware else 0, ax, ay, bx, by]))
		return super(ax, ay, bx, by)

## Times its inner system, and tags the rules' trace with its index.
class Timed extends SimSystem:
	var us := 0
	var inner: SimSystem
	var tag := 0
	func _init(s: SimSystem, t: int) -> void:
		inner = s
		tag = t
	func system_name() -> StringName:
		return inner.system_name()
	func run(ctx: SimContext) -> void:
		var state := ctx as BattleState
		if state.rules is TraceRules:
			(state.rules as TraceRules).tag = tag
		var t0 := Time.get_ticks_usec()
		inner.run(ctx)
		us += Time.get_ticks_usec() - t0

## MovementSystem with the firing-position pass timed on its own.
class MS extends MovementSystem:
	var fp_us := 0
	func run(ctx: SimContext) -> void:
		var state := ctx as BattleState
		if state.rules is TraceRules:
			(state.rules as TraceRules).tag = 1
		var a := Time.get_ticks_usec()
		FiringPositions.update(state)
		fp_us += Time.get_ticks_usec() - a
		if state.rules is TraceRules:
			(state.rules as TraceRules).tag = 2
		_plan_routes(state)
		_move_anchors(state)
		_move_units(state)
		_separation.run(state)

const TAGS := ["effects", "fp", "move", "centroids", "vision", "reactions", "combat", "health", "pools"]

var loader: PackageLoader
var save_dir := ""
var fp_scale := 0
var quality := false


func _initialize() -> void:
	Fixed.warm()
	loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var args := OS.get_cmdline_user_args()
	var squads := [40, 80, 160]
	var battles := [1, 2, 4]
	var ticks := 300
	var reps := 1
	var trace := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--squads":
				squads = Array(args[i + 1].split(",")).map(func(s): return int(s))
				i += 1
			"--battles":
				battles = Array(args[i + 1].split(",")).map(func(s): return int(s))
				i += 1
			"--ticks":
				ticks = int(args[i + 1])
				i += 1
			"--reps":
				reps = int(args[i + 1])
				i += 1
			"--trace":
				trace = true
			"--fp-scale":
				fp_scale = int(args[i + 1])
				i += 1
			"--quality":
				quality = true
			"--save-trace":
				save_dir = args[i + 1]
				trace = true
				i += 1
		i += 1
	print("config            wall ms/t  ms/battle-t  ms/battle-s   fp   move  vision combat other   hash(b0)")
	for n in squads:
		for k in battles:
			var runs := []
			for rep in reps:
				runs.append(_run(n, k, ticks, trace and k == 1 and rep == 0))
			runs.sort_custom(func(a, b): return a["wall"] < b["wall"])
			var med: Dictionary = runs[runs.size() / 2]
			for x in runs:
				if x.has("replay"):
					med["replay"] = x["replay"]
			_print(n, k, ticks, med)
	quit(0)


func _tiles(n: int) -> Vector2i:
	if n <= 40:
		return Vector2i(1, 1)
	if n <= 80:
		return Vector2i(1, 2)
	if n <= 160:
		return Vector2i(2, 2)
	return Vector2i(4, 2)


## Rules for one battle: compiled from the core data, the map tiled.
func _rules(n: int, traced: bool) -> BattleRules:
	var base := BattleRules.compile(loader.templates, "duel_crossroads", loader.data_hash)
	var r: BattleRules = base
	if traced:
		r = TraceRules.new()
		for p in base.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				r.set(p.name, base.get(p.name))
		r.set("los_cache", PackedInt64Array())
		r.set("los_memo", {})
	var t := _tiles(n)
	if t != Vector2i(1, 1):
		var w := base.width
		var h := base.height
		var ter := PackedByteArray()
		ter.resize(w * t.x * h * t.y)
		for y in h * t.y:
			for x in w * t.x:
				ter[y * w * t.x + x] = base.terrain[(y % h) * w + (x % w)]
		r.width = w * t.x
		r.height = h * t.y
		r.terrain = ter
		var fac := PackedByteArray()
		fac.resize(ter.size())
		r.facing = fac
		r.routes = BattleRoute.new()
	r.clear_los_memo()
	if fp_scale > 0:
		r.set("fp_search_scale", fp_scale)
	Stats.warm(r)
	r.routes.warm(r)
	return r


## n squads, half per side, in blocks 60 m apart across the map's centre,
## every squad attack-moving toward its mirror.
func _state(n: int, traced: bool) -> BattleState:
	var r := _rules(n, traced)
	var s := BattleState.new(1, r, 1)
	var per_side := n / 2
	var rows_max := (r.height - 16) / 14
	var cols := maxi(2 if per_side <= 4 else 4, ceili(float(per_side) / rows_max))
	var rows := ceili(float(per_side) / cols)
	var cx := r.width / 2
	var cy := r.height / 2
	for i in per_side:
		var c := i % cols
		var rr := i / cols
		var y := clampi(cy - (rows - 1) * 7 + rr * 14, 8, r.height - 8)
		var st := r.squad_index(MIX[i % MIX.size()])
		var a := BattleSetup.spawn_squad(s, 1, st, (cx - 30 - c * 7) * ONE, y * ONE, 0)
		var b := BattleSetup.spawn_squad(s, 2, st, (cx + 30 + c * 7) * ONE, y * ONE, Fixed.ANGLE_HALF)
		Centroids.update(s)
		var ra := s.squads.row_of(a)
		var rb := s.squads.row_of(b)
		BattleOrders.set_order(s, ra, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[rb], s.squads.cy[rb], -1, 0)
		BattleOrders.set_order(s, rb, BattleSquads.Order.ATTACK_MOVE, s.squads.cx[ra], s.squads.cy[ra], -1, 0)
	Centroids.update(s)
	return s


func _sim(t: Array) -> BattleSim:
	var sim := BattleSim.new()
	var runner := SystemRunner.new()
	var ms := MS.new()
	var mk := func(s: SimSystem, tag: int) -> SimSystem:
		var x := Timed.new(s, tag)
		t.append(x)
		return x
	runner.add_phase(&"effects", [mk.call(AbilitySystem.new(), 0), mk.call(EffectSystem.new(), 0)] as Array[SimSystem])
	runner.add_phase(&"move", [mk.call(Centroids.new(), 3), mk.call(ms, 2)] as Array[SimSystem])
	runner.add_phase(&"sense", [mk.call(Centroids.new(), 3), mk.call(VisionSystem.new(), 4), mk.call(Reactions.new(), 5)] as Array[SimSystem])
	runner.add_phase(&"fight", [mk.call(CombatSystem.new(), 6), mk.call(HealthSystem.new(), 7)] as Array[SimSystem])
	runner.add_phase(&"pressure", [mk.call(Centroids.new(), 3), mk.call(PoolsSystem.new(), 8)] as Array[SimSystem])
	sim.runner = runner
	t.append(ms)
	return sim


func _run(n: int, k: int, ticks: int, traced: bool) -> Dictionary:
	var states: Array[BattleState] = []
	var sims: Array[BattleSim] = []
	var timers: Array = []
	for b in k:
		var t := []
		states.append(_state(n, traced and b == 0))
		sims.append(_sim(t))
		timers.append(t)
		states[b].begin_turn()
	var q := {"shots": 0, "has": 0, "armed": 0, "hp0": _hp(states[0])}
	var t0 := Time.get_ticks_usec()
	for tick in ticks:
		for b in k:
			var s := states[b]
			if tick > 0 and tick % s.rules.ticks_per_turn == 0:
				s.begin_turn()
			sims[b].runner.step(s)
			if quality and b == 0:
				_observe(s, q)
	var wall := Time.get_ticks_usec() - t0
	var split := {"fp": 0, "move": 0, "vision": 0, "combat": 0, "all": 0}
	for t: Array in timers:
		var ms: MS = t[t.size() - 1]
		split["fp"] += ms.fp_us
		for x in t:
			if x is Timed:
				var name := String((x as Timed).inner.system_name())
				split["all"] += x.us
				if name == "movement":
					split["move"] += x.us - ms.fp_us
				elif name == "vision":
					split["vision"] += x.us
				elif name == "combat":
					split["combat"] += x.us
	var out := {"wall": wall, "split": split, "hash": states[0].state_hash().hex_encode().substr(0, 12),
		"units": states[0].units.count(), "tps": states[0].rules.tps, "k": k}
	if quality:
		var hp1 := _hp(states[0])
		out["quality"] = "  quality: shots %d  damage dealt p1 %.0f p2 %.0f  HAS %.1f%% of armed unit-ticks under attack orders" % [
			q["shots"], (q["hp0"][2] - hp1[2]) / float(ONE), (q["hp0"][1] - hp1[1]) / float(ONE), 100.0 * q["has"] / maxi(q["armed"], 1)]
	if traced:
		out["replay"] = _replay(states[0].rules as TraceRules, ticks)
		if save_dir != "":
			var f := FileAccess.open("%s/trace_%d.bin" % [save_dir, n], FileAccess.WRITE)
			f.store_var({"n": n, "ticks": ticks, "width": states[0].rules.width, "height": states[0].rules.height,
				"terrain": states[0].rules.terrain, "trace": (states[0].rules as TraceRules).trace})
			f.close()
	return out


func _print(n: int, k: int, ticks: int, res: Dictionary) -> void:
	var sp: Dictionary = res["split"]
	var bt := float(ticks * k) * 1000.0
	var other: float = (sp["all"] - sp["fp"] - sp["move"] - sp["vision"] - sp["combat"]) / bt
	var per: float = res["wall"] / bt
	print("n=%-3d (%3d units) k=%d  %7.2f  %9.2f  %10.1f  %5.2f %5.2f %5.2f %5.2f %5.2f   %s" % [
		n, res["units"], k, res["wall"] / (ticks * 1000.0), per, per * res["tps"],
		sp["fp"] / bt, sp["move"] / bt, sp["vision"] / bt, sp["combat"] / bt, other, res["hash"]])
	if res.has("quality"):
		print(res["quality"])
	if res.has("replay"):
		print(res["replay"])


## Replays battle 0's los() queries: counts per caller, the memo's hit rate,
## and the cost of each implementation over the same queries.
func _replay(r: TraceRules, ticks: int) -> String:
	var tr := r.trace
	var m := tr.size() / 10
	var by_tag := {}
	var aware := 0
	for i in m:
		var tag: String = TAGS[tr[10 * i]]
		by_tag[tag] = int(by_tag.get(tag, 0)) + 1
		aware += tr[10 * i + 5]
	var lines := PackedStringArray()
	lines.append("  los() calls %d over %d ticks (%.0f/t), awareness %.0f%%, by caller %s" % [m, ticks, m / float(ticks), 100.0 * aware / maxi(m, 1), by_tag])
	# Through los() with a fresh cache, as the sim saw them.
	var base := BattleRules.new()
	for p in r.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.name != "trace" and p.name != "tag":
			base.set(p.name, r.get(p.name))
	base.clear_los_memo()
	var ref := PackedByteArray()
	ref.resize(m)
	var t0 := Time.get_ticks_usec()
	for i in m:
		ref[i] = 1 if base.los(tr[10 * i + 6], tr[10 * i + 7], tr[10 * i + 8], tr[10 * i + 9]) else 0
	var t_memo := Time.get_ticks_usec() - t0
	var walks := 0
	t0 = Time.get_ticks_usec()
	for i in m:
		if tr[10 * i + 5] == 0:
			base._walk_los(tr[10 * i + 1], tr[10 * i + 2], tr[10 * i + 3], tr[10 * i + 4])
			walks += 1
	var t_walk := Time.get_ticks_usec() - t0
	var distinct := {}
	for i in m:
		if tr[10 * i + 5] == 0:
			distinct[((tr[10 * i + 2] * r.width + tr[10 * i + 1]) * r.width * r.height) + tr[10 * i + 4] * r.width + tr[10 * i + 3]] = true
	lines.append("  walks needed %d, distinct cell pairs %d (best possible memo hit %.0f%%)" % [walks, distinct.size(), 100.0 - 100.0 * distinct.size() / maxi(walks, 1)])
	lines.append("  replay: los() as built %.3f ms/t (%.2f us/call), every walk uncached %.3f ms/t (%.2f us/walk)" % [
		t_memo / 1000.0 / ticks, t_memo / float(maxi(m, 1)), t_walk / 1000.0 / ticks, t_walk / float(maxi(walks, 1))])
	if base.has_method("los_field_stats"):
		lines.append("  " + base.call("los_field_stats"))
	return "\n".join(lines)


func _observe(s: BattleState, q: Dictionary) -> void:
	var u := s.units
	for urow in u.count():
		if u.hp[urow] <= 0:
			continue
		if u.fired_tick[urow] == s.tick - 1:
			q["shots"] += 1
		if u.weapon[urow] >= 0 and u.fpos[urow] != FiringPositions.NONE:
			q["armed"] += 1
			if u.fpos[urow] == FiringPositions.HAS:
				q["has"] += 1


## Living HP per player [0, p1, p2].
func _hp(s: BattleState) -> Array:
	var out := [0, 0, 0]
	for urow in s.units.count():
		var row := s.squads.row_of(s.units.squad[urow])
		if s.units.hp[urow] > 0 and row >= 0:
			out[s.squads.player[row]] += s.units.hp[urow]
	return out
