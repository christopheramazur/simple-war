extends GutTest
## Scenario `placed` squads and the fixed deployment (sw-bafi.15, sw-tdz, U1Q31):
## entries are storage, default places (the player may move them unless
## `locked`), validated at compile; the rest deal evenly over the area; overworld
## battles ignore them; a fixed scenario never deploys.

static var _loader: PackageLoader
static var _core: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _packaged() -> PackageLoader:
	if _core == null:
		_core = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _core


func _f(v: float) -> int:
	return int(round(v * Fixed.ONE))


## duel_crossroads as scenario "t", with `placed` and `extra` laid over it.
func _table(placed: Array, extra: Dictionary = {}) -> TemplateTable:
	var defs := _l().defs.duplicate()
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["placed"] = placed
	sc.merge(extra, true)
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	return TemplateTable.build(defs)


func _rules(placed: Array, extra: Dictionary = {}) -> BattleRules:
	return BattleRules.compile(_table(placed, extra), "t", _l().data_hash)


func _session(r: BattleRules) -> BattleSession:
	var s := BattleSession.new()
	s._setup(r, "t", 11, _l().data_hash, null)
	s.clock.start()
	s._pump()
	return s


## Side 1's squads, as squad IDs in list order.
func _side_ids(s: BattleSession, player: int) -> Array:
	var out := []
	for row in s.state.squads.count():
		if s.state.squads.player[row] == player:
			out.append(s.state.squads.id_at(row))
	return out


func _row(s: BattleSession, sid: int) -> int:
	return s.state.squads.row_of(sid)


func _finish_turn(s: BattleSession) -> void:
	s.ready(1)
	s.ready(2)
	if s.phase_name() == "REACTION":
		s.ready(1)
		s.ready(2)


## A placed squad's entry, as the rules store it.
func _entry(r: BattleRules, player: int, squad_id: String) -> Dictionary:
	for p: Dictionary in r.sides[0 if player == 1 else 1]["placed"]:
		if p["squad"] == r.squad_index(squad_id):
			return p
	return {}


# --- storage and the fixed deployment -----------------------------------------

func test_storage_keeps_point_facing_default_and_lock() -> void:
	var r := _rules([
		{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30},
		{"side": 2, "squad": "scout_team", "x": 180, "y": 40, "facing": 4096, "locked": true},
	])
	assert_true(r.is_valid(), str(r.errors))
	var a := _entry(r, 1, "heavy_weapons_team")
	assert_eq([a["x"], a["y"], a["facing"], a["locked"]],
		[_f(12), _f(30), r.sides[0]["facing"], false], "facing defaults to the side's")
	var b := _entry(r, 2, "scout_team")
	assert_eq([b["x"], b["y"], b["facing"], b["locked"]], [_f(180), _f(40), 4096, true])


func test_no_placed_list_keeps_the_even_deal_rules() -> void:
	var r := _rules([])
	assert_true(r.is_valid(), str(r.errors))
	assert_eq((r.sides[0]["placed"] as Array).size(), 0)


func test_fixed_scenario_never_deploys() -> void:
	var r := _rules([], {"deployment": "fixed"})
	assert_true(r.is_valid(), str(r.errors))
	assert_false(_session(r).state.deploying)
	var core := _packaged()
	var ang := BattleRules.compile(core.templates, "angelfall_spaceport", core.data_hash)
	assert_true(ang.is_valid(), str(ang.errors))
	assert_false(ang.deployment_open, "Angelfall is fixed")
	assert_false(_session(ang).state.deploying)


# --- validation at compile ----------------------------------------------------

func test_refused_outside_its_side_area() -> void:
	var r := _rules([{"side": 1, "squad": "rifle_squad", "x": 100, "y": 30}])
	assert_false(r.is_valid())
	assert_string_contains(r.errors[0], "outside its side's deployment area")


func test_refused_squad_placed_twice_on_one_side() -> void:
	var r := _rules([
		{"side": 1, "squad": "rifle_squad", "x": 10, "y": 30},
		{"side": 1, "squad": "rifle_squad", "x": 10, "y": 40},
	])
	assert_false(r.is_valid())
	assert_string_contains(r.errors[0], "squad placed twice")


func test_refused_two_entries_on_one_cell() -> void:
	var r := _rules([
		{"side": 1, "squad": "rifle_squad", "x": "10.2", "y": "30.1"},
		{"side": 1, "squad": "scout_team", "x": "10.8", "y": "30.9"},
	])
	assert_false(r.is_valid())
	assert_string_contains(r.errors[0], "two placed squads on cell")


func test_refused_squad_its_side_does_not_list_and_unknown_side() -> void:
	var r := _rules([{"side": 2, "squad": "jeff_squad", "x": 180, "y": 30}])
	assert_false(r.is_valid())
	assert_string_contains(r.errors[0], "does not list it")
	var no_side := _rules([{"side": 7, "squad": "rifle_squad", "x": 10, "y": 30}])
	assert_string_contains(no_side.errors[0], "no side has player 7")


func test_schema_checks_a_placed_entry() -> void:
	var good := DataSchema.validate(_table([{"side": 1, "squad": "rifle_squad", "x": 10, "y": 30}]))
	var bad := DataSchema.validate(_table([{"side": 1, "squad": "rifle_squad", "y": 30}]))
	assert_gt(bad.size(), good.size(), "a missing x is a schema error")


# --- placement -----------------------------------------------------------------

func test_placed_squad_stands_on_its_cell_and_the_rest_deal_evenly() -> void:
	var r := _rules([{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30}])
	assert_true(r.is_valid(), str(r.errors))
	var s := _session(r)
	var ids := _side_ids(s, 1)
	var sq := s.state.squads
	var heavy := r.squad_index("heavy_weapons_team")
	var d: PackedInt64Array = r.sides[0]["deploy"]
	# duel_crossroads side 1: rifle, rifle, heavy, marksman, scout. Heavy is placed
	# (index 2), so the other four deal over the area in list order.
	var k := 0
	for i in ids.size():
		var row := _row(s, ids[i])
		var st := sq.tmpl[row]
		if st == heavy:
			var at := BattleSetup.open_point(r, st, _f(12), _f(30))
			assert_eq([sq.ax[row], sq.ay[row]], [at[0], at[1]], "placed at its cell")
			continue
		var ay := d[1] + Fixed.round_div(d[3] * (2 * k + 1), 2 * 4)
		var want := BattleSetup.open_point(r, st, d[0] + d[2] / 2, ay)
		assert_eq([sq.ax[row], sq.ay[row]], [want[0], want[1]], "even deal, slot %d" % k)
		k += 1
	assert_eq(k, 4)


func test_placed_squad_goes_to_the_nearest_enterable_cell() -> void:
	var r := _rules([{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30}])
	assert_true(r.is_valid(), str(r.errors))
	var wall := r.feature_ids.find("wall")
	assert_ne(wall, -1)
	var cell := 30 * r.width + 12
	r.terrain[cell] = wall
	var s := _session(r)
	var heavy := r.squad_index("heavy_weapons_team")
	var row := -1
	for i in s.state.squads.count():
		if s.state.squads.tmpl[i] == heavy and s.state.squads.player[i] == 1:
			row = i
	var ax: int = s.state.squads.ax[row]
	var ay: int = s.state.squads.ay[row]
	var ccx := Fixed.to_int_floor(ax)
	var ccy := Fixed.to_int_floor(ay)
	assert_ne(r.terrain[ccy * r.width + ccx], wall, "stands on an enterable cell")
	assert_true(absi(ccx - 12) <= 1 and absi(ccy - 30) <= 1, "the nearest one to its point")


# --- overworld and planner -------------------------------------------------------

func test_overworld_sides_ignore_placed() -> void:
	var with := _rules([{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30}])
	var without := _rules([])
	var squads := PackedInt64Array([with.squad_index("heavy_weapons_team"), with.squad_index("rifle_squad")])
	var alive := PackedInt64Array()
	var overworld_side := OverworldBattles._side(with.sides, 0, 1, squads, alive)
	assert_false(overworld_side.has("placed"), "overworld sides carry no placed entries")
	var state_with := BattleState.new(1, with, 0)
	var state_without := BattleState.new(1, without, 0)
	var plain_side := OverworldBattles._side(without.sides, 0, 1, squads, alive)
	var a := BattleSetup.deploy_side(state_with, overworld_side)
	var b := BattleSetup.deploy_side(state_without, plain_side)
	var anchors_a := []
	var anchors_b := []
	for sid in a:
		anchors_a.append([state_with.squads.ax[state_with.squads.row_of(sid)], state_with.squads.ay[state_with.squads.row_of(sid)]])
	for sid in b:
		anchors_b.append([state_without.squads.ax[state_without.squads.row_of(sid)], state_without.squads.ay[state_without.squads.row_of(sid)]])
	assert_eq(anchors_a, anchors_b, "the even deal, as with no placed list")


func test_planner_reads_the_positions_after_deployment() -> void:
	var r := _rules([{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30}])
	var s := _session(r)
	var heavy_id := 0
	for sid in _side_ids(s, 1):
		if s.state.squads.tmpl[_row(s, sid)] == r.squad_index("heavy_weapons_team"):
			heavy_id = sid
	var before := BattleSession.observe_state(s.state, 1)
	var moved := _f(20)
	assert_eq(s.submit_deployment(1, [{"squad": heavy_id, "x": moved, "y": _f(30), "facing": 0}]).size(), 0)
	_finish_turn(s)
	var after := BattleSession.observe_state(s.state, 1)
	var row_b := _find(before, heavy_id)
	var row_a := _find(after, heavy_id)
	assert_ne(row_b["x"], row_a["x"], "the observation follows the battle state")
	assert_eq(row_a["x"], s.state.squads.cx[_row(s, heavy_id)])


func _find(obs: Dictionary, sid: int) -> Dictionary:
	for d: Dictionary in obs["squads"]:
		if int(d["id"]) == sid:
			return d
	return {}


# --- locked and unlocked defaults ----------------------------------------------

func test_locked_placed_squad_refuses_a_placement() -> void:
	var r := _rules([{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30, "locked": true}])
	var s := _session(r)
	var heavy_id := 0
	for sid in _side_ids(s, 1):
		if s.state.squads.tmpl[_row(s, sid)] == r.squad_index("heavy_weapons_team"):
			heavy_id = sid
	assert_true(s.state.pinned.has(heavy_id))
	var errs := s.submit_deployment(1, [{"squad": heavy_id, "x": _f(20), "y": _f(30), "facing": 0}])
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "locked")


func test_unlocked_placed_squad_is_a_default_the_player_can_move() -> void:
	var r := _rules([{"side": 1, "squad": "heavy_weapons_team", "x": 12, "y": 30}])
	var s := _session(r)
	var heavy_id := 0
	for sid in _side_ids(s, 1):
		if s.state.squads.tmpl[_row(s, sid)] == r.squad_index("heavy_weapons_team"):
			heavy_id = sid
	assert_false(s.state.pinned.has(heavy_id))
	var errs := s.submit_deployment(1, [{"squad": heavy_id, "x": _f(20), "y": _f(30), "facing": 0}])
	assert_eq(errs.size(), 0, str(errs))
	_finish_turn(s)
	var row := _row(s, heavy_id)
	var want := BattleDeploy.open_point_in(r, s.state.squads.tmpl[row], _f(20), _f(30), BattleDeploy.area(s.state, 1))
	assert_eq([s.state.squads.ax[row], s.state.squads.ay[row]], [want[0], want[1]])
