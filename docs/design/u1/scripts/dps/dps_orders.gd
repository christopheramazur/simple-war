extends SceneTree
## U1 DPS-by-order harness (throwaway; a bead may adopt it as a sim lab).
## One attacker squad vs a target under each battle order, real core data
## (data/packages/core), open ground on the Crossroads map (lane y = 80).
## Measures damage dealt (HP + temp HP actually applied), shots, hits,
## unit-ticks moving vs firing, fire mode (moving/standing), Instinct, and
## BattleActivity hold reasons per unit-tick and per second.
##
## Run: harness/bin/hx godot run <this file> --tail 400

const ONE := Fixed.ONE
const TICKS := 300  # 3 battle turns at 10 tps
const LANE_Y := 80
const AX := 20

var rules: BattleRules
const HOLD_LETTERS := {
	BattleActivity.Hold.NONE: ".", BattleActivity.Hold.UNARMED: "u", BattleActivity.Hold.FALLING_BACK: "f",
	BattleActivity.Hold.RELOADING: "R", BattleActivity.Hold.COOLDOWN: "c", BattleActivity.Hold.NO_MOVING_FIRE: "m",
	BattleActivity.Hold.MIN_RANGE: "n", BattleActivity.Hold.OUT_OF_RANGE: "o", BattleActivity.Hold.NO_LOS: "l",
	BattleActivity.Hold.NOT_SPOTTED: "s", BattleActivity.Hold.NO_TARGET: "t",
}


func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	rules = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	print("legend: per-second timeline char = F if most armed units fired that second, else the dominant hold reason;")
	print("  . none  R reload  c cooldown  m no moving fire  n min range  o out of range  l no LOS  s not spotted  t no target")
	print("cols: scenario | dmg | DPS(300t) | DPS from 1st shot | shots | hits | hit% | 1st shot s | unit-ticks moving | unit fire events moving/standing | instinct end/min | end centroid dist m | holds (unit-ticks)")
	var rifle := [
		# name, order, dist, extra
		["R1 HOLD in range 35m", "hold", 35, {}],
		["R2 HOLD out of range 44m", "hold", 44, {}],
		["R3 MOVE to enemy centre 44m", "move", 44, {}],
		["R3b MOVE to 20m short of enemy", "move", 44, {"move_short": 20}],
		["R4 ATTACK_MOVE to enemy 44m", "attack_move", 44, {}],
		["R5 ATTACK target 44m", "attack", 44, {}],
		["R6 MOVE run 44m", "move", 44, {"run": true}],
		["R6b ATTACK_MOVE run 44m", "attack_move", 44, {"run": true}],
		["R6c ATTACK run 44m", "attack", 44, {"run": true}],
		["R7 MOVE 70m (unseen start)", "move", 70, {}],
		["R7b ATTACK_MOVE 70m", "attack_move", 70, {}],
		["R8 HOLD flank 35m @45deg", "hold", 35, {"flank": true}],
		["R8b ATTACK_MOVE flank 50m @45deg", "attack_move", 50, {"flank": true}],
		["R8c ATTACK flank 44m @45deg", "attack", 44, {"flank": true}],
		["R8d ATTACK_MOVE vs column 44m", "attack_move", 44, {"enemy_facing_south": true}],
		["R9 2 enemies: ATTACK A only", "attack", 44, {"second": true}],
		["R9b 2 enemies: ATTACK B only", "attack", 44, {"second": true, "target_b": true}],
		["R9c 2 enemies: ATTACK A, retarget B @t50", "attack", 44, {"second": true, "retarget_at": 50}],
		["R9d 2 enemies: ATTACK A, retarget B @t150", "attack", 44, {"second": true, "retarget_at": 150}],
		["R9e 2 enemies: ATTACK_MOVE", "attack_move", 44, {"second": true}],
	]
	print("\n== Rifle squad (8 x rifle: aimed 1x0.6x3/1.0s standing; burst 3x0.3x3/1.5s moving) vs disarmed 1000-HP rifle squad on HOLD ==")
	for s in rifle:
		_run("rifle_squad", s[0], s[1], s[2], s[3])
	print("\n== Rifle squad vs ARMED rifle squad on HOLD (real duel, 300 ticks) ==")
	for s in rifle.slice(0, 11):
		var ex: Dictionary = s[3].duplicate()
		ex["armed"] = true
		_run("rifle_squad", s[0] + " [armed]", s[1], s[2], ex)
	print("\n== Mortar team (3 x mortar: 1x0.35x10 AoE5 / max(reload 30, cd 60) = 6 s, range 20-90, standing only) vs disarmed target; a disarmed friendly spotter holds 25 m from the target ==")
	var mortar := [
		["M1 HOLD in range 60m", "hold", 60, {}],
		["M2 HOLD out of range 100m", "hold", 100, {}],
		["M3 MOVE to enemy centre 100m", "move", 100, {}],
		["M3b MOVE to 50m short", "move", 100, {"move_short": 50}],
		["M4 ATTACK_MOVE to enemy 100m", "attack_move", 100, {}],
		["M5 ATTACK target 100m", "attack", 100, {}],
		["M5b ATTACK target 60m (in range)", "attack", 60, {}],
		["M6 ATTACK_MOVE run 100m", "attack_move", 100, {"run": true}],
	]
	for s in mortar:
		var ex: Dictionary = s[3].duplicate()
		ex["spotter"] = true
		_run("mortar_team", s[0], s[1], s[2], ex)
	print("
== Mixed-range squads vs disarmed target (does the squad stop where only its longest weapon reaches?) ==")
	for sq in [["assault_squad", "1 sgt rifle 40m + 4 breacher shotgun 15m"], ["heavy_weapons_team", "2 lmg 50m + 2 rifle 40m"], ["rocket_team", "2 rocket 45m + 1 rifle 40m"]]:
		print("-- %s (%s)" % sq)
		for s in [["HOLD at 12m (all in range)", "hold", 12, {}], ["MOVE to enemy centre 60m", "move", 60, {}],
				["ATTACK_MOVE to enemy 60m", "attack_move", 60, {}], ["ATTACK target 44m", "attack", 44, {}]]:
			_run(sq[0], "  " + s[0], s[1], s[2], s[3])
	print("
== Far second target and moving targets (rifle vs disarmed) ==")
	for s in [["R10 A at 35m in range; ATTACK far B (55m, spotted)", "attack", 35, {"far_b": true, "target_b": true}],
			["R10b A at 35m; HOLD (fires at A)", "hold", 35, {"far_b": true}],
			["R10c HOLD on A, retarget far B @t50", "hold", 35, {"far_b": true, "retarget_at": 50}],
			["R11 target walks north 40m: ATTACK", "attack", 38, {"foe_walk": true}],
			["R11b target walks north 40m: ATTACK_MOVE to its start", "attack_move", 38, {"foe_walk": true}],
			["R11c target walks north 40m: HOLD", "hold", 38, {"foe_walk": true}]]:
		_run("rifle_squad", s[0], s[1], s[2], s[3])
	print("
== Armed rifle duels, both sides acting (attacker order vs defender order), start 60 m (out of sight) ==")
	for s in [["A: ATTACK_MOVE vs D: ATTACK_MOVE (mirror)", "attack_move", 60, {"armed": true, "foe_order": "attack_move"}],
			["A: HOLD vs D: ATTACK_MOVE", "hold", 60, {"armed": true, "foe_order": "attack_move"}],
			["A: MOVE vs D: ATTACK_MOVE", "move", 60, {"armed": true, "foe_order": "attack_move"}],
			["A: MOVE vs D: MOVE (mirror)", "move", 60, {"armed": true, "foe_order": "move"}],
			["A: ATTACK_MOVE vs D: HOLD", "attack_move", 60, {"armed": true}],
			["A: ATTACK_MOVE vs D: HOLD (deaths traced)", "attack_move", 60, {"armed": true, "trace_deaths": true}],
			["A: HOLD 35m vs D: HOLD (deaths traced)", "hold", 35, {"armed": true, "trace_deaths": true}]]:
		_run("rifle_squad", s[0], s[1], s[2], s[3])
	quit(0)


func _place(s: BattleState, player: int, squad: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, rules.squad_index(squad), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid


func _disarm(s: BattleState, sid: int) -> void:
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)


func _toughen(s: BattleState, sid: int) -> void:
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"hp", 1000 * ONE)
		s.units.set_value(s.units.id_at(urow), &"hp_max", 1000 * ONE)


func _order(s: BattleState, sid: int, kind: String, x: int, y: int, target: int, run: bool) -> void:
	var row := s.squads.row_of(sid)
	var t: int = BattleOrders.TYPES[kind]
	var tx := x
	var ty := y
	if kind == "hold":
		tx = s.squads.cx[row]
		ty = s.squads.cy[row]
	BattleOrders.set_order(s, row, t, tx, ty, target, 1 if run else 0)


func _run(squad: String, name: String, order: String, dist: int, ex: Dictionary) -> void:
	var s := BattleState.new(1, rules, 1)
	s.trace_shots = true
	var armed: bool = ex.get("armed", false)
	var ex_x := AX + dist
	var ex_y := LANE_Y
	var enemy_facing := Fixed.ANGLE_HALF
	if ex.get("flank", false):
		# 45 degrees off the attacker's facing (east), to the north.
		var d := Fixed.mul(dist * ONE, Fixed.fcos(Fixed.ANGLE_QUARTER / 2))
		ex_x = AX + Fixed.to_int_round(d)
		ex_y = LANE_Y - Fixed.to_int_round(d)
	if ex.get("enemy_facing_south", false):
		enemy_facing = Fixed.ANGLE_QUARTER
	var me := _place(s, 1, squad, AX, LANE_Y, 0)
	var foe := _place(s, 2, "rifle_squad", ex_x, ex_y, enemy_facing)
	var foe_b := -1
	if ex.get("second", false):
		foe_b = _place(s, 2, "rifle_squad", AX + dist - 4, LANE_Y - 18, Fixed.ANGLE_HALF)
	if ex.get("far_b", false):
		foe_b = _place(s, 2, "rifle_squad", AX + 45, LANE_Y - 32, Fixed.ANGLE_HALF)
		var spb := _place(s, 1, "rifle_squad", AX + 45, LANE_Y - 55, 0)
		_disarm(s, spb)
	if not armed:
		for f in [foe, foe_b]:
			if f >= 0:
				_disarm(s, f)
				_toughen(s, f)
	if ex.get("spotter", false):
		var sp := _place(s, 1, "rifle_squad", ex_x - 25, ex_y + 5, 0)
		_disarm(s, sp)
	if ex.get("foe_walk", false):
		var frow0 := s.squads.row_of(foe)
		BattleOrders.set_order(s, frow0, BattleSquads.Order.MOVE, s.squads.cx[frow0], s.squads.cy[frow0] - 40 * ONE, -1, 0)
	if ex.has("foe_order"):
		var mrow := s.squads.row_of(me)
		_order(s, foe, ex["foe_order"], s.squads.cx[mrow], s.squads.cy[mrow], -1, false)
	var target := foe_b if ex.get("target_b", false) else foe
	var trow := s.squads.row_of(target)
	var tx := s.squads.cx[trow]
	var ty := s.squads.cy[trow]
	var short: int = ex.get("move_short", 0)
	if short > 0:
		tx -= short * ONE
	_order(s, me, order, tx, ty, target if order == "attack" else -1, ex.get("run", false))
	var my_units := {}
	for urow in Centroids.units_of(s, s.squads.row_of(me)):
		my_units[s.units.id_at(urow)] = true
	var sim := BattleSim.new()
	var holds := {}
	var timeline := ""
	var sec_counts := {}
	var sec_fired := 0
	var sec_armed := 0
	var moving_ticks := 0
	var fire_moving := 0
	var fire_standing := 0
	var inst_min := 1 << 62
	var first_shot := -1
	var death_me := "-"
	var death_foe := "-"
	var me0: int = s.squads.alive[s.squads.row_of(me)]
	var foe0: int = s.squads.alive[s.squads.row_of(foe)]
	for t in TICKS:
		if ex.has("retarget_at") and t == ex["retarget_at"]:
			# What the Retarget reaction's order effect does (effects.gd _order "attack").
			var brow := s.squads.row_of(foe_b)
			BattleOrders.set_order(s, s.squads.row_of(me), BattleSquads.Order.ATTACK, s.squads.cx[brow], s.squads.cy[brow], foe_b, 0)
		sim.runner.step(s)
		if ex.get("trace_deaths", false):
			var cm := 0
			var cf := 0
			var hm := PackedStringArray()
			var hf := PackedStringArray()
			for ur in s.units.count():
				if s.units.hp[ur] <= 0:
					continue
				if s.units.squad[ur] == me:
					cm += 1
					hm.append("%.0f" % (float(s.units.hp[ur]) / ONE))
				elif s.units.squad[ur] == foe:
					cf += 1
					hf.append("%.0f" % (float(s.units.hp[ur]) / ONE))
			if cm != int(ex.get("_cm", me0)) or cf != int(ex.get("_cf", foe0)):
				print("      t=%.1f alive me %d foe %d  my hp [%s]  foe hp [%s]" % [t / 10.0, cm, cf, ",".join(hm), ",".join(hf)])
				ex["_cm"] = cm
				ex["_cf"] = cf
		var row := s.squads.row_of(me)
		if row < 0:
			break
		var frw := s.squads.row_of(foe)
		if death_me == "-" and s.squads.alive[row] < me0:
			death_me = "%.1f" % (t / 10.0)
		if death_foe == "-" and (frw < 0 or s.squads.alive[frw] < foe0):
			death_foe = "%.1f" % (t / 10.0)
		var ivalue := Pools.value(s, row, BattleSquads.INSTINCT)
		inst_min = mini(inst_min, ivalue)
		for urow in Centroids.units_of(s, row):
			if s.units.hp[urow] <= 0:
				continue
			if s.units.moving[urow] == 1:
				moving_ticks += 1
			if s.units.weapon[urow] < 0:
				continue
			sec_armed += 1
			if s.units.fired_tick[urow] == s.tick - 1:
				sec_fired += 1
				if first_shot < 0:
					first_shot = s.tick - 1
				if s.units.moving[urow] == 1:
					fire_moving += 1
				else:
					fire_standing += 1
				holds["F"] = int(holds.get("F", 0)) + 1
				continue
			var h: String = HOLD_LETTERS[BattleActivity.hold(s, urow)]
			holds[h] = int(holds.get(h, 0)) + 1
			sec_counts[h] = int(sec_counts.get(h, 0)) + 1
		if (t + 1) % rules.tps == 0:
			# A rifle fires about once a second, so "most fired" = fired events >= half the armed units.
			var units_alive: int = maxi(sec_armed / rules.tps, 1)
			if sec_fired * 2 >= units_alive:
				timeline += "F"
			else:
				var best := "."
				var bn := -1
				for k: String in sec_counts:
					if sec_counts[k] > bn:
						bn = sec_counts[k]
						best = k
				timeline += best
			sec_counts = {}
			sec_fired = 0
			sec_armed = 0
	var shots := 0
	var hits := 0
	for o in range(0, s.shot_trace.size(), BattleState.SHOT_STRIDE):
		if my_units.has(s.shot_trace[o + 1]):
			shots += 1
			hits += s.shot_trace[o + 3]
	var dmg := 0
	for o in range(0, s.hit_trace.size(), BattleState.HIT_STRIDE):
		if my_units.has(s.hit_trace[o + 3]):
			dmg += s.hit_trace[o + 2]
	var foe_dmg := 0
	for o in range(0, s.hit_trace.size(), BattleState.HIT_STRIDE):
		if not my_units.has(s.hit_trace[o + 3]):
			foe_dmg += s.hit_trace[o + 2]
	var row := s.squads.row_of(me)
	var end_d := -1.0
	var inst_end := -1.0
	var alive := 0
	if row >= 0:
		var frow := s.squads.row_of(target)
		if frow >= 0:
			end_d = float(Fixed.distance(s.squads.cx[row], s.squads.cy[row], s.squads.cx[frow], s.squads.cy[frow])) / ONE
		inst_end = float(Pools.value(s, row, BattleSquads.INSTINCT)) / ONE
		alive = s.squads.alive[row]
	var dmgf := float(dmg) / ONE
	var secs := float(TICKS) / rules.tps
	var after := (float(TICKS - first_shot) / rules.tps) if first_shot >= 0 else 0.0
	var extra := ""
	if armed:
		var frow2 := s.squads.row_of(foe)
		extra = " | my alive %d | foe alive %d | foe dmg %.0f | first foe death s %s, first own death s %s" % [alive, s.squads.alive[frow2] if frow2 >= 0 else 0, float(foe_dmg) / ONE, death_foe, death_me]
	print("%-44s | %6.1f | %5.2f | %5.2f | %4d | %4d | %3d%% | %5s | %4d | %d/%d | %.0f/%.0f | %5.1f | %s%s" % [
		name, dmgf, dmgf / secs, (dmgf / after) if after > 0 else 0.0, shots, hits,
		(100 * hits / shots) if shots > 0 else 0, ("%.1f" % (first_shot / float(rules.tps))) if first_shot >= 0 else "-",
		moving_ticks, fire_moving, fire_standing, inst_end, float(inst_min) / ONE, end_d, _fmt_holds(holds), extra])
	print("    " + timeline)


func _fmt_holds(h: Dictionary) -> String:
	var keys := h.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s:%d" % [k, h[k]])
	return " ".join(parts)
