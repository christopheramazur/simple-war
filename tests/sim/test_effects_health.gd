extends GutTest
## Queued damage applied by the health system: simultaneous fire (E2Q2).
## Task sw-ps1.3.

const ONE := Fixed.ONE

static var _rules_cache: BattleRules


func _rules() -> BattleRules:
	if _rules_cache == null:
		var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
		_rules_cache = BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	return _rules_cache


func _place(s: BattleState, player: int, x: int, facing: int) -> int:
	var sid := BattleSetup.spawn_squad(s, player, _rules().squad_index("rifle_squad"), x * ONE, 50 * ONE, facing)
	Centroids.update(s)
	return sid


## Every unit at a sliver of HP, with its next shot certain to hit.
func _fragile(s: BattleState) -> void:
	var u := s.units
	var hp: PackedInt64Array = u.take_column(&"hp")
	var acc: PackedInt64Array = u.take_column(&"acc_hit")
	for row in u.count():
		hp[row] = 1
		acc[row] = ONE
	u.put_column(&"hp", hp)
	u.put_column(&"acc_hit", acc)


func test_both_sides_kill_in_the_same_tick() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, 40, 0)
	var b := _place(s, 2, 55, Fixed.ANGLE_HALF)
	_fragile(s)
	var sim := BattleSim.new()
	sim.runner.step(s)
	var killed_by := {}
	for e in s.turn_log:
		if e.type == &"unit_killed":
			killed_by[e.data["by"]] = true
	assert_true(killed_by.has(a), "squad A killed someone")
	assert_true(killed_by.has(b), "squad B killed someone, though A fired at it the same tick")
	assert_eq(s.damage_queue.size(), 0, "queue drained within the tick")


func test_canonical_order_and_no_hits_on_the_dead() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var a := _place(s, 1, 40, 0)
	var b := _place(s, 2, 55, Fixed.ANGLE_HALF)
	var u := s.units
	var shooters := Centroids.units_of(s, s.squads.row_of(a))
	var victim := Centroids.units_of(s, s.squads.row_of(b))[0]
	var vid := u.id_at(victim)
	var lethal := u.hp[victim] + 100 * ONE
	# Queued in reverse ID order: the lowest shooter ID must still apply first.
	var ids: Array[int] = []
	for r in shooters:
		ids.append(u.id_at(r))
	ids.sort()
	ids.reverse()
	for sid in ids:
		Health.queue(s, sid, a, vid, b, lethal, 0)
	HealthSystem.new().run(s)
	s.end_tick()
	var kills := 0
	var damaged := 0
	for e in s.turn_log:
		if e.type == &"unit_killed":
			kills += 1
		elif e.type == &"squad_damaged":
			damaged += 1
			assert_eq(e.data["kills"], 1)
	assert_eq(kills, 1, "one death, later hits on the corpse are dropped")
	assert_eq(damaged, 1, "one squad_damaged per attacker/target pair")
	assert_eq(s.squads.alive[s.squads.row_of(b)], Centroids.units_of(s, s.squads.row_of(b)).size() - 1)
