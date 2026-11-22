extends GutTest
## Enemy attack telegraphs in the reaction window (sw-7o7).

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _controllers() -> Dictionary:
	return {1: ZoneController.new(1), 2: ZoneController.new(2, {"fall_back_pct": 60})}


## Plays turns until the reaction window shows a telegraph for a player.
## Returns {"s", "player", "told"} stopped inside that window, or {}.
func _until_telegraph(seed_value: int) -> Dictionary:
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", seed_value)
	var c := _controllers()
	for _t in 8:
		if s.is_over():
			break
		for p in s.players():
			s.submit_orders(p, c[p].orders(s.observe(p)))
		for p in s.players():
			s.ready(p)
		for p in s.players():
			var told := s.telegraphs(p)
			if not told.is_empty():
				return {"s": s, "player": p, "told": told}
		s.ready(1)
		s.ready(2)
		s.ready(1)
		s.ready(2)
	return {}


func _executed(s: BattleSession) -> Dictionary:
	var out := {}
	for e in s.state.turn_log:
		if e.type == &"squad_damaged":
			var key := "%d,%d" % [e.data["squad"], e.data["target"]]
			out[key] = int(out.get(key, 0)) + int(e.data["damage"])
	return out


func test_telegraph_damage_equals_the_sim_result() -> void:
	var found := {}
	for seed_value in [11, 21, 5, 7]:
		found = _until_telegraph(seed_value)
		if not found.is_empty():
			break
	assert_false(found.is_empty(), "a telegraph appeared within 8 turns")
	if found.is_empty():
		return
	var s: BattleSession = found["s"]
	var told: Array = found["told"]
	var mine := s.state.squads
	for t: Dictionary in told:
		assert_eq(mine.player[mine.row_of(t["target"])], found["player"], "only attacks on own squads")
		assert_ne(mine.player[mine.row_of(t["attacker"])], found["player"], "only enemy attacks")
		assert_gt(t["damage"], 0)
	s.ready(1)
	s.ready(2)
	var real := _executed(s)
	for t: Dictionary in told:
		var key := "%d,%d" % [t["attacker"], t["target"]]
		assert_eq(t["damage"], real.get(key, -1), "telegraph %s equals the executed damage" % key)


func test_telegraphs_are_deterministic_and_window_only() -> void:
	var a := _until_telegraph(11)
	var b := _until_telegraph(11)
	assert_eq(a.get("told"), b.get("told"))
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 11)
	assert_eq(s.telegraphs(1), [], "none outside the reaction window")


func test_telegraph_label_shares_playback_damage_text() -> void:
	var one := Fixed.ONE
	assert_eq(Telegraph.label({"damage": 12 * one}), "▶ 12")
	assert_eq(Telegraph.label({"damage": one / 2}), "▶ " + BattleFx.damage_text(one / 2))
	assert_eq(Telegraph.label({"damage": 30 * one, "kills": 2}), "▶ 30 · 2 down")
	var ct := {"tick": 7, "reactions": ["a", "b"]}
	assert_eq(Telegraph.contact_label(ct), "⚔")
	assert_eq(Telegraph.contact_label(ct, true), "⚔ t7 · 2 reactions")
	assert_eq(Telegraph.contact_label({"tick": 3}, true), "⚔ t3")
	assert_eq(GameSettings.DEFAULTS["forecast_detail"], "summary")




## sw-abk: contacts on the planning forecast carry the damage the sim then
## executes (same HealthSystem totals), when orders are committed unchanged.
func test_forecast_contact_damage_equals_executed_damage() -> void:
	var checked := 0
	for seed_value in [11, 21, 5, 7, 1, 2, 3, 4, 6, 8]:
		var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", seed_value)
		var c := _controllers()
		for t in 14:
			if s.is_over():
				break
			# Odd turns: player 2 keeps the orders it already has (unchanged).
			var orders := {}
			for p in s.players():
				orders[p] = c[p].orders(s.observe(p)) if (p == 1 or t % 2 == 0) else []
			var fc := s.forecast(1, orders[1])
			# The forecast removes enemies player 1 can't see (fog), so exact
			# equality holds unless a hidden one takes part in the turn's fire.
			var sq := s.state.squads
			var hidden := {}
			for row in sq.count():
				if sq.player[row] != 1 and sq.is_active(row) and sq.seen_by[row] & BattleSquads.bit(1) == 0:
					hidden[sq.id_at(row)] = true
			var before: String = s.state.state_hash().hex_encode()
			for p in s.players():
				s.submit_orders(p, orders[p])
			assert_eq(before, s.state.state_hash().hex_encode(), "forecast is read-only")
			for p in s.players():
				s.ready(p)
			s.ready(1)
			s.ready(2)
			s.ready(1)
			s.ready(2)
			var real := _executed(s)
			for ct: Dictionary in fc.get("contacts", []):
				if ct["dealt"] > 0 or ct["taken"] > 0:
					checked += 1
			var touched := false
			for key: String in real:
				for part in key.split(","):
					touched = touched or hidden.has(int(part))
			if t % 2 == 0 or touched:
				continue
			for ct: Dictionary in fc.get("contacts", []):
				assert_true(ct.has("dealt") and ct.has("taken"))
				var out: int = real.get("%d,%d" % [ct["squad"], ct["target"]], 0)
				var inn: int = real.get("%d,%d" % [ct["target"], ct["squad"]], 0)
				assert_eq(ct["dealt"], out, "dealt %d->%d" % [ct["squad"], ct["target"]])
				assert_eq(ct["taken"], inn, "taken %d<-%d" % [ct["squad"], ct["target"]])
	assert_gt(checked, 0, "some contact predicted damage")


func test_contact_label_summary_then_numbers() -> void:
	var one := Fixed.ONE
	var ct := {"dealt": 12 * one, "taken": 5 * one}
	assert_eq(Telegraph.contact_label(ct), "⚔ favourable")
	assert_eq(Telegraph.contact_label(ct, true), "⚔ deal 12 · take 5")
	assert_eq(Telegraph.contact_label({"dealt": 0, "taken": 0}), "⚔")
