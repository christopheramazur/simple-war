extends GutTest
## DamagePipeline.preview (sw-pd2l.3): the expected effective damage a shooter
## counts against a victim (GDD 02 §2.6 Remaining HP). Pure: no state writes,
## no evasion or block. With those at zero it is apply's `through`.

const ONE := Fixed.ONE

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


func _empty() -> BattleState:
	return BattleState.new(1, _rules(), 1)


func _place(s: BattleState, player: int, squad: String, x: int, y: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _unit_of(s: BattleState, sid: int, nth: int = 0) -> int:
	return Centroids.units_of(s, s.squads.row_of(sid))[nth]


## Carapace (block 10%, resist, flat, percent, floor) with its block
## accumulator held at 0, so the hit is never blocked: every defence but
## block applies, exactly as preview computes it.
func test_preview_matches_apply_when_evasion_and_block_are_zero() -> void:
	var s := _empty()
	var sid := _place(s, 2, "chi_operatives", 20, 20)
	var u := _unit_of(s, sid, 1)
	var id := s.units.id_at(u)
	var checked := 0
	for dtype in _rules().damage_types.size():
		for dmg: int in [ONE, 4 * ONE, 10 * ONE, 37 * ONE + ONE / 3]:
			s.units.set_value(id, &"hp", 100 * ONE)
			s.units.set_value(id, &"acc_block", 0)
			var want := DamagePipeline.preview(s, u, dmg, dtype)
			var res := DamagePipeline.apply(s, u, dmg, dtype, 0)
			assert_eq(res["blocked"], 0, "block held off for this hit")
			assert_eq(want, res["through"], "dmg %d type %d: preview equals apply's through" % [dmg, dtype])
			checked += 1
	assert_gt(checked, 0)


func test_preview_is_the_expected_damage_through_armour() -> void:
	# 10 kinetic through carapace is 7.2 (test_battle_rules): preview says so.
	var s := _empty()
	var sid := _place(s, 2, "chi_operatives", 20, 20)
	var u := _unit_of(s, sid, 1)
	assert_eq(Fixed.to_display(DamagePipeline.preview(s, u, 10 * ONE, 0)), "7.2")


func test_preview_writes_no_state_and_leaves_block_accumulator_alone() -> void:
	var s := _empty()
	var sid := _place(s, 2, "chi_operatives", 20, 20)
	var u := _unit_of(s, sid, 1)
	var id := s.units.id_at(u)
	var hp_before: int = s.units.hp[u]
	for _i in 25:
		DamagePipeline.preview(s, u, 10 * ONE, 0)
	assert_eq(s.units.hp[u], hp_before, "preview leaves HP alone")
	# Had preview ticked the block accumulator, the 10th real hit would not be
	# the first blocked one; it still is (test_battle_rules pins this).
	var blocked_on := -1
	for i in range(1, 12):
		s.units.set_value(id, &"hp", 100 * ONE)
		if DamagePipeline.apply(s, u, 4 * ONE, 0, 0)["blocked"] > 0:
			blocked_on = i
			break
	assert_eq(blocked_on, 10, "the block accumulator is untouched by preview")


func test_armoured_unit_is_not_covered_by_raw_damage_it_survives() -> void:
	# HP 8: the raw 10 would cover it, but through carapace only 7.2 lands,
	# so the shooter has not really covered it (sw-pd2l.3).
	var s := _empty()
	var sid := _place(s, 2, "chi_operatives", 20, 20)
	var u := _unit_of(s, sid, 1)
	s.units.set_value(s.units.id_at(u), &"hp", 8 * ONE)
	var expected := DamagePipeline.preview(s, u, 10 * ONE, 0)
	assert_false(TargetPolicy.covered(s.units, u, {u: expected}), "expected damage 7.2 does not cover 8 HP")
	assert_true(TargetPolicy.covered(s.units, u, {u: 10 * ONE}), "raw damage would (the old rule)")
