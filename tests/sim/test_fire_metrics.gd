extends GutTest
## Fire metrics (U1 D1, sw-pd2l.1): a rifle squad against a passive no_armour
## rifle squad. The target's HP is 12 + 7 x 10 = 82, so dealt = 82 means the
## whole squad died; raw minus dealt is overkill plus wasted fire. The numbers
## pin today's picker (CombatSystem._nearest_target).

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


## Battle metrics for one rifle squad (player 1) ordered to attack a passive
## rifle squad (player 2) that wears no armour and cannot shoot back.
func _duel() -> Dictionary:
	var r := _rules()
	var s := BattleState.new(1, r, 1)
	var rifle := r.squad_index("rifle_squad")
	var no_armour: Array = []
	for i in r.sq_members[rifle].size():
		no_armour.append({"defense": "no_armour"})
	var a := BattleSetup.spawn_squad(s, 1, rifle, 50 * ONE, 70 * ONE, 0)
	var b := BattleSetup.spawn_squad(s, 2, rifle, 70 * ONE, 70 * ONE, 0, -1, no_armour)
	Centroids.update(s)
	for urow in Centroids.units_of(s, s.squads.row_of(b)):
		s.units.set_value(s.units.id_at(urow), &"weapon", -1)
	BattleOrders.set_order(s, s.squads.row_of(a), BattleSquads.Order.ATTACK, 0, 0, b, 0)
	var sim := BattleSim.new()
	var m := SimMetrics.new()
	m.watch_battle(s, sim)
	for _t in 40:
		if s.is_over():
			break
		sim.execute_turn(s)
	var out := {}
	for row: Dictionary in m.battle(s, sim):
		out["%s|%d" % [row["metric"], row["player"]]] = row["value"]
	return out


func test_rifle_squad_against_passive_no_armour_squad() -> void:
	var v := _duel()
	assert_eq(v["fire.raw|1"], 96.0, "display points, not fixed-point")
	assert_eq(v["fire.dealt|1"], 82.0)
	# 60 ticks under today's picker (sw-pd2l.1 acceptance). Before main's
	# firing-position change (sw-txnj.5, MOVING_TO_FIRE) the first kill came at
	# 55 ticks: the squad now walks to a firing position before its first shot.
	assert_eq(v["fire.first_kill_ticks|1"], 60.0)
	assert_eq(v["fire.dealt|1"] + v["fire.overkill|1"] + v["fire.wasted_damage|1"] + v["fire.mitigation|1"],
		v["fire.raw|1"], "every queued point is dealt, overkill, wasted or mitigated")


func test_kills_and_wipes_count_enemy_units_only() -> void:
	# U1 D6: every unit the attacker killed is a kill; a wipe is a tick in
	# which half or more of a squad's start members die. Nothing is killed
	# on the attacker's side, so player 1 owns all the kills.
	var v := _duel()
	var members := float(_rules().sq_members[_rules().squad_index("rifle_squad")].size())
	assert_eq(v["fire.kills|1"], members, "the passive squad's units all die")
	assert_eq(v["fire.kills|2"], 0.0, "the passive squad kills nothing")
	assert_true(v["fire.wipes|1"] >= 0.0 and v["fire.wipes|1"] <= 1.0, "at most one wipe per squad killed")
