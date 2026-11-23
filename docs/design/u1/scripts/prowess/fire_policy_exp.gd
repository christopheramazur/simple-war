extends SceneTree
## U1 Prowess fire-distribution experiment (throwaway, not part of the game).
## Compares target-selection policies on fixed matchups using the real sim
## (BattleRules from data/packages/core, real CombatSystem/HealthSystem),
## with CombatSystem._nearest_target overridden per squad.

const ONE := Fixed.ONE
const MAX_TICKS := 1200


class PolicyCombat extends CombatSystem:
	## squad id -> {"kind": nearest|focus|spread, "q": 0..1, "c": 0..100, "def": bool}
	var policy: Dictionary = {}
	var acc_c: Dictionary = {}   # unit id -> coordination accumulator
	var acc_k: Dictionary = {}   # unit id -> focus-width accumulator
	var coord_at: Dictionary = {}  # unit id -> [tick, bool]

	func _coordinated(state: BattleState, uid: int, c: int) -> bool:
		var prev: Array = coord_at.get(uid, [-1, false])
		if prev[0] == state.tick:
			return prev[1]
		var a: int = int(acc_c.get(uid, 0)) + c
		var ok := a >= 100
		if ok:
			a -= 100
		acc_c[uid] = a
		coord_at[uid] = [state.tick, ok]
		return ok

	func _eff(state: BattleState, t: int, d: int, dtype: int) -> int:
		var r := state.rules
		var prof := state.units.defense[t]
		var nt := r.damage_types.size()
		var x := d - Fixed.round_div(d * r.df_resist[prof * nt + dtype], 100)
		x -= mini(r.df_flat[prof], x)
		x -= Fixed.round_div(x * r.df_percent[prof], 100)
		return maxi(x, r.df_floor[prof * nt + dtype])

	func _nearest_target(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary) -> int:
		var u := state.units
		var p: Dictionary = policy.get(u.squad[urow], {"kind": "nearest"})
		if p["kind"] == "nearest":
			return super._nearest_target(state, urow, targets, w, m, pending)
		var uid := u.id_at(urow)
		var coord := _coordinated(state, uid, int(p.get("c", 100)))
		var r := state.rules
		var d := r.md_damage[m]
		var cands := []  # [rem, dist, t, id]
		for t in targets:
			if u.hp[t] <= 0:
				continue
			var dist := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
			if shot_gate(state, urow, t, w, m, dist) != GATE_OK:
				continue
			var q_raw: int = int(pending.get(t, 0)) if coord else 0
			var seen := q_raw
			if p.get("def", false) and q_raw > 0:
				seen = Fixed.mul_ratio(q_raw, _eff(state, t, d, r.wp_type[w]), d)
			cands.append([u.hp[t] - seen, dist, t, u.id_at(t)])
		if cands.is_empty():
			return -1
		var open := cands.filter(func(c): return c[0] > 0)
		if open.is_empty():
			open = cands
		if p["kind"] == "spread":
			open.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
			return open[0][2]
		# focus: kill priority = least remaining first, then unit id (squad-wide agreement)
		open.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[3] < b[3])
		var q: float = p.get("q", 1.0)
		var kf := 1.0 + (1.0 - q) * float(open.size() - 1)
		var k := int(floor(kf))
		var frac := int(round((kf - k) * 100.0))
		var ak: int = int(acc_k.get(uid, 0)) + frac
		if ak >= 100:
			ak -= 100
			k += 1
		acc_k[uid] = ak
		k = clampi(k, 1, open.size())
		var best: Array = open[0]
		for i in k:
			if open[i][1] < best[1]:
				best = open[i]
		return best[2]


class ProbePre extends SimSystem:
	var target_squads: Dictionary = {}  # squad id -> true
	var raw: Dictionary = {}            # squad id -> raw damage queued
	var hp_before: Dictionary = {}
	func system_name() -> StringName:
		return &"probe_pre"
	func run(ctx: SimContext) -> void:
		var s := ctx as BattleState
		var q := s.damage_queue
		for i in q.size() / Health.STRIDE:
			var o := i * Health.STRIDE
			var vs := q[o + Health.Q_VICTIM_SQUAD]
			if target_squads.has(vs) and q[o + Health.Q_DAMAGE] > 0:
				raw[vs] = int(raw.get(vs, 0)) + q[o + Health.Q_DAMAGE]
		hp_before = {}
		for urow in s.units.count():
			hp_before[s.units.id_at(urow)] = maxi(s.units.hp[urow], 0)


class ProbePost extends SimSystem:
	var pre: ProbePre
	var removed: Dictionary = {}  # squad id -> hp removed
	func system_name() -> StringName:
		return &"probe_post"
	func run(ctx: SimContext) -> void:
		var s := ctx as BattleState
		for urow in s.units.count():
			var sid := s.units.squad[urow]
			if not pre.target_squads.has(sid):
				continue
			var id := s.units.id_at(urow)
			var dh: int = int(pre.hp_before.get(id, 0)) - maxi(s.units.hp[urow], 0)
			if dh > 0:
				removed[sid] = int(removed.get(sid, 0)) + dh


var rules: BattleRules


func _init() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var pols := {
		"nearest(current)": {"kind": "nearest"},
		"optimal q1 c100": {"kind": "focus", "q": 1.0, "c": 100},
		"surging q.9 c100": {"kind": "focus", "q": 0.9, "c": 100},
		"neutral q.6 c70": {"kind": "focus", "q": 0.6, "c": 70},
		"fraying q.3 c35": {"kind": "focus", "q": 0.3, "c": 35},
		"broken q.1 c10": {"kind": "focus", "q": 0.1, "c": 10},
		"bad-overkill q1 c0": {"kind": "focus", "q": 1.0, "c": 0},
		"bad-spread": {"kind": "spread", "c": 100},
	}
	var matchups := [
		["rifle_squad", "rifle_squad", "no_armour", 30, "line"],
		["hf_militia", "rifle_squad", "no_armour", 30, "line"],
		["heavy_weapons_team", "rifle_squad", "no_armour", 30, "line"],
		["marksman_team", "scout_team", "no_armour", 40, "line"],
		["mortar_team", "rifle_squad", "no_armour", 36, "line"],
		["rocket_team", "rifle_squad", "no_armour", 30, "line"],
		["rifle_squad", "chi_operatives", "", 30, "line"],
	]
	print("=== passive target (disarmed), attacker HOLD; ticks at 10/s ===")
	print("matchup | policy | first_kill_t | mean_kill_t | kills@10s | kills@20s | wipe_t | raw_dmg | removed | waste% | kills/100raw")
	for mu: Array in matchups:
		for name: String in pols:
			_passive(mu, name, pols[name])
		if mu[1] == "chi_operatives":
			_passive(mu, "optimal+def-aware", {"kind": "focus", "q": 1.0, "c": 100, "def": true})
	print("=== duels: rifle_squad vs rifle_squad, both armed, 30 m, B = nearest(current) ===")
	print("policy A | side | winner | A_alive | B_alive | end_t")
	for name: String in pols:
		for swap in [false, true]:
			_duel(name, pols[name], swap, false, "rifle_squad")
	print("=== duels with staggered hit accumulators (acc_hit = (37*uid mod 100)%) ===")
	for name: String in pols:
		for swap in [false, true]:
			_duel(name, pols[name], swap, true, "rifle_squad")
	print("=== duels: A = hf_militia (10x trooper, value 75) vs B = rifle_squad nearest (value 100) ===")
	for name: String in pols:
		_duel(name, pols[name], false, false, "hf_militia")
	quit()


func _spawn(s: BattleState, player: int, squad: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, rules.squad_index(squad), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid


func _runner(combat: PolicyCombat, pre: ProbePre, post: ProbePost) -> SystemRunner:
	var rn := SystemRunner.new()
	rn.add_phase(&"effects", [AbilitySystem.new(), EffectSystem.new()] as Array[SimSystem])
	rn.add_phase(&"move", [Centroids.new(), MovementSystem.new()] as Array[SimSystem])
	rn.add_phase(&"sense", [Centroids.new(), VisionSystem.new(), Reactions.new()] as Array[SimSystem])
	rn.add_phase(&"fight", [combat, pre, HealthSystem.new(), post] as Array[SimSystem])
	rn.add_phase(&"pressure", [Centroids.new(), PoolsSystem.new()] as Array[SimSystem])
	return rn


func _passive(mu: Array, pname: String, pol: Dictionary) -> void:
	var s := BattleState.new(1, rules, 1)
	var a := _spawn(s, 1, mu[0], 15, 50, 0)
	var b := _spawn(s, 2, mu[1], 15 + int(mu[3]), 50, 32768)
	var brow := s.squads.row_of(b)
	for urow in Centroids.units_of(s, brow):
		var id := s.units.id_at(urow)
		s.units.set_value(id, &"weapon", -1)
		if mu[2] != "":
			s.units.set_value(id, &"defense", rules.defense_index[mu[2]])
	var combat := PolicyCombat.new()
	combat.policy[a] = pol
	var pre := ProbePre.new()
	pre.target_squads[b] = true
	var post := ProbePost.new()
	post.pre = pre
	var rn := _runner(combat, pre, post)
	var n0 := s.squads.alive[brow]
	var first := -1
	var k10 := 0
	var k20 := 0
	var wipe := -1
	var prev_k := 0
	var ksum := 0
	for t in MAX_TICKS:
		rn.step(s)
		brow = s.squads.row_of(b)
		var alive := s.squads.alive[brow] if brow >= 0 else 0
		var kills := n0 - alive
		ksum += (kills - prev_k) * t
		prev_k = kills
		if first < 0 and kills > 0:
			first = t
		if t == 99:
			k10 = kills
		if t == 199:
			k20 = kills
		if alive == 0:
			wipe = t
			if t < 199:
				k20 = kills
			if t < 99:
				k10 = kills
			break
	var raw: int = pre.raw.get(b, 0)
	var rem: int = post.removed.get(b, 0)
	var waste := 100.0 * float(raw - rem) / float(maxi(raw, 1))
	var total_kills := n0 - (s.squads.alive[s.squads.row_of(b)] if s.squads.row_of(b) >= 0 else 0)
	var kp100 := 100.0 * float(total_kills) / maxf(float(raw) / ONE, 1.0)
	print("%s>%s(%s) | %s | %d | %.0f | %d | %d | %d | %d | %d | %.1f | %.2f" % [mu[0], mu[1], mu[2] if mu[2] != "" else "own", pname,
		first, float(ksum) / maxf(prev_k, 1), k10, k20, wipe, raw / ONE, rem / ONE, waste, kp100])


func _duel(pname: String, pol: Dictionary, swap: bool, stagger: bool, a_squad: String) -> void:
	var s := BattleState.new(1, rules, 1)
	# swap: the policy squad is player 2 on the east side (spawned second, higher unit ids)
	var west := _spawn(s, 1, a_squad if not swap else "rifle_squad", 15, 50, 0)
	var east := _spawn(s, 2, "rifle_squad" if not swap else a_squad, 45, 50, 32768)
	if stagger:
		for urow in s.units.count():
			var id := s.units.id_at(urow)
			s.units.set_value(id, &"acc_hit", Fixed.from_ratio((37 * id) % 100, 100))
	var a := east if swap else west
	var b := west if swap else east
	var combat := PolicyCombat.new()
	combat.policy[a] = pol
	var pre := ProbePre.new()
	var post := ProbePost.new()
	post.pre = pre
	var rn := _runner(combat, pre, post)
	var end_t := -1
	for t in MAX_TICKS:
		rn.step(s)
		var aa := _alive(s, a)
		var bb := _alive(s, b)
		if aa == 0 or bb == 0:
			end_t = t
			break
	var aa := _alive(s, a)
	var bb := _alive(s, b)
	var winner := "A" if bb == 0 and aa > 0 else ("B" if aa == 0 and bb > 0 else "draw")
	print("%s | %s | %s | %d | %d | %d" % [pname, "east" if swap else "west", winner, aa, bb, end_t])


func _alive(s: BattleState, sid: int) -> int:
	var row := s.squads.row_of(sid)
	return s.squads.alive[row] if row >= 0 else 0
