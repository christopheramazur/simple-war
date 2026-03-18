extends GutTest

## Tests for AttackResolver -- the "Making Attacks" process.

var resolver: AttackResolver


func before_each() -> void:
	resolver = AttackResolver.new()


func _make_model(endurance: int, reflex: int, speed: int) -> ModelData:
	var m := ModelData.new()
	m.id = "test_model"
	m.endurance = endurance
	m.reflex = reflex
	m.speed = speed
	m.durability = 10
	return m


func _make_unit(model: ModelData) -> UnitData:
	var u := UnitData.new()
	u.id = "test_unit"
	u.models.append(model)
	return u


func _make_ranged_profile(damage_value: int = 3, range_max: int = 40) -> AttackProfile:
	var p := AttackProfile.new()
	p.id = "test_ranged"
	p.category = "ranged"
	p.range_min = 5
	p.range_short = 10
	p.range_long = 30
	p.range_max = range_max
	p.damage_type = "kinetic"
	p.damage_value = damage_value
	p.damage_count = 1
	return p


func _make_melee_profile(damage_value: int = 2) -> AttackProfile:
	var p := AttackProfile.new()
	p.id = "test_melee"
	p.category = "melee"
	p.range_max = 1
	p.damage_type = "kinetic"
	p.damage_value = damage_value
	p.damage_count = 1
	return p


func _make_item_with_profiles(profiles: Array[AttackProfile]) -> ItemData:
	var item := ItemData.new()
	item.id = "test_weapon"
	item.attack_profiles = profiles
	return item


func test_hit_chance_has_floor_of_5_percent() -> void:
	var attacker := _make_model(1, 1, 1)
	var target := _make_model(1, 20, 20)
	var profile := _make_ranged_profile()

	var chance := resolver.compute_hit_chance(attacker, profile, target, 15.0)
	assert_eq(chance, AttackResolver.HIT_FLOOR,
		"Worst-case hit chance should equal the 5%% floor")


func test_hit_chance_has_ceiling_of_95_percent() -> void:
	var attacker := _make_model(20, 1, 1)
	var target := _make_model(1, 1, 1)
	var profile := _make_ranged_profile()

	var chance := resolver.compute_hit_chance(attacker, profile, target, 15.0)
	assert_eq(chance, AttackResolver.HIT_CEILING,
		"Best-case hit chance should equal the 95%% ceiling")


func test_hit_chance_increases_with_endurance() -> void:
	var target := _make_model(10, 5, 5)
	var profile := _make_ranged_profile()

	var low := resolver.compute_hit_chance(_make_model(5, 5, 5), profile, target, 15.0)
	var high := resolver.compute_hit_chance(_make_model(15, 5, 5), profile, target, 15.0)
	assert_gt(high, low, "Higher endurance should increase hit chance")


func test_hit_chance_decreases_with_target_evasion() -> void:
	var attacker := _make_model(10, 5, 5)
	var profile := _make_ranged_profile()

	var easy := resolver.compute_hit_chance(attacker, profile, _make_model(10, 3, 3), 15.0)
	var hard := resolver.compute_hit_chance(attacker, profile, _make_model(10, 15, 15), 15.0)
	assert_gt(easy, hard, "Higher target evasion should reduce hit chance")


func test_resolve_returns_combat_events() -> void:
	var attacker := _make_model(20, 5, 5)
	var profile := _make_ranged_profile(5)
	var item := _make_item_with_profiles([profile] as Array[AttackProfile])
	attacker.equipped_items.append(item)

	var target := _make_model(10, 1, 1)
	var atk_unit := _make_unit(attacker)
	var def_unit := _make_unit(target)

	seed(42)
	var total_hits := 0
	for _i in range(100):
		attacker.equipped_items = [item]
		var events: Array[CombatEvent] = resolver.resolve_model_attacks(attacker, atk_unit, target, def_unit, 15.0)
		for evt in events:
			if evt.hit:
				total_hits += 1

	assert_gt(total_hits, 0, "Should produce at least some hits over 100 attempts")
	assert_lt(total_hits, 100, "Should not hit every single time")


func test_damage_instance_carries_correct_metadata() -> void:
	var attacker := _make_model(20, 5, 5)
	var profile := _make_ranged_profile(7)
	var item := _make_item_with_profiles([profile] as Array[AttackProfile])
	attacker.equipped_items.append(item)

	var target := _make_model(10, 1, 1)
	var atk_unit := _make_unit(attacker)
	atk_unit.id = "atk_unit_id"
	var def_unit := _make_unit(target)
	def_unit.id = "def_unit_id"

	seed(1)
	var hit_evt: CombatEvent = null
	for _i in range(50):
		attacker.equipped_items = [item]
		var events: Array[CombatEvent] = resolver.resolve_model_attacks(attacker, atk_unit, target, def_unit, 15.0)
		for evt in events:
			if evt.hit and evt.damage_instance != null:
				hit_evt = evt
				break
		if hit_evt != null:
			break

	if hit_evt == null:
		pending("Could not generate a hit in 50 attempts; check seed")
		return

	var dmg: DamageInstance = hit_evt.damage_instance
	assert_eq(dmg.damage_value, 7, "Damage value should match profile")
	assert_eq(dmg.damage_type, "kinetic", "Damage type should match profile")
	assert_eq(dmg.source_unit_id, "atk_unit_id", "Source unit id should be set")
	assert_eq(dmg.target_unit_id, "def_unit_id", "Target unit id should be set")


func test_out_of_range_produces_no_events() -> void:
	var attacker := _make_model(20, 5, 5)
	var profile := _make_ranged_profile(5, 40)
	var item := _make_item_with_profiles([profile] as Array[AttackProfile])
	attacker.equipped_items.append(item)

	var target := _make_model(10, 5, 5)
	var atk_unit := _make_unit(attacker)
	var def_unit := _make_unit(target)

	var events: Array[CombatEvent] = resolver.resolve_model_attacks(attacker, atk_unit, target, def_unit, 100.0)
	assert_eq(events.size(), 0, "No events when target is out of range (no profile selected)")


func test_every_attempt_produces_one_event() -> void:
	var attacker := _make_model(20, 5, 5)
	var profile := _make_ranged_profile(3)
	profile.damage_count = 4
	var item := _make_item_with_profiles([profile] as Array[AttackProfile])
	attacker.equipped_items.append(item)

	var target := _make_model(10, 1, 1)
	var atk_unit := _make_unit(attacker)
	var def_unit := _make_unit(target)

	var events: Array[CombatEvent] = resolver.resolve_model_attacks(attacker, atk_unit, target, def_unit, 15.0)
	assert_eq(events.size(), 4, "One event per damage_count (4 attempts)")


func test_miss_events_have_no_damage_instance() -> void:
	var attacker := _make_model(1, 1, 1)
	var profile := _make_ranged_profile(5)
	var item := _make_item_with_profiles([profile] as Array[AttackProfile])
	attacker.equipped_items.append(item)

	var target := _make_model(20, 20, 20)
	var atk_unit := _make_unit(attacker)
	var def_unit := _make_unit(target)

	seed(12345)
	var events: Array[CombatEvent] = resolver.resolve_model_attacks(attacker, atk_unit, target, def_unit, 15.0)
	for evt in events:
		if not evt.hit:
			assert_null(evt.damage_instance, "Miss events should have null damage_instance")
		else:
			assert_not_null(evt.damage_instance, "Hit events should have non-null damage_instance")


func test_events_record_hit_chance() -> void:
	var attacker := _make_model(10, 5, 5)
	var profile := _make_ranged_profile(3)
	var item := _make_item_with_profiles([profile] as Array[AttackProfile])
	attacker.equipped_items.append(item)

	var target := _make_model(10, 5, 5)
	var atk_unit := _make_unit(attacker)
	var def_unit := _make_unit(target)

	var events: Array[CombatEvent] = resolver.resolve_model_attacks(attacker, atk_unit, target, def_unit, 15.0)
	if events.size() > 0:
		var expected_chance := resolver.compute_hit_chance(attacker, profile, target, 15.0)
		assert_almost_eq(events[0].hit_chance, expected_chance, 0.001,
			"Event hit_chance should match compute_hit_chance")
