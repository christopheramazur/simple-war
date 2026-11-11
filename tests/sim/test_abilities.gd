extends GutTest
## Abilities: toggles, upkeep and auto-off, planning-order validation,
## readying and its loss, reactions as abilities, rules text (GDD 02 §2.13,
## E2Q10, E3Q6, E3Q7). Task sw-ps1.5.

const ONE := Fixed.ONE

static var _core: BattleRules
static var _dig: BattleRules


func _rules() -> BattleRules:
	if _core == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_core = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _core


## Core rules where rifle squads also know "dig_in" (a readying ability the
## core roster doesn't use yet).
func _dig_rules() -> BattleRules:
	if _dig == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_dig = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
		var st := _dig.squad_index("rifle_squad")
		var list := _dig.sq_abilities[st].duplicate()
		list.append(Array(_dig.ab_ids).find("dig_in"))
		_dig.sq_abilities[st] = list
	return _dig


func _place(s: BattleState, player: int, squad: String, x: int, y: int = 50) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _aid(s: BattleState, sid: int, ability: String) -> int:
	return Abilities.find(s, sid, Abilities.index_of(s, ability))


func _tick(s: BattleState) -> void:
	AbilitySystem.new().run(s)
	EffectSystem.new().run(s)
	HealthSystem.new().run(s)
	s.commands.apply(s)
	Centroids.update(s)
	s.end_tick()


func _events(s: BattleState, type: StringName) -> Array:
	return s.turn_log.filter(func(e: SimEvent) -> bool: return e.type == type)


func test_core_abilities_compile() -> void:
	var r := _rules()
	assert_true(r.is_valid(), str(r.errors))
	var cloak := Array(r.ab_ids).find("scout_cloak")
	assert_eq(r.ab_toggle[cloak], 1)
	assert_eq(r.ab_default_on[cloak], 0, "sinks Instinct: starts off")
	assert_eq(r.ab_default_on[Array(r.ab_ids).find("field_camo")], 1, "sinks nothing: starts on (R7Q4)")
	assert_eq(r.ab_reaction[Array(r.ab_ids).find("halt")], 1)
	assert_eq(r.ab_costs[Array(r.ab_ids).find("halt")][BattleSquads.INSTINCT], 8 * ONE)


func test_toggle_upkeep_and_view() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "scout_team", 20)
	var row := s.squads.row_of(sid)
	var cloak := _aid(s, sid, "scout_cloak")
	assert_eq(s.abilities.get_value(cloak, &"on"), 0)
	assert_eq(s.abilities.get_value(_aid(s, sid, "auspex"), &"on"), 1, "auspex sinks nothing: on")
	var before := Pools.value(s, row, BattleSquads.INSTINCT)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": sid, "abilities": [{"id": "scout_cloak", "on": true}]}]).size(), 0)
	AbilitySystem.new().run(s)
	assert_eq(Pools.value(s, row, BattleSquads.INSTINCT), before - Fixed.round_div(2 * ONE, 10), "2 Instinct per second")
	assert_true(s.ledger.has("%d|%d|ability_scout_cloak" % [sid, BattleSquads.INSTINCT]))
	var view := Abilities.view(s, sid)
	var by_id := {}
	for v: Dictionary in view:
		by_id[v["id"]] = v
	assert_true(by_id["scout_cloak"]["on"])
	assert_true(by_id["halt"]["reaction"])
	BattleOrders.apply(s, 1, [{"squad": sid, "abilities": [{"id": "scout_cloak", "on": false}]}])
	assert_eq(s.abilities.get_value(cloak, &"on"), 0)
	assert_eq(s.effects.count(), 1, "only auspex's bundle remains")


func test_concealment_stat_from_bundle_conditions() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "marksman_team", 20, 75)
	var row := s.squads.row_of(sid)
	var vis := VisionSystem.new()
	EffectSystem.new().run(s)
	assert_eq(vis.concealment_pct(s, row), 20)
	s.squads.set_value(sid, &"moving", 1)
	EffectSystem.new().run(s)
	assert_eq(vis.concealment_pct(s, row), 5, "20 - 15 while moving")
	s.squads.set_value(sid, &"fired_tick", s.tick)
	EffectSystem.new().run(s)
	assert_eq(vis.concealment_pct(s, row), 0, "firing: clamped at 0")


func test_concealment_on_feature() -> void:
	var r := _rules()
	var forest := Array(r.feature_ids).find("forest")
	var cell := Array(r.terrain).find(forest)
	if forest < 0 or cell < 0:
		pending("no forest on this map")
		return
	var s := BattleState.new(1, r, 1)
	var sid := _place(s, 1, "marksman_team", cell % r.width + 5, cell / r.width + 5)
	var row := s.squads.row_of(sid)
	assert_eq(r.feature_at(s.squads.cx[row], s.squads.cy[row]), forest, "standing in the forest")
	EffectSystem.new().run(s)
	assert_eq(VisionSystem.new().concealment_pct(s, row), 40, "20 + 20 in forest")


func test_order_validation() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var rifles := _place(s, 1, "rifle_squad", 20)
	var scouts := _place(s, 1, "scout_team", 20, 80)
	var errs := BattleOrders.apply(s, 1, [
		{"squad": rifles, "abilities": [{"id": "dig_in"}]},
		{"squad": rifles, "abilities": [{"id": "halt"}]},
		{"squad": scouts, "abilities": [{"id": "scout_cloak"}]},
		{"squad": scouts, "abilities": "scout_cloak"},
		{"squad": scouts, "abilities": [{"on": true}]},
	])
	assert_eq(errs.size(), 5, "\n".join(errs))
	assert_string_contains(errs[0], "squad has no ability 'dig_in'")
	assert_string_contains(errs[1], "is a reaction")
	assert_string_contains(errs[2], "needs on: true or false")
	assert_string_contains(errs[3], "abilities must be a list")
	assert_string_contains(errs[4], "needs an id")


func test_reaction_needs_its_cost() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 40)
	var b := _place(s, 2, "rifle_squad", 60)
	Pools.flow(s, s.squads.row_of(a), BattleSquads.INSTINCT, -1000 * ONE, &"test")
	assert_string_contains(Reactions.queue(s, a, "fall_back", b), "not enough instinct")
	assert_string_contains(Reactions.queue(s, a, "dig_in", b), "squad cannot dig_in")
	assert_eq(Reactions.available(s, s.squads.row_of(a)), [], "nothing affordable")


func test_reactions_are_abilities() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, "rifle_squad", 40)
	var b := _place(s, 2, "rifle_squad", 60)
	var arow := s.squads.row_of(a)
	Abilities.react(s, _aid(s, a, "retarget"), b)
	assert_eq(s.squads.order[arow], BattleSquads.Order.ATTACK)
	assert_eq(s.squads.target[arow], b, "attacks the trigger ('other')")
	assert_true(s.ledger.has("%d|%d|reaction" % [a, BattleSquads.INSTINCT]))
	assert_eq(s.effects.count(), 0, "instant bundle released")
	for _i in 2:
		BattleOrders.set_order(s, arow, BattleSquads.Order.MOVE, 0, 0, -1, 0)
		Abilities.react(s, _aid(s, a, "halt"), b)
		assert_eq(s.squads.order[arow], BattleSquads.Order.HOLD, "halts every time")


func test_readying_then_readied_state() -> void:
	var s := BattleState.new(1, _dig_rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 40)
	var row := s.squads.row_of(sid)
	var dig := _aid(s, sid, "dig_in")
	var prowess := Pools.value(s, row, BattleSquads.PROWESS)
	assert_eq(BattleOrders.apply(s, 1, [{"squad": sid, "type": "hold", "abilities": [{"id": "dig_in"}]}]).size(), 0)
	assert_eq(s.abilities.get_value(dig, &"ready_at"), 30, "3 s at 10 ticks/s")
	assert_eq(s.effects.count(), 0, "readying: not dug in yet")
	for _i in 32:
		_tick(s)
	assert_eq(_events(s, &"ability_ready").size(), 1)
	assert_almost_eq(prowess - Pools.value(s, row, BattleSquads.PROWESS), 6 * ONE, ONE / 2, "Prowess Vacuum 2/s for 3 s")
	var urow := Centroids.units_of(s, row)[0]
	var base := Fixed.from_int(5)
	assert_eq(Stats.unit(s, urow, &"defense.evasion_pct", base), base + 15 * ONE, "dug in: +15 evasion")
	assert_string_contains(Abilities.validate_use(s, row, {"id": "dig_in"}), "cooling down")
	s.squads.set_value(sid, &"moving", 1)
	_tick(s)
	assert_eq(s.abilities.get_value(dig, &"on"), 0, "moving loses the readied state")
	assert_eq(s.effects.count(), 0)


func test_interrupting_readying_floats_the_interrupter() -> void:
	var s := BattleState.new(1, _dig_rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 40)
	var foe := _place(s, 2, "rifle_squad", 60)
	BattleOrders.apply(s, 1, [{"squad": sid, "abilities": [{"id": "dig_in"}]}])
	_tick(s)
	var victim := s.units.id_at(Centroids.units_of(s, s.squads.row_of(sid))[0])
	Health.queue(s, -1, foe, victim, sid, ONE, 0)
	_tick(s)
	assert_eq(s.abilities.get_value(_aid(s, sid, "dig_in"), &"on"), 0)
	assert_eq(_events(s, &"ability_interrupted").size(), 1)
	assert_true(s.ledger.has("%d|%d|interrupt" % [foe, BattleSquads.PROWESS]), "interrupter floats Prowess (R7Q3)")


func test_rules_text() -> void:
	var r := _rules()
	var cloak := RulesText.ability_lines(r, Array(r.ab_ids).find("scout_cloak"))
	assert_eq(cloak[0], "Toggle.")
	assert_eq(cloak[1], "Sinks 2 Instinct per second while on; switches off at Broken Instinct.")
	assert_eq(cloak[2], "+45% Concealment")
	assert_eq(cloak[3], "+30% Concealment in Forest")
	assert_eq(cloak[5], "-10% Concealment while moving")
	assert_eq(RulesText.ability_lines(r, Array(r.ab_ids).find("retarget")), PackedStringArray(["Reaction.", "Costs 6 Instinct.", "Attacks them"]))
	assert_eq(RulesText.ability_lines(r, Array(r.ab_ids).find("dig_in")), PackedStringArray([
		"Cooldown 10 s.", "Readies for 3 s (sinks 2 Prowess per second), then:", "Lost on moving or taking damage.",
		"+15% Evasion", "Lasts 2 turns."]))


func test_abilities_are_deterministic_through_save() -> void:
	var s := BattleState.new(1, _dig_rules(), 1)
	var a := _place(s, 1, "rifle_squad", 40)
	_place(s, 1, "scout_team", 30, 70)
	_place(s, 2, "rifle_squad", 70)
	BattleOrders.apply(s, 1, [{"squad": a, "abilities": [{"id": "dig_in"}]}])
	var sim := BattleSim.new()
	for _i in 10:
		sim.runner.step(s)
	var copy := BattleState.new(1, _dig_rules(), 1)
	copy.restore(s.snapshot())
	Centroids.update(copy)
	for _i in 40:
		sim.runner.step(s)
		sim.runner.step(copy)
	assert_eq(copy.state_hash_hex(), s.state_hash_hex())
