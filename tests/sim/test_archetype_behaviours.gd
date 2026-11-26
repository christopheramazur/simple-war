extends GutTest
## The archetype behaviours are data (GDD 02 §2.15, U1 draft 01 §3.2, sw-txnj.11):
## humanity.json gives mortars a stand-off band of min_range + 5 m, marksmen a
## max band of range - 5 m, and assault squads a wider coherency radius. These
## tests read what the core package compiles to and check the band holds in play.

const ONE := Fixed.ONE
const LANE := 80

static var _loader: PackageLoader
static var _base: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules() -> BattleRules:
	if _base == null:
		_base = BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	return _base


func _place(s: BattleState, player: int, squad: String, x: int, y: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index(squad), x * ONE, y * ONE, facing)
	Centroids.update(s)
	return sid


## An unarmed, 1000-HP squad that stands still.
func _dummy(s: BattleState, x: int, y: int) -> int:
	var sid := _place(s, 2, "rifle_squad", x, y, Fixed.ANGLE_HALF)
	for urow in Centroids.units_of(s, s.squads.row_of(sid)):
		var id := s.units.id_at(urow)
		s.units.set_value(id, &"weapon", -1)
		s.units.set_value(id, &"hp", 1000 * ONE)
		s.units.set_value(id, &"hp_max", 1000 * ONE)
	return sid


func _order(s: BattleState, sid: int, order: int, x: int, y: int, target: int = -1) -> void:
	BattleOrders.set_order(s, s.squads.row_of(sid), order, x * ONE, y * ONE, target, 0)


func test_mortar_team_stands_off_at_min_range_plus_5() -> void:
	var r := _rules()
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "mortar_team", 40, LANE, 0)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 80, LANE)
	var i := FiringPositions.bh(s, s.squads.row_of(me))
	assert_eq(r.bh_keep_min[i], 25 * ONE, "keep_distance min_m is the mortar's 20 m minimum range + 5 m")
	assert_eq(r.bh_keep_max[i], -1, "no maximum band")
	assert_eq(r.bh_fire_on_move[i], 0, "mortars never fire on the move")
	assert_eq(r.bh_stand_reloading[i], 1, "mortars stand while their tubes reload")


func test_mortar_team_backs_out_of_its_minimum_range() -> void:
	# 22 m from the target: inside the band (20 m minimum range + 5 m), so the
	# team backs out to 25 m and stays there.
	var s := BattleState.new(1, _rules(), 1)
	var me := _place(s, 1, "mortar_team", 40, LANE, 0)
	var foe := _dummy(s, 62, LANE)
	_order(s, me, BattleSquads.Order.ATTACK, 40, LANE, foe)
	var row := s.squads.row_of(me)
	var frow := s.squads.row_of(foe)
	var sim := BattleSim.new()
	for i in 300:
		sim.runner.step(s)
		Centroids.update(s)
	var d := Fixed.distance(s.squads.cx[row], s.squads.cy[row], s.squads.cx[frow], s.squads.cy[frow])
	assert_true(d >= 24 * ONE, "backed out to the 25 m band: %d" % d)
	assert_true(d <= 27 * ONE, "and no farther: %d" % d)


func test_marksman_team_stops_within_5_m_of_its_range() -> void:
	var r := _rules()
	var s := BattleState.new(1, r, 1)
	var me := _place(s, 1, "marksman_team", 5, LANE, 0)
	_order(s, me, BattleSquads.Order.ATTACK_MOVE, 80, LANE)
	var i := FiringPositions.bh(s, s.squads.row_of(me))
	assert_eq(r.bh_keep_max[i], 65 * ONE, "keep_distance max_m is the 70 m marksman rifle range - 5 m")
	assert_eq(r.bh_keep_min[i], -1, "no minimum band")


func test_assault_squad_has_wider_coherency_than_the_line() -> void:
	var r := _rules()
	var s := BattleState.new(1, r, 1)
	var assault := _place(s, 1, "assault_squad", 20, LANE, 0)
	var line := _place(s, 1, "rifle_squad", 20, 60, 0)
	_order(s, assault, BattleSquads.Order.ATTACK_MOVE, 80, LANE)
	_order(s, line, BattleSquads.Order.ATTACK_MOVE, 80, 60)
	var ai := FiringPositions.bh(s, s.squads.row_of(assault))
	var li := FiringPositions.bh(s, s.squads.row_of(line))
	var a_row := s.squads.row_of(assault)
	var l_row := s.squads.row_of(line)
	assert_eq(r.bh_coherency[ai], r.sq_coherency[s.squads.tmpl[a_row]] + 3 * ONE, "assault: formation radius + 3 m")
	assert_eq(r.bh_coherency[li], r.sq_coherency[s.squads.tmpl[l_row]], "line: the A3 default radius")
