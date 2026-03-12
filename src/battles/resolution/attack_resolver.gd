class_name AttackResolver
extends RefCounted

## "Making Attacks" process.
## Each model selects an attack profile, picks a target, resolves the hit,
## and emits CombatEvent objects (one per attempt, hit or miss). Does not know about armour or defense.

const HIT_FLOOR := 0.05
const HIT_CEILING := 0.95


func resolve_model_attacks(
	attacker: ModelData,
	attacker_unit: UnitData,
	target: ModelData,
	target_unit: UnitData,
	distance: float
) -> Array[CombatEvent]:
	var results: Array[CombatEvent] = []
	var profiles := _select_profiles(attacker, distance)

	for profile: AttackProfile in profiles:
		for _i in range(profile.damage_count):
			var comps := _compute_hit_components(attacker, attacker_unit, profile, target, target_unit, distance)
			var hit_chance: float = comps["chance"]
			var roll := randf()
			var hit := roll <= hit_chance

			var evt := CombatEvent.new()
			evt.attacker_name = attacker.display_name if attacker.display_name else attacker.id
			evt.attacker_unit_name = attacker_unit.display_name if attacker_unit.display_name else attacker_unit.id
			evt.target_name = target.display_name if target.display_name else target.id
			evt.target_unit_name = target_unit.display_name if target_unit.display_name else target_unit.id
			evt.attack_name = profile.display_name
			evt.attack_category = profile.category
			evt.distance = distance
			evt.hit_chance = hit_chance
			evt.base_hit_chance = comps["base"]
			evt.range_modifier = comps["range_mod"]
			evt.evasion_factor = comps["evasion"]
			evt.hit = hit

			if hit:
				var dmg := DamageInstance.new()
				dmg.damage_value = profile.damage_value
				dmg.damage_type = profile.damage_type
				dmg.source_model_id = attacker.id
				dmg.source_attack_id = profile.id
				dmg.source_unit_id = attacker_unit.id
				dmg.target_model_id = target.id
				dmg.target_unit_id = target_unit.id
				evt.damage_instance = dmg

			results.append(evt)

	return results


func compute_hit_chance(
	attacker: ModelData,
	profile: AttackProfile,
	target: ModelData,
	distance: float
) -> float:
	# Used primarily in tests; ignore movement/evasion that depend on units.
	return _compute_hit_components(attacker, null, profile, target, null, distance)["chance"]


func _select_profiles(attacker: ModelData, distance: float) -> Array[AttackProfile]:
	# Only use profiles that are in range. Prefer melee when target is in melee range.
	var ranged: Array[AttackProfile] = attacker.get_ranged_profiles()
	var melee: Array[AttackProfile] = attacker.get_melee_profiles()

	var melee_in_range: Array[AttackProfile] = []
	for p in melee:
		if p.is_in_range(distance):
			melee_in_range.append(p)

	var ranged_in_range: Array[AttackProfile] = []
	for p in ranged:
		if p.is_in_range(distance):
			ranged_in_range.append(p)

	# Prefer melee at point-blank (distance <= 2) so we don't use grenades/ranged in melee
	if distance <= 2.0 and not melee_in_range.is_empty():
		return melee_in_range
	if not ranged_in_range.is_empty():
		return ranged_in_range
	return melee_in_range


func _compute_hit_components(
	attacker: ModelData,
	attacker_unit: UnitData,
	profile: AttackProfile,
	target: ModelData,
	target_unit: UnitData,
	distance: float
) -> Dictionary:
	# Baseline competence: endurance normalized to 0-1 range (10 = 50% base)
	var base_chance := _compute_base_from_skill(attacker, profile)

	# Range penalty for ranged attacks
	var range_mod := profile.get_range_penalty(distance) if profile.category == "ranged" else 0.0

	# Static evasion from target's armour/abilities
	var evasion := 0.0
	if target != null:
		evasion = target.get_hit_modifier_for_profile(profile)

	var raw := base_chance + range_mod - evasion
	var movement_factor := _compute_movement_factor(attacker_unit, target_unit)
	var final_chance := clampf(raw * movement_factor, HIT_FLOOR, HIT_CEILING)
	return {
		"base": base_chance,
		"range_mod": range_mod,
		"evasion": evasion,
		"movement_factor": movement_factor,
		"chance": final_chance,
	}


func _compute_base_from_skill(attacker: ModelData, profile: AttackProfile) -> float:
	var skills: Dictionary = attacker.weapon_skill
	if skills.is_empty():
		# Fallback to endurance-based if no skill map defined
		return clampf(float(attacker.endurance) / 20.0, 0.1, 0.9)

	var cat: String = profile.skill_category
	var skill_val: int = int(skills.get(cat, skills.get("default", 5)))
	# Assume 0–10 skill range mapped to 10%–90%
	return clampf(float(skill_val) / 10.0, 0.1, 0.9)


func _compute_movement_factor(attacker_unit: UnitData, target_unit: UnitData) -> float:
	if attacker_unit == null or target_unit == null:
		return 1.0
	var m: float = target_unit.distance_moved_this_turn
	if m <= 0.0:
		return 1.0
	var r: int = max(attacker_unit.reflex, 1)
	const MAX_SPEED_PENALTY := 0.5
	const MOTION_SCALE := 10.0
	var ratio: float = (m / MOTION_SCALE) / float(r)
	var penalty := clampf(ratio, 0.0, MAX_SPEED_PENALTY)
	return 1.0 - penalty
