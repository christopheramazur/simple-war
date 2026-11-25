extends GutTest
## LineOfFire.unit_shot and shot_share (sw-txnj.2): whether one unit can shoot
## a squad and, if not, why; and the standing-DPS share of a squad with a shot.
## Read-only: the state hash never moves.

const ONE := Fixed.ONE

## A column of walls three cells thick at x = 29..31: more than LOS_DEPTH
## blocking cells between x = 20 and x = 40, so no line passes it.
const WALL := [
	{"feature": "wall", "x": 29, "y": 5, "h": 35},
	{"feature": "wall", "x": 30, "y": 5, "h": 35},
	{"feature": "wall", "x": 31, "y": 5, "h": 35},
]

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## Rules for a 60 x 40 field with `cells` painted on it (as test_battle_route).
func _rules(cells: Array) -> BattleRules:
	var defs := _l().defs.duplicate()
	defs.append({"id": "m", "kind": "battle_map", "values": {"width": 60, "height": 40, "base": "open", "cells": cells}})
	var sc: Dictionary = _l().templates.values_of("duel_crossroads").duplicate(true)
	sc["map"] = "m"
	sc["zones"] = []
	defs.append({"id": "t", "kind": "scenario", "values": sc})
	var r := BattleRules.compile(TemplateTable.build(defs), "t")
	assert_eq(r.errors, PackedStringArray())
	return r


func _battle(cells: Array = []) -> BattleState:
	return BattleState.new(1, _rules(cells), 1)


## Spawns a squad of template `st` (`units` members, -1 = all, `gear` as
## BattleSetup takes it). Returns the squad ID.
func _squad(s: BattleState, st: String, player: int, x: int, y: int, units: int = -1, gear: Array = []) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index(st), x * ONE, y * ONE, 0, units, gear)
	Centroids.update(s)
	return sid


func _row(s: BattleState, sid: int) -> int:
	return s.squads.row_of(sid)


func _unit(s: BattleState, sid: int, nth: int = 0) -> int:
	return Centroids.units_of(s, _row(s, sid))[nth]


func _put(s: BattleState, urow: int, x: int, y: int) -> void:
	s.units.x[urow] = x * ONE
	s.units.y[urow] = y * ONE


## Lets `player` see squad `sid` (seen_by is the side's fog).
func _see(s: BattleState, sid: int, player: int) -> void:
	var row := _row(s, sid)
	s.squads.seen_by[row] = s.squads.seen_by[row] | BattleSquads.bit(player)


func test_shot_when_in_range_and_clear() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 10, 20, 1)
	var b := _squad(s, "rifle_squad", 2, 25, 20, 1)
	_see(s, b, 1)
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.SHOT)


func test_blocked_by_a_wall_between() -> void:
	var walled := _battle(WALL)
	var a := _squad(walled, "rifle_squad", 1, 20, 30, 1)
	var b := _squad(walled, "rifle_squad", 2, 40, 30, 1)
	_see(walled, b, 1)
	assert_eq(LineOfFire.unit_shot(walled, _unit(walled, a), _row(walled, b)), LineOfFire.BLOCKED, "wall in the line")
	var open := _battle()
	var a2 := _squad(open, "rifle_squad", 1, 20, 30, 1)
	var b2 := _squad(open, "rifle_squad", 2, 40, 30, 1)
	_see(open, b2, 1)
	assert_eq(LineOfFire.unit_shot(open, _unit(open, a2), _row(open, b2)), LineOfFire.SHOT, "same field, no wall: a shot")


func test_out_of_range() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 2, 20, 1)
	var b := _squad(s, "rifle_squad", 2, 58, 20, 1)
	_see(s, b, 1)
	# Service rifle range 40; the target is 56 m away.
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.OUT_OF_RANGE)


func test_min_range_for_a_mortar() -> void:
	var close := _battle()
	var a := _squad(close, "mortar_team", 1, 10, 20, 1)
	var b := _squad(close, "rifle_squad", 2, 15, 20, 1)
	_see(close, b, 1)
	# Light mortar: min range 20 m, range 90 m. The target is 5 m away.
	assert_eq(LineOfFire.unit_shot(close, _unit(close, a), _row(close, b)), LineOfFire.MIN_RANGE)
	var far := _battle()
	var a2 := _squad(far, "mortar_team", 1, 10, 20, 1)
	var b2 := _squad(far, "rifle_squad", 2, 35, 20, 1)
	_see(far, b2, 1)
	assert_eq(LineOfFire.unit_shot(far, _unit(far, a2), _row(far, b2)), LineOfFire.SHOT, "outside min range it shoots")


func test_indirect_fire_ignores_the_wall() -> void:
	var s := _battle(WALL)
	var a := _squad(s, "mortar_team", 1, 20, 30, 1)
	var b := _squad(s, "rifle_squad", 2, 40, 30, 1)
	_see(s, b, 1)
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.SHOT, "the mortar lobs over the wall")


func test_an_unseen_squad_is_no_target() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 10, 20, 1)
	var b := _squad(s, "rifle_squad", 2, 25, 20, 1)
	# In range and in the clear, but player 1 doesn't see it.
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.NO_TARGET)
	_see(s, b, 1)
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.SHOT, "seen now")


func test_dead_target_units_are_ignored() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 10, 20, 1)
	var b := _squad(s, "rifle_squad", 2, 25, 20, 2)
	_see(s, b, 1)
	var near := _unit(s, b, 0)
	var far := _unit(s, b, 1)
	_put(s, near, 25, 20)
	_put(s, far, 58, 20)
	s.units.hp[near] = 0
	# The only living unit is 48 m away: out of range, not a shot at the corpse.
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.OUT_OF_RANGE)
	s.units.hp[far] = 0
	assert_eq(LineOfFire.unit_shot(s, _unit(s, a), _row(s, b)), LineOfFire.NO_TARGET, "all dead")


func test_dead_or_unarmed_attacker_cannot_shoot() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 10, 20, 1)
	var b := _squad(s, "rifle_squad", 2, 25, 20, 1)
	_see(s, b, 1)
	var urow := _unit(s, a)
	s.units.hp[urow] = 0
	assert_eq(LineOfFire.unit_shot(s, urow, _row(s, b)), LineOfFire.BLOCKED, "dead")
	s.units.hp[urow] = s.units.hp_max[urow]
	s.units.weapon[urow] = -1
	assert_eq(LineOfFire.unit_shot(s, urow, _row(s, b)), LineOfFire.BLOCKED, "unarmed")


func test_share_is_1000_when_every_armed_unit_has_a_shot() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 10, 20)
	var b := _squad(s, "rifle_squad", 2, 20, 20, 1)
	_see(s, b, 1)
	assert_eq(LineOfFire.shot_share(s, _row(s, a), _row(s, b)), 1000)


func test_share_is_0_when_no_unit_has_a_shot() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 2, 20)
	var b := _squad(s, "rifle_squad", 2, 58, 20, 1)
	_see(s, b, 1)
	assert_eq(LineOfFire.shot_share(s, _row(s, a), _row(s, b)), 0, "all out of range")
	var c := _squad(s, "rifle_squad", 2, 12, 20, 1)
	assert_eq(LineOfFire.shot_share(s, _row(s, a), _row(s, c)), 0, "unseen target: no shot")


func test_unarmed_squad_gives_0_without_error() -> void:
	var s := _battle()
	var a := _squad(s, "rifle_squad", 1, 10, 20)
	for urow in Centroids.units_of(s, _row(s, a)):
		s.units.weapon[urow] = -1
	var b := _squad(s, "rifle_squad", 2, 25, 20, 1)
	_see(s, b, 1)
	assert_eq(LineOfFire.shot_share(s, _row(s, a), _row(s, b)), 0)


func test_mixed_squad_share_is_dps_weighted() -> void:
	var s := _battle()
	# Mortar team gear: two lmg (range 50) and one service rifle (range 40),
	# all standing at 10, 20. Mortar-team members share one template, so
	# proficiency is equal across the squad.
	var gear := [{"weapon": "lmg"}, {"weapon": "lmg"}, {"weapon": "rifle"}]
	var a := _squad(s, "mortar_team", 1, 10, 20, 3, gear)
	for urow in Centroids.units_of(s, _row(s, a)):
		_put(s, urow, 10, 20)
	var b := _squad(s, "rifle_squad", 2, 55, 20, 1)
	_see(s, b, 1)
	var units := Centroids.units_of(s, _row(s, a))
	assert_eq(LineOfFire.unit_shot(s, units[0], _row(s, b)), LineOfFire.SHOT, "lmg reaches 45 m")
	assert_eq(LineOfFire.unit_shot(s, units[2], _row(s, b)), LineOfFire.OUT_OF_RANGE, "rifle does not")
	# Standing DPS per tick: rifle 0.6 x 3.375 / 10 = 0.2025, lmg 0.3 x 3 x 5 / 20 = 0.225.
	# Two lmg of three: 2 x 0.225 / (2 x 0.225 + 0.2025) = 689 permille.
	assert_almost_eq(LineOfFire.shot_share(s, _row(s, a), _row(s, b)), 689, 2)


func test_neither_call_changes_the_state_hash() -> void:
	var s := _battle(WALL)
	var a := _squad(s, "rifle_squad", 1, 20, 30, 4, [{"weapon": "lmg"}, {"weapon": "lmg"}, {}, {}])
	var b := _squad(s, "rifle_squad", 2, 40, 30, 2)
	var c := _squad(s, "mortar_team", 2, 50, 10, 1)
	_see(s, b, 1)
	_see(s, c, 1)
	var before := s.state_hash()
	for urow in Centroids.units_of(s, _row(s, a)):
		for t in [b, c]:
			LineOfFire.unit_shot(s, urow, _row(s, t))
	LineOfFire.shot_share(s, _row(s, a), _row(s, b))
	LineOfFire.shot_share(s, _row(s, a), _row(s, c))
	assert_eq(s.state_hash(), before, "read-only")
