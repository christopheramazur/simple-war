class_name ScenarioBuilder
extends RefCounted
## Hand-placed micro-battles (sw-tho3.3, U1 B3): the shared builder behind
## the behaviour workshop and the sim tests. Places squads exactly, makes
## them dummies, and teleports them. Positions are raw fixed ints.
##
## Teleporting writes the state directly; only setup code and tests do that.
## A workshop run places squads before the first tick and never touches the
## state again.


## An empty battle on `rules` with its sides kept (players, facings) but no
## squads deployed: squads are placed by hand with `place`.
static func empty(rules: BattleRules, seed_value: int, context_id: int = 1) -> BattleState:
	return BattleState.new(context_id, rules, seed_value)


## Spawns squad template `squad` (its ID) for `player` with its anchor at
## (x, y) fixed. Returns the squad ID, or -1 for an unknown template.
static func place(state: BattleState, player: int, squad: String, x: int, y: int, facing: int = 0) -> int:
	var st := state.rules.squad_index(squad)
	if st < 0:
		return -1
	var sid := BattleSetup.spawn_squad(state, player, st, x, y, facing)
	Centroids.update(state)
	return sid


## Takes the weapons away from every unit of a squad (it cannot shoot back).
static func disarm(state: BattleState, sid: int) -> void:
	var row := state.squads.row_of(sid)
	for urow in Centroids.units_of(state, row):
		var uid := state.units.id_at(urow)
		state.units.set_value(uid, &"weapon", -1)
		state.units.set_value(uid, &"ammo", 0)
	state.squads.set_value(sid, &"reach", 0)


## Sets every unit's HP and maximum HP (fixed) and the squad's HP total.
static func set_hp(state: BattleState, sid: int, hp: int) -> void:
	var row := state.squads.row_of(sid)
	var total := 0
	for urow in Centroids.units_of(state, row):
		var uid := state.units.id_at(urow)
		state.units.set_value(uid, &"hp", hp)
		state.units.set_value(uid, &"hp_max", hp)
		total += hp
	state.squads.set_value(sid, &"hp_max", total)


## A stationary enemy that cannot shoot back (disarmed) and cannot die
## (huge HP), so only the observer's own behaviour is under test.
static func target_dummy(state: BattleState, player: int, squad: String, x: int, y: int, hp: int = 1000 * Fixed.ONE) -> int:
	var sid := place(state, player, squad, x, y)
	if sid < 0:
		return sid
	for urow in Centroids.units_of(state, state.squads.row_of(sid)):
		state.units.set_value(state.units.id_at(urow), &"weapon", -1)
	set_hp(state, sid, hp)
	return sid


## Teleports a squad (anchor, order point and every unit by the same delta)
## so its anchor lands on (nx, ny) fixed.
static func move_squad(state: BattleState, sid: int, nx: int, ny: int) -> void:
	var s := state.squads
	var row := s.row_of(sid)
	var dx := nx - s.ax[row]
	var dy := ny - s.ay[row]
	for c: StringName in [&"ax", &"tx", &"ay", &"ty"]:
		var col: PackedInt64Array = s.take_column(c)
		col[row] += dx if c in [&"ax", &"tx"] else dy
		s.put_column(c, col)
	var ux: PackedInt64Array = state.units.take_column(&"x")
	var uy: PackedInt64Array = state.units.take_column(&"y")
	for urow in Centroids.units_of(state, row):
		ux[urow] += dx
		uy[urow] += dy
	state.units.put_column(&"x", ux)
	state.units.put_column(&"y", uy)
	Centroids.update(state)
