extends GutTest
## Squad behaviour vocabulary (GDD 02 §2.15 Squad behaviours, U1Q12, U1Q29,
## sw-txnj.9): the `behaviour` template kind validates against the closed
## component list and compiles to BattleRules.bh_* per squad template x order.
## Pure addition: nothing reads the arrays yet, and the defaults are the
## built closing-to-fire constants (sw-txnj.5).

const ONE := Fixed.ONE

static var _fixture: PackageLoader
static var _core: PackageLoader


func _fx() -> PackageLoader:
	if _fixture == null:
		_fixture = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _fixture


func _core_loader() -> PackageLoader:
	if _core == null:
		_core = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _core


## Fixture defs plus a behaviour `b` with `components`, named by the rifle
## squad's attack-move.
func _defs_with(components: Array) -> Array:
	var defs := _fx().defs.duplicate(true)
	defs.append({"id": "b", "kind": "behaviour", "values": {"components": components}})
	for d: Dictionary in defs:
		if d["id"] == "rifle_squad":
			d["values"]["behaviours"] = {"attack_move": "b"}
	return defs


func _errors_for(components: Array) -> PackedStringArray:
	return DataSchema.validate(TemplateTable.build(_defs_with(components)))


func _assert_one_error(errs: PackedStringArray, want: String) -> void:
	assert_eq(errs.size(), 1, "one error: %s" % [errs])
	if errs.size() > 0:
		assert_string_contains(errs[0], "b: ")
		assert_string_contains(errs[0], want)


func test_battle_orders_match_the_order_enum() -> void:
	assert_eq(DataSchema.BATTLE_ORDERS.size(), BattleRules.BH_ORDERS)
	for name: String in BattleSquads.Order:
		assert_eq(DataSchema.BATTLE_ORDERS[BattleSquads.Order[name]], name.to_lower())


func test_core_and_fixture_validate() -> void:
	assert_eq(_core_loader().errors, PackedStringArray())
	assert_eq(_fx().errors, PackedStringArray())


func test_a_full_behaviour_validates() -> void:
	assert_eq(_errors_for([
		{"c": "firing_position", "extra_m": 3, "stand_off_m": "2.5", "cadence_ticks": 4, "hysteresis_s": 2},
		{"c": "keep_distance", "min_m": 10, "max_m": 40},
		{"c": "leash", "chase_m": 25},
		{"c": "fire_on_move", "allow": false},
		{"c": "stand_while", "firing": true, "reloading": true},
		{"c": "separate", "radius_m": "0.6"}]), PackedStringArray())


func test_unknown_component_fails() -> void:
	_assert_one_error(_errors_for([{"c": "advance", "quorum_pct": 100}]), "unknown behaviour component 'advance'")
	_assert_one_error(_errors_for([{"c": "step_out", "max_m": 3}]), "unknown behaviour component 'step_out'")
	_assert_one_error(_errors_for([{"chase_m": 3}]), "unknown behaviour component")


func test_unknown_parameter_fails() -> void:
	_assert_one_error(_errors_for([{"c": "leash", "chase_m": 15, "quorum_pct": 100}]),
		"'components/0' (leash) has unknown parameter 'quorum_pct'")


func test_wrong_type_fails() -> void:
	_assert_one_error(_errors_for([{"c": "fire_on_move", "allow": "no"}]), "'components/0/allow' must be true or false")
	_assert_one_error(_errors_for([{"c": "leash", "chase_m": "far"}]), "'components/0/chase_m' must be an integer or decimal string")
	_assert_one_error(_errors_for([{"c": "firing_position", "cadence_ticks": 0}]), "'components/0/cadence_ticks' below minimum 1")
	_assert_one_error(_errors_for(["leash"]), "'components/0' must be an object")


func test_missing_required_parameter_fails() -> void:
	_assert_one_error(_errors_for([{"c": "separate"}]), "missing required field 'components/0/radius_m'")


func test_repeated_and_conflicting_components_fail() -> void:
	_assert_one_error(_errors_for([{"c": "leash", "chase_m": 1}, {"c": "leash", "chase_m": 2}]),
		"repeats behaviour component 'leash'")
	_assert_one_error(_errors_for([{"c": "firing_position", "coherency_m": 8, "extra_m": 2}]), "both coherency_m and extra_m")
	_assert_one_error(_errors_for([{"c": "keep_distance", "min_m": 20, "max_m": 10}]), "min_m is above max_m")


func test_squad_behaviours_keys_and_refs_checked() -> void:
	var defs := _fx().defs.duplicate(true)
	for d: Dictionary in defs:
		if d["id"] == "engineer_team":
			d["values"]["behaviours"] = {"charge": "line_attack", "attack": "trooper"}
	var errs := DataSchema.validate(TemplateTable.build(defs))
	assert_eq(errs.size(), 2, str(errs))
	var joined := "\n".join(errs)
	assert_string_contains(joined, "engineer_team: 'behaviours' has unknown key 'charge'")
	assert_string_contains(joined, "engineer_team: 'behaviours/attack' must reference a behaviour template")


## Every core squad template compiles one behaviour per order: explicit for
## humanity's attack orders, the default for the rest, all equal to the
## built constants.
func test_every_core_squad_compiles_a_behaviour_per_order() -> void:
	var r := BattleRules.compile(_core_loader().templates, "duel_crossroads")
	assert_eq(r.errors, PackedStringArray())
	var n := r.squad_ids.size() * BattleRules.BH_ORDERS
	assert_gt(r.squad_ids.size(), 10)
	for arr: Variant in [r.bh_ids, r.bh_coherency, r.bh_stand_off, r.bh_cadence, r.bh_hysteresis, r.bh_keep_min,
			r.bh_keep_max, r.bh_leash, r.bh_fire_on_move, r.bh_stand_firing, r.bh_stand_reloading, r.bh_separate]:
		assert_eq(arr.size(), n)
	# The archetype behaviours (humanity.json, sw-txnj.11), under the engaging orders only.
	var archetype := {
		"mortar_team": {"keep_min": 25 * Fixed.ONE, "fire_on_move": 0, "stand_reloading": 1},
		"marksman_team": {"keep_max": 65 * Fixed.ONE},
		"assault_squad": {"extra": 3 * Fixed.ONE},
	}
	for st in r.squad_ids.size():
		var tid := r.squad_ids[st]
		var arch: Dictionary = archetype.get(tid, {})
		for o in BattleRules.BH_ORDERS:
			var i := r.bh_at(st, o)
			var engaging := o == BattleSquads.Order.ATTACK_MOVE or o == BattleSquads.Order.ATTACK
			var a: Dictionary = arch if engaging else {}
			assert_eq(r.bh_coherency[i], r.sq_coherency[st] + a.get("extra", 0), "%s/%d coherency" % [tid, o])
			assert_eq(r.bh_stand_off[i], FiringPositions.STAND_OFF)
			assert_eq(r.bh_cadence[i], FiringPositions.CADENCE)
			assert_eq(r.bh_hysteresis[i], FiringPositions.HYSTERESIS_S * r.tps)
			assert_eq(r.bh_leash[i], r.chase_leash if o == BattleSquads.Order.ATTACK_MOVE else -1, "%s/%d leash" % [tid, o])
			assert_eq(r.bh_keep_min[i], a.get("keep_min", -1), "%s/%d keep_min" % [tid, o])
			assert_eq(r.bh_keep_max[i], a.get("keep_max", -1), "%s/%d keep_max" % [tid, o])
			assert_eq(r.bh_fire_on_move[i], a.get("fire_on_move", 1), "%s/%d fire_on_move" % [tid, o])
			assert_eq(r.bh_stand_firing[i], 1)
			assert_eq(r.bh_stand_reloading[i], a.get("stand_reloading", 0), "%s/%d stand_reloading" % [tid, o])
			assert_eq(r.bh_separate[i], -1)
	var rifle := r.squad_index("rifle_squad")
	assert_eq(r.bh_ids[r.bh_at(rifle, BattleSquads.Order.ATTACK_MOVE)], "line_attack_move")
	assert_eq(r.bh_ids[r.bh_at(rifle, BattleSquads.Order.ATTACK)], "line_attack")
	assert_eq(r.bh_ids[r.bh_at(rifle, BattleSquads.Order.HOLD)], "")


func test_explicit_components_override_the_default() -> void:
	var defs := _defs_with([
		{"c": "firing_position", "extra_m": 3, "stand_off_m": "2.5", "cadence_ticks": 4, "hysteresis_s": "1.5"},
		{"c": "keep_distance", "max_m": 40},
		{"c": "leash", "chase_m": 25},
		{"c": "fire_on_move", "allow": false},
		{"c": "stand_while", "reloading": true},
		{"c": "separate", "radius_m": "0.5"}])
	defs.append({"id": "b2", "kind": "behaviour", "values": {"components": [{"c": "firing_position", "coherency_m": 9}]}})
	for d: Dictionary in defs:
		if d["id"] == "rifle_squad":
			d["values"]["behaviours"]["hold"] = "b2"
	var r := BattleRules.compile(TemplateTable.build(defs), "duel_crossroads")
	assert_eq(r.errors, PackedStringArray())
	var st := r.squad_index("rifle_squad")
	var i := r.bh_at(st, BattleSquads.Order.ATTACK_MOVE)
	assert_eq(r.bh_ids[i], "b")
	assert_eq(r.bh_coherency[i], r.sq_coherency[st] + 3 * ONE)
	assert_eq(r.bh_stand_off[i], 5 * ONE / 2)
	assert_eq(r.bh_cadence[i], 4)
	assert_eq(r.bh_hysteresis[i], 3 * r.tps / 2)
	assert_eq(r.bh_keep_min[i], -1)
	assert_eq(r.bh_keep_max[i], 40 * ONE)
	assert_eq(r.bh_leash[i], 25 * ONE)
	assert_eq(r.bh_fire_on_move[i], 0)
	assert_eq(r.bh_stand_firing[i], 1, "unset parameter keeps its default")
	assert_eq(r.bh_stand_reloading[i], 1)
	assert_eq(r.bh_separate[i], ONE / 2)
	var h := r.bh_at(st, BattleSquads.Order.HOLD)
	assert_eq(r.bh_ids[h], "b2")
	assert_eq(r.bh_coherency[h], 9 * ONE)
	assert_eq(r.bh_leash[h], -1)
	# The squad's other orders keep the inherited explicit behaviours.
	assert_eq(r.bh_ids[r.bh_at(st, BattleSquads.Order.ATTACK)], "line_attack")
