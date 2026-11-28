extends GutTest
## Owner actions as the owner sees them (sw-63wt.10, GDD 04 §4.4):
## inspect_feature's "actions" (price with the markup, and why not) and
## "buys" (planned, cancellable one at a time). test_vale: player 1's village
## (1,6) recruits rifle squads for 6 (8), scouts for 4 (5) and engineers for
## 5; it allows buy, rally and output, and buys one a turn.

const W := 16

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func P(col: int, row: int) -> int:
	return Hex.plot(col, row, W)


## A session in Planning with at least 5 Value, reached by turns (a Value
## set by hand is not an input, so a replay would not match it).
func _planning() -> OverworldSession:
	var l := _l()
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	for i in 30:
		if s.phase_name() == "PLANNING" and int(s.observe(1)["value"]) >= 5:
			break
		s.ready(1)
		s.ready(2)
	assert_eq(s.phase_name(), "PLANNING")
	assert_true(int(s.observe(1)["value"]) >= 5)
	return s


func _village(s: OverworldSession) -> int:
	for f: Dictionary in s.inspect_plot(1, P(1, 6))["features"]:
		if f["name"] == "Village":
			return f["id"]
	return -1


func _action(actions: Array, action: String, option: String = "") -> Dictionary:
	for a: Dictionary in actions:
		if a["action"] == action and str(a.get("option", "")) == option:
			return a
	return {}


func test_actions_list_price_with_markup_and_the_reason_not_to() -> void:
	var s := _planning()
	var village := _village(s)
	assert_true(village >= 0)
	s.state.value[1] = 30
	var info := s.inspect_feature(1, village)
	var scout := _action(info["actions"], "buy", "scout_team")
	assert_eq(int(scout["cost"]), 4, "the plain price")
	assert_eq(int(scout["price"]), 5, "with the 25% remote markup, rounded up")
	assert_eq(int(scout["markup"]), 25)
	assert_eq(scout["reason"], "")
	assert_false(_action(info["actions"], "rally").is_empty(), "the village allows a rally point")
	s.state.value[1] = 4
	scout = _action(s.inspect_feature(1, village)["actions"], "buy", "scout_team")
	assert_eq(scout["reason"], "not enough Value (costs 5, you have 4)", "a Value shortfall says why")


func test_a_planned_buy_takes_the_limit_and_shows_as_pending() -> void:
	var s := _planning()
	var village := _village(s)
	s.state.value[1] = 30
	assert_eq(s.set_owner_action(1, village, "buy", "scout_team"), "")
	var info := s.inspect_feature(1, village)
	assert_eq(info["buys"].size(), 1)
	assert_eq(info["buys"][0]["option"], "scout_team")
	assert_eq(int(info["buys"][0]["price"]), 5)
	assert_eq(_action(info["actions"], "buy", "rifle_squad")["reason"], OverworldOwnerActions.LIMIT, "one buy a turn")
	assert_eq(int(s.observe(1)["value"]), 30, "nothing is paid while planned")


func test_cancel_removes_one_planned_buy_and_keeps_the_rest() -> void:
	var s := _planning()
	var village := _village(s)
	var t := s.rules.feature_index("hex_village")
	s.rules.hf_buys[t] = 2
	s.state.value[1] = 30
	assert_eq(s.set_owner_action(1, village, "buy", "scout_team"), "")
	assert_eq(s.set_owner_action(1, village, "buy", "rifle_squad"), "")
	assert_eq(s.cancel_owner_buy(1, village, 0), "")
	var buys: Array = s.inspect_feature(1, village)["buys"]
	assert_eq(buys.size(), 1)
	assert_eq(buys[0]["option"], "rifle_squad", "the other stays, in order")
	assert_eq(s.cancel_owner_buy(1, village, 5), "no such buy")
	assert_eq(s.cancel_owner_buy(2, village, 0), "no such buy", "not the owner's")
	assert_eq(s.cancel_owner_buy(1, village, 0), "")
	assert_true(s.inspect_feature(1, village)["buys"].is_empty())
	assert_eq(int(s.observe(1)["value"]), 30, "cancelling pays nothing")


func test_cancelled_buy_replays_to_the_same_state() -> void:
	var s := _planning()
	var village := _village(s)
	assert_eq(s.set_owner_action(1, village, "buy", "scout_team"), "")
	assert_eq(s.cancel_owner_buy(1, village, 0), "")
	var r :=OverworldSession.rebuild(s.save(), _l().templates, _l().data_hash)
	assert_not_null(r, OverworldSession.last_error)
	assert_eq(r.state.state_hash_hex(), s.state.state_hash_hex())


func test_only_the_owner_gets_actions() -> void:
	var s := _planning()
	var village := _village(s)
	assert_true(s.inspect_feature(2, village).get("actions", []).is_empty(), "nothing for someone else's feature")
	assert_false(s.inspect_feature(1, village)["actions"].is_empty())


func test_output_choices_are_actions_and_mark_the_selected_one() -> void:
	var s := _planning()
	var t := s.rules.feature_index("hex_barracks")
	var barracks := s.state.features.id_at(s.state.feature_row(P(8, 7), t))
	s.state.features.set_value(barracks, &"owner", 1)
	var info := s.inspect_feature(1, barracks)
	var outs := (info["actions"] as Array).filter(func(a: Dictionary) -> bool: return a["action"] == "output")
	assert_eq(outs.size(), (info["produces"] as Array).size(), "one output choice per production option")
	assert_eq(s.set_output(1, barracks, 1), "")
	outs = (s.inspect_feature(1, barracks)["actions"] as Array).filter(func(a: Dictionary) -> bool: return a["action"] == "output")
	assert_true(bool(outs[1]["selected"]))
	assert_false(bool(outs[0]["selected"]))
