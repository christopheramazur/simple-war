extends GutTest
## Angelfall content (GDD 06 §6.9, 02 §2.11, R1Q10, R3Q17, R7Q7). Task
## sw-136.2. angelfall_frontier: Jeff starts at the town (1,4); cliffs
## wall off column 7 except the Angel blockade on (7,3); the spaceport
## (10,3) is held by Angels that can't be dispersed. angelfall_spaceport:
## the control console (45,50) opens two locked hangars (135,25 / 135,75).

const W := 12
const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


func _of(events: Array, type: StringName) -> Array:
	return events.filter(func(e: Variant) -> bool:
		return (e.type if e is SimEvent else StringName(e["type"])) == type)


func _ow() -> OverworldState:
	var r := OverworldRules.compile(_l().templates, "angelfall_frontier", _l().data_hash)
	assert_true(r.is_valid(), "; ".join(r.errors))
	var s := OverworldState.create(1, r, 5)
	for st in r.starts:
		Commanders.spawn_index(s, st["player"], st["commander"], st["plot"])
	return s


func _jeff(s: OverworldState) -> int:
	return s.commanders.ids()[0]


func test_the_roster() -> void:
	var br := BattleRules.compile(_l().templates, "angelfall_spaceport", _l().data_hash)
	assert_true(br.is_valid(), "; ".join(br.errors))
	assert_eq(br.sq_cr[br.squad_index("cr0_patrol")], 0, "robots can't take zones (R7Q7)")
	assert_eq(br.sq_cr[br.squad_index("civilian_group")], 10)
	var civ := Array(br.unit_ids).find("civilian")
	assert_eq(br.ut_weapon[civ], -1, "civilians are unarmed")
	assert_eq(br.zn_locked[br.zone_ids.find("hangar_a")], 1)


## Readies the one player through a whole turn.
func _turn_ow(x: OverworldSession) -> void:
	x.ready(1)
	x.ready(1)


func test_jeff_needs_no_battleforce_to_scatter_angels() -> void:
	var x := OverworldSession.create(_l().templates, _l().data_hash, "angelfall_frontier", 5)
	assert_not_null(x, OverworldSession.last_error)
	var s := x.state
	var j := _jeff(s)
	assert_eq(x.set_battleforce(1, j, OverworldBattleforce.NONE, PackedInt64Array(), false), "")
	assert_eq(OverworldBattleforce.pick(s, j).size(), 0, "no battleforce at all")
	s.commanders.set_value(j, &"plot", P(6, 3))
	assert_eq(x.set_route(1, j, PackedInt64Array([P(7, 3)])), "")
	_turn_ow(x)
	assert_eq(_of(x.last_events, &"guard_dispersed").size(), 1)
	assert_eq(_of(x.last_events, &"battle_started").size(), 0, "no battle: they give way")
	assert_true(x.battles.is_empty())
	assert_eq(s.vars.get("angels_dispersed", 0), 1, "counted for the campaign")
	assert_true(s.guard_at(P(7, 3)).is_empty())
	assert_eq(x.set_route(1, j, PackedInt64Array([P(8, 3)])), "", "the road is open")
	var back_on := -1
	for i in 4:
		_turn_ow(x)
		if _of(x.last_events, &"guard_returned").size() == 1:
			back_on = i
	assert_eq(back_on, 3, "gone for 3 full turns, back on the 4th")
	assert_false(s.guard_at(P(7, 3)).is_empty())


func test_the_spaceport_angels_hold() -> void:
	var s := _ow()
	var j := _jeff(s)
	OverworldBattleforce.set_plan(s, 1, j, OverworldBattleforce.NONE, PackedInt64Array(), false)
	s.commanders.set_value(j, &"plot", P(9, 3))
	OverworldOrders.set_route(s, 1, j, PackedInt64Array([P(10, 3)]))
	var ev := OverworldTurn.resolve(s)
	var errs := PackedStringArray()
	var eid := s.engagement_at(P(10, 3))
	assert_ne(eid, -1)
	assert_null(OverworldBattles.build(_l().templates, _l().data_hash, s, eid, 100, 1, errs), "nobody to fight")
	OverworldBattles.finish_unopposed(s, eid)
	assert_false(s.guard_at(P(10, 3)).is_empty(), "the final Angels can't be dispersed")
	assert_eq(_of(ev, &"guard_dispersed").size(), 0)


func test_a_normal_battleforce_fights_on_the_spaceport_field() -> void:
	var s := _ow()
	var j := _jeff(s)
	s.commanders.set_value(j, &"plot", P(9, 3))
	OverworldOrders.set_route(s, 1, j, PackedInt64Array([P(10, 3)]))
	OverworldTurn.resolve(s)
	var errs := PackedStringArray()
	var b := OverworldBattles.build(_l().templates, _l().data_hash, s, s.engagement_at(P(10, 3)), 100, 1, errs)
	assert_not_null(b, "; ".join(errs))
	assert_eq(b.scenario, "angelfall_spaceport")
	assert_false(b.rules.triggers.is_empty(), "the evacuation script comes with the battlefield")


func test_towns_produce_civilians_and_the_angels_hunt() -> void:
	var s := _ow()
	var ev := []
	for i in 4:
		ev.append_array(OverworldTurn.resolve(s))
	assert_gt(_of(ev, &"squad_produced").size(), 0)
	assert_ne(s.feature_row(P(5, 5), s.rules.feature_index("hex_angel_blockade")), -1, "turn 4: a new blockade")
	assert_eq(_of(ev, &"trigger_message").filter(func(e: SimEvent) -> bool: return e.data["rule"] == "af_intro").size(), 1)


## Moves a battle squad's units so its centre sits at (x, y) metres.
func _put(st: BattleState, sid: int, x: int, y: int) -> void:
	var row := st.squads.row_of(sid)
	var dx := x * ONE - st.squads.cx[row]
	var dy := y * ONE - st.squads.cy[row]
	for c: StringName in [&"tx", &"ax"]:
		st.squads.set_value(sid, c, x * ONE)
	for c: StringName in [&"ty", &"ay"]:
		st.squads.set_value(sid, c, y * ONE)
	for urow in st.units.count():
		if st.units.squad[urow] == sid:
			st.units.set_value(st.units.id_at(urow), &"x", st.units.x[urow] + dx)
			st.units.set_value(st.units.id_at(urow), &"y", st.units.y[urow] + dy)
	Centroids.update(st)


func _squad(s: BattleSession, template: String) -> int:
	for q: Dictionary in s.observe(1)["squads"]:
		if q["template"] == template and q["player"] == 1:
			return q["id"]
	return -1


func _turn(s: BattleSession) -> void:
	var t := s.state.turn
	var guard := 0
	while s.state.turn == t and guard < 8 and not s.is_over():
		guard += 1
		s.ready(1)
		s.ready(2)


func test_the_hangar_objective() -> void:
	var s := BattleSession.create(_l().templates, _l().data_hash, "angelfall_spaceport", 4)
	assert_not_null(s)
	var st := s.state
	var a := st.rules.zone_ids.find("hangar_a")
	var b := st.rules.zone_ids.find("hangar_b")
	# Robots alone in a hangar, civilians in the other: both locked, nothing counts.
	_put(st, _squad(s, "cr0_patrol"), 135, 75)
	_put(st, _squad(s, "civilian_group"), 135, 25)
	_turn(s)
	assert_eq(st.zone_owner[a], 0, "locked")
	# Jeff reaches the console: the planetary AI opens the hangars.
	_put(st, _squad(s, "jeff_squad"), 45, 50)
	_turn(s)
	assert_eq(st.zone_locked[a], 0)
	assert_eq(st.zone_locked[b], 0)
	_put(st, _squad(s, "cr0_patrol"), 135, 75)
	_put(st, _squad(s, "civilian_group"), 135, 25)
	_turn(s)
	assert_eq(st.zone_owner[a], 1, "civilians board")
	assert_eq(st.zone_owner[b], 0, "robots have Capture Rate 0")
	assert_gt(int(st.vars.get("shuttles", 0)), 0)
