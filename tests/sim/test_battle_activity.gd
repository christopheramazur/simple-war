extends GutTest
## Per-squad activity and per-unit hold-fire reasons (sw-ll4.27.2, GDD 02
## §2.6 "Shown"): the codes come from the sim's own gates, observe/inspect
## expose them fog-safe, and playback frames carry them for every tick.

const ONE := Fixed.ONE

static var _loader: PackageLoader
static var _rules_cache: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _rules() -> BattleRules:
	if _rules_cache == null:
		_rules_cache = BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	return _rules_cache


## An empty battle (no deployment) to place squads by hand.
func _empty() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


## A stationary enemy that cannot shoot back (disarmed) and cannot die
## (huge HP), so only the observer's own timing is under test.
func _target(s: BattleState, x: int, y: int) -> int:
	var sid := _place(s, 2, "rifle_squad", x, y)
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
		s.units.set_value(s.units.id_at(urow), &"hp", 1000 * ONE)
		s.units.set_value(s.units.id_at(urow), &"hp_max", 1000 * ONE)
	return sid


## Teleports a squad (anchor, order point and every unit by the same delta).
func _move_squad(s: BattleState, sid: int, nx: int, ny: int) -> void:
	var row := s.squads.row_of(sid)
	var dx := nx * ONE - s.squads.ax[row]
	var dy := ny * ONE - s.squads.ay[row]
	for c: StringName in [&"ax", &"tx", &"ay", &"ty"]:
		var col: PackedInt64Array = s.squads.take_column(c)
		col[row] += dx if c in [&"ax", &"tx"] else dy
		s.squads.put_column(c, col)
	var ux: PackedInt64Array = s.units.take_column(&"x")
	var uy: PackedInt64Array = s.units.take_column(&"y")
	for urow in Centroids.units_of(s, row):
		ux[urow] += dx
		uy[urow] += dy
	s.units.put_column(&"x", ux)
	s.units.put_column(&"y", uy)
	Centroids.update(s)


func _squad_obs(obs: Dictionary, sid: int) -> Dictionary:
	for d: Dictionary in obs["squads"]:
		if d["id"] == sid:
			return d
	return {}


func _unit_obs(obs: Dictionary, sid: int) -> Array:
	return (obs["units"] as Array).filter(func(u: Dictionary) -> bool: return u["squad"] == sid)


## The mortar emptied its magazine on tick 0: the next tick it is reloading,
## and observe carries the reason plus the whole weapon report.
func test_reloading_reason_and_weapon_report() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 85, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	sim.runner.step(s)
	var urow := Centroids.units_of(s, s.squads.row_of(mortar))[0]
	assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.RELOADING)
	var obs := BattleSession.observe_state(s, 1)
	var sd := _squad_obs(obs, mortar)
	assert_eq(sd["activity"], BattleActivity.Squad.READY, "engaged but did not fire the last tick")
	assert_eq(sd["target"], enemy)
	var ud: Dictionary = _unit_obs(obs, mortar)[0]
	assert_eq(ud["hold"], BattleActivity.Hold.RELOADING)
	assert_eq(ud["weapon"], "mortar")
	assert_eq(ud["ammo"], 0)
	assert_eq(ud["magazine"], 1)
	assert_eq(ud["reload"], 29, "30 set at the shot, one tick passed")
	assert_eq(ud["cooldown"], 59)
	assert_gte(ud["victim"], 0, "aims at a living enemy unit")
	assert_gt(ud["victim_dist"], 0)
	assert_eq(Glossary.hold_text(BattleActivity.Hold.RELOADING, 29), "Reloading (29 ticks left)")


## A rifle that fired but keeps ammo left is cooling down, not reloading.
func test_cooling_down_reason() -> void:
	var s := _empty()
	var rifles := _place(s, 1, "rifle_squad", 50, 70)
	_target(s, 70, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	sim.runner.step(s)
	var urow := Centroids.units_of(s, s.squads.row_of(rifles))[0]
	assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.COOLDOWN)
	var ud: Dictionary = _unit_obs(BattleSession.observe_state(s, 1), rifles)[0]
	assert_eq(ud["hold"], BattleActivity.Hold.COOLDOWN)
	assert_eq(ud["cooldown"], 9, "aimed cooldown 10, one tick passed")
	assert_eq(ud["reload"], 0)
	assert_eq(ud["ammo"], 29, "magazine 30, one aimed shot")
	assert_eq(Glossary.hold_text(BattleActivity.Hold.COOLDOWN, 9), "Cooling down (9 ticks left)")


## The engaged target sits inside the mortar's minimum range: engaged, but
## every unit reports MIN_RANGE and no shot is fired.
func test_inside_minimum_range() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 60, 70)
	BattleSim.new().runner.step(s)
	var mrow := s.squads.row_of(mortar)
	assert_eq(s.squads.engaged[mrow], enemy, "engaged: within reach and seen")
	assert_eq(s.shot_trace.size(), 0, "too close to fire")
	for urow in Centroids.units_of(s, mrow):
		assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.MIN_RANGE)
	assert_eq(_squad_obs(BattleSession.observe_state(s, 1), mortar)["activity"], BattleActivity.Squad.READY)


## An enemy in weapon reach but beyond own sight is not spotted; once it
## leaves weapon reach there is no target at all.
func test_not_spotted_then_no_target() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 120, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	var mrow := s.squads.row_of(mortar)
	assert_eq(s.squads.engaged[mrow], -1)
	var urow := Centroids.units_of(s, mrow)[0]
	assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.NOT_SPOTTED)
	assert_eq(_squad_obs(BattleSession.observe_state(s, 1), mortar)["activity"], BattleActivity.Squad.HOLDING)
	_move_squad(s, enemy, 190, 70)
	sim.runner.step(s)
	assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.NO_TARGET)


## A moving mortar has no moving fire mode: it engages but cannot shoot.
func test_cannot_fire_while_moving() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	_target(s, 85, 70)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": mortar, "type": "move", "x": 30 * ONE, "y": 70 * ONE}]).size(), 0)
	BattleSim.new().runner.step(s)
	var mrow := s.squads.row_of(mortar)
	assert_eq(s.squads.moving[mrow], 1)
	assert_gte(s.squads.engaged[mrow], 0, "still engages while moving")
	assert_eq(s.shot_trace.size(), 0)
	for urow in Centroids.units_of(s, mrow):
		assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.NO_MOVING_FIRE)
	assert_eq(_squad_obs(BattleSession.observe_state(s, 1), mortar)["activity"], BattleActivity.Squad.MOVING)
	assert_eq(Glossary.hold_text(BattleActivity.Hold.NO_MOVING_FIRE), "Cannot fire while moving")


## Falling back holds fire: the squad code says so, every unit reports it,
## and no shot leaves the squad.
func test_falling_back_holds_fire() -> void:
	var s := _empty()
	s.trace_shots = true
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	_target(s, 85, 70)
	var sim := BattleSim.new()
	sim.runner.step(s)
	assert_gt(s.shot_trace.size(), 0, "fires before the order")
	assert_eq(BattleOrders.apply(s, 1, [{"squad": mortar, "type": "fall_back"}]).size(), 0)
	var before := s.shot_trace.size()
	sim.runner.step(s)
	assert_eq(s.shot_trace.size(), before, "falling back holds fire")
	var mrow := s.squads.row_of(mortar)
	assert_eq(s.squads.engaged[mrow], -1)
	assert_eq(_squad_obs(BattleSession.observe_state(s, 1), mortar)["activity"], BattleActivity.Squad.FALLING_BACK)
	for urow in Centroids.units_of(s, mrow):
		assert_eq(BattleActivity.hold(s, urow), BattleActivity.Hold.FALLING_BACK)
	assert_eq(Glossary.activity_text(BattleActivity.Squad.FALLING_BACK), "Falling back (holds fire)")


## Enemy squads show behaviour only: no orders, no weapon internals; their
## target shows only while seen and firing. Unseen squads stay hidden.
func test_enemy_observation_is_fog_safe() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 70, 70)
	BattleSim.new().runner.step(s)
	var obs := BattleSession.observe_state(s, 2)
	var sd := _squad_obs(obs, mortar)
	assert_false(sd.is_empty(), "the enemy sees the mortar")
	assert_eq(sd["activity"], BattleActivity.Squad.ENGAGED, "firing is observable")
	assert_eq(sd["target"], enemy, "its target is the viewer's own seen squad")
	assert_false(sd.has("order"), "orders stay hidden")
	assert_false(sd.has("engaged"))
	assert_false(sd.has("pools"))
	for ud: Dictionary in _unit_obs(obs, mortar):
		for key in ["hold", "weapon", "ammo", "reload", "cooldown", "victim"]:
			assert_false(ud.has(key), "enemy weapon internals stay hidden: " + key)
	for ud: Dictionary in _unit_obs(obs, enemy):
		assert_eq(ud["hold"], BattleActivity.Hold.UNARMED, "own units carry the report")
	var insp := Inspection.squad(s, mortar, 2)
	assert_false(insp.has("abilities"))
	assert_false(insp.has("target"))
	for ud: Dictionary in insp["units"]:
		assert_false(ud.has("hold"))
	var own_insp := Inspection.squad(s, mortar, 1)
	assert_true(own_insp.has("target"))
	assert_true((own_insp["units"] as Array)[0].has("hold"))
	# Out of sight: the squad disappears from the enemy's observation.
	_move_squad(s, mortar, 190, 70)
	BattleSim.new().runner.step(s)
	assert_true(_squad_obs(BattleSession.observe_state(s, 2), mortar).is_empty(), "unseen squads stay hidden")


## Playback frames carry the same codes per tick, and playback() keeps enemy
## internals hidden while sanitising enemy activity to behaviour only.
func test_playback_frames_carry_the_codes() -> void:
	var s := _empty()
	var mortar := _place(s, 1, "mortar_team", 50, 70)
	var enemy := _target(s, 85, 70)
	var frames: Array[PackedInt64Array] = [OverworldSession._frame(s)]
	var sim := BattleSim.new()
	for _t in 2:
		sim.runner.step(s)
		frames.append(OverworldSession._frame(s))
	var mrow := s.squads.row_of(mortar)
	var uids := {}
	for urow in Centroids.units_of(s, mrow):
		uids[s.units.id_at(urow)] = true
	# Frame 1 is after the firing tick: just fired, magazine empty.
	var f1: PackedInt64Array = frames[1]
	assert_eq(f1.size() % OverworldSession.PLAYBACK_STRIDE, 0)
	var checked := 0
	for o in range(0, f1.size(), OverworldSession.PLAYBACK_STRIDE):
		if not uids.has(f1[o]):
			continue
		checked += 1
		assert_eq(f1[o + 11], BattleActivity.Hold.NONE, "just fired")
		assert_eq(f1[o + 12], BattleActivity.Squad.ENGAGED)
		assert_eq(f1[o + 13], 30, "reload left")
		assert_eq(f1[o + 14], 60, "cooldown left")
		assert_eq(f1[o + 15], 0, "ammo")
	assert_eq(checked, 3, "all three mortarmen in the frame")
	var f2: PackedInt64Array = frames[2]
	for o in range(0, f2.size(), OverworldSession.PLAYBACK_STRIDE):
		if uids.has(f2[o]):
			assert_eq(f2[o + 11], BattleActivity.Hold.RELOADING)
			assert_eq(f2[o + 12], BattleActivity.Squad.READY)
			assert_eq(f2[o + 13], 29)
	# Through playback(): own squads full, enemy squads behaviour only.
	var os := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	assert_not_null(os)
	os._playback[99] = {"rules": s.rules, "players": PackedInt64Array([1, 2]), "frames": frames,
		"shots": [], "volleys": [], "hits": []}
	var pb1: Dictionary = os.playback(1)[99]
	var own: Dictionary = pb1["frames"][1][mortar]
	assert_eq(own["activity"], BattleActivity.Squad.ENGAGED)
	assert_eq((own["holds"] as Array)[0], BattleActivity.Hold.NONE)
	assert_eq((own["reload"] as Array)[0], 30)
	assert_false((pb1["frames"][1][enemy] as Dictionary).has("holds"), "enemy internals stay hidden")
	var pb2: Dictionary = os.playback(2)[99]
	var theirs: Dictionary = pb2["frames"][1][mortar]
	assert_false(theirs.has("holds"))
	assert_eq(theirs["activity"], BattleActivity.Squad.ENGAGED, "firing is observable")
	assert_eq((pb2["frames"][2][mortar] as Dictionary)["activity"], BattleActivity.Squad.IDLE,
		"READY would leak the engagement: sanitised to standing")


## The glossary turns every code into display text.
func test_glossary_covers_every_code() -> void:
	for code in BattleActivity.Squad.values():
		assert_false(Glossary.activity_text(code, "the enemy").is_empty())
		assert_false(Glossary.activity_text(code, "the enemy").contains("activity."), "no missing EN entry")
	for code in BattleActivity.Hold.values():
		assert_false(Glossary.hold_text(code, 3).contains("hold."), "no missing EN entry")
	assert_eq(Glossary.activity_text(BattleActivity.Squad.ENGAGED, "Rifle squad"), "Firing at Rifle squad")
