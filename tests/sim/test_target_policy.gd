extends GutTest
## CombatSystem.pick_target (sw-txnj.1) is the choice _engage applies: asked
## from the same state, before a tick's fight phase, it names the engaged
## squad that the fight phase then sets. Pure refactor seam for the read model.

const ONE := Fixed.ONE

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


func _place(s: BattleState, player: int, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index("rifle_squad"), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


## Runs the phases that feed the fight phase, in BattleSim's order (effects,
## move, sense), then asks pick_target for every squad row before the fight
## phase runs. Returns row -> picked squad id.
func _picks_before_fight(s: BattleState) -> Dictionary:
	AbilitySystem.new().run(s)
	EffectSystem.new().run(s)
	Centroids.update(s)
	MovementSystem.new().run(s)
	Centroids.update(s)
	VisionSystem.new().run(s)
	Reactions.new().run(s)
	var picks := {}
	for row in s.squads.count():
		picks[row] = CombatSystem.pick_target(s, row)
	return picks


## Three squads: A (player 1) between B and C (both player 2). B is nearer.
func _three_squad_battle() -> Array:
	var s := BattleState.new(1, _rules(), 1)
	var sim := BattleSim.new()
	var a := _place(s, 1, 50, 70)
	var b := _place(s, 2, 62, 70)
	var c := _place(s, 2, 50, 92)
	# One full tick so sight (seen_by) is established on both sides.
	sim.runner.step(s)
	return [s, a, b, c]


func _assert_picks_match_engagement(s: BattleState, ticks: int) -> int:
	var engaged_ticks := 0
	for _t in ticks:
		var picks := _picks_before_fight(s)
		CombatSystem.new().run(s)
		for row in s.squads.count():
			assert_eq(s.squads.engaged[row], picks[row], "row %d: pick_target equals the engaged set this tick" % row)
		for row in s.squads.count():
			if picks[row] >= 0:
				engaged_ticks += 1
	return engaged_ticks


func test_pick_target_matches_engagement_nearest() -> void:
	var fixture := _three_squad_battle()
	var s: BattleState = fixture[0]
	var a: int = fixture[1]
	var b: int = fixture[2]
	var engaged := _assert_picks_match_engagement(s, 5)
	assert_gt(engaged, 0, "fixture: at least one squad engaged, so the match is not vacuous")
	assert_eq(s.squads.engaged[s.squads.row_of(a)], b, "A engages the nearer enemy B")


func test_pick_target_honours_attack_order() -> void:
	var fixture := _three_squad_battle()
	var s: BattleState = fixture[0]
	var a: int = fixture[1]
	var c: int = fixture[3]
	var row_a := s.squads.row_of(a)
	var row_c := s.squads.row_of(c)
	BattleOrders.set_order(s, row_a, BattleSquads.Order.ATTACK, s.squads.ax[row_c], s.squads.ay[row_c], c, 0)
	var picks := _picks_before_fight(s)
	assert_eq(picks[row_a], c, "an ordered attack target in sight and reach wins over the nearer enemy")
	_assert_picks_match_engagement(s, 3)
