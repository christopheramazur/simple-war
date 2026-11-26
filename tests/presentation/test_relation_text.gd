extends GutTest
## RelationText (sw-bafi.6, U1 C6a): the pure fact-to-line function, tested
## on hand-built fact lists in SquadRelation's shape (no sim): ordering, the
## 3-line cap, the hold-fire reason surviving the cap, "likely" wording,
## translation keys with English fallbacks.


func _fact(kind: String, value: String, data: Dictionary = {}) -> Dictionary:
	return {"kind": kind, "value": value, "from": 1, "to": 2, "rule": "test", "data": data}


func _aiming(hold: int) -> Dictionary:
	return _fact("targeting", "aiming", {"hold": hold})


func test_no_facts_no_lines() -> void:
	assert_eq(RelationText.lines([]), PackedStringArray())


func test_unknown_kinds_are_skipped() -> void:
	var lines := RelationText.lines([_fact("gossip", "rumour"), _fact("sight", "unseen")])
	assert_eq(lines, PackedStringArray(["Unseen"]))


func test_ordering_targeting_range_movement_contact() -> void:
	var lines := RelationText.lines([
		_fact("sight", "allies"),
		_fact("moving", "toward"),
		_fact("range", "in_range"),
		_fact("targeting", "firing"),
	])
	# Sight is contact, the lowest rank: the cap drops it, not the rest.
	assert_eq(lines, PackedStringArray(["Firing at the enemy", "In range", "Moving toward"]))


func test_ordering_within_a_rank_puts_fleeing_before_moving() -> void:
	var lines := RelationText.lines([
		_fact("moving", "away"),
		_fact("fleeing", "falling_back", {"moving": true}),
	])
	assert_eq(lines, PackedStringArray(["Falling back", "Moving away"]))


func test_the_cap_is_three_lines() -> void:
	var lines := RelationText.lines([
		_fact("targeting", "firing"),
		_fact("under_fire", "recent"),
		_fact("would_engage", "likely"),
		_fact("ordered", "attack"),
		_fact("range", "in_range"),
		_fact("fleeing", "retreating"),
		_fact("moving", "across"),
		_fact("sight", "own"),
	])
	assert_eq(lines.size(), RelationText.MAX_LINES)
	assert_eq(lines, PackedStringArray(["Firing at the enemy", "Under fire", "Likely to engage next"]))


func test_identical_lines_are_dropped() -> void:
	var lines := RelationText.lines([_fact("sight", "unseen"), _fact("sight", "unseen")])
	assert_eq(lines, PackedStringArray(["Unseen"]))


func test_hold_reason_from_an_aiming_squad_survives_the_cap() -> void:
	var lines := RelationText.lines([
		_aiming(BattleActivity.Hold.MIN_RANGE),
		_fact("range", "in_range"),
		_fact("moving", "toward"),
		_fact("fleeing", "falling_back"),
		_fact("sight", "own"),
	])
	assert_eq(lines.size(), 3)
	assert_eq(lines[0], "Aiming at the enemy; Too close to fire", "the reason rides on the targeting line")
	assert_true(_joined(lines).contains("Too close to fire"))


func test_hold_reason_from_a_range_fact_survives_the_cap() -> void:
	var lines := RelationText.lines([
		_fact("range", "no_line"),
		_fact("moving", "away"),
		_fact("fleeing", "falling_back"),
		_fact("sight", "own"),
	])
	assert_eq(lines.size(), 3)
	assert_eq(lines[0], "No line of fire")
	assert_false(_joined(lines).contains("Spotted by its own side"), "contact is dropped by the cap")


func test_hold_reason_survives_many_targeting_facts() -> void:
	var lines := RelationText.lines([
		_fact("targeting", "firing"),
		_fact("under_fire", "recent"),
		_fact("would_engage", "likely"),
		_fact("ordered", "attack"),
		_fact("range", "min_range"),
	])
	assert_eq(lines.size(), RelationText.MAX_LINES)
	assert_eq(lines[0], "Firing at the enemy; Too close to fire")
	assert_eq(_joined(lines).count("Too close to fire"), 1, "the reason is not repeated as its own line")


func test_hold_reason_text_by_hold_value() -> void:
	assert_eq(RelationText.hold_reason([_aiming(BattleActivity.Hold.RELOADING)]), "Reloading")
	assert_eq(RelationText.hold_reason([_aiming(BattleActivity.Hold.NO_LOS)]), "No line of fire")
	assert_eq(RelationText.hold_reason([_aiming(BattleActivity.Hold.NONE)]), "", "no reason, no hold text")
	assert_eq(RelationText.hold_reason([_fact("range", "in_range")]), "")


func test_would_engage_reads_as_likely() -> void:
	var lines := RelationText.lines([_fact("would_engage", "likely")])
	assert_eq(lines, PackedStringArray(["Likely to engage next"]))
	assert_true(lines[0].to_lower().contains("likely"))
	assert_false(lines[0].to_lower().contains("will"), "never a commitment")


func test_out_of_range_states_the_gap() -> void:
	var lines := RelationText.lines([_fact("range", "out_of_range", {"gap": Fixed.from_int(12)})])
	assert_eq(lines, PackedStringArray(["Out of range by 12 m"]))
	var bare := RelationText.lines([_fact("range", "out_of_range", {"gap": 0})])
	assert_eq(bare, PackedStringArray(["Out of range"]))


func test_every_sim_value_has_a_line_and_no_key_leaks() -> void:
	var facts := [
		_fact("range", "in_range"), _fact("range", "min_range"), _fact("range", "no_line"),
		_fact("range", "out_of_range"), _fact("range", "not_spotted"), _fact("range", "unarmed"),
		_fact("sight", "own"), _fact("sight", "allies"), _fact("sight", "unseen"),
		_fact("targeting", "firing"), _fact("targeting", "aiming"),
		_fact("ordered", "attack"), _fact("would_engage", "likely"), _fact("under_fire", "recent"),
		_fact("fleeing", "falling_back"), _fact("fleeing", "withdrawing"), _fact("fleeing", "retreating"),
		_fact("moving", "toward"), _fact("moving", "away"), _fact("moving", "across"),
	]
	for f: Dictionary in facts:
		var text := RelationText.text_of(f)
		assert_ne(text, "", "text for %s/%s" % [f["kind"], f["value"]])
		assert_false(text.begins_with("relation."), "no raw key in " + text)


func test_unknown_kind_has_no_text() -> void:
	assert_eq(RelationText.text_of(_fact("gossip", "rumour")), "")


func test_translation_keys_override_the_english() -> void:
	var tr := Translation.new()
	tr.locale = "fr"
	tr.add_message("relation.sight.unseen", "Invisible")
	TranslationServer.add_translation(tr)
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("fr")
	assert_eq(RelationText.lines([_fact("sight", "unseen")]), PackedStringArray(["Invisible"]))
	# A key with no translation falls back to its English.
	assert_eq(RelationText.lines([_fact("range", "no_line")]), PackedStringArray(["No line of fire"]))
	TranslationServer.set_locale(was)
	TranslationServer.remove_translation(tr)


func _joined(lines: PackedStringArray) -> String:
	return "\n".join(lines)
