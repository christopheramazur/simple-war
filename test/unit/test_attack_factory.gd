extends GutTest

## Tests for AttackFactory — base attack loading and override merging.

var factory: AttackFactory


func before_each() -> void:
	factory = AttackFactory.new()
	factory.load_all()


func test_all_base_attacks_load() -> void:
	var ids := factory.get_all_ids()
	assert_gt(ids.size(), 0, "Should load at least one base attack")

	var expected := [
		"small_arms_kinetic", "small_arms_energy", "heavy_ordnance",
		"thrown_explosive", "placed_explosive", "energy_blast",
		"combat_blade", "blunt_melee", "heavy_melee",
		"natural_weapon_melee", "natural_weapon_ranged",
	]
	for id in expected:
		assert_has(ids, id, "Should contain base attack '%s'" % id)


func test_resolve_bare_reference_inherits_all_base_values() -> void:
	var profile := factory.resolve({"attack_id": "small_arms_kinetic"})

	assert_not_null(profile)
	assert_eq(profile.id, "small_arms_kinetic")
	assert_eq(profile.category, "ranged")
	assert_eq(profile.damage_type, "kinetic")
	assert_eq(profile.damage_value, 3)
	assert_eq(profile.damage_count, 1)
	assert_eq(profile.range_min, 5)
	assert_eq(profile.range_short, 10)
	assert_eq(profile.range_long, 30)
	assert_eq(profile.range_max, 40)


func test_resolve_override_replaces_shallow_fields() -> void:
	var profile := factory.resolve({
		"attack_id": "combat_blade",
		"display_name": "Hack",
	})

	assert_not_null(profile)
	assert_eq(profile.display_name, "Hack", "Override should replace display_name")
	assert_eq(profile.id, "combat_blade", "Non-overridden id should be inherited")
	assert_eq(profile.damage_value, 2, "Non-overridden damage should be inherited")


func test_resolve_deep_merge_on_damage() -> void:
	var profile := factory.resolve({
		"attack_id": "heavy_ordnance",
		"damage": {"value": 25, "count": 2},
	})

	assert_not_null(profile)
	assert_eq(profile.damage_value, 25, "Damage value should be overridden")
	assert_eq(profile.damage_count, 2, "Damage count should be overridden")
	assert_eq(profile.damage_type, "concussive",
		"Damage type should be inherited from base")


func test_resolve_deep_merge_on_range() -> void:
	var profile := factory.resolve({
		"attack_id": "small_arms_energy",
		"range": {"short": 12, "long": 35, "max": 45},
	})

	assert_not_null(profile)
	assert_eq(profile.range_min, 5, "Unoverridden range_min should be inherited")
	assert_eq(profile.range_short, 12, "Overridden range_short should apply")
	assert_eq(profile.range_long, 35, "Overridden range_long should apply")
	assert_eq(profile.range_max, 45, "Overridden range_max should apply")


func test_resolve_deep_merge_on_splash() -> void:
	var profile := factory.resolve({
		"attack_id": "heavy_ordnance",
		"damage": {"splash": {"close": 3, "medium": 5, "far": 8}},
	})

	assert_not_null(profile)
	assert_true(profile.has_splash, "Splash should be present after override")
	assert_eq(profile.splash_close, 3)
	assert_eq(profile.splash_medium, 5)
	assert_eq(profile.splash_far, 8)
	assert_eq(profile.damage_value, 10,
		"Non-overridden damage value should be inherited")


func test_resolve_unknown_attack_id_returns_null() -> void:
	var profile := factory.resolve({"attack_id": "nonexistent_attack"})
	assert_null(profile, "Unknown attack_id should return null")


func test_resolve_missing_attack_id_returns_null() -> void:
	var profile := factory.resolve({"display_name": "Orphaned"})
	assert_null(profile, "Missing attack_id should return null")


func test_base_not_mutated_by_overrides() -> void:
	factory.resolve({
		"attack_id": "combat_blade",
		"display_name": "Modified Name",
		"damage": {"value": 99},
	})

	var base := factory.get_base("combat_blade")
	assert_eq(base.get("display_name"), "Blade Strike",
		"Base attack should not be mutated by resolve overrides")
	var base_damage: Dictionary = base.get("damage", {})
	assert_eq(base_damage.get("value"), 2,
		"Base damage value should not be mutated")
