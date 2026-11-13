class_name SimMetrics
extends RefCounted
## The metrics library (GDD 05 §5.2, R7Q17): what a harness run measures,
## for balance, feel and performance analysis and the AI factory's scoring.
## Read-only: it watches through the battle sim's tick hook and reads
## states and events; it never changes them.
##
## Rows: {"metric", "player" (0 = the whole run), "value"}. Battles:
##   vp (influence), value_destroyed, value_lost, units_lost, squads_lost;
##   band.<pool>.<band>: squad-ticks spent in each pressure band;
##   ledger.<pool>: net SIMPL flow (the per-battle ledger, R6Q3);
##   first_contact_tick, first_casualty_tick, first_capture_turn
##   (milestones, -1 = never); perf.<system>_usec (per-system time).
## Overworld runs: value, value_earned, hexes_explored, fog_revealed_pct,
##   features_owned, commanders_alive; battles, first_battle_turn,
##   first_capture_turn.

var rows: Array = []
var _band_ticks: Dictionary = {}  # [player, pool, band] key -> squad-ticks
var _first_contact: int = -1
var _first_casualty: int = -1
var _first_capture: int = -1
var _log_seen: int = 0
var _start_value: Dictionary = {}  # player -> Value of its squads at the start


## Starts watching a battle: samples bands every tick.
func watch_battle(state: BattleState, sim: BattleSim) -> void:
	sim.runner.profiling = true
	sim.runner.profile = {}
	var sq := state.squads
	for row in sq.count():
		var p := sq.player[row]
		_start_value[p] = int(_start_value.get(p, 0)) + state.rules.sq_value[sq.tmpl[row]]
	sim.tick_hook = _sample


func _sample(state: BattleState) -> void:
	var sq := state.squads
	for row in sq.count():
		if not sq.is_active(row) or sq.alive[row] <= 0:
			continue
		for p in 5:
			var key := "%d|%s|%s" % [sq.player[row], DataSchema.SIMPL[p], DataSchema.BANDS[Pools.band(state, row, p)]]
			_band_ticks[key] = int(_band_ticks.get(key, 0)) + 1
	if state.turn_log.size() < _log_seen:
		_log_seen = 0  # a new turn's log
	for i in range(_log_seen, state.turn_log.size()):
		var e: SimEvent = state.turn_log[i]
		if e.type == &"engagement" and _first_contact < 0:
			_first_contact = e.tick
		if e.type == &"unit_killed" and _first_casualty < 0:
			_first_casualty = e.tick
	_log_seen = state.turn_log.size()
	if _first_capture < 0:
		for z in state.zone_owner.size():
			if state.zone_owner[z] != 0:
				_first_capture = state.turn


## Battle metrics once it has ended (or stopped).
func battle(state: BattleState, sim: BattleSim, prefix: String = "") -> Array:
	var out := []
	var r := state.rules
	var sq := state.squads
	var lost_value := {}
	var lost_units := {}
	var lost_squads := {}
	for row in sq.count():
		var p := sq.player[row]
		var st := sq.tmpl[row]
		var start := r.sq_members[st].size()
		var gone := start - sq.alive[row]
		lost_units[p] = int(lost_units.get(p, 0)) + gone
		lost_value[p] = int(lost_value.get(p, 0)) + r.sq_value[st] * gone / maxi(start, 1)
		if sq.destroyed[row] == 1:
			lost_squads[p] = int(lost_squads.get(p, 0)) + 1
	for p in state.players:
		out.append(_row(prefix + "vp", p, state.influence[p]))
		out.append(_row(prefix + "value_destroyed", p, state.value_score[p]))
		out.append(_row(prefix + "value_lost", p, lost_value.get(p, 0)))
		out.append(_row(prefix + "units_lost", p, lost_units.get(p, 0)))
		out.append(_row(prefix + "squads_lost", p, lost_squads.get(p, 0)))
	var keys: Array = _band_ticks.keys()
	keys.sort()
	for k: String in keys:
		var parts := k.split("|")
		out.append(_row(prefix + "band.%s.%s" % [parts[1], parts[2]], int(parts[0]), _band_ticks[k]))
	var ledger := {}
	for k: String in state.ledger:
		var parts := k.split("|")
		var p := sq.player[sq.row_of(int(parts[0]))] if sq.row_of(int(parts[0])) >= 0 else 0
		var key := "%d|%s" % [p, DataSchema.SIMPL[int(parts[1])]]
		ledger[key] = int(ledger.get(key, 0)) + int(state.ledger[k])
	keys = ledger.keys()
	keys.sort()
	for k: String in keys:
		out.append(_row(prefix + "ledger." + k.get_slice("|", 1), int(k.get_slice("|", 0)), Fixed.to_display(ledger[k]).to_float()))
	out.append(_row(prefix + "turns", 0, state.turn))
	out.append(_row(prefix + "first_contact_tick", 0, _first_contact))
	out.append(_row(prefix + "first_casualty_tick", 0, _first_casualty))
	out.append(_row(prefix + "first_capture_turn", 0, _first_capture))
	keys = sim.runner.profile.keys()
	keys.sort()
	for k: String in keys:
		out.append(_row(prefix + "perf.%s_usec" % k, 0, sim.runner.profile[k]))
	return out


## Overworld metrics for a played session.
func overworld(x: OverworldSession, events: Array) -> Array:
	var s := x.state
	var out := []
	var earned := {}
	var first_battle := -1
	var first_capture := -1
	var battles := 0
	for e: Dictionary in events:
		match StringName(e["type"]):
			&"value_changed":
				if int(e["data"]["amount"]) > 0:
					var p := int(e["data"]["player"])
					earned[p] = int(earned.get(p, 0)) + int(e["data"]["amount"])
			&"battle_started":
				battles += 1
				if first_battle < 0:
					first_battle = int(e["turn"])
			&"feature_captured":
				if first_capture < 0:
					first_capture = int(e["turn"])
	var plots := s.rules.plot_count()
	for p in x.players():
		var explored: int = (s.memory.get(p, {}) as Dictionary).size()
		var owned := 0
		for row in s.features.count():
			if s.features.owner[row] == p:
				owned += 1
		var alive := 0
		for row in s.commanders.count():
			if s.commanders.player[row] == p:
				alive += 1
		out.append(_row("value", p, s.value_of(p)))
		out.append(_row("value_earned", p, earned.get(p, 0)))
		out.append(_row("hexes_explored", p, explored))
		out.append(_row("fog_revealed_pct", p, 100.0 * explored / maxi(plots, 1)))
		out.append(_row("features_owned", p, owned))
		out.append(_row("commanders_alive", p, alive))
	out.append(_row("turns", 0, s.turn))
	out.append(_row("battles", 0, battles))
	out.append(_row("first_battle_turn", 0, first_battle))
	out.append(_row("first_capture_turn", 0, first_capture))
	return out


static func _row(metric: String, player: int, value: Variant) -> Dictionary:
	return {"metric": metric, "player": player, "value": float(value)}
