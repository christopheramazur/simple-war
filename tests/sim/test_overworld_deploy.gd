extends GutTest
## Deployment through the overworld Game API (sw-bafi.11): drafts for a battle
## while it deploys, logged as battle_deploy inputs, kept through saves and
## rebuilds, ignored when the battle is gone, automatic places on an empty
## draft, and the deployment fields of the battle observation.

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


## Player 1's field commander attacks the bandit camp: a battle in Planning
## of the turn after it starts (as in test_overworld_reactions).
func _session() -> OverworldSession:
	var s := OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7)
	var a := Commanders.spawn(s.state, 1, "field_commander", P(12, 4))
	assert_eq(s.set_route(1, a, PackedInt64Array([P(11, 3)])), "")
	_ready_all(s)
	_ready_all(s)
	assert_eq(s.battles.size(), 1, "the battle has begun")
	assert_eq(s.clock.phase, PulseClock.Phase.PLANNING)
	return s


func _ready_all(s: OverworldSession) -> void:
	for p in s.players():
		s.ready(p)


## Readies through the turn until the next Planning.
func _next_planning(s: OverworldSession) -> void:
	_ready_all(s)
	for i in 10:
		if s.clock.phase == PulseClock.Phase.PLANNING:
			return
		_ready_all(s)


func _eid(s: OverworldSession) -> int:
	return s.battles.keys()[0]


func _state(s: OverworldSession, eid: int) -> BattleState:
	return (s.battles[eid] as OverworldBattle).state


## Player's squads in the battle (battle squad IDs).
func _own(s: OverworldSession, eid: int, player: int) -> Array:
	var st := _state(s, eid)
	var out := []
	for row in st.squads.count():
		if st.squads.player[row] == player:
			out.append(st.squads.id_at(row))
	return out


## A placement of `squad` at the centre of player's deployment area.
func _centre(s: OverworldSession, eid: int, player: int, squad: int) -> Dictionary:
	var rect := BattleDeploy.area(_state(s, eid), player)
	return {"squad": squad, "x": rect[0] + rect[2] / 2, "y": rect[1] + rect[3] / 2, "facing": 0}


func test_observation_shows_deploying_and_areas() -> void:
	var s := _session()
	var eid := _eid(s)
	var o := s.observe_battle(1, eid)
	assert_true(o["deploying"])
	assert_eq((o["areas"] as Array).size(), _state(s, eid).rules.sides.size())
	assert_eq((o["area"] as Array).size(), 4, "the player's own area")
	assert_eq(o["area"], Array(BattleDeploy.area(_state(s, eid), 1)))


func test_draft_is_logged_and_applies_at_reveal() -> void:
	var s := _session()
	var eid := _eid(s)
	var sid: int = _own(s, eid, 1)[0]
	var errs := s.submit_battle_deployment(1, eid, [_centre(s, eid, 1, sid)])
	assert_eq(errs.size(), 0, str(errs))
	assert_eq((s.battles[eid] as OverworldBattle).deploys[1].size(), 1)
	var last: Dictionary = s.input_log[-1]
	assert_eq(last["kind"], "battle_deploy")
	assert_eq(last["payload"]["engagement"], eid)
	_next_planning(s)
	assert_true(s.battles.has(eid), "the battle goes on")
	assert_false(_state(s, eid).deploying, "cleared at Reveal")
	assert_true((s.battles[eid] as OverworldBattle).deploys.is_empty())


func test_refused_outside_planning_and_unknown_battle() -> void:
	var s := _session()
	var eid := _eid(s)
	var errs := s.submit_battle_deployment(1, 9999, [])
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "not in that battle")
	var sid: int = _own(s, eid, 1)[0]
	var bad := s.submit_battle_deployment(1, eid, [{"squad": sid, "x": 0, "y": 0, "facing": 0}])
	assert_eq(bad.size(), 1, "outside the area is refused")
	assert_eq((s.battles[eid] as OverworldBattle).deploys[1].size(), 0, "nothing kept")


func test_save_mid_deployment_reloads_with_drafts() -> void:
	var s := _session()
	var eid := _eid(s)
	var sid: int = _own(s, eid, 1)[0]
	s.submit_battle_deployment(1, eid, [_centre(s, eid, 1, sid)])
	var bytes := s.save()
	var loaded := OverworldSession.load_save(bytes, _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	if loaded == null:
		return
	assert_eq((loaded.battles[eid] as OverworldBattle).deploys, (s.battles[eid] as OverworldBattle).deploys)
	assert_true(loaded.observe_battle(1, eid)["deploying"])


func test_rebuild_with_deployments_reproduces_hashes() -> void:
	var placing := _PlacingExpand.new(1)
	var s := HeadlessOverworld.play(OverworldSession.create(_l().templates, _l().data_hash, "test_vale", 7),
		{1: placing, 2: ExpandController.new(2)}, 8)
	var n := 0
	for e: Dictionary in s.input_log:
		if e["kind"] == "battle_deploy":
			n += 1
	assert_gt(n, 0, "the run deployed in a battle")
	var rebuilt := OverworldSession.rebuild(s.save(), _l().templates, _l().data_hash)
	assert_not_null(rebuilt, OverworldSession.last_error)
	if rebuilt != null:
		assert_eq(rebuilt.state_hash_hex(), s.state_hash_hex())


func test_orphan_deploy_input_has_no_effect_on_replay() -> void:
	var s := _session()
	var before_hash := s.state_hash_hex()
	var before_log := s.input_log.size()
	var orphan := {"turn": s.state.turn + 1, "phase": PulseClock.Phase.PLANNING, "player": 1,
		"kind": "battle_deploy", "payload": {"engagement": 9999, "placements": []}}
	s.replay_inputs([orphan])
	assert_eq(s.state_hash_hex(), before_hash)
	assert_eq(s.input_log.size(), before_log, "a refused draft is not logged")


func test_empty_draft_is_the_automatic_places() -> void:
	var auto := _session()
	var empty := _session()
	var eid := _eid(empty)
	assert_eq(empty.submit_battle_deployment(1, eid, []).size(), 0)
	_next_planning(auto)
	_next_planning(empty)
	assert_eq(empty.state_hash_hex(), auto.state_hash_hex(), "no placements: the automatic places")


func test_placement_changes_the_battle() -> void:
	var auto := _session()
	var placed := _session()
	var eid := _eid(placed)
	var sid: int = _own(placed, eid, 1)[0]
	placed.submit_battle_deployment(1, eid, [_centre(placed, eid, 1, sid)])
	_next_planning(auto)
	_next_planning(placed)
	assert_ne(placed.state_hash_hex(), auto.state_hash_hex())


func test_headless_controller_with_deploy_hook_places_squads() -> void:
	var s := _session()
	var eid := _eid(s)
	var placer := _PlacingExpand.new(1)
	HeadlessOverworld.plan_for(s, 1, placer)
	assert_gt(placer.seen, 0, "the hook saw the deploying battle")
	var kinds := []
	for e: Dictionary in s.input_log:
		kinds.append(e["kind"])
	assert_has(kinds, "battle_deploy")
	assert_eq((s.battles[eid] as OverworldBattle).deploys[1].size(), 1)


## An expand controller that also places its first squad at its area's centre.
class _PlacingExpand extends ExpandController:
	var seen := 0

	func deploy(obs: Dictionary) -> Array:
		seen += 1
		var area: Array = obs["area"]
		for sq: Dictionary in obs["squads"]:
			if int(sq["player"]) == 1:
				return [{"squad": sq["id"], "x": area[0] + area[2] / 2, "y": area[1] + area[3] / 2, "facing": 0}]
		return []


## sw-bafi.14: a non-empty draft for a battle adds the deployment bonus to the
## player's Planning time; an empty one doesn't, and it survives a save.
func test_deployment_bonus_follows_drafts_and_saves() -> void:
	var s := _session()
	var eid := _eid(s)
	var base := s.clock.remaining_ms(1)
	var base2 := s.clock.remaining_ms(2)
	var sid: int = _own(s, eid, 1)[0]
	s.submit_battle_deployment(1, eid, [_centre(s, eid, 1, sid)])
	assert_eq(s.clock.remaining_ms(1), base + 15000, "one battle deployed in")
	assert_eq(s.clock.remaining_ms(2), base2, "player 2 deployed nothing")
	var loaded := OverworldSession.load_save(s.save(), _l().templates, _l().data_hash)
	assert_not_null(loaded, OverworldSession.last_error)
	if loaded != null:
		assert_eq(loaded.clock.remaining_ms(1), base + 15000, "the bonus survives a save")
	s.submit_battle_deployment(1, eid, [])
	assert_eq(s.clock.remaining_ms(1), base, "an empty draft deploys nowhere")
